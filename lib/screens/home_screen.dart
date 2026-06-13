import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../models/monitored_service.dart';
import '../models/audit_event.dart';
import '../services/service_manager.dart';
import '../services/shizuku_service.dart';
import '../services/storage_service.dart';
import '../services/app_info_service.dart';
import '../services/database_service.dart';
import '../services/system_service.dart';
import '../widgets/service_tile.dart';
import 'service_picker_screen.dart';
import 'service_detail_screen.dart';
import 'service_audit_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _storage = StorageService();
  final _shizuku = ShizukuService();
  final _appInfo = AppInfoService();
  final _db = DatabaseService();
  final _system = SystemService();
  late final ServiceManager _manager;

  List<MonitoredService> _services = [];
  Map<String, Uint8List?> _iconCache = {};
  Map<String, String> _appNameCache = {};
  Map<String, Color> _appColorCache = {};
  ShizukuStatus _shizukuStatus = ShizukuStatus.notInstalled;
  bool _batteryExempt = true;
  bool _useAppColors = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _manager = ServiceManager(_shizuku);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkShizuku();
      _checkBatteryOptimization();
    }
  }

  Future<void> _init() async {
    await _db.importPendingEvents();
    await _checkShizuku();
    await _loadColorPreference();
    await _loadServices();
    await _checkBatteryOptimization();
    setState(() => _loading = false);
  }

  Future<void> _loadColorPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _useAppColors = prefs.getBool('use_app_colors') ?? false);
  }

  Future<void> _checkBatteryOptimization() async {
    final exempt = await _system.isBatteryOptimizationExempt();
    if (mounted) setState(() => _batteryExempt = exempt);
  }

  Future<void> _log(MonitoredService s, AuditEventType type, AuditTrigger trigger,
          {String? notes}) =>
      _db.addEvent(AuditEvent(
        timestamp: DateTime.now(),
        packageName: s.packageName,
        serviceClass: s.serviceClass,
        displayLabel: s.displayLabel,
        eventType: type,
        trigger: trigger,
        notes: notes,
      ));

  Future<void> _checkShizuku() async {
    final status = await _shizuku.checkStatus();
    if (mounted) setState(() => _shizukuStatus = status);
  }

  Future<void> _loadServices() async {
    final list = await _storage.loadServices();
    if (mounted) setState(() => _services = list);
    _fetchIconsAndNames(list);
    _system.startKeeperService(list.length);
  }

  Future<void> _fetchIconsAndNames(List<MonitoredService> services) async {
    final prefs = await SharedPreferences.getInstance();
    final packages = services.map((s) => s.packageName).toSet();

    final cachedIcons = <String, Uint8List?>{};
    for (final pkg in packages) {
      final b64 = prefs.getString('app_icon_v1_$pkg');
      if (b64 != null) cachedIcons[pkg] = base64Decode(b64);
    }
    if (mounted && cachedIcons.isNotEmpty) {
      setState(() => _iconCache = {..._iconCache, ...cachedIcons});
    }

    final missingIcons = packages.where((p) => !cachedIcons.containsKey(p)).toSet();
    if (missingIcons.isNotEmpty) {
      final fetched = await Future.wait(
        missingIcons.map((pkg) async => MapEntry(pkg, await _appInfo.getAppIcon(pkg))),
      );
      for (final e in fetched) {
        if (e.value != null) {
          await prefs.setString('app_icon_v1_${e.key}', base64Encode(e.value!));
        }
      }
      if (mounted) setState(() => _iconCache = {..._iconCache, ...Map.fromEntries(fetched)});
    }

    final nameMap = <String, String>{};
    for (final s in services) {
      if (nameMap.containsKey(s.packageName)) continue;
      if (s.appName != null) {
        nameMap[s.packageName] = s.appName!;
      } else {
        final name = await _appInfo.getAppName(s.packageName);
        nameMap[s.packageName] = name ?? s.packageName.split('.').last;
      }
    }
    if (mounted) setState(() => _appNameCache = {..._appNameCache, ...nameMap});

    if (_useAppColors) _generateAppColors();
  }

  Future<void> _generateAppColors() async {
    for (final pkg in _iconCache.keys) {
      if (_appColorCache.containsKey(pkg)) continue;
      final bytes = _iconCache[pkg];
      if (bytes == null) continue;
      try {
        final palette = await PaletteGenerator.fromImageProvider(
          MemoryImage(bytes),
          maximumColorCount: 16,
        );
        final color = palette.vibrantColor?.color ??
            palette.lightVibrantColor?.color ??
            palette.dominantColor?.color;
        if (color != null && mounted) {
          setState(() => _appColorCache[pkg] = color);
        }
      } catch (_) {}
    }
  }

  Future<void> _refreshStatuses() async {
    if (_shizukuStatus != ShizukuStatus.ready) return;
    final updated = await Future.wait(
      _services.map((s) async {
        final running = await _manager.isServiceRunning(s);
        return s.copyWith(
          wasRunning: running ?? s.wasRunning,
          lastChecked: DateTime.now(),
        );
      }),
    );
    if (mounted) setState(() => _services = updated);
    await _storage.saveServices(updated);
  }

  void _scheduleWork(MonitoredService service) {
    if (!service.enabled) {
      Workmanager().cancelByTag(service.workTag);
      return;
    }
    if (service.intervalMinutes >= 15) {
      Workmanager().registerPeriodicTask(
        service.workTag,
        'serviceCheck',
        tag: service.workTag,
        frequency: Duration(minutes: service.intervalMinutes),
        inputData: {
          'packageName': service.packageName,
          'serviceClass': service.serviceClass,
          'displayLabel': service.displayLabel,
        },
        constraints: Constraints(networkType: NetworkType.notRequired),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      );
    } else {
      Workmanager().registerOneOffTask(
        '${service.workTag}_once',
        'serviceCheck',
        tag: service.workTag,
        initialDelay: Duration(minutes: service.intervalMinutes),
        inputData: {
          'packageName': service.packageName,
          'serviceClass': service.serviceClass,
          'displayLabel': service.displayLabel,
          'intervalMinutes': service.intervalMinutes,
          'selfChain': true,
        },
      );
    }
  }

  Future<void> _addService() async {
    final result = await Navigator.push<MonitoredService>(
      context,
      MaterialPageRoute(
        builder: (_) => ServicePickerScreen(alreadyMonitored: _services, manager: _manager),
      ),
    );
    if (result == null) return;
    await _storage.addService(result);
    await _log(result, AuditEventType.added, AuditTrigger.manual);
    await _loadServices();
    _scheduleWork(result);
  }

  Future<void> _configureService(MonitoredService service) async {
    final updated = await Navigator.push<MonitoredService>(
      context,
      MaterialPageRoute(builder: (_) => ServiceDetailScreen(service: service)),
    );
    if (updated == null) return;
    await _storage.updateService(updated);
    await _loadServices();
    _scheduleWork(updated);
  }

  Future<void> _toggleService(MonitoredService service) async {
    final updated = service.copyWith(enabled: !service.enabled);
    await _storage.updateService(updated);
    await _log(updated, updated.enabled ? AuditEventType.enabled : AuditEventType.disabled,
        AuditTrigger.manual);
    await _loadServices();
    _scheduleWork(updated);
  }

  Future<void> _removeService(MonitoredService service) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove service'),
        content: Text('Stop monitoring "${service.displayLabel}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    Workmanager().cancelByTag(service.workTag);
    await _storage.removeService(service);
    await _log(service, AuditEventType.removed, AuditTrigger.manual);
    await _loadServices();
  }

  Future<void> _restartNow(MonitoredService service) async {
    if (_shizukuStatus != ShizukuStatus.ready) {
      _showShizukuWarning();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Restarting ${service.displayLabel}...')),
    );
    await _log(service, AuditEventType.restartAttempted, AuditTrigger.manual);
    final ok = await _manager.startService(service);
    await _log(service, ok ? AuditEventType.restartSuccess : AuditEventType.restartFailed,
        AuditTrigger.manual);
    final updated = service.copyWith(
      lastRestarted: ok ? DateTime.now() : service.lastRestarted,
      wasRunning: ok ? true : service.wasRunning,
    );
    await _storage.updateService(updated);
    await _loadServices();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? '${service.displayLabel} restart sent.'
            : 'Failed to restart ${service.displayLabel}.'),
        backgroundColor: ok ? Colors.green : Colors.red,
      ));
    }
  }

  /// Returns a lastChecked value that schedules the next _checkDue in [delay].
  DateTime _retryTime(MonitoredService service, [Duration delay = const Duration(seconds: 30)]) =>
      DateTime.now().subtract(Duration(minutes: service.intervalMinutes)).add(delay);

  Future<void> _checkDue(MonitoredService service) async {
    if (_shizukuStatus != ShizukuStatus.ready) return;

    final running = await _manager.isServiceRunning(service);

    if (running == null) {
      // Shizuku exec failed — can't determine state, retry in 30 s without changing status
      await _storage.updateService(service.copyWith(lastChecked: _retryTime(service)));
      await _loadServices();
      return;
    }

    if (running) {
      // Running normally — reset to full cycle
      await _storage.updateService(service.copyWith(wasRunning: true, lastChecked: DateTime.now()));
      await _loadServices();
      return;
    }

    // Service is stopped — log and attempt restart
    await _log(service, AuditEventType.detectedStopped, AuditTrigger.automatic);
    await _log(service, AuditEventType.restartAttempted, AuditTrigger.automatic);
    final ok = await _manager.startService(service);

    if (!ok) {
      // Start command itself failed — retry in 30 s
      await _log(service, AuditEventType.restartFailed, AuditTrigger.automatic);
      await _storage.updateService(service.copyWith(
        wasRunning: false,
        lastChecked: _retryTime(service),
      ));
      await _loadServices();
      return;
    }

    // Start command sent — wait 3 s then verify
    await Future.delayed(const Duration(seconds: 3));
    final nowRunning = await _manager.isServiceRunning(service);

    if (nowRunning == true) {
      await _log(service, AuditEventType.restartSuccess, AuditTrigger.automatic);
      await _storage.updateService(service.copyWith(
        wasRunning: true,
        lastChecked: DateTime.now(),
        lastRestarted: DateTime.now(),
      ));
    } else {
      // Still not confirmed running — retry in 30 s, keep red status
      await _log(service, AuditEventType.restartFailed, AuditTrigger.automatic);
      await _storage.updateService(service.copyWith(
        wasRunning: false,
        lastChecked: _retryTime(service),
        lastRestarted: DateTime.now(),
      ));
    }
    await _loadServices();
  }

  Future<void> _restartAll(List<MonitoredService> services) async {
    if (_shizukuStatus != ShizukuStatus.ready) {
      _showShizukuWarning();
      return;
    }
    final enabled = services.where((s) => s.enabled).toList();
    if (enabled.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Restarting ${enabled.length} service${enabled.length == 1 ? '' : 's'}...')),
    );
    for (final s in enabled) {
      await _log(s, AuditEventType.restartAttempted, AuditTrigger.manual);
      final ok = await _manager.startService(s);
      await _log(s, ok ? AuditEventType.restartSuccess : AuditEventType.restartFailed,
          AuditTrigger.manual);
      if (ok) {
        await _storage.updateService(s.copyWith(lastRestarted: DateTime.now(), wasRunning: true));
      }
    }
    await _loadServices();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Restart commands sent')));
    }
  }

  void _viewAppHistory(String packageName, String appName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceAuditScreen.forApp(packageName: packageName, appName: appName),
      ),
    );
  }

  Future<void> _backup() async {
    if (_services.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No services to back up')));
      return;
    }
    try {
      final events = await _db.getAllEvents();
      final now = DateTime.now();
      final ts =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
          '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final data = {
        'version': 1,
        'exportedAt': now.toIso8601String(),
        'services': _services.map((s) => s.toJson()).toList(),
        'auditLog': events.map((e) => e.toMap()).toList(),
      };
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/service_keeper_backup_$ts.json');
      await file.writeAsString(jsonEncode(data));
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'Service Keeper Backup',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _restore() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final bytes = result.files.single.bytes;
      final path = result.files.single.path;
      final String content;
      if (bytes != null) {
        content = utf8.decode(bytes);
      } else if (path != null) {
        content = await File(path).readAsString();
      } else {
        return;
      }

      final data = jsonDecode(content) as Map<String, dynamic>;
      final services = (data['services'] as List)
          .map((e) => MonitoredService.fromJson(e as Map<String, dynamic>))
          .toList();
      final rawLog = data['auditLog'] as List? ?? [];
      final auditLog = rawLog.map((e) => AuditEvent.fromMap(e as Map<String, dynamic>)).toList();

      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore Backup'),
          content: Text(
            'This will replace your ${_services.length} current service${_services.length == 1 ? '' : 's'} '
            'with ${services.length} from the backup, and import ${auditLog.length} history events.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
          ],
        ),
      );
      if (ok != true) return;

      await _storage.saveServices(services);
      await _db.importAuditEvents(auditLog);
      for (final s in services) _scheduleWork(s);
      await _loadServices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restored ${services.length} services and ${auditLog.length} history events')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleAppColors() async {
    final prefs = await SharedPreferences.getInstance();
    final newValue = !_useAppColors;
    await prefs.setBool('use_app_colors', newValue);
    setState(() => _useAppColors = newValue);
    if (newValue) _generateAppColors();
  }

  void _showShizukuWarning() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Shizuku Required'),
        content: const Text(
          'Shizuku is not active. Please:\n\n'
          '1. Install Shizuku from Play Store\n'
          '2. Enable it via Wireless Debugging\n'
          '   (Developer Options → Wireless debugging)\n'
          '3. Return to this app',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _shizuku.requestPermission();
              await _checkShizuku();
            },
            child: const Text('Grant Permission'),
          ),
        ],
      ),
    );
  }

  Widget _buildShizukuBanner() {
    final color = _shizukuStatus == ShizukuStatus.ready ? Colors.green : Colors.orange;
    final label = switch (_shizukuStatus) {
      ShizukuStatus.ready => 'Shizuku active',
      ShizukuStatus.permissionDenied => 'Shizuku: permission denied',
      ShizukuStatus.notRunning => 'Shizuku not running',
      ShizukuStatus.notInstalled => 'Shizuku not installed',
    };
    final icon = _shizukuStatus == ShizukuStatus.ready ? Icons.check_circle : Icons.warning_amber;
    return GestureDetector(
      onTap: _shizukuStatus != ShizukuStatus.ready ? _showShizukuWarning : null,
      child: Container(
        color: color.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
          if (_shizukuStatus != ShizukuStatus.ready) ...[
            const Spacer(),
            Text('Tap to fix →', style: TextStyle(color: color, fontSize: 12)),
          ],
        ]),
      ),
    );
  }

  Widget _buildBatteryBanner() {
    if (_batteryExempt) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () async {
        await _system.requestBatteryOptimizationExemption();
      },
      child: Container(
        color: Colors.deepOrange.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: const Row(children: [
          Icon(Icons.battery_alert, color: Colors.deepOrange, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Battery optimization active — checks may be delayed',
              style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Text('Tap to fix →', style: TextStyle(color: Colors.deepOrange, fontSize: 12)),
        ]),
      ),
    );
  }

  List<(String pkg, String appName, List<MonitoredService> services)> _groupedServices() {
    final groups = <String, List<MonitoredService>>{};
    for (final s in _services) {
      groups.putIfAbsent(s.packageName, () => []).add(s);
    }
    final result = groups.entries.map((e) {
      final name = _appNameCache[e.key] ?? e.key.split('.').last;
      return (e.key, name, e.value);
    }).toList();
    result.sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));
    return result;
  }

  Widget _buildAppIcon(String packageName, {double radius = 20, Color? bgColor}) {
    final bytes = _iconCache[packageName];
    if (bytes != null) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: MemoryImage(bytes),
        backgroundColor: Colors.transparent,
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: bgColor ?? Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        packageName.isNotEmpty ? packageName.split('.').last[0].toUpperCase() : '?',
        style: TextStyle(
          color: bgColor != null
              ? (ThemeData.estimateBrightnessForColor(bgColor) == Brightness.dark
                  ? Colors.white70
                  : Colors.black54)
              : Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Service Keeper'),
        actions: [
          if (_shizukuStatus == ShizukuStatus.ready)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Check statuses now',
              onPressed: _refreshStatuses,
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'backup') _backup();
              if (v == 'restore') _restore();
              if (v == 'app_colors') _toggleAppColors();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'backup', child: Text('Backup')),
              const PopupMenuItem(value: 'restore', child: Text('Restore')),
              CheckedPopupMenuItem(
                value: 'app_colors',
                checked: _useAppColors,
                child: const Text('Use app colors'),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              _buildShizukuBanner(),
              _buildBatteryBanner(),
              Expanded(
                child: _services.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _refreshStatuses,
                        child: ListView(
                          children: _groupedServices().map((group) {
                            final (pkg, appName, services) = group;
                            final allEnabled = services.every((s) => s.enabled);
                            final anyIssue =
                                services.any((s) => s.wasRunning == false && s.enabled);

                            // App color theming
                            final appColor = _useAppColors ? _appColorCache[pkg] : null;
                            final Color? headerFg = appColor == null
                                ? null
                                : (ThemeData.estimateBrightnessForColor(appColor) ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black87);
                            final Color? bodyBg = appColor == null
                                ? null
                                : Color.alphaBlend(
                                    appColor.withValues(alpha: isDark ? 0.22 : 0.10),
                                    isDark ? const Color(0xFF1C1C1C) : Colors.white,
                                  );

                            return Card(
                              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                              clipBehavior: Clip.antiAlias,
                              child: ExpansionTile(
                                key: PageStorageKey(pkg),
                                initiallyExpanded: false,
                                collapsedBackgroundColor: appColor,
                                backgroundColor: appColor,
                                collapsedIconColor: headerFg,
                                iconColor: headerFg,
                                leading: _buildAppIcon(pkg, bgColor: appColor),
                                title: Text(appName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: headerFg,
                                    )),
                                subtitle: Text(
                                  '${services.length} service${services.length == 1 ? '' : 's'} monitored',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: headerFg?.withValues(alpha: 0.75) ??
                                        Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (anyIssue)
                                      Icon(Icons.warning_amber,
                                          color: appColor != null ? headerFg : Colors.orange,
                                          size: 18),
                                    if (!anyIssue && allEnabled)
                                      Icon(Icons.check_circle,
                                          color: appColor != null ? headerFg : Colors.green,
                                          size: 18),
                                    PopupMenuButton<String>(
                                      icon: Icon(Icons.more_vert, size: 20, color: headerFg),
                                      padding: EdgeInsets.zero,
                                      onSelected: (v) {
                                        if (v == 'restart_all') _restartAll(services);
                                        if (v == 'view_history') _viewAppHistory(pkg, appName);
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                            value: 'restart_all', child: Text('Restart all')),
                                        PopupMenuItem(
                                            value: 'view_history', child: Text('View history')),
                                      ],
                                    ),
                                    Icon(Icons.expand_more, color: headerFg),
                                  ],
                                ),
                                children: services
                                    .map((s) => Container(
                                          color: bodyBg,
                                          child: ServiceTile(
                                            service: s,
                                            iconBytes: _iconCache[s.packageName],
                                            accentColor: appColor,
                                            onToggle: () => _toggleService(s),
                                            onConfigure: () => _configureService(s),
                                            onRemove: () => _removeService(s),
                                            onRestartNow: () => _restartNow(s),
                                            onCheckDue: () => _checkDue(s),
                                            onViewHistory: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => ServiceAuditScreen(service: s),
                                              ),
                                            ),
                                          ),
                                        ))
                                    .toList(),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
              ),
            ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _shizukuStatus == ShizukuStatus.ready ? _addService : _showShizukuWarning,
        icon: const Icon(Icons.add),
        label: const Text('Add Service'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings_suggest,
                size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('No services monitored', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Tap "Add Service" to browse running Android services '
              'and select which ones to keep alive.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
