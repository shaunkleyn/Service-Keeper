import 'package:flutter/material.dart';
import '../models/audit_event.dart';
import '../models/monitored_service.dart';
import '../services/database_service.dart';

enum AuditCategory { service, accessibility, notification }

class ServiceAuditScreen extends StatefulWidget {
  final String _packageName;
  final String? _serviceClass;
  final String _title;
  final AuditCategory _category;

  ServiceAuditScreen({super.key, required MonitoredService service})
      : _packageName = service.packageName,
        _serviceClass = service.serviceClass,
        _title = '${service.displayLabel} — History',
        _category = AuditCategory.service;

  const ServiceAuditScreen.forApp({
    super.key,
    required String packageName,
    required String appName,
  })  : _packageName = packageName,
        _serviceClass = null,
        _title = '$appName — History',
        _category = AuditCategory.service;

  const ServiceAuditScreen.forAccessibility({
    super.key,
    required String packageName,
    required String serviceClass,
    required String appName,
  })  : _packageName = packageName,
        _serviceClass = serviceClass,
        _title = '$appName — Accessibility History',
        _category = AuditCategory.accessibility;

  const ServiceAuditScreen.forNotification({
    super.key,
    required String packageName,
    required String serviceClass,
    required String appName,
  })  : _packageName = packageName,
        _serviceClass = serviceClass,
        _title = '$appName — Notification History',
        _category = AuditCategory.notification;

  @override
  State<ServiceAuditScreen> createState() => _ServiceAuditScreenState();
}

class _ServiceAuditScreenState extends State<ServiceAuditScreen> {
  final _db = DatabaseService();
  List<AuditEvent> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _db.importPendingEvents();
    final events = await _db.getEvents(
      packageName: widget._packageName,
      serviceClass: widget._serviceClass,
    );
    setState(() {
      _events = events;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget._title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
              ? const Center(child: Text('No events recorded yet.'))
              : ListView.separated(
                  itemCount: _events.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) => _buildEventTile(_events[i]),
                ),
    );
  }

  String _eventLabel(AuditEventType t) {
    if (widget._category == AuditCategory.service) return t.label;
    return switch (t) {
      AuditEventType.detectedStopped => 'Access revoked',
      AuditEventType.restartAttempted => 'Re-enable attempted',
      AuditEventType.restartSuccess => 'Access re-enabled',
      AuditEventType.restartFailed => 'Re-enable failed',
      _ => t.label,
    };
  }

  Widget _buildEventTile(AuditEvent e) {
    final (icon, color) = _iconAndColor(e.eventType);
    final usedBroadcastFallback = e.eventType == AuditEventType.restartSuccess &&
        (e.notes ?? '').toLowerCase().contains('broadcast fallback');
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, size: 16, color: color),
      ),
      title: Text(_eventLabel(e.eventType),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(_formatTs(e.timestamp), style: const TextStyle(fontSize: 11)),
            if (usedBroadcastFallback) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Fallback',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal.shade700,
                  ),
                ),
              ),
            ],
            if (e.trigger != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: e.trigger == AuditTrigger.automatic
                      ? Colors.blue.shade50
                      : Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  e.trigger == AuditTrigger.automatic ? 'Auto' : 'Manual',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: e.trigger == AuditTrigger.automatic
                        ? Colors.blue.shade700
                        : Colors.purple.shade700,
                  ),
                ),
              ),
            ],
          ]),
          if (widget._serviceClass == null)
            Text(e.displayLabel,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          if (e.notes != null &&
              e.notes!.isNotEmpty &&
              e.eventType == AuditEventType.restartFailed)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                e.notes!,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.red.shade700,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
      trailing: null,
    );
  }

  (IconData, Color) _iconAndColor(AuditEventType t) => switch (t) {
        AuditEventType.detectedStopped => (Icons.stop_circle_outlined, Colors.orange),
        AuditEventType.restartAttempted => (Icons.refresh, Colors.blue),
        AuditEventType.restartSuccess => (Icons.check_circle_outline, Colors.green),
        AuditEventType.restartFailed => (Icons.error_outline, Colors.red),
        AuditEventType.added => (Icons.add_circle_outline, Colors.teal),
        AuditEventType.removed => (Icons.remove_circle_outline, Colors.red),
        AuditEventType.enabled => (Icons.toggle_on_outlined, Colors.green),
        AuditEventType.disabled => (Icons.toggle_off_outlined, Colors.grey),
      };

  String _formatTs(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (diff.inDays == 0) return 'Today $time';
    if (diff.inDays == 1) return 'Yesterday $time';
    return '${dt.day}/${dt.month}/${dt.year} $time';
  }
}
