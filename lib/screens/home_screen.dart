import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
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
  final ShizukuStatus shizukuStatus;
  final Future<void> Function() onRequestShizukuPermission;
  final void Function({
    required VoidCallback refresh,
    required VoidCallback runMonitorNow,
    required VoidCallback checkStatuses,
    required VoidCallback addService,
  }) onRegister;

  const HomeScreen({
    super.key,
    required this.shizukuStatus,
    required this.onRequestShizukuPermission,
    required this.onRegister,
  });

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
  bool _useAppColors = false;
  bool _loading = true;
  final _expandedGroups = <String, bool>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _manager = ServiceManager(_shizuku);
    widget.onRegister(
      refresh: _reload,
      runMonitorNow: _runMonitorNow,
      checkStatuses: _refreshStatuses,
      addService: _addService,
    );
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadColorPreference();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadColorPreference();
      _loadServices();
    }
  }

  Future<void> _init() async {
    await _db.importPendingEvents();
    await _loadColorPreference();
    await _loadServices();
    await _system.rescheduleAllMonitorWork();
    setState(() => _loading = false);
  }

  Future<void> _reload() async {
    await _loadColorPreference();
    await _loadServices();
  }

  Future<void> _loadColorPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _useAppColors = prefs.getBool('use_app_colors') ?? false);
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
    final prefs = await SharedPreferences.getInstance();
    for (final pkg in _iconCache.keys) {
      if (_appColorCache.containsKey(pkg)) continue;
      final cached = prefs.getInt('app_color_v1_$pkg');
      if (cached != null && mounted) {
        setState(() => _appColorCache[pkg] = Color(cached));
      }
    }
    for (final pkg in _iconCache.keys) {
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
        if (color != null) {
          final cached = prefs.getInt('app_color_v1_$pkg');
          if (cached != color.toARGB32()) {
            await prefs.setInt('app_color_v1_$pkg', color.toARGB32());
          }
          if (mounted) setState(() => _appColorCache[pkg] = color);
        }
      } catch (_) {}
    }
  }

  Future<void> _refreshStatuses() async {
    if (widget.shizukuStatus != ShizukuStatus.ready) return;
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

  Future<void> _runMonitorNow() async {
    if (widget.shizukuStatus != ShizukuStatus.ready) {
      _showShizukuWarning();
      return;
    }
    final enabledCount = _services.where((s) => s.enabled).length;
    if (enabledCount == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('No enabled services to check')));
      }
      return;
    }
    final queued = await _system.runMonitorNowForAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Triggered monitor now for $queued service${queued == 1 ? '' : 's'}')),
    );
  }

  Future<void> _scheduleWork(MonitoredService service) async {
    if (!service.enabled) {
      Workmanager().cancelByTag(service.workTag);
      await _system.cancelMonitorWork(service.workTag);
      return;
    }

    await _system.scheduleMonitorWork(
      packageName: service.packageName,
      serviceClass: service.serviceClass,
      displayLabel: service.displayLabel,
      intervalMinutes: service.intervalMinutes,
    );

    Workmanager().cancelByTag(service.workTag);

    if (service.intervalMinutes >= 15) {
      await Workmanager().registerPeriodicTask(
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
      await Workmanager().registerOneOffTask(
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

    Workmanager().cancelByTag(service.workTag);
  }

  Future<void> _onServicePicked(MonitoredService result) async {
    final prefs = await SharedPreferences.getInstance();
    final defaultInterval = prefs.getInt('default_check_interval') ?? 15;
    final service = result.copyWith(intervalMinutes: defaultInterval);
    await _storage.addService(service);
    await _log(service, AuditEventType.added, AuditTrigger.manual);
    await _loadServices();
    await _scheduleWork(service);
  }

  Future<void> _addServiceForApp(String packageName) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServicePickerScreen(
          alreadyMonitored: _services,
          manager: _manager,
          initialQuery: packageName,
          onServiceAdded: _onServicePicked,
        ),
      ),
    );
  }

  Future<void> _addService() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServicePickerScreen(
          alreadyMonitored: _services,
          manager: _manager,
          onServiceAdded: _onServicePicked,
        ),
      ),
    );
  }

  Future<void> _configureService(MonitoredService service) async {
    final updated = await Navigator.push<MonitoredService>(
      context,
      MaterialPageRoute(builder: (_) => ServiceDetailScreen(service: service)),
    );
    if (updated == null) return;
    await _storage.updateService(updated);
    await _loadServices();
    await _scheduleWork(updated);
  }

  Future<void> _toggleService(MonitoredService service) async {
    final updated = service.copyWith(enabled: !service.enabled);
    await _storage.updateService(updated);
    await _log(updated, updated.enabled ? AuditEventType.enabled : AuditEventType.disabled,
        AuditTrigger.manual);
    await _loadServices();
    await _scheduleWork(updated);
  }

  Future<void> _removeService(MonitoredService service) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove service'),
        content: Text('Stop monitoring "${service.displayLabel}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    Workmanager().cancelByTag(service.workTag);
    await _system.cancelMonitorWork(service.workTag);
    await _storage.removeService(service);
    await _log(service, AuditEventType.removed, AuditTrigger.manual);
    await _loadServices();
  }

  Future<void> _restartNow(MonitoredService service) async {
    if (widget.shizukuStatus != ShizukuStatus.ready) {
      _showShizukuWarning();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Restarting ${service.displayLabel}...')),
    );
    await _log(service, AuditEventType.restartAttempted, AuditTrigger.manual);
    final (ok, detail) = await _manager.startService(service);
    await _log(service, ok ? AuditEventType.restartSuccess : AuditEventType.restartFailed,
        AuditTrigger.manual, notes: detail);
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

  DateTime _retryTime(MonitoredService service,
          [Duration delay = const Duration(seconds: 30)]) =>
      DateTime.now().subtract(Duration(minutes: service.intervalMinutes)).add(delay);

  Future<void> _checkDue(MonitoredService service) async {
    if (widget.shizukuStatus != ShizukuStatus.ready) return;

    final running = await _manager.isServiceRunning(service);

    if (running == null) {
      await _storage.updateService(service.copyWith(lastChecked: _retryTime(service)));
      await _loadServices();
      return;
    }

    if (running) {
      await _storage.updateService(
          service.copyWith(wasRunning: true, lastChecked: DateTime.now()));
      await _loadServices();
      return;
    }

    await _log(service, AuditEventType.detectedStopped, AuditTrigger.automatic);
    await _log(service, AuditEventType.restartAttempted, AuditTrigger.automatic);
    final (ok, detail) = await _manager.startService(service);

    if (!ok) {
      await _log(service, AuditEventType.restartFailed, AuditTrigger.automatic,
          notes: detail);
      await _storage.updateService(service.copyWith(
        wasRunning: false,
        lastChecked: _retryTime(service),
      ));
      await _loadServices();
      return;
    }

    await Future.delayed(const Duration(seconds: 3));
    final nowRunning = await _manager.isServiceRunning(service);

    if (nowRunning == true) {
      await _log(service, AuditEventType.restartSuccess, AuditTrigger.automatic,
          notes: detail);
      await _storage.updateService(service.copyWith(
        wasRunning: true,
        lastChecked: DateTime.now(),
        lastRestarted: DateTime.now(),
      ));
    } else {
      await _log(service, AuditEventType.restartFailed, AuditTrigger.automatic,
          notes: detail);
      await _storage.updateService(service.copyWith(
        wasRunning: false,
        lastChecked: _retryTime(service),
        lastRestarted: DateTime.now(),
      ));
    }
    await _loadServices();
  }

  Future<void> _restartAll(List<MonitoredService> services) async {
    if (widget.shizukuStatus != ShizukuStatus.ready) {
      _showShizukuWarning();
      return;
    }
    final enabled = services.where((s) => s.enabled).toList();
    if (enabled.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Restarting ${enabled.length} service${enabled.length == 1 ? '' : 's'}...')),
    );
    for (final s in enabled) {
      await _log(s, AuditEventType.restartAttempted, AuditTrigger.manual);
      final (ok, detail) = await _manager.startService(s);
      await _log(s, ok ? AuditEventType.restartSuccess : AuditEventType.restartFailed,
          AuditTrigger.manual, notes: detail);
      if (ok) {
        await _storage.updateService(
            s.copyWith(lastRestarted: DateTime.now(), wasRunning: true));
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
        builder: (_) =>
            ServiceAuditScreen.forApp(packageName: packageName, appName: appName),
      ),
    );
  }

  Future<void> _toggleAppNotifications(
      List<MonitoredService> services, String appName) async {
    final allOn = services.every((s) => s.notificationsEnabled);
    setState(() {
      _services = _services
          .map((s) => services.contains(s) ? s.copyWith(notificationsEnabled: !allOn) : s)
          .toList();
    });
    for (final s in services) {
      await _storage.updateService(s.copyWith(notificationsEnabled: !allOn));
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(allOn
            ? 'Notifications disabled for $appName'
            : 'Notifications enabled for $appName'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _toggleServiceNotification(MonitoredService service) async {
    final nowEnabled = !service.notificationsEnabled;
    final updated = service.copyWith(notificationsEnabled: nowEnabled);
    setState(() {
      _services = _services.map((s) => s == service ? updated : s).toList();
    });
    await _storage.updateService(updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(nowEnabled
            ? 'Notifications enabled for ${service.displayLabel}'
            : 'Notifications disabled for ${service.displayLabel}'),
        duration: const Duration(seconds: 2),
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
              await widget.onRequestShizukuPermission();
            },
            child: const Text('Grant Permission'),
          ),
        ],
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
      final sorted = [...e.value]
        ..sort((a, b) => a.displayLabel.toLowerCase().compareTo(b.displayLabel.toLowerCase()));
      return (e.key, name, sorted);
    }).toList();
    result.sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_services.isEmpty) return _buildEmptyState();
    return RefreshIndicator(
      onRefresh: _refreshStatuses,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          for (final (pkg, appName, services) in _groupedServices())
            SliverMainAxisGroup(
              slivers: [
                SliverPersistentHeader(
                  pinned: _expandedGroups[pkg] == true,
                  delegate: _GroupHeaderDelegate(
                    packageName: pkg,
                    appName: appName,
                    iconBytes: _iconCache[pkg],
                    services: services,
                    expanded: _expandedGroups[pkg] ?? false,
                    appColor: _useAppColors ? _appColorCache[pkg] : null,
                    onTap: () => setState(() {
                      _expandedGroups[pkg] = !(_expandedGroups[pkg] ?? false);
                    }),
                    onRestartAll: () => _restartAll(services),
                    onViewHistory: () => _viewAppHistory(pkg, appName),
                    onToggleNotifications: () =>
                        _toggleAppNotifications(services, appName),
                    notificationsEnabled: services.every((s) => s.notificationsEnabled),
                    onAddServices: () => _addServiceForApp(pkg),
                  ),
                ),
                if (_expandedGroups[pkg] == true)
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final s = services[i];
                        final tileTheme = Theme.of(ctx);
                        final isLast = i == services.length - 1;
                        final appColor = _useAppColors ? _appColorCache[pkg] : null;
                        final darkMode = tileTheme.brightness == Brightness.dark;
                        final bodyBg = appColor == null
                            ? tileTheme.colorScheme.surfaceContainerLow
                            : Color.alphaBlend(
                                appColor.withValues(alpha: darkMode ? 0.22 : 0.10),
                                darkMode ? const Color(0xFF1C1C1C) : Colors.white,
                              );
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: ClipRRect(
                            borderRadius: isLast
                                ? const BorderRadius.only(
                                    bottomLeft: Radius.circular(12),
                                    bottomRight: Radius.circular(12),
                                  )
                                : BorderRadius.zero,
                            child: ColoredBox(
                              color: bodyBg,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ServiceTile(
                                    service: s,
                                    showLeading: false,
                                    accentColor: appColor,
                                    onToggle: () => _toggleService(s),
                                    onConfigure: () => _configureService(s),
                                    onRemove: () => _removeService(s),
                                    onRestartNow: () => _restartNow(s),
                                    onCheckDue: () => _checkDue(s),
                                    onToggleNotifications: () =>
                                        _toggleServiceNotification(s),
                                    onViewHistory: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ServiceAuditScreen(service: s),
                                      ),
                                    ),
                                  ),
                                  if (!isLast)
                                    Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: tileTheme.colorScheme.outlineVariant
                                          .withValues(alpha: 0.5),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: services.length,
                    ),
                  ),
              ],
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
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

