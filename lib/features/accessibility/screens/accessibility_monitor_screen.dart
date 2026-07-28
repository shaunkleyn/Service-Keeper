import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:service_keeper/core/services/app_info_service.dart';
import 'package:service_keeper/core/theme/app_spacing.dart';
import 'package:service_keeper/core/theme/app_text_styles.dart';
import 'package:service_keeper/core/theme/app_theme.dart';
import 'package:service_keeper/core/services/database_service.dart';
import 'package:service_keeper/core/services/diagnostics_service.dart';
import 'package:service_keeper/core/services/shizuku_service.dart';
import 'package:service_keeper/core/services/storage_service.dart';
import 'package:service_keeper/core/services/system_service.dart';
import 'package:service_keeper/core/widgets/monitor_screen_mixin.dart';
import 'package:service_keeper/core/widgets/page_banner.dart';
import 'package:service_keeper/core/widgets/undo_snack_bar.dart';
import 'package:service_keeper/features/services/screens/service_audit_screen.dart';
import 'package:service_keeper/features/services/widgets/app_group_card.dart';

class AccessibilityMonitorScreen extends StatefulWidget {
  final void Function(VoidCallback refresh) onRegisterRefresh;
  final PageController? pageController;
  final void Function(String? label, VoidCallback? action)? onUndoChange;

  const AccessibilityMonitorScreen({
    super.key,
    required this.onRegisterRefresh,
    this.pageController,
    this.onUndoChange,
  });

  @override
  State<AccessibilityMonitorScreen> createState() =>
      _AccessibilityMonitorScreenState();
}

