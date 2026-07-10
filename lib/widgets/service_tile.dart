import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/monitored_service.dart';

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
  final Color? accentColor;
  final bool showLeading;

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
    this.accentColor,
    this.showLeading = true,
  });

  @override
  State<ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends State<ServiceTile> with WidgetsBindingObserver {
  Timer? _timer;
  bool _checkTriggered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  @override
  void didUpdateWidget(ServiceTile old) {
    super.didUpdateWidget(old);
    if (old.service.lastChecked != widget.service.lastChecked ||
        old.service.intervalMinutes != widget.service.intervalMinutes ||
        old.service.enabled != widget.service.enabled) {
      _checkTriggered = false;
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = null;
    if (widget.service.enabled && widget.service.lastChecked != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_progressValue() <= 0 && !_checkTriggered) {
          _checkTriggered = true;
          widget.onCheckDue?.call();
        }
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Color _statusColor(BuildContext context) {
    if (!widget.service.enabled) return Colors.grey;
    if (widget.service.wasRunning == null) return Colors.grey;
    return widget.service.wasRunning! ? Colors.green : Colors.red;
  }

  String _statusLabel() {
    if (!widget.service.enabled) return 'Disabled';
    if (widget.service.wasRunning == null) return 'Unknown';
    return widget.service.wasRunning! ? 'Running' : 'Restarted';
  }

  String _intervalLabel() {
    if (widget.service.intervalMinutes < 60) {
      return 'Every ${widget.service.intervalMinutes}m';
    }
    return 'Every ${widget.service.intervalMinutes ~/ 60}h';
  }

  double _progressValue() {
    if (!widget.service.enabled) return 0;
    if (widget.service.lastChecked == null) return 1;
    final elapsed = DateTime.now().difference(widget.service.lastChecked!);
    final interval = Duration(minutes: widget.service.intervalMinutes);
    final remaining = interval - elapsed;
    if (remaining.inSeconds <= 0) return 0;
    return remaining.inSeconds / interval.inSeconds;
  }

  String _nextCheckLabel() {
    if (!widget.service.enabled) return '';
    if (widget.service.lastChecked == null) return 'Pending first check';
    final elapsed = DateTime.now().difference(widget.service.lastChecked!);
    final remaining = Duration(minutes: widget.service.intervalMinutes) - elapsed;
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
    final progress = _progressValue();
    final nextLabel = _nextCheckLabel();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                const SizedBox(width: 16),
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.schedule, size: 12, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        _intervalLabel(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _statusLabel(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        widget.service.notificationsEnabled
                            ? Icons.notifications
                            : Icons.notifications_off,
                        size: 13,
                        color: widget.service.notificationsEnabled
                            ? (widget.accentColor ?? theme.colorScheme.primary)
                            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                      ),
                    ]),
                    if (widget.service.lastChecked != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Last checked: ${_formatTime(widget.service.lastChecked!)}',
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                      ),
                    ],
                    if (widget.service.lastRestarted != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Last restarted: ${_formatTime(widget.service.lastRestarted!)}',
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                      ),
                    ],
                    if (nextLabel.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        nextLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
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
                      const PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        if (widget.service.enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progress < 0.15
                          ? Colors.orange
                          : (widget.accentColor ?? theme.colorScheme.primary).withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
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
