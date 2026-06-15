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
  }) async {
    try {
      await _channel.invokeMethod('scheduleMonitorWork', {
        'packageName': packageName,
        'serviceClass': serviceClass,
        'displayLabel': displayLabel,
        'intervalMinutes': intervalMinutes,
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
}
