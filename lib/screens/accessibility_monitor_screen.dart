import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:service_keeper/widgets/page_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_info_service.dart';
import '../services/database_service.dart';
import '../services/diagnostics_service.dart';
import '../services/shizuku_service.dart';
import '../services/storage_service.dart';
import '../services/system_service.dart';
import 'service_audit_screen.dart';

class AccessibilityMonitorScreen extends StatefulWidget {
  final void Function(VoidCallback refresh) onRegisterRefresh;
  final PageController? pageController;

  const AccessibilityMonitorScreen({
    super.key,
    required this.onRegisterRefresh,
    this.pageController,
  });

  @override
  State<AccessibilityMonitorScreen> createState() =>
      _AccessibilityMonitorScreenState();
}

class _AccessibilityMonitorScreenState extends State<AccessibilityMonitorScreen>
    with WidgetsBindingObserver {
  final _appInfo = AppInfoService();
  final _db = DatabaseService();
  final _shizuku = ShizukuService();
  final _storage = StorageService();
  final _system = SystemService();

  List<({String packageName, String serviceClass, String appName, bool exported, String permission})>
      _a11yServices = [];
  Set<String> _enabledKeys = {};
  Set<String> _monitoredKeys = {};
  Set<String> _notifOffKeys = {};
  Map<String, Uint8List?> _iconCache = {};
  Map<String, Color> _colorCache = {};
  Map<String, bool> _expandedGroups = {};
  bool _useAppColors = false;
  bool _loading = true;
  bool _permInfoDismissed = false;
  bool _revokeBannerDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.onRegisterRefresh(_load);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshEnabledState();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _useAppColors = prefs.getBool('use_app_colors') ?? false;

    final all = await _appInfo.getInstalledServices();
    final a11y = all
        .where((s) => s.permission == 'android.permission.BIND_ACCESSIBILITY_SERVICE')
        .toList();

    final enabled = await _system.getEnabledAccessibilityServices();
    var monKeys = await _storage.loadA11yMonitoredKeys();
    final notifOff = await _storage.loadA11yNotifOffKeys();

    final newKeys = enabled
        .where((k) =>
            !monKeys.contains(k) && a11y.any((s) => '${s.packageName}/${s.serviceClass}' == k))
        .toSet();
    if (newKeys.isNotEmpty) {
      monKeys = {...monKeys, ...newKeys};
      for (final k in newKeys) {
        final slash = k.indexOf('/');
        if (slash >= 0) {
          await _storage.addA11yMonitored(k.substring(0, slash), k.substring(slash + 1));
        }
      }
    }

    final validKeys = a11y.map((s) => '${s.packageName}/${s.serviceClass}').toSet();
    final staleKeys = monKeys.where((k) => !validKeys.contains(k)).toSet();
    if (staleKeys.isNotEmpty) {
      monKeys = monKeys.difference(staleKeys);
      for (final k in staleKeys) {
        final slash = k.indexOf('/');
        if (slash >= 0) {
          await _storage.removeA11yMonitored(k.substring(0, slash), k.substring(slash + 1));
        }
      }
    }

    if (mounted) {
      setState(() {
        _a11yServices = a11y;
        _enabledKeys = enabled;
        _monitoredKeys = monKeys;
        _notifOffKeys = notifOff;
        _permInfoDismissed = prefs.getBool('a11y_perm_info_dismissed') ?? false;
        _revokeBannerDismissed = prefs.getBool('a11y_revoke_banner_dismissed') ?? false;
        _loading = false;
        for (final s in a11y) {
          _expandedGroups.putIfAbsent(s.packageName, () => false);
        }
      });
    }
    await _fetchIcons(a11y.map((s) => s.packageName).toSet());
    if (_useAppColors) _generateColors();
  }

  Future<void> _refreshEnabledState() async {
    final prev = Set<String>.from(_enabledKeys);
    final enabled = await _system.getEnabledAccessibilityServices();
    if (!mounted) return;
    final newlyEnabled = enabled
        .difference(prev)
        .where((k) => _a11yServices.any((s) => '${s.packageName}/${s.serviceClass}' == k))
        .toSet();
    final revoked = prev.difference(enabled).where(_monitoredKeys.contains).toSet();
    setState(() {
      _enabledKeys = enabled;
      if (newlyEnabled.isNotEmpty) _monitoredKeys = {..._monitoredKeys, ...newlyEnabled};
      if (revoked.isNotEmpty) _monitoredKeys = Set.from(_monitoredKeys)..removeAll(revoked);
    });
    for (final k in newlyEnabled) {
      final slash = k.indexOf('/');
      if (slash >= 0) await _storage.addA11yMonitored(k.substring(0, slash), k.substring(slash + 1));
    }
    for (final k in revoked) {
      final slash = k.indexOf('/');
      if (slash >= 0) await _storage.removeA11yMonitored(k.substring(0, slash), k.substring(slash + 1));
    }
  }

  Future<void> _fetchIcons(Set<String> packages) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = <String, Uint8List?>{};
    for (final pkg in packages) {
      final b64 = prefs.getString('app_icon_v1_$pkg');
      if (b64 != null) cached[pkg] = base64Decode(b64);
    }
    if (mounted && cached.isNotEmpty) setState(() => _iconCache = {..._iconCache, ...cached});

    final missing = packages.where((p) => !cached.containsKey(p)).toSet();
    for (final pkg in missing) {
      final bytes = await _appInfo.getAppIcon(pkg);
      if (bytes != null) {
        await prefs.setString('app_icon_v1_$pkg', base64Encode(bytes));
        if (mounted) setState(() => _iconCache[pkg] = bytes);
      }
    }
    if (_useAppColors) _generateColors();
  }

  Future<void> _generateColors() async {
    final prefs = await SharedPreferences.getInstance();
    for (final pkg in _iconCache.keys) {
      if (_colorCache.containsKey(pkg)) continue;
      final cached = prefs.getInt('app_color_v1_$pkg');
      if (cached != null && mounted) {
        setState(() => _colorCache[pkg] = Color(cached));
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
          if (mounted) setState(() => _colorCache[pkg] = color);
        }
      } catch (_) {}
    }
  }

  Future<void> _toggle(String packageName, String serviceClass, String appName) async {
    final key = '$packageName/$serviceClass';
    final nowMonitored = !_monitoredKeys.contains(key);
    setState(() {
      if (nowMonitored)
        _monitoredKeys.add(key);
      else
        _monitoredKeys.remove(key);
    });
    if (nowMonitored) {
      await _storage.addA11yMonitored(packageName, serviceClass);
    } else {
      await _storage.removeA11yMonitored(packageName, serviceClass);
    }
    if (mounted) {
      final label = serviceClass.split('.').last;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(nowMonitored ? 'Now monitoring $label' : 'Stopped monitoring $label'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _toggleAll(
      String packageName, List<({String serviceClass, String appName})> services) async {
    final allOn =
        services.every((s) => _monitoredKeys.contains('$packageName/${s.serviceClass}'));
    final applicable = allOn
        ? services
        : services
            .where((s) => _enabledKeys.contains('$packageName/${s.serviceClass}'))
            .toList();
    if (!allOn && applicable.isEmpty) {
      _showPermissionRequiredDialog(
          packageName, services.first.serviceClass, services.first.appName);
      return;
    }
    setState(() {
      for (final s in applicable) {
        final key = '$packageName/${s.serviceClass}';
        if (allOn)
          _monitoredKeys.remove(key);
        else
          _monitoredKeys.add(key);
      }
    });
    for (final s in applicable) {
      if (allOn) {
        await _storage.removeA11yMonitored(packageName, s.serviceClass);
      } else {
        await _storage.addA11yMonitored(packageName, s.serviceClass);
      }
    }
  }

  Future<void> _showPermissionRequiredDialog(
      String packageName, String serviceClass, String appName) async {
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permission Required'),
        content: Text(
          '$appName needs its Accessibility Service permission granted in Android Settings '
          'before Service Keeper can monitor it.\n\nOpen Android Settings now?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open Settings')),
        ],
      ),
    );
    if (result == true && mounted) {
      await _system.openAccessibilitySettings(
          packageName: packageName, serviceClass: serviceClass);
    }
  }
 
  Widget _buildDismissableBanner({
    required bool dismissed,
    required String text,
    required VoidCallback onDismiss,
    IconData icon = Icons.info_outline,
  }) {
    if (dismissed) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.primaryContainer.withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Icon(icon, size: 14, color: cs.onPrimaryContainer),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer))),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onDismiss,
          child: Icon(Icons.close, size: 16, color: cs.onPrimaryContainer),
        ),
      ]),
    );
  }

  Future<void> _toggleAppNotif(
      String packageName, List<({String serviceClass, String appName})> services) async {
    final allOn =
        services.every((s) => !_notifOffKeys.contains('$packageName/${s.serviceClass}'));
    setState(() {
      for (final s in services) {
        final key = '$packageName/${s.serviceClass}';
        if (allOn)
          _notifOffKeys.add(key);
        else
          _notifOffKeys.remove(key);
      }
    });
    for (final s in services) {
      if (allOn) {
        await _storage.setA11yNotifOff(packageName, s.serviceClass);
      } else {
        await _storage.clearA11yNotifOff(packageName, s.serviceClass);
      }
    }
  }

  Future<void> _reportServiceIssue(
    String packageName,
    String appName,
    String serviceClass,
  ) async {
    if (!mounted) return;
    final diag = DiagnosticsService(_shizuku, _db);
    var loadingOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text('Gathering diagnostics...'),
        ]),
      ),
    );

    try {
      final key = '$packageName/$serviceClass';
      final body = await diag.buildExternalServiceReport(
        reportType: 'Accessibility Service',
        packageName: packageName,
        appName: appName,
        serviceClass: serviceClass,
        isMonitored: _monitoredKeys.contains(key),
        isEnabled: _enabledKeys.contains(key),
        notificationsEnabled: !_notifOffKeys.contains(key),
      );
      if (!mounted) return;
      if (loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }
      final label = serviceClass.split('.').last;
      final title = 'Accessibility service issue: $label ($packageName)';
      await DiagnosticsService.openGitHubIssue(context, title: title, body: body);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate diagnostics: $e')),
        );
      }
    } finally {
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<void> _reportAppIssue(
    String packageName,
    String appName,
    List<({String serviceClass, String appName})> services,
  ) async {
    if (!mounted) return;
    final diag = DiagnosticsService(_shizuku, _db);
    var loadingOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text('Gathering diagnostics...'),
        ]),
      ),
    );

    try {
      final snapshots = services.map((svc) {
        final key = '$packageName/${svc.serviceClass}';
        return DiagnosticsReportService(
          displayLabel: svc.serviceClass.split('.').last,
          serviceClass: svc.serviceClass,
          isMonitored: _monitoredKeys.contains(key),
          isEnabled: _enabledKeys.contains(key),
          notificationsEnabled: !_notifOffKeys.contains(key),
        );
      }).toList();

      final body = await diag.buildExternalAppReport(
        reportType: 'Accessibility Services',
        packageName: packageName,
        appName: appName,
        services: snapshots,
      );

      if (!mounted) return;
      if (loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }
      final title = 'Accessibility services issue: $appName ($packageName)';
      await DiagnosticsService.openGitHubIssue(context, title: title, body: body);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate diagnostics: $e')),
        );
      }
    } finally {
      if (mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Map<String, List<({String serviceClass, String appName})>> _grouped() {
    final groups = <String, List<({String serviceClass, String appName})>>{};
    for (final s in _a11yServices) {
      groups.putIfAbsent(s.packageName, () => []).add((
        serviceClass: s.serviceClass,
        appName: s.appName,
      ));
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _grouped();
    final pkgs = groups.keys.toList()
      ..sort((a, b) {
        final an = groups[a]!.first.appName.toLowerCase();
        final bn = groups[b]!.first.appName.toLowerCase();
        return an.compareTo(bn);
      });

    if (_loading) return const Center(child: CircularProgressIndicator());

    final pc = widget.pageController;
    final bannersContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PageBanner(
          pref: 'a11y_perm_info_dismissed',
          dismissed: _permInfoDismissed,
          text: 'The apps listed here support Accessibility Services. '
              'Before Service Keeper can monitor one, its permission must be granted in Android Settings.',
          onDismiss: () async {
            if (mounted) setState(() => _permInfoDismissed = true);
          },
          icon: Icons.lock_open,
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
          textColor: Theme.of(context).colorScheme.onSecondaryContainer,
          pageIndex: 1,
          pageController: widget.pageController,
        ),
        PageBanner(
          pref: 'a11y_revoke_banner_dismissed',
          dismissed: _revokeBannerDismissed,
          text: 'Disabling monitoring here does not revoke the app\'s Android accessibility permission. '
              'To revoke, go to Android Settings.',
          onDismiss: () async {
            if (mounted) setState(() => _revokeBannerDismissed = true);
          },
          icon: Icons.lock_open,
          color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.4),
          textColor: Theme.of(context).colorScheme.onSecondaryContainer,
          pageIndex: 1,
          pageController: widget.pageController,
        ),
      ],
    );

    return Column(
      children: [
          bannersContent,
        Expanded(
          child: pkgs.isEmpty
              ? const Center(child: Text('No third-party accessibility services found.'))
              : CustomScrollView(
                  slivers: [
                    for (final pkg in pkgs)
                      SliverMainAxisGroup(
                        slivers: [
                          SliverPersistentHeader(
                            pinned: _expandedGroups[pkg] == true,
                            delegate: _A11yGroupHeaderDelegate(
                              packageName: pkg,
                              appName: groups[pkg]!.first.appName,
                              iconBytes: _iconCache[pkg],
                              services: groups[pkg]!,
                              enabledKeys: _enabledKeys,
                              monitoredKeys: _monitoredKeys,
                              notifOffKeys: _notifOffKeys,
                              expanded: _expandedGroups[pkg] ?? false,
                              appColor: _useAppColors ? _colorCache[pkg] : null,
                              onTap: () => setState(() {
                                _expandedGroups[pkg] = !(_expandedGroups[pkg] ?? false);
                              }),
                              onToggleAll: () => _toggleAll(pkg, groups[pkg]!),
                              onToggleNotif: () => _toggleAppNotif(pkg, groups[pkg]!),
                              onOpenHistory: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ServiceAuditScreen.forApp(
                                    packageName: pkg,
                                    appName: groups[pkg]!.first.appName,
                                  ),
                                ),
                              ),
                              onReportIssue: () =>
                                  _reportAppIssue(pkg, groups[pkg]!.first.appName, groups[pkg]!),
                              onManagePermission: () =>
                                  _system.openAccessibilitySettings(packageName: pkg),
                            ),
                          ),
                          if (_expandedGroups[pkg] == true)
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                childCount: groups[pkg]!.length,
                                (ctx, i) {
                                  final svc = groups[pkg]![i];
                                  final key = '$pkg/${svc.serviceClass}';
                                  final enabled = _enabledKeys.contains(key);
                                  final monitored = _monitoredKeys.contains(key);
                                  final isLast = i == groups[pkg]!.length - 1;
                                  final tileTheme = Theme.of(ctx);
                                  final appColor = _useAppColors ? _colorCache[pkg] : null;
                                  final dark = tileTheme.brightness == Brightness.dark;
                                  final bodyBg = appColor == null
                                      ? tileTheme.colorScheme.surfaceContainerLow
                                      : Color.alphaBlend(
                                          appColor.withValues(alpha: dark ? 0.22 : 0.10),
                                          dark ? const Color(0xFF1C1C1C) : Colors.white,
                                        );

                                  return Padding(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 12),
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
                                            ListTile(
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16, vertical: 2),
                                              title: Text(
                                                svc.serviceClass.split('.').last,
                                                style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w500),
                                              ),
                                              subtitle: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    svc.serviceClass,
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: tileTheme.colorScheme
                                                            .onSurfaceVariant),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  _StatusChip(enabled: enabled),
                                                ],
                                              ),
                                              trailing: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    _notifOffKeys.contains(key)
                                                        ? Icons.notifications_off
                                                        : Icons.notifications,
                                                    size: 16,
                                                    color: _notifOffKeys.contains(key)
                                                        ? tileTheme.colorScheme
                                                            .onSurfaceVariant
                                                            .withValues(alpha: 0.4)
                                                        : (appColor ??
                                                            tileTheme.colorScheme.primary),
                                                  ),
                                                  Opacity(
                                                    opacity: enabled ? 1.0 : 0.45,
                                                    child: Transform.scale(
                                                      scale: 0.8,
                                                      alignment: Alignment.centerRight,
                                                      child: Switch(
                                                        value: monitored,
                                                        thumbColor: WidgetStateProperty.resolveWith(
                                                            (s) => s.contains(WidgetState.selected) ? appColor : null),
                                                        trackColor: WidgetStateProperty.resolveWith(
                                                            (s) => s.contains(WidgetState.selected) ? appColor?.withValues(alpha: 0.5) : null),
                                                        onChanged: (_) {
                                                          if (!enabled) {
                                                            _showPermissionRequiredDialog(pkg, svc.serviceClass, svc.appName);
                                                          } else {
                                                            _toggle(pkg, svc.serviceClass, svc.appName);
                                                          }
                                                        },
                                                      ),
                                                    ),
                                                  ),
                                                  PopupMenuButton<String>(
                                                    icon: Icon(Icons.more_vert,
                                                        size: 18,
                                                        color: tileTheme
                                                            .colorScheme.onSurfaceVariant),
                                                    padding: EdgeInsets.zero,
                                                    onSelected: (v) {
                                                      if (v == 'history') {
                                                        Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (_) =>
                                                                ServiceAuditScreen
                                                                    .forAccessibility(
                                                              packageName: pkg,
                                                              serviceClass:
                                                                  svc.serviceClass,
                                                              appName: svc.appName,
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                      if (v == 'manage_permission') {
                                                        _system.openAccessibilitySettings(
                                                            packageName: pkg,
                                                            serviceClass: svc.serviceClass);
                                                      }
                                                      if (v == 'report_issue') {
                                                        _reportServiceIssue(
                                                          pkg,
                                                          svc.appName,
                                                          svc.serviceClass,
                                                        );
                                                      }
                                                    },
                                                    itemBuilder: (_) => [
                                                      const PopupMenuItem(
                                                        value: 'history',
                                                        child: Row(children: [
                                                          Icon(Icons.history, size: 18),
                                                          SizedBox(width: 8),
                                                          Text('History'),
                                                        ]),
                                                      ),
                                                      const PopupMenuItem(
                                                        value: 'manage_permission',
                                                        child: Row(children: [
                                                          Icon(Icons.security_outlined, size: 18),
                                                          SizedBox(width: 8),
                                                          Text('Manage permission'),
                                                        ]),
                                                      ),
                                                      const PopupMenuDivider(),
                                                      const PopupMenuItem(
                                                        value: 'report_issue',
                                                        child: Row(children: [
                                                          Icon(Icons.bug_report_outlined, size: 18),
                                                          SizedBox(width: 8),
                                                          Text('Report Issue'),
                                                        ]),
                                                      ),
                                                    ],
                                                  ),
                                                ],
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
                              ),
                            ),
                        ],
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                ),
        ),
      ],
    );
  }
}

