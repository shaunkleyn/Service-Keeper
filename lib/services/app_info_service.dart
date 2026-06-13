import 'package:flutter/services.dart';

class AppInfoService {
  static const _channel = MethodChannel('com.shaunkleyn.service_keeper/shizuku');

  Future<String?> getAppName(String packageName) async {
    try {
      return await _channel.invokeMethod<String>('getAppName', {'packageName': packageName});
    } on PlatformException {
      return null;
    }
  }

  Future<Uint8List?> getAppIcon(String packageName) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('getAppIcon', {'packageName': packageName});
      return bytes;
    } on PlatformException {
      return null;
    }
  }

  /// Returns all declared services from installed non-system apps.
  /// Each entry has keys: p (packageName), c (serviceClass), n (appName).
  Future<List<({String packageName, String serviceClass, String appName})>> getInstalledServices({bool includeSystem = false}) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'getInstalledServices',
        {'includeSystem': includeSystem},
      );
      if (raw == null) return [];
      return raw.map((item) {
        final m = Map<String, dynamic>.from(item as Map);
        return (
          packageName: (m['p'] as String?) ?? '',
          serviceClass: (m['c'] as String?) ?? '',
          appName: (m['n'] as String?) ?? '',
        );
      }).where((e) => e.packageName.isNotEmpty && e.serviceClass.isNotEmpty).toList();
    } on PlatformException {
      return [];
    }
  }
}
