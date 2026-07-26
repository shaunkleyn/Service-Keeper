import 'package:flutter/services.dart';
import 'package:shizuku_api/shizuku_api.dart';

enum ShizukuStatus {
  notInstalled,
  notRunning,
  permissionDenied,
  ready,
}

class ShizukuService {
  static const _channel = MethodChannel('com.shaunkleyn.service_keeper/shizuku');
  final _api = ShizukuApi();

  Future<ShizukuStatus> checkStatus() async {
    try {
      final bool running = await _api.pingBinder() ?? false;
      if (!running) return ShizukuStatus.notRunning;

      final bool granted = await _api.checkPermission() ?? false;
      if (!granted) return ShizukuStatus.permissionDenied;

      return ShizukuStatus.ready;
    } catch (_) {
      return ShizukuStatus.notInstalled;
    }
  }

  Future<bool> requestPermission() async {
    try {
      await _api.requestPermission();
      return await _api.checkPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Execute a shell command via Shizuku and return stdout.
  Future<String?> exec(String command) async {
    try {
      return await _channel.invokeMethod<String>(
        'execCommand',
        {'command': command},
      );
    } on PlatformException {
      return null;
    }
  }
}