class _A11yGroupHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String packageName;
  final String appName;
  final Uint8List? iconBytes;
  final List<({String serviceClass, String appName})> services;
  final Set<String> enabledKeys;
  final Set<String> monitoredKeys;
  final Set<String> notifOffKeys;
  final bool expanded;
  final Color? appColor;
  final VoidCallback onTap;
  final VoidCallback onToggleAll;
  final VoidCallback onToggleNotif;
  final VoidCallback onOpenHistory;
  final VoidCallback onReportIssue;
  final VoidCallback onManagePermission;

  const _A11yGroupHeaderDelegate({
    required this.packageName,
    required this.appName,
    this.iconBytes,
    required this.services,
    required this.enabledKeys,
    required this.monitoredKeys,
    required this.notifOffKeys,
    required this.expanded,
    this.appColor,
    required this.onTap,
    required this.onToggleAll,
    required this.onToggleNotif,
    required this.onOpenHistory,
    required this.onReportIssue,
    required this.onManagePermission,
  });

  @override
  double get minExtent => 80;
  @override
  double get maxExtent => 80;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);

    final Color? headerFg = appColor == null
        ? null
        : (ThemeData.estimateBrightnessForColor(appColor!) == Brightness.dark
            ? Colors.white
            : Colors.black87);

    final bgColor = appColor ?? theme.colorScheme.surfaceContainerHighest;
    final fg = headerFg ?? theme.colorScheme.onSurface;

    final allMonitored =
        services.every((s) => monitoredKeys.contains('$packageName/${s.serviceClass}'));
    final notifEnabled =
        services.every((s) => !notifOffKeys.contains('$packageName/${s.serviceClass}'));
    final monitoredCount =
        services.where((s) => monitoredKeys.contains('$packageName/${s.serviceClass}')).length;
    final activeMonitored = services
        .where((s) =>
            monitoredKeys.contains('$packageName/${s.serviceClass}') &&
            enabledKeys.contains('$packageName/${s.serviceClass}'))
        .length;
    final hasIssue = monitoredCount > 0 && activeMonitored < monitoredCount;

    final cardRadius = BorderRadius.only(
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: expanded ? Radius.zero : const Radius.circular(12),
      bottomRight: expanded ? Radius.zero : const Radius.circular(12),
    );

    final Widget avatarWidget;
    if (iconBytes != null) {
      avatarWidget = CircleAvatar(
        radius: 20,
        backgroundImage: MemoryImage(iconBytes!),
        backgroundColor: Colors.transparent,
      );
    } else {
      avatarWidget = CircleAvatar(
        radius: 20,
        backgroundColor: appColor ?? theme.colorScheme.primaryContainer,
        child: Text(
          packageName.isNotEmpty ? packageName.split('.').last[0].toUpperCase() : '?',
          style: TextStyle(color: headerFg ?? theme.colorScheme.onPrimaryContainer),
        ),
      );
    }

    final subtitle = monitoredCount == 0
        ? '${services.length} service${services.length == 1 ? '' : 's'}'
        : '$monitoredCount monitored · $activeMonitored active';

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
                    avatarWidget,
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
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                              color: headerFg?.withValues(alpha: 0.75) ??
                                  theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasIssue)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.warning_amber,
                            color: appColor != null ? fg : Colors.orange, size: 18),
                      ),
                    Transform.scale(
                      scale: 0.75,
                      alignment: Alignment.centerRight,
                      child: Switch(
                        value: allMonitored,
                        thumbColor: WidgetStateProperty.resolveWith(
                            (s) => s.contains(WidgetState.selected) && appColor != null ? fg : null),
                        trackColor: WidgetStateProperty.resolveWith(
                            (s) => s.contains(WidgetState.selected) && appColor != null ? fg.withValues(alpha: 0.4) : null),
                        onChanged: (_) => onToggleAll(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(
                        notifEnabled ? Icons.notifications : Icons.notifications_off,
                        size: 16,
                        color: notifEnabled ? fg : fg.withValues(alpha: 0.35),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, size: 20, color: fg),
                      padding: EdgeInsets.zero,
                      onSelected: (v) {
                        if (v == 'toggle_notif') {
                          onToggleNotif();
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(notifEnabled
                                ? 'Notifications disabled'
                                : 'Notifications enabled'),
                            duration: const Duration(seconds: 2),
                          ));
                        } else if (v == 'history') {
                          onOpenHistory();
                        } else if (v == 'manage_permission') {
                          onManagePermission();
                        } else if (v == 'report_issue') {
                          onReportIssue();
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'toggle_notif',
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Notifications'),
                              IgnorePointer(
                                child: Transform.scale(
                                  scale: 0.8,
                                  alignment: Alignment.centerRight,
                                  child: Switch(value: notifEnabled, onChanged: (_) {}),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'history',
                          child: Row(children: [
                            Icon(Icons.history, size: 18),
                            SizedBox(width: 8),
                            Text('History'),
                          ]),
                        ),
                        const PopupMenuItem(
                          value: 'manage_permission',
                          child: Row(children: [
                            Icon(Icons.security_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Manage permission'),
                          ]),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'report_issue',
                          child: Row(children: [
                            Icon(Icons.bug_report_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Report Issue'),
                          ]),
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
  bool shouldRebuild(_A11yGroupHeaderDelegate old) =>
      old.expanded != expanded ||
      old.appColor != appColor ||
      old.iconBytes != iconBytes ||
      old.enabledKeys != enabledKeys ||
      old.monitoredKeys != monitoredKeys ||
      old.notifOffKeys != notifOffKeys ||
      old.onToggleAll != onToggleAll ||
      old.onToggleNotif != onToggleNotif ||
      old.onReportIssue != onReportIssue ||
      old.onManagePermission != onManagePermission;
}

class _StatusChip extends StatelessWidget {
  final bool enabled;

  const _StatusChip({required this.enabled});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const activeColor = Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (enabled ? activeColor : cs.surfaceContainerHighest).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(enabled ? Icons.check_circle : Icons.cancel,
            size: 11, color: enabled ? activeColor : cs.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          enabled ? 'Active' : 'Inactive',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: enabled ? activeColor : cs.onSurfaceVariant,
          ),
        ),
      ]),
    );
  }
}
