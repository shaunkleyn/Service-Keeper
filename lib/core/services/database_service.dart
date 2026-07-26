import 'dart:convert';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:service_keeper/core/models/audit_event.dart';
import 'package:service_keeper/core/models/monitored_service.dart';
import 'package:service_keeper/core/models/service_stats.dart';

class _StatAccum {
  int restarts7d = 0, restarts30d = 0;
  int appRestarts7d = 0, appRestarts30d = 0;
  int failed7d = 0;
}

class DatabaseService {
  static DatabaseService? _instance;
  static Database? _db;

  DatabaseService._();
  factory DatabaseService() => _instance ??= DatabaseService._();

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = join(dir, 'service_keeper.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE services (
            package_name           TEXT NOT NULL,
            service_class          TEXT NOT NULL,
            display_label          TEXT NOT NULL,
            app_name               TEXT,
            interval_minutes       INTEGER NOT NULL DEFAULT 15,
            custom_interval_minutes INTEGER,
            enabled                INTEGER NOT NULL DEFAULT 1,
            notifications_enabled  INTEGER NOT NULL DEFAULT 1,
            app_restart_enabled    INTEGER NOT NULL DEFAULT 0,
            last_restarted         TEXT,
            last_checked           TEXT,
            was_running            INTEGER,
            PRIMARY KEY (package_name, service_class)
          )
        ''');
        await db.execute('''
          CREATE TABLE audit_log (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp     TEXT NOT NULL,
            package_name  TEXT NOT NULL,
            service_class TEXT NOT NULL,
            display_label TEXT NOT NULL,
            event_type    TEXT NOT NULL,
            trigger_type  TEXT,
            notes         TEXT
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_audit_pkg ON audit_log (package_name, service_class)');
        await db.execute(
            'CREATE INDEX idx_audit_ts ON audit_log (timestamp DESC)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE services ADD COLUMN custom_interval_minutes INTEGER');
          await db.execute(
              'ALTER TABLE services ADD COLUMN notifications_enabled INTEGER NOT NULL DEFAULT 1');
          await db.execute(
              'ALTER TABLE services ADD COLUMN app_restart_enabled INTEGER NOT NULL DEFAULT 0');
        }
      },
    );
  }

  // ── Services ────────────────────────────────────────────────────────────────

  Future<List<MonitoredService>> loadServices() async {
    final d = await db;
    final rows = await d.query(
      'services',
      orderBy:
          'package_name COLLATE NOCASE ASC, display_label COLLATE NOCASE ASC, service_class COLLATE NOCASE ASC',
    );
    return rows.map(_serviceFromMap).toList();
  }

  Future<void> upsertService(MonitoredService s) async {
    final d = await db;
    await d.insert('services', _serviceToMap(s),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeService(MonitoredService s) async {
    final d = await db;
    await d.delete('services',
        where: 'package_name = ? AND service_class = ?',
        whereArgs: [s.packageName, s.serviceClass]);
  }

  Future<void> saveAllServices(List<MonitoredService> services) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete('services');
      for (final s in services) {
        await txn.insert('services', _serviceToMap(s));
      }
    });
  }

  // ── Audit log ────────────────────────────────────────────────────────────────

  Future<void> addEvent(AuditEvent event) async {
    final d = await db;
    await d.insert('audit_log', event.toMap());
  }

  Future<List<AuditEvent>> getEvents({
    String? packageName,
    String? serviceClass,
    int limit = 200,
  }) async {
    final d = await db;
    final where = <String>[];
    final args = <dynamic>[];
    if (packageName != null) {
      where.add('package_name = ?');
      args.add(packageName);
    }
    if (serviceClass != null) {
      where.add('service_class = ?');
      args.add(serviceClass);
    }
    final rows = await d.query(
      'audit_log',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(AuditEvent.fromMap).toList();
  }

  Future<List<AuditEvent>> getAllEvents() async {
    final d = await db;
    final rows = await d.query('audit_log', orderBy: 'timestamp ASC');
    return rows.map(AuditEvent.fromMap).toList();
  }

  Future<void> importAuditEvents(List<AuditEvent> events) async {
    if (events.isEmpty) return;
    final d = await db;
    await d.transaction((txn) async {
      for (final e in events) {
        await txn.insert('audit_log', e.toMap());
      }
    });
  }

  /// Import pending events written by MonitorWorker into the audit_log table,
  /// then clear the queue from SharedPreferences.
  Future<void> importPendingEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('flutter.pending_audit_events');
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      if (list.isEmpty) return;
      final d = await db;
      await d.transaction((txn) async {
        for (final item in list) {
          final m = Map<String, dynamic>.from(item as Map);
          await txn.insert('audit_log', {
            'timestamp': m['ts'] as String,
            'package_name': m['pkg'] as String,
            'service_class': m['cls'] as String,
            'display_label': m['lbl'] as String? ?? '',
            'event_type': m['evt'] as String,
            'trigger_type': m['trg'] as String?,
            'notes': m['notes'] as String?,
          });
        }
      });
      await prefs.remove('flutter.pending_audit_events');
    } catch (_) {}
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _serviceToMap(MonitoredService s) => {
        'package_name': s.packageName,
        'service_class': s.serviceClass,
        'display_label': s.displayLabel,
        'app_name': s.appName,
        'interval_minutes': s.intervalMinutes,
        'custom_interval_minutes': s.customIntervalMinutes,
        'enabled': s.enabled ? 1 : 0,
        'notifications_enabled': s.notificationsEnabled ? 1 : 0,
        'app_restart_enabled': s.appRestartEnabled ? 1 : 0,
        'last_restarted': s.lastRestarted?.toIso8601String(),
        'last_checked': s.lastChecked?.toIso8601String(),
        'was_running': s.wasRunning == null ? null : (s.wasRunning! ? 1 : 0),
      };

  static MonitoredService _serviceFromMap(Map<String, dynamic> m) =>
      MonitoredService(
        packageName: m['package_name'] as String,
        serviceClass: m['service_class'] as String,
        displayLabel: m['display_label'] as String,
        appName: m['app_name'] as String?,
        intervalMinutes: m['interval_minutes'] as int? ?? 15,
        customIntervalMinutes: m['custom_interval_minutes'] as int?,
        enabled: (m['enabled'] as int? ?? 1) == 1,
        notificationsEnabled: (m['notifications_enabled'] as int? ?? 1) == 1,
        appRestartEnabled: (m['app_restart_enabled'] as int? ?? 0) == 1,
        lastRestarted: m['last_restarted'] != null
            ? DateTime.parse(m['last_restarted'] as String)
            : null,
        lastChecked: m['last_checked'] != null
            ? DateTime.parse(m['last_checked'] as String)
            : null,
        wasRunning: m['was_running'] == null
            ? null
            : (m['was_running'] as int) == 1,
      );

  // ── Stats ────────────────────────────────────────────────────────────────────

  Future<AppStats> getAppStats(String packageName) async {
    final events = await getEvents(packageName: packageName, limit: 1000);
    final now = DateTime.now();
    final cutoff30 = now.subtract(const Duration(days: 30));
    final cutoff7 = now.subtract(const Duration(days: 7));

    final Map<String, _StatAccum> acc = {};

    for (final e in events) {
      if (e.timestamp.isBefore(cutoff30)) continue;
      final a = acc.putIfAbsent(e.serviceClass, _StatAccum.new);
      final in7d = !e.timestamp.isBefore(cutoff7);

      if (e.eventType == AuditEventType.restartSuccess) {
        final isAppLaunch = e.notes?.contains('app launch') == true;
        if (isAppLaunch) {
          a.appRestarts30d++;
          if (in7d) a.appRestarts7d++;
        } else {
          a.restarts30d++;
          if (in7d) a.restarts7d++;
        }
      } else if (e.eventType == AuditEventType.restartFailed) {
        if (in7d) a.failed7d++;
      }
    }

    return AppStats(
      byService: acc.map((cls, a) => MapEntry(
            cls,
            ServiceStats(
              restarts7d: a.restarts7d,
              restarts30d: a.restarts30d,
              appRestarts7d: a.appRestarts7d,
              appRestarts30d: a.appRestarts30d,
              failed7d: a.failed7d,
            ),
          )),
    );
  }
}
