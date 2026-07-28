import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:service_keeper/core/models/monitored_service.dart';
import 'package:service_keeper/core/models/service_stats.dart';
import 'package:service_keeper/core/theme/app_spacing.dart';
import 'package:service_keeper/core/theme/app_text_styles.dart';
import 'package:service_keeper/core/theme/app_theme.dart';

class ServiceTile extends StatefulWidget {
  final MonitoredService service;
  final Uint8List? iconBytes;
  final VoidCallback? onToggle;
  final VoidCallback? onConfigure;
  final VoidCallback? onRemove;
  final VoidCallback? onRestartNow;
  final VoidCallback? onViewHistory;
  final VoidCallback? onCheckDue;
  final VoidCallback? onToggleNotifications;
  final VoidCallback? onReportIssue;
  final Color? accentColor;
  final ServiceStats? serviceStats;
  final bool showLeading;
  final bool globalIntervalEnabled;
  final int effectiveIntervalMinutes;
  final bool isRestarting;
  final DateTime now;

  const ServiceTile({
    super.key,
    required this.service,
    this.iconBytes,
    this.onToggle,
    this.onConfigure,
    this.onRemove,
    this.onRestartNow,
    this.onViewHistory,
    this.onCheckDue,
    this.onToggleNotifications,
    this.onReportIssue,
    this.accentColor,
    this.serviceStats,
    this.showLeading = true,
    this.globalIntervalEnabled = true,
    this.effectiveIntervalMinutes = 15,
    this.isRestarting = false,
    required this.now,
  });

