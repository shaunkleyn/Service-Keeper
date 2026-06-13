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
}