class _GroupHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String packageName;
  final String appName;
  final Uint8List? iconBytes;
  final List<MonitoredService> services;
  final bool expanded;
  final Color? appColor;
  final VoidCallback onTap;
  final VoidCallback onRestartAll;
  final VoidCallback onViewHistory;
  final VoidCallback onToggleNotifications;
  final bool notificationsEnabled;
  final VoidCallback onAddServices;

  const _GroupHeaderDelegate({
    required this.packageName,
    required this.appName,
    this.iconBytes,
    required this.services,
    required this.expanded,
    this.appColor,
    required this.onTap,
    required this.onRestartAll,
    required this.onViewHistory,
    required this.onToggleNotifications,
    required this.notificationsEnabled,
    required this.onAddServices,
  });

  @override
  double get minExtent => 80;
  @override
  double get maxExtent => 80;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    final anyIssue = services.any((s) => s.wasRunning == false && s.enabled);
    final allEnabled = services.every((s) => s.enabled);

    final Color? headerFg = appColor == null
        ? null
        : (ThemeData.estimateBrightnessForColor(appColor!) == Brightness.dark
            ? Colors.white
            : Colors.black87);

    final bgColor = appColor ?? theme.colorScheme.surfaceContainerHighest;
    final fg = headerFg ?? theme.colorScheme.onSurface;

    final cardRadius = BorderRadius.only(
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: expanded ? Radius.zero : const Radius.circular(12),
      bottomRight: expanded ? Radius.zero : const Radius.circular(12),
    );

    final Widget icon;
    if (iconBytes != null) {
      icon = CircleAvatar(
        radius: 20,
        backgroundImage: MemoryImage(iconBytes!),
        backgroundColor: Colors.transparent,
      );
    } else {
      icon = CircleAvatar(
        radius: 20,
        backgroundColor: appColor ?? theme.colorScheme.primaryContainer,
        child: Text(
          packageName.isNotEmpty ? packageName.split('.').last[0].toUpperCase() : '?',
          style: TextStyle(color: headerFg ?? theme.colorScheme.onPrimaryContainer),
        ),
      );
    }

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          color: bgColor,
          borderRadius: cardRadius,
          elevation: overlapsContent ? 4 : 1,
          shadowColor: Colors.black26,
          child: InkWell(
            borderRadius: cardRadius,
            onTap: onTap,
            child: SizedBox(
              height: 72,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    icon,
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: fg,
                            ),
                          ),
                          Text(
                            '${services.length} service${services.length == 1 ? '' : 's'} monitored',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                              color: headerFg?.withValues(alpha: 0.75) ??
                                  theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (anyIssue)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.warning_amber,
                            color: appColor != null ? fg : Colors.orange, size: 18),
                      ),
                    if (!anyIssue && allEnabled)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.check_circle,
                            color: appColor != null ? fg : Colors.green, size: 18),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        notificationsEnabled ? Icons.notifications : Icons.notifications_off,
                        size: 18,
                        color: notificationsEnabled
                            ? (appColor != null ? fg : theme.colorScheme.primary)
                            : (appColor != null
                                ? fg.withValues(alpha: 0.45)
                                : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, size: 20, color: fg),
                      padding: EdgeInsets.zero,
                      onSelected: (v) {
                        if (v == 'add_services') onAddServices();
                        if (v == 'restart_all') onRestartAll();
                        if (v == 'view_history') onViewHistory();
                        if (v == 'toggle_notifications') onToggleNotifications();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'add_services', child: Text('Add services')),
                        const PopupMenuItem(value: 'restart_all', child: Text('Restart all')),
                        const PopupMenuItem(value: 'view_history', child: Text('View history')),
                        PopupMenuItem(
                          value: 'toggle_notifications',
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Notifications'),
                              IgnorePointer(
                                child: Transform.scale(
                                  scale: 0.8,
                                  alignment: Alignment.centerRight,
                                  child: Switch(value: notificationsEnabled, onChanged: (_) {}),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.expand_more, color: fg),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_GroupHeaderDelegate old) =>
      old.expanded != expanded ||
      old.appColor != appColor ||
      old.iconBytes != iconBytes ||
      old.services != services ||
      old.notificationsEnabled != notificationsEnabled ||
      old.onAddServices != onAddServices;
}
