import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/monitored_service.dart';
import 'database_service.dart';

class StorageService {
  final _db = DatabaseService();

  // SharedPreferences key used by MonitorWorker.kt on the native side
  static const _nativeKey = 'monitored_services';

  // Separate keys for a11y and notification listener monitoring
  // (never mixed into the main service DB)
  static const _a11yKey = 'a11y_monitored';
  static const _notifKey = 'notif_monitored';

  Future<List<MonitoredService>> loadServices() => _db.loadServices();

  Future<void> saveServices(List<MonitoredService> services) async {
    await _db.saveAllServices(services);
    await _syncToPrefs(services);
  }

  Future<void> addService(MonitoredService service) async {
    await _db.upsertService(service);
    await _syncToPrefs(await _db.loadServices());
  }

  Future<void> removeService(MonitoredService service) async {
    await _db.removeService(service);
    await _syncToPrefs(await _db.loadServices());
  }

  Future<void> updateService(MonitoredService service) async {
    await _db.upsertService(service);
    await _syncToPrefs(await _db.loadServices());
  }

  /// Keeps flutter.monitored_services in SharedPreferences so MonitorWorker
  /// can read it on device boot without needing Flutter running.
  Future<void> _syncToPrefs(List<MonitoredService> services) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nativeKey, MonitoredService.listToJson(services));
  }

  // ── Accessibility monitor storage ─────────────────────────────────────────

  Future<Set<String>> loadA11yMonitoredKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_a11yKey);
    if (raw == null) return {};
    return Set<String>.from(jsonDecode(raw) as List);
  }

  Future<void> addA11yMonitored(String pkg, String cls) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = await loadA11yMonitoredKeys();
    keys.add('$pkg/$cls');
    await prefs.setString(_a11yKey, jsonEncode(keys.toList()));
  }

  Future<void> removeA11yMonitored(String pkg, String cls) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = await loadA11yMonitoredKeys();
    keys.remove('$pkg/$cls');
    await prefs.setString(_a11yKey, jsonEncode(keys.toList()));
  }

  // ── Notification listener monitor storage ─────────────────────────────────

  Future<Set<String>> loadNotifMonitoredKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_notifKey);
    if (raw == null) return {};
    return Set<String>.from(jsonDecode(raw) as List);
  }

  Future<void> addNotifMonitored(String pkg, String cls) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = await loadNotifMonitoredKeys();
    keys.add('$pkg/$cls');
    await prefs.setString(_notifKey, jsonEncode(keys.toList()));
  }

  Future<void> removeNotifMonitored(String pkg, String cls) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = await loadNotifMonitoredKeys();
    keys.remove('$pkg/$cls');
    await prefs.setString(_notifKey, jsonEncode(keys.toList()));
  }

  // ── Accessibility notification preferences ────────────────────────────────
  // Stores keys where notifications are DISABLED (default = enabled)

  static const _a11yNotifOffKey = 'a11y_notif_off';

  Future<Set<String>> loadA11yNotifOffKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_a11yNotifOffKey);
    if (raw == null) return {};
    return Set<String>.from(jsonDecode(raw) as List);
  }

  Future<void> setA11yNotifOff(String pkg, String cls) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = await loadA11yNotifOffKeys();
    keys.add('$pkg/$cls');
    await prefs.setString(_a11yNotifOffKey, jsonEncode(keys.toList()));
  }

  Future<void> clearA11yNotifOff(String pkg, String cls) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = await loadA11yNotifOffKeys();
    keys.remove('$pkg/$cls');
    await prefs.setString(_a11yNotifOffKey, jsonEncode(keys.toList()));
  }

  // ── Notification listener notification preferences ────────────────────────
  // Stores keys where notifications are DISABLED (default = enabled)

  static const _notifListenerNotifOffKey = 'notif_listener_notif_off';

  Future<Set<String>> loadNotifListenerNotifOffKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_notifListenerNotifOffKey);
    if (raw == null) return {};
    return Set<String>.from(jsonDecode(raw) as List);
  }

  Future<void> setNotifListenerNotifOff(String pkg, String cls) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = await loadNotifListenerNotifOffKeys();
    keys.add('$pkg/$cls');
    await prefs.setString(_notifListenerNotifOffKey, jsonEncode(keys.toList()));
  }

  Future<void> clearNotifListenerNotifOff(String pkg, String cls) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = await loadNotifListenerNotifOffKeys();
    keys.remove('$pkg/$cls');
    await prefs.setString(_notifListenerNotifOffKey, jsonEncode(keys.toList()));
  }

  // ── Bulk-save for backup/restore ──────────────────────────────────────────

  Future<void> saveA11yMonitoredKeys(Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_a11yKey, jsonEncode(keys.toList()));
  }

  Future<void> saveNotifMonitoredKeys(Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_notifKey, jsonEncode(keys.toList()));
  }

  Future<void> saveA11yNotifOffKeys(Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_a11yNotifOffKey, jsonEncode(keys.toList()));
  }

  Future<void> saveNotifListenerNotifOffKeys(Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_notifListenerNotifOffKey, jsonEncode(keys.toList()));
  }
}
