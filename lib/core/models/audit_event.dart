enum AuditEventType {
  detectedStopped,
  restartAttempted,
  restartSuccess,
  restartFailed,
  added,
  removed,
  enabled,
  disabled,
  notificationsEnabled,
  notificationsDisabled,
  intervalChanged,
  configChanged;

  String get value => switch (this) {
        detectedStopped => 'DETECTED_STOPPED',
        restartAttempted => 'RESTART_ATTEMPTED',
        restartSuccess => 'RESTART_SUCCESS',
        restartFailed => 'RESTART_FAILED',
        added => 'ADDED',
        removed => 'REMOVED',
        enabled => 'ENABLED',
        disabled => 'DISABLED',
        notificationsEnabled => 'NOTIFICATIONS_ENABLED',
        notificationsDisabled => 'NOTIFICATIONS_DISABLED',
        intervalChanged => 'INTERVAL_CHANGED',
        configChanged => 'CONFIG_CHANGED',
      };

  static AuditEventType fromValue(String v) => switch (v) {
        'DETECTED_STOPPED' => detectedStopped,
        'RESTART_ATTEMPTED' => restartAttempted,
        'RESTART_SUCCESS' => restartSuccess,
        'RESTART_FAILED' => restartFailed,
        'ADDED' => added,
        'REMOVED' => removed,
        'ENABLED' => enabled,
        'DISABLED' => disabled,
        'NOTIFICATIONS_ENABLED' => notificationsEnabled,
        'NOTIFICATIONS_DISABLED' => notificationsDisabled,
        'INTERVAL_CHANGED' => intervalChanged,
        'CONFIG_CHANGED' => configChanged,
        _ => restartAttempted,
      };

  String get label => switch (this) {
        detectedStopped => 'Detected stopped',
        restartAttempted => 'Restart attempted',
        restartSuccess => 'Restarted successfully',
        restartFailed => 'Restart failed',
        added => 'Added to monitoring',
        removed => 'Removed from monitoring',
        enabled => 'Monitoring enabled',
        disabled => 'Monitoring disabled',
        notificationsEnabled => 'Notifications enabled',
        notificationsDisabled => 'Notifications disabled',
        intervalChanged => 'Check interval changed',
        configChanged => 'Config changed',
      };
}

enum AuditTrigger {
  automatic,
  manual;

  String get value => this == automatic ? 'AUTOMATIC' : 'MANUAL';
  static AuditTrigger fromValue(String v) =>
      v == 'MANUAL' ? manual : automatic;
}

class AuditEvent {
  final int? id;
  final DateTime timestamp;
  final String packageName;
  final String serviceClass;
  final String displayLabel;
  final AuditEventType eventType;
  final AuditTrigger? trigger;
  final String? notes;

  const AuditEvent({
    this.id,
    required this.timestamp,
    required this.packageName,
    required this.serviceClass,
    required this.displayLabel,
    required this.eventType,
    this.trigger,
    this.notes,
  });

  Map<String, dynamic> toMap() => {
        'timestamp': timestamp.toIso8601String(),
        'package_name': packageName,
        'service_class': serviceClass,
        'display_label': displayLabel,
        'event_type': eventType.value,
        'trigger_type': trigger?.value,
        'notes': notes,
      };

  factory AuditEvent.fromMap(Map<String, dynamic> m) => AuditEvent(
        id: m['id'] as int?,
        timestamp: DateTime.parse(m['timestamp'] as String),
        packageName: m['package_name'] as String,
        serviceClass: m['service_class'] as String,
        displayLabel: m['display_label'] as String,
        eventType: AuditEventType.fromValue(m['event_type'] as String),
        trigger: m['trigger_type'] != null
            ? AuditTrigger.fromValue(m['trigger_type'] as String)
            : null,
        notes: m['notes'] as String?,
      );
}