  @override
  State<ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends State<ServiceTile> {
  bool _checkTriggered = false;

  @override
  void initState() {
    super.initState();
    _maybeTriggerDueCheck();
  }

  @override
  void didUpdateWidget(ServiceTile old) {
    super.didUpdateWidget(old);
    if (old.service.lastChecked != widget.service.lastChecked ||
        old.effectiveIntervalMinutes != widget.effectiveIntervalMinutes ||
        old.globalIntervalEnabled != widget.globalIntervalEnabled ||
        old.service.enabled != widget.service.enabled) {
      _checkTriggered = false;
    }
    _maybeTriggerDueCheck();
  }

  void _maybeTriggerDueCheck() {
    if (!widget.globalIntervalEnabled || !widget.service.enabled) return;
    if (widget.service.lastChecked == null) return;
    if (_progressValue(widget.now) <= 0 && !_checkTriggered) {
      _checkTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onCheckDue?.call();
      });
    }
  }

  Color _statusColor(BuildContext context) {
    if (widget.isRestarting) return context.appTheme.serviceRestarting;
    return switch (widget.service.state) {
      ServiceState.running => context.appTheme.serviceRunning,
      ServiceState.crashed => Theme.of(context).colorScheme.error,
      ServiceState.stopped || ServiceState.unknown => context.appTheme.serviceStopped,
    };
  }

  String _statusLabel() {
    if (widget.isRestarting) return 'Restarting';
    return switch (widget.service.state) {
      ServiceState.running => 'Running',
      ServiceState.crashed => 'Not Running',
      ServiceState.stopped => 'Disabled',
      ServiceState.unknown => 'Unknown',
    };
  }

  String _intervalLabel() {
    final minutes = widget.effectiveIntervalMinutes;
    final suffix = widget.service.customIntervalMinutes != null ? ' (custom)' : '';
    if (minutes < 60) return 'Every ${minutes}m$suffix';
    return 'Every ${minutes ~/ 60}h$suffix';
  }

  double _progressValue(DateTime now) {
    if (!widget.service.enabled) return 0;
    if (widget.service.lastChecked == null) return 1;
    final elapsed = now.difference(widget.service.lastChecked!);
    final interval = Duration(minutes: widget.effectiveIntervalMinutes);
    final remaining = interval - elapsed;
    if (remaining.inSeconds <= 0) return 0;
    return remaining.inSeconds / interval.inSeconds;
  }

  String _nextCheckLabel(DateTime now) {
    if (!widget.service.enabled) return '';
    if (widget.service.lastChecked == null) return 'Pending first check';
    final elapsed = now.difference(widget.service.lastChecked!);
    final remaining = Duration(minutes: widget.effectiveIntervalMinutes) - elapsed;
    if (remaining.inSeconds <= 0) return 'Check pending';
    final m = remaining.inMinutes;
    final s = remaining.inSeconds % 60;
    if (m >= 60) return 'Next check in ${m ~/ 60}h ${m % 60}m';
    if (m > 0) return 'Next check in ${m}m ${s}s';
    return 'Next check in ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(context);
    final progress = _progressValue(widget.now);
    final nextLabel = widget.globalIntervalEnabled ? _nextCheckLabel(widget.now) : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding, vertical: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (widget.showLeading) ...[
                Stack(
                  children: [
                    widget.iconBytes != null
                        ? CircleAvatar(
                            backgroundImage: MemoryImage(widget.iconBytes!),
                            backgroundColor: Colors.transparent,
                          )
                        : CircleAvatar(
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Text(
                              widget.service.displayLabel.isNotEmpty
                                  ? widget.service.displayLabel[0].toUpperCase()
                                  : '?',
                              style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                            ),
                          ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: theme.colorScheme.surface, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: AppSpacing.screenPadding),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.service.displayLabel,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.service.serviceClass,
                      style: AppTextStyles.tinyLabel(context)?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(children: [
                      if (widget.globalIntervalEnabled) ...[
                        Icon(Icons.schedule,
                            size: AppSpacing.iconSm, color: theme.colorScheme.primary),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          _intervalLabel(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: widget.service.customIntervalMinutes != null
                                ? theme.colorScheme.tertiary
                                : theme.colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _statusLabel(),
                          style: AppTextStyles.tinyLabelBold(context)?.copyWith(
                            color: statusColor,
                          ),
                        ),
                      ),
                      if (widget.serviceStats != null &&
                          widget.serviceStats!.hasData) ...[
                        const SizedBox(width: 6),
                        _HealthChip(health: widget.serviceStats!.health),
                      ],
                      const SizedBox(width: AppSpacing.sm),
                      Icon(
                        widget.service.notificationsEnabled
                            ? Icons.notifications
                            : Icons.notifications_off,
                        size: AppSpacing.iconMd,
                        color: widget.service.notificationsEnabled
                            ? (widget.accentColor ?? theme.colorScheme.primary)
                            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                      ),
                      if (widget.service.appRestartEnabled) ...[
                        const SizedBox(width: 5),
                        Icon(
                          Icons.open_in_browser,
                          semanticLabel: 'App restart enabled',
                          size: AppSpacing.iconMd,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ],
                    ]),
                    if (widget.service.lastChecked != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Last checked: ${_formatTime(widget.service.lastChecked!)}',
                        style: AppTextStyles.metaLabel(context),
                      ),
                    ],
                    if (widget.service.lastRestarted != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Last restarted: ${_formatTime(widget.service.lastRestarted!)}',
                        style: AppTextStyles.metaLabel(context),
                      ),
                    ],
                    if (nextLabel.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        nextLabel,
                        style: AppTextStyles.metaLabelItalic(context)?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (widget.serviceStats?.triggeredAppRestart == true) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.rocket_launch_outlined,
                              size: AppSpacing.iconXs,
                              color: theme.colorScheme.error
                                  .withValues(alpha: 0.85)),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              'Required app relaunch to recover'
                              ' (${widget.serviceStats!.appRestarts30d}× in 30 days)',
                              style: AppTextStyles.metaLabelItalic(context)?.copyWith(
                                color: theme.colorScheme.error.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (widget.service.state == ServiceState.crashed &&
                        !widget.service.appRestartEnabled) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: AppSpacing.iconXs,
                              color: theme.colorScheme.error.withValues(alpha: 0.8)),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              'Enable app restart fallback in App settings to recover this service.',
                              style: AppTextStyles.metaLabelItalic(context)?.copyWith(
                                color: theme.colorScheme.error.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: 0.75,
                    alignment: Alignment.centerRight,
                    child: Switch(
                      value: widget.service.enabled,
                      onChanged: widget.onToggle != null ? (_) => widget.onToggle!() : null,
                      thumbColor: widget.accentColor == null
                          ? null
                          : WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return ThemeData.estimateBrightnessForColor(widget.accentColor!) ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black87;
                              }
                              return null;
                            }),
                      trackColor: widget.accentColor == null
                          ? null
                          : WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return widget.accentColor;
                              }
                              return null;
                            }),
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'configure') widget.onConfigure?.call();
                      if (v == 'restart') widget.onRestartNow?.call();
                      if (v == 'history') widget.onViewHistory?.call();
                      if (v == 'toggle_notifications') widget.onToggleNotifications?.call();
                      if (v == 'report_issue') widget.onReportIssue?.call();
                      if (v == 'remove') widget.onRemove?.call();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'configure', child: Text('Configure')),
                      const PopupMenuItem(value: 'restart', child: Text('Restart now')),
                      const PopupMenuItem(value: 'history', child: Text('View history')),
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
                                child: Switch(
                                  value: widget.service.notificationsEnabled,
                                  onChanged: (_) {},
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'report_issue',
                        child: Row(
                          children: [
                            Icon(Icons.bug_report_outlined, size: 16),
                            SizedBox(width: 8),
                            Text('Report Issue'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove',
                              style: TextStyle(color: context.appTheme.destructive))),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        if (widget.globalIntervalEnabled && widget.service.enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding, 0, AppSpacing.screenPadding, AppSpacing.sm),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              builder: (context, animatedProgress, _) {
                final baseColor = widget.accentColor ?? theme.colorScheme.primary;
                final activeColor = animatedProgress < 0.15
                    ? theme.colorScheme.error
                    : animatedProgress < 0.35
                        ? theme.colorScheme.tertiary
                        : baseColor;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: animatedProgress,
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    color: activeColor,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _HealthChip extends StatelessWidget {
  final ServiceHealth health;
  const _HealthChip({required this.health});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = health.color(cs);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.5),
      ),
      child: Text(
        health.label,
        style: AppTextStyles.metaLabelBold(context)?.copyWith(color: color),
      ),
    );
  }
}
