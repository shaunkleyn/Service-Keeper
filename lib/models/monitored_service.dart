import 'dart:convert';

class MonitoredService {
  final String packageName;
  final String serviceClass;
  final String displayLabel;
  final String? appName;
  final int intervalMinutes;
  final bool enabled;
  final DateTime? lastRestarted;
  final DateTime? lastChecked;
  final bool? wasRunning;

  const MonitoredService({
    required this.packageName,
    required this.serviceClass,
    required this.displayLabel,
    this.appName,
    this.intervalMinutes = 15,
    this.enabled = true,
    this.lastRestarted,
    this.lastChecked,
    this.wasRunning,
  });

  String get workTag => '${packageName}_${serviceClass.replaceAll('.', '_')}';

  String get fullServiceName => '$packageName/$serviceClass';

  MonitoredService copyWith({
    String? packageName,
    String? serviceClass,
    String? displayLabel,
    String? appName,
    int? intervalMinutes,
    bool? enabled,
    DateTime? lastRestarted,
    DateTime? lastChecked,
    bool? wasRunning,
  }) {
    return MonitoredService(
      packageName: packageName ?? this.packageName,
      serviceClass: serviceClass ?? this.serviceClass,
      displayLabel: displayLabel ?? this.displayLabel,
      appName: appName ?? this.appName,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      enabled: enabled ?? this.enabled,
      lastRestarted: lastRestarted ?? this.lastRestarted,
      lastChecked: lastChecked ?? this.lastChecked,
      wasRunning: wasRunning ?? this.wasRunning,
    );
  }

  Map<String, dynamic> toJson() => {
        'packageName': packageName,
        'serviceClass': serviceClass,
        'displayLabel': displayLabel,
        'appName': appName,
        'intervalMinutes': intervalMinutes,
        'enabled': enabled,
        'lastRestarted': lastRestarted?.toIso8601String(),
        'lastChecked': lastChecked?.toIso8601String(),
        'wasRunning': wasRunning,
      };

  factory MonitoredService.fromJson(Map<String, dynamic> json) =>
      MonitoredService(
        packageName: json['packageName'] as String,
        serviceClass: json['serviceClass'] as String,
        displayLabel: json['displayLabel'] as String,
        appName: json['appName'] as String?,
        intervalMinutes: json['intervalMinutes'] as int? ?? 15,
        enabled: json['enabled'] as bool? ?? true,
        lastRestarted: json['lastRestarted'] != null
            ? DateTime.parse(json['lastRestarted'] as String)
            : null,
        lastChecked: json['lastChecked'] != null
            ? DateTime.parse(json['lastChecked'] as String)
            : null,
        wasRunning: json['wasRunning'] as bool?,
      );

  static List<MonitoredService> listFromJson(String raw) {
    final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => MonitoredService.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJson(List<MonitoredService> services) =>
      jsonEncode(services.map((s) => s.toJson()).toList());

  @override
  bool operator ==(Object other) =>
      other is MonitoredService &&
      packageName == other.packageName &&
      serviceClass == other.serviceClass;

  @override
  int get hashCode => Object.hash(packageName, serviceClass);
}

class RunningService {
  final String packageName;
  final String serviceClass;
  final String? processName;
  final String? appName;
  final bool isRunning;

  const RunningService({
    required this.packageName,
    required this.serviceClass,
    this.processName,
    this.appName,
    this.isRunning = false,
  });

  String get displayServiceClass {
    if (serviceClass.startsWith(packageName)) {
      return serviceClass.substring(packageName.length);
    }
    return serviceClass;
  }

  /// True when the service is part of the app's own codebase (not a library).
  /// Uses the first two package segments as the company prefix (e.g. com.life360)
  /// and excludes well-known third-party library namespaces.
  bool get isAppOwned {
    const libraryPrefixes = [
      'androidx.',
      'com.google.firebase.',
      'com.google.android.gms.',
      'com.google.android.datatransport.',
      'kotlin.',
      'io.flutter.',
      'com.facebook.',
      'com.microsoft.',
      'com.adjust.',
      'com.amplitude.',
      'com.braze.',
      'io.sentry.',
    ];
    if (libraryPrefixes.any((p) => serviceClass.startsWith(p))) return false;
    final parts = packageName.split('.');
    if (parts.length >= 2) {
      return serviceClass.startsWith('${parts[0]}.${parts[1]}.');
    }
    return serviceClass.startsWith(packageName);
  }
}