class _AccessibilityMonitorScreenState extends State<AccessibilityMonitorScreen>
    with WidgetsBindingObserver, MonitorScreenMixin {
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initMonitorScreen();
    widget.onRegisterRefresh(_load);
    _load();
  }

  @override
  void dispose() {
    disposeMonitorScreen();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void onColorfulCardsToggled() {
    if (useAppColors) generateColors();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshEnabledState();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final prefs = await SharedPreferences.getInstance();
    useAppColors = prefs.getBool('use_app_colors') ?? false;

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
        permInfoDismissed = prefs.getBool('a11y_perm_info_dismissed') ?? false;
        revokeBannerDismissed = prefs.getBool('a11y_revoke_banner_dismissed') ?? false;
        loading = false;
        for (final pkg in a11y.map((s) => s.packageName).toSet()) {
          expandedGroups.putIfAbsent(pkg, () => false);
        }
      });
    }
    await fetchIcons(a11y.map((s) => s.packageName).toSet());
    if (useAppColors) generateColors();
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

  Future<void> _setGroupState(
      String packageName,
      List<({String serviceClass, String appName})> services,
      int state) async {
    final prevMonitored = Set<String>.from(_monitoredKeys);
    final prevNotifOff = Set<String>.from(_notifOffKeys);

    if (state == 0) {
      setState(() {
        for (final s in services) {
          final key = '$packageName/${s.serviceClass}';
          _monitoredKeys.remove(key);
          _notifOffKeys.add(key);
        }
      });
      for (final s in services) {
        await _storage.removeA11yMonitored(packageName, s.serviceClass);
        await _storage.setA11yNotifOff(packageName, s.serviceClass);
      }
    } else {
      final applicable = services
          .where((s) => _enabledKeys.contains('$packageName/${s.serviceClass}'))
          .toList();
      final alreadyMonitored = services
          .where((s) => _monitoredKeys.contains('$packageName/${s.serviceClass}'))
          .toList();
      if (applicable.isEmpty && alreadyMonitored.isEmpty) {
        await _showPermissionRequiredDialog(
            packageName, services.first.serviceClass, services.first.appName);
        if (mounted) setState(() {});
        return;
      }
      setState(() {
        for (final s in applicable) {
          _monitoredKeys.add('$packageName/${s.serviceClass}');
        }
        for (final s in services) {
          final key = '$packageName/${s.serviceClass}';
          if (state == 1) {
            _notifOffKeys.add(key);
          } else {
            _notifOffKeys.remove(key);
          }
        }
      });
      for (final s in applicable) {
        await _storage.addA11yMonitored(packageName, s.serviceClass);
      }
      for (final s in services) {
        if (state == 1) {
          await _storage.setA11yNotifOff(packageName, s.serviceClass);
        } else {
          await _storage.clearA11yNotifOff(packageName, s.serviceClass);
        }
      }
    }
    if (!mounted) return;
    final appName = services.first.appName;
    final label = state == 0 ? 'Disabled' : state == 1 ? 'Monitor' : 'Notify';
    final message = '$appName: $label';

    Future<void> undoFn() async {
      setState(() {
        _monitoredKeys = prevMonitored;
        _notifOffKeys = prevNotifOff;
      });
      for (final s in services) {
        final key = '$packageName/${s.serviceClass}';
        if (prevMonitored.contains(key)) {
          await _storage.addA11yMonitored(packageName, s.serviceClass);
        } else {
          await _storage.removeA11yMonitored(packageName, s.serviceClass);
        }
        if (prevNotifOff.contains(key)) {
          await _storage.setA11yNotifOff(packageName, s.serviceClass);
        } else {
          await _storage.clearA11yNotifOff(packageName, s.serviceClass);
        }
      }
      widget.onUndoChange?.call(null, null);
    }

    widget.onUndoChange?.call(message, undoFn);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(buildUndoSnackBar(message: message, onUndo: undoFn));
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

    if (loading) return const Center(child: CircularProgressIndicator());

    final bannersContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PageBanner(
          pref: 'a11y_perm_info_dismissed',
          dismissed: permInfoDismissed,
          text: 'The apps listed here support Accessibility Services. '
              'Before Service Keeper can monitor one, its permission must be granted in Android Settings.',
          onDismiss: () async {
            if (mounted) setState(() => permInfoDismissed = true);
          },
          icon: Icons.lock_open,
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
          textColor: Theme.of(context).colorScheme.onSecondaryContainer,
          pageIndex: 1,
          pageController: widget.pageController,
        ),
        PageBanner(
          pref: 'a11y_revoke_banner_dismissed',
          dismissed: revokeBannerDismissed,
          text: 'Disabling monitoring here does not revoke the app\'s Android accessibility permission. '
              'To revoke, go to Android Settings.',
          onDismiss: () async {
            if (mounted) setState(() => revokeBannerDismissed = true);
          },
          icon: Icons.lock_open,
          color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.4),
          textColor: Theme.of(context).colorScheme.onSecondaryContainer,
          pageIndex: 1,
          pageController: widget.pageController,
        ),
      ],
    );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: bannersContent),
        if (pkgs.isEmpty)
          const SliverFillRemaining(
            child: Center(child: Text('No third-party accessibility services found.')),
          )
        else
          ...pkgs.map((pkg) {
            final services = groups[pkg]!;
            final appColor = useAppColors ? colorCache[pkg] : null;

            final monitoredCount = services
                .where((s) => _monitoredKeys.contains('$pkg/${s.serviceClass}'))
                .length;
            final activeMonitored = services
                .where((s) =>
                    _monitoredKeys.contains('$pkg/${s.serviceClass}') &&
                    _enabledKeys.contains('$pkg/${s.serviceClass}'))
                .length;
            final hasIssue = monitoredCount > 0 && activeMonitored < monitoredCount;
            final monitoredSvcs =
                services.where((s) => _monitoredKeys.contains('$pkg/${s.serviceClass}'));
            final allMonitoredNotifOff = monitoredSvcs.isNotEmpty &&
                monitoredSvcs.every((s) => _notifOffKeys.contains('$pkg/${s.serviceClass}'));
            final groupState = monitoredCount == 0 ? 0 : allMonitoredNotifOff ? 1 : 2;

            final subtitle = monitoredCount == 0
                ? '${services.length} service${services.length == 1 ? '' : 's'}'
                : '$monitoredCount monitored · $activeMonitored active';

            return AppGroupCard(
              key: ValueKey(pkg),
              expanded: expandedGroups[pkg] ?? false,
              onToggleExpanded: () => setState(
                  () => expandedGroups[pkg] = !(expandedGroups[pkg] ?? false)),
              packageName: pkg,
              appName: services.first.appName,
              iconBytes: iconCache[pkg],
              appColor: appColor,
              subtitle: subtitle,
              groupState: groupState,
              hasIssue: hasIssue,
              onGroupStateChanged: (state) => _setGroupState(pkg, services, state),
              menuItems: const [
                PopupMenuItem(
                  value: 'history',
                  child: Row(children: [
                    Icon(Icons.history, size: 18),
                    SizedBox(width: 8),
                    Text('History'),
                  ]),
                ),
                PopupMenuItem(
                  value: 'manage_permission',
                  child: Row(children: [
                    Icon(Icons.security_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Manage permission'),
                  ]),
                ),
                PopupMenuItem(
                  value: 'repair_access',
                  child: Row(children: [
                    Icon(Icons.refresh, size: 18),
                    SizedBox(width: 8),
                    Text('Revoke & regrant access'),
                  ]),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: 'report_issue',
                  child: Row(children: [
                    Icon(Icons.bug_report_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Report Issue'),
                  ]),
                ),
              ],
              onMenuSelected: (v) {
                if (v == 'history') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ServiceAuditScreen.forApp(
                        packageName: pkg,
                        appName: services.first.appName,
                      ),
                    ),
                  );
                } else if (v == 'manage_permission') {
                  _system.openAccessibilitySettings(packageName: pkg);
                } else if (v == 'repair_access') {
                  _repairAccessibilityAccess(
                    pkg,
                    services.first.appName,
                    services.first.serviceClass,
                  );
                } else if (v == 'report_issue') {
                  _reportAppIssue(pkg, services.first.appName, services);
                }
              },
              children: [
                for (final svc in services) _buildServiceTile(context, pkg, svc, appColor),
              ],
            );
          }),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  Widget _buildServiceTile(
    BuildContext context,
    String pkg,
    ({String serviceClass, String appName}) svc,
    Color? appColor,
  ) {
    final key = '$pkg/${svc.serviceClass}';
    final enabled = _enabledKeys.contains(key);
    final monitored = _monitoredKeys.contains(key);
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenPadding,
        vertical: 2,
      ),
      title: Text(
        svc.serviceClass.split('.').last,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            svc.serviceClass,
            style: AppTextStyles.tinyLabel(context)?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
                ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                : (appColor ?? theme.colorScheme.primary),
          ),
          Opacity(
            opacity: enabled ? 1.0 : 0.45,
            child: Transform.scale(
              scale: 0.8,
              alignment: Alignment.centerRight,
              child: Switch(
                value: monitored,
                thumbColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.selected) ? appColor : null,
                ),
                trackColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.selected)
                      ? appColor?.withValues(alpha: 0.5)
                      : null,
                ),
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
            icon: Icon(Icons.more_vert, size: 18, color: theme.colorScheme.onSurfaceVariant),
            padding: EdgeInsets.zero,
            onSelected: (v) {
              if (v == 'history') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ServiceAuditScreen.forAccessibility(
                      packageName: pkg,
                      serviceClass: svc.serviceClass,
                      appName: svc.appName,
                    ),
                  ),
                );
              } else if (v == 'manage_permission') {
                _system.openAccessibilitySettings(
                  packageName: pkg,
                  serviceClass: svc.serviceClass,
                );
              } else if (v == 'repair_access') {
                _repairAccessibilityAccess(pkg, svc.appName, svc.serviceClass);
              } else if (v == 'report_issue') {
                _reportServiceIssue(pkg, svc.appName, svc.serviceClass);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'history',
                child: Row(children: [
                  Icon(Icons.history, size: 18),
                  SizedBox(width: 8),
                  Text('History'),
                ]),
              ),
              PopupMenuItem(
                value: 'manage_permission',
                child: Row(children: [
                  Icon(Icons.security_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('Manage permission'),
                ]),
              ),
              PopupMenuItem(
                value: 'repair_access',
                child: Row(children: [
                  Icon(Icons.refresh, size: 18),
                  SizedBox(width: 8),
                  Text('Revoke & regrant access'),
                ]),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
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
    );
  }

  Future<void> _repairAccessibilityAccess(
    String packageName,
    String appName,
    String serviceClass,
  ) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Repair accessibility access?'),
        content: Text(
          'Service Keeper will revoke and immediately regrant $appName\'s Accessibility access. '
          'This can fix Android showing it as granted but not working.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Repair'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Repairing $appName accessibility access...')),
    );

    final ok = await _system.repairAccessibilityService(
      packageName: packageName,
      serviceClass: serviceClass,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '$appName accessibility access repaired'
              : 'Could not repair $appName accessibility access',
        ),
      ),
    );
    if (ok) {
      await _refreshEnabledState();
    }
  }
}

class _StatusChip extends StatelessWidget {
  final bool enabled;

  const _StatusChip({required this.enabled});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeColor = context.appTheme.serviceRunning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (enabled ? activeColor : cs.surfaceContainerHighest).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(enabled ? Icons.check_circle : Icons.cancel,
            size: AppSpacing.iconXs,
            color: enabled ? activeColor : cs.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          enabled ? 'Active' : 'Inactive',
          style: AppTextStyles.metaLabelBold(context)?.copyWith(
            color: enabled ? activeColor : cs.onSurfaceVariant,
          ),
        ),
      ]),
    );
  }
}
