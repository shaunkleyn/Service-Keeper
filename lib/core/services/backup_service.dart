import 'dart:convert';
import 'package:service_keeper/core/models/monitored_service.dart';

class AppBackupSettings {
  final bool useAppColors;
  final bool globalIntervalEnabled;
  final int defaultCheckInterval;
  final bool useMaterialYou;

  const AppBackupSettings({
    this.useAppColors = false,
    this.globalIntervalEnabled = true,
    this.defaultCheckInterval = 15,
    this.useMaterialYou = false,
  });

  Map<String, dynamic> toJson() => {
    'use_app_colors': useAppColors,
    'global_interval_enabled': globalIntervalEnabled,
    'default_check_interval': defaultCheckInterval,
    'use_material_you': useMaterialYou,
  };

  factory AppBackupSettings.fromJson(Map<String, dynamic> json) => AppBackupSettings(
    useAppColors: json['use_app_colors'] as bool? ?? false,
    globalIntervalEnabled: json['global_interval_enabled'] as bool? ?? true,
    defaultCheckInterval: json['default_check_interval'] as int? ?? 15,
    useMaterialYou: json['use_material_you'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
    other is AppBackupSettings &&
    useAppColors == other.useAppColors &&
    globalIntervalEnabled == other.globalIntervalEnabled &&
    defaultCheckInterval == other.defaultCheckInterval &&
    useMaterialYou == other.useMaterialYou;

  @override
  int get hashCode => Object.hash(useAppColors, globalIntervalEnabled, defaultCheckInterval, useMaterialYou);
}

class BackupData {
  final int version;
  final DateTime exportedAt;
  final List<MonitoredService> services;
  final Set<String> a11yMonitoredKeys;
  final Set<String> notifMonitoredKeys;
  final Set<String> a11yNotifOffKeys;
  final Set<String> notifListenerNotifOffKeys;
  final AppBackupSettings settings;
  final List<Map<String, dynamic>> auditLog;

  const BackupData({
    required this.version,
    required this.exportedAt,
    required this.services,
    required this.a11yMonitoredKeys,
    required this.notifMonitoredKeys,
    required this.a11yNotifOffKeys,
    required this.notifListenerNotifOffKeys,
    required this.settings,
    required this.auditLog,
  });
}

class BackupService {
  static const int currentVersion = 3;

  static String encode(BackupData data) {
    return jsonEncode({
      'version': currentVersion,
      'exportedAt': data.exportedAt.toIso8601String(),
      'services': data.services.map((s) => s.toJson()).toList(),
      'a11yMonitoredKeys': data.a11yMonitoredKeys.toList(),
      'notifMonitoredKeys': data.notifMonitoredKeys.toList(),
      'a11yNotifOffKeys': data.a11yNotifOffKeys.toList(),
      'notifListenerNotifOffKeys': data.notifListenerNotifOffKeys.toList(),
      'appSettings': data.settings.toJson(),
      'auditLog': data.auditLog,
    });
  }

  static BackupData decode(String content) {
    final json = jsonDecode(content) as Map<String, dynamic>;
    final version = json['version'] as int? ?? 1;

    final services = (json['services'] as List? ?? [])
        .map((e) => MonitoredService.fromJson(e as Map<String, dynamic>))
        .toList();

    final a11yKeys = version >= 2
        ? Set<String>.from(json['a11yMonitoredKeys'] as List? ?? [])
        : <String>{};
    final notifKeys = version >= 2
        ? Set<String>.from(json['notifMonitoredKeys'] as List? ?? [])
        : <String>{};
    final a11yNotifOff = version >= 2
        ? Set<String>.from(json['a11yNotifOffKeys'] as List? ?? [])
        : <String>{};
    final notifListenerNotifOff = version >= 2
        ? Set<String>.from(json['notifListenerNotifOffKeys'] as List? ?? [])
        : <String>{};

    final settings = version >= 3
        ? AppBackupSettings.fromJson(json['appSettings'] as Map<String, dynamic>? ?? {})
        : const AppBackupSettings();

    final rawLog = json['auditLog'] as List? ?? [];
    final auditLog = rawLog
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final exportedAt = json['exportedAt'] != null
        ? DateTime.parse(json['exportedAt'] as String)
        : DateTime.now();

    return BackupData(
      version: version,
      exportedAt: exportedAt,
      services: services,
      a11yMonitoredKeys: a11yKeys,
      notifMonitoredKeys: notifKeys,
      a11yNotifOffKeys: a11yNotifOff,
      notifListenerNotifOffKeys: notifListenerNotifOff,
      settings: settings,
      auditLog: auditLog,
    );
  }

  /// Returns package names from [services] not present in [installedPackages].
  static Set<String> findMissingPackages(
    List<MonitoredService> services,
    Set<String> installedPackages,
  ) {
    return services
        .map((s) => s.packageName)
        .toSet()
        .difference(installedPackages);
  }

  /// Returns services with missing-package entries disabled and runtime state cleared.
  static List<MonitoredService> disableMissingServices(
    List<MonitoredService> services,
    Set<String> missingPackages,
  ) {
    if (missingPackages.isEmpty) return services;
    return services.map((s) {
      if (!missingPackages.contains(s.packageName)) return s;
      return MonitoredService(
        packageName: s.packageName,
        serviceClass: s.serviceClass,
        displayLabel: s.displayLabel,
        appName: s.appName,
        intervalMinutes: s.intervalMinutes,
        customIntervalMinutes: s.customIntervalMinutes,
        enabled: false,
        notificationsEnabled: s.notificationsEnabled,
        appRestartEnabled: s.appRestartEnabled,
      );
    }).toList();
  }

  /// Removes entries whose package prefix is in [missingPackages] from a key set.
  /// Keys are formatted as "packageName/serviceClass".
  static Set<String> filterKeysForMissing(
    Set<String> keys,
    Set<String> missingPackages,
  ) {
    if (missingPackages.isEmpty) return keys;
    return keys.where((k) {
      final pkg = k.contains('/') ? k.split('/').first : k;
      return !missingPackages.contains(pkg);
    }).toSet();
  }
}
