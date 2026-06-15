import '../models/monitored_service.dart';
import 'shizuku_service.dart';
import 'app_info_service.dart';

class ServiceManager {
  final ShizukuService _shizuku;
  final _appInfo = AppInfoService();
  final Map<String, List<String>> _broadcastStartActionCache = {};

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

  /// Returns null if Shizuku exec fails (can't determine state).
  Future<bool?> isServiceRunning(MonitoredService service) async {
    final output = await _shizuku.exec(
      'dumpsys activity services ${service.packageName}',
    );
    if (output == null) return null;
    return _parseDumpsys(output).any(
      (s) => s.packageName == service.packageName && s.serviceClass == service.serviceClass,
    );
  }

  /// Start (or restart) a service. Returns (success, errorReason); errorReason is null on success.
  Future<(bool, String?)> startService(MonitoredService service) async {
    final result = await _shizuku.exec(
      'am start-foreground-service -n ${service.fullServiceName}',
    );
    if (result == null || result.contains('Error')) {
      final fallback = await _shizuku.exec(
        'am startservice -n ${service.fullServiceName}',
      );
      if (fallback != null && !fallback.contains('Error')) {
        return (true, null);
      }

      // If direct start is blocked by app export/permission rules,
      // attempt app-defined exported broadcast actions as a fallback.
      final (broadcastOk, broadcastReason) = await _tryBroadcastStartFallback(service);
      if (broadcastOk) return (true, broadcastReason);

      final reason = fallback == null
          ? (result != null ? _amError(result) : 'Shizuku returned null')
          : _amError(fallback);
      if (broadcastReason == null || broadcastReason.isEmpty) return (false, reason);
      return (false, '$reason; broadcast fallback failed: $broadcastReason');
    }
    return (true, null);
  }

  Future<(bool, String?)> _tryBroadcastStartFallback(MonitoredService service) async {
    final actions = await _getBroadcastStartActions(service.packageName);
    if (actions.isEmpty) {
      return (false, 'no matching exported start/toggle broadcast actions found');
    }

    final tried = <String>[];
    for (final action in actions) {
      tried.add(action);
      await _shizuku.exec(
        'am broadcast --user 0 --include-stopped-packages '
        '-a $action -p ${service.packageName}',
      );

      await Future.delayed(const Duration(seconds: 2));
      final running = await isServiceRunning(service);
      if (running == true) {
        return (true, 'restart method: broadcast fallback ($action)');
      }
    }

    return (false, 'tried actions: ${tried.join(', ')}');
  }

  Future<List<String>> _getBroadcastStartActions(String packageName) async {
    final cached = _broadcastStartActionCache[packageName];
    if (cached != null) return cached;

    final output = await _shizuku.exec('dumpsys package $packageName');
    final actions = <String>[];
    if (output != null) {
      final actionRegex = RegExp('Action: "([^"]+)"');
      for (final match in actionRegex.allMatches(output)) {
        final action = match.group(1);
        if (action == null) continue;
        final upper = action.toUpperCase();
        if (!upper.startsWith('${packageName.toUpperCase()}.')) continue;
        if (upper.contains('START') || upper.contains('TOGGLE') || upper.contains('RESTART')) {
          actions.add(action);
        }
      }
    }

    // Deterministic fallback guesses for apps that expose custom actions.
    final guesses = [
      '$packageName.INTENT_START_SERVICE',
      '$packageName.INTENT_RESTART_SERVICE',
      '$packageName.INTENT_TOGGLE_SERVICE',
      '$packageName.ACTION_START_SERVICE',
      '$packageName.ACTION_RESTART_SERVICE',
      '$packageName.ACTION_TOGGLE_SERVICE',
    ];

    final seen = <String>{};
    final deduped = <String>[];
    for (final action in [...actions, ...guesses]) {
      if (seen.add(action)) deduped.add(action);
    }

    _broadcastStartActionCache[packageName] = deduped;
    return deduped;
  }

  static String _amError(String output) {
    for (final line in output.split('\n')) {
      if (line.startsWith('Error:')) return line.replaceFirst('Error: ', '').trim();
    }
    return output.trim();
  }

  /// Force-stop then restart — harder reset for stubborn services.
  Future<bool> forceRestartService(MonitoredService service) async {
    await _shizuku.exec('am force-stop ${service.packageName}');
    await Future.delayed(const Duration(seconds: 2));
    final (ok, _) = await startService(service);
    return ok;
  }

  /// Check and restart if dead. Returns true if a restart was triggered.
  Future<bool> ensureRunning(MonitoredService service) async {
    final running = await isServiceRunning(service);
    if (running == true) return false;
    final (ok, _) = await startService(service);
    return ok;
  }
}
