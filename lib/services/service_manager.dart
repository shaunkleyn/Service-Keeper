import '../models/monitored_service.dart';
import 'shizuku_service.dart';
import 'app_info_service.dart';

class ServiceManager {
  final ShizukuService _shizuku;
  final _appInfo = AppInfoService();

  ServiceManager(this._shizuku);

  /// Parse `dumpsys activity services` output into RunningService list.
  List<RunningService> _parseDumpsys(String raw) {
    final services = <RunningService>[];
    // Lines look like:
    //   ServiceRecord{abc1234 u0 com.example/.MyService}
    // Newer Android may use 0x prefix or uppercase hex for the address.
    // Android 16+ appends ` c:<caller>` before the closing brace, so don't anchor on `}`.
    final re = RegExp(
      r'ServiceRecord\{(?:0x)?[0-9a-f]+ +u\d+ +([^\s/}]+)/([^\s}]+)',
      caseSensitive: false,
    );
    for (final match in re.allMatches(raw)) {
      final pkg = match.group(1)!;
      var cls = match.group(2)!;
      // Expand short-form class names
      if (cls.startsWith('.')) cls = pkg + cls;
      services.add(RunningService(packageName: pkg, serviceClass: cls));
    }
    return services;
  }

  /// All installed services (non-system apps) with isRunning flag set.
  Future<List<RunningService>> listAllServices() async {
    final installed = await _appInfo.getInstalledServices();

    // Build a set of currently-running service keys for O(1) lookup
    final runningKeys = <String>{};
    try {
      final output = await _shizuku.exec('dumpsys activity services');
      if (output != null) {
        for (final s in _parseDumpsys(output)) {
          runningKeys.add('${s.packageName}/${s.serviceClass}');
        }
      }
    } catch (_) {}

    return installed.map((e) => RunningService(
      packageName: e.packageName,
      serviceClass: e.serviceClass,
      appName: e.appName,
      isRunning: runningKeys.contains('${e.packageName}/${e.serviceClass}'),
    )).toList();
  }

  Future<List<RunningService>> listRunningServices() async {
    final output = await _shizuku.exec('dumpsys activity services');
    if (output == null) {
      throw Exception('Shell command returned no output. Is Shizuku active?');
    }
    return _parseDumpsys(output);
  }

  Future<bool> isServiceRunning(MonitoredService service) async {
    final output = await _shizuku.exec(
      'dumpsys activity services ${service.packageName}',
    );
    if (output == null) return false;
    return output.contains(service.serviceClass);
  }

  /// Start (or restart) a service. Returns true if command sent successfully.
  Future<bool> startService(MonitoredService service) async {
    final result = await _shizuku.exec(
      'am start-foreground-service -n ${service.fullServiceName}',
    );
    // Fallback to regular startservice for older APIs
    if (result == null || result.contains('Error')) {
      final fallback = await _shizuku.exec(
        'am startservice -n ${service.fullServiceName}',
      );
      return fallback != null && !fallback.contains('Error');
    }
    return true;
  }

  /// Force-stop then restart — harder reset for stubborn services.
  Future<bool> forceRestartService(MonitoredService service) async {
    await _shizuku.exec('am force-stop ${service.packageName}');
    // Brief pause to let the process fully die
    await Future.delayed(const Duration(seconds: 2));
    return startService(service);
  }

  /// Check and restart if dead. Returns true if a restart was triggered.
  Future<bool> ensureRunning(MonitoredService service) async {
    final running = await isServiceRunning(service);
    if (running) return false;
    await startService(service);
    return true;
  }
}
