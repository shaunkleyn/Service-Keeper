import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/monitored_service.dart';

class ServiceTile extends StatelessWidget {
  final MonitoredService service;
  final Uint8List? iconBytes;
  final VoidCallback? onToggle;
  final VoidCallback? onConfigure;
  final VoidCallback? onRemove;
  final VoidCallback? onRestartNow;

  const ServiceTile({
    super.key,
    required this.service,
    this.iconBytes,
    this.onToggle,
    this.onConfigure,
    this.onRemove,
    this.onRestartNow,
  });

  Color _statusColor(BuildContext context) {
    if (!service.enabled) return Colors.grey;
    if (service.wasRunning == null) return Colors.grey;
    return service.wasRunning! ? Colors.green : Colors.red;
  }

  String _statusLabel() {
    if (!service.enabled) return 'Disabled';
    if (service.wasRunning == null) return 'Unknown';
    return service.wasRunning! ? 'Running' : 'Restarted';
  }

  String _intervalLabel() {
    if (service.intervalMinutes < 60) return 'Every ${service.intervalMinutes}m';
    final h = service.intervalMinutes ~/ 60;
    return 'Every ${h}h';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(
        children: [
          iconBytes != null
              ? CircleAvatar(
                  backgroundImage: MemoryImage(iconBytes!),
                  backgroundColor: Colors.transparent,
                )
              : CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    service.displayLabel.isNotEmpty
                        ? service.displayLabel[0].toUpperCase()
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
      title: Text(
        service.displayLabel,
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            service.serviceClass,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
            overflow: TextOverflow.ellipsis,
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
          ]),
          if (service.lastRestarted != null) ...[
            const SizedBox(height: 2),
            Text(
              'Last restarted: ${_formatTime(service.lastRestarted!)}',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: service.enabled,
            onChanged: onToggle != null ? (_) => onToggle!() : null,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'configure') onConfigure?.call();
              if (v == 'restart') onRestartNow?.call();
              if (v == 'remove') onRemove?.call();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'configure', child: Text('Configure')),
              const PopupMenuItem(value: 'restart', child: Text('Restart now')),
              const PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove', style: TextStyle(color: Colors.red))),
            ],
          ),
        ],
      ),
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
