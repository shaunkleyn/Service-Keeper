import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../models/monitored_service.dart';
import '../services/service_manager.dart';
import '../services/shizuku_service.dart';
import '../services/storage_service.dart';
import '../services/app_info_service.dart';
import '../widgets/service_tile.dart';
import 'service_picker_screen.dart';
import 'service_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _storage = StorageService();
  final _shizuku = ShizukuService();
  final _appInfo = AppInfoService();
  late final ServiceManager _manager;

  List<MonitoredService> _services = [];
  Map<String, Uint8List?> _iconCache = {};
  Map<String, String> _appNameCache = {};
  ShizukuStatus _shizukuStatus = ShizukuStatus.notInstalled;
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
    if (state == AppLifecycleState.resumed) _checkShizuku();
  }

  Future<void> _init() async {
    await _checkShizuku();
    await _loadServices();
    setState(() => _loading = false);
  }

  Future<void> _checkShizuku() async {
    final status = await _shizuku.checkStatus();
    setState(() => _shizukuStatus = status);
  }

  Future<void> _loadServices() async {
    final list = await _storage.loadServices();
    setState(() => _services = list);
    _fetchIconsAndNames(list);
  }

  Future<void> _fetchIconsAndNames(List<MonitoredService> services) async {
    final prefs = await SharedPreferences.getInstance();
    final packages = services.map((s) => s.packageName).toSet();

    // Icons — load from cache first, then fetch missing
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

    // App names — use stored appName if available, else fetch
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
  }

  Future<void> _refreshStatuses() async {
    if (_shizukuStatus != ShizukuStatus.ready) return;
    final updated = await Future.wait(
      _services.map((s) async {
        final running = await _manager.isServiceRunning(s);
        return s.copyWith(wasRunning: running, lastChecked: DateTime.now());
      }),
    );
    setState(() => _services = updated);
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
    await _loadServices();
  }

  Future<void> _restartNow(MonitoredService service) async {
    if (_shizukuStatus != ShizukuStatus.ready) { _showShizukuWarning(); return; }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Restarting ${service.displayLabel}...')),
    );
    final ok = await _manager.startService(service);
    final updated = service.copyWith(
      lastRestarted: ok ? DateTime.now() : service.lastRestarted,
      wasRunning: false,
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
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
          if (_shizukuStatus != ShizukuStatus.ready) ...[
            const Spacer(),
            Text('Tap to fix →', style: TextStyle(color: color, fontSize: 12)),
          ],
        ]),
      ),
    );
  }

  /// Group services by packageName, sorted by app name
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

  Widget _buildAppIcon(String packageName, {double radius = 20}) {
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
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        packageName.isNotEmpty ? packageName.split('.').last[0].toUpperCase() : '?',
        style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              _buildShizukuBanner(),
              Expanded(
                child: _services.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _refreshStatuses,
                        child: ListView(
                          children: _groupedServices().map((group) {
                            final (pkg, appName, services) = group;
                            final allEnabled = services.every((s) => s.enabled);
                            final anyIssue = services.any(
                                (s) => s.wasRunning == false && s.enabled);
                            return Card(
                              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                              clipBehavior: Clip.antiAlias,
                              child: ExpansionTile(
                                key: PageStorageKey(pkg),
                                initiallyExpanded: true,
                                leading: _buildAppIcon(pkg),
                                title: Text(appName,
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                  '${services.length} service${services.length == 1 ? '' : 's'} monitored',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (anyIssue)
                                      Icon(Icons.warning_amber,
                                          color: Colors.orange, size: 18),
                                    if (!anyIssue && allEnabled)
                                      Icon(Icons.check_circle,
                                          color: Colors.green, size: 18),
                                    const Icon(Icons.expand_more),
                                  ],
                                ),
                                children: services.map((s) => ServiceTile(
                                  service: s,
                                  iconBytes: _iconCache[s.packageName],
                                  onToggle: () => _toggleService(s),
                                  onConfigure: () => _configureService(s),
                                  onRemove: () => _removeService(s),
                                  onRestartNow: () => _restartNow(s),
                                )).toList(),
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
            Text('No services monitored',
                style: Theme.of(context).textTheme.headlineSmall),
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
