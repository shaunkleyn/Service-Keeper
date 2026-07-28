import 'package:flutter/services.dart';

class SystemService {
  static const _channel = MethodChannel('com.shaunkleyn.service_keeper/shizuku');

  Future<bool> isBatteryOptimizationExempt() async {
    try {
      return await _channel.invokeMethod<bool>('isBatteryOptimizationExempt') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> requestBatteryOptimizationExemption() async {
    try {
      await _channel.invokeMethod('requestBatteryOptimizationExemption');
    } on PlatformException {
      // ignore
    }
  }

  Future<void> startKeeperService(int serviceCount) async {
    try {
      await _channel.invokeMethod('startKeeperService', {'count': serviceCount});
    } on PlatformException {
      // ignore
    }
  }

  Future<void> stopKeeperService() async {
    try {
      await _channel.invokeMethod('stopKeeperService');
    } on PlatformException {
      // ignore
    }
  }

  Future<void> scheduleMonitorWork({
    required String packageName,
    required String serviceClass,
    required String displayLabel,
    required int intervalMinutes,
    bool appRestartEnabled = false,
  }) async {
    try {
      await _channel.invokeMethod('scheduleMonitorWork', {
        'packageName': packageName,
        'serviceClass': serviceClass,
        'displayLabel': displayLabel,
        'intervalMinutes': intervalMinutes,
        'appRestartEnabled': appRestartEnabled,
      });
    } on PlatformException {
      // ignore
    }
  }

  Future<void> cancelMonitorWork(String workTag) async {
    try {
      await _channel.invokeMethod('cancelMonitorWork', {'workTag': workTag});
    } on PlatformException {
      // ignore
    }
  }

  Future<void> rescheduleAllMonitorWork() async {
    try {
      await _channel.invokeMethod('rescheduleAllMonitorWork');
    } on PlatformException {
      // ignore
    }
  }

  Future<int> runMonitorNowForAll() async {
    try {
      return await _channel.invokeMethod<int>('runMonitorNowForAll') ?? 0;
    } on PlatformException {
      return 0;
    }
  }

  Future<Set<String>> getEnabledAccessibilityServices() async {
    try {
      final raw = await _channel.invokeMethod<String>('getEnabledAccessibilityServices') ?? '';
      if (raw.isEmpty) return {};
      return raw.split(':').map((e) {
        final slash = e.indexOf('/');
        if (slash < 0) return e;
        final pkg = e.substring(0, slash);
        var cls = e.substring(slash + 1);
        if (cls.startsWith('.')) cls = pkg + cls;
        return '$pkg/$cls';
      }).toSet();
    } on PlatformException {
      return {};
    }
  }

  Future<Set<String>> getEnabledNotificationListeners() async {
    try {
      final raw = await _channel.invokeMethod<String>('getEnabledNotificationListeners') ?? '';
      if (raw.isEmpty) return {};
      return raw.split(':').map((e) {
        final slash = e.indexOf('/');
        if (slash < 0) return e;
        final pkg = e.substring(0, slash);
        var cls = e.substring(slash + 1);
        if (cls.startsWith('.')) cls = pkg + cls;
        return '$pkg/$cls';
      }).toSet();
    } on PlatformException {
      return {};
    }
  }

  Future<bool> isNotificationPermissionGranted() async {
    try {
      return await _channel.invokeMethod<bool>('checkNotificationPermission') ?? true;
    } on PlatformException {
      return true;
    }
  }

  Future<bool> requestNotificationPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestNotificationPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> postShizukuOfflineNotification() async {
    try {
      await _channel.invokeMethod('postShizukuOfflineNotification');
    } on PlatformException {
      // ignore
    }
  }

  Future<void> openAccessibilitySettings({String? packageName, String? serviceClass}) async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings', {
        if (packageName != null) 'packageName': packageName,
        if (serviceClass != null) 'serviceClass': serviceClass,
      });
    } on PlatformException {
      // ignore
    }
  }

  Future<bool> repairAccessibilityService({
    required String packageName,
    required String serviceClass,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('repairAccessibilityService', {
            'packageName': packageName,
            'serviceClass': serviceClass,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openNotificationListenerSettings({String? packageName, String? serviceClass}) async {
    try {
      await _channel.invokeMethod('openNotificationListenerSettings', {
        if (packageName != null) 'packageName': packageName,
        if (serviceClass != null) 'serviceClass': serviceClass,
      });
    } on PlatformException {
      // ignore
    }
  }
}
