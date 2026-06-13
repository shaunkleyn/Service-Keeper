import 'package:shared_preferences/shared_preferences.dart';
import '../models/monitored_service.dart';
import 'database_service.dart';

class StorageService {
  final _db = DatabaseService();

  // SharedPreferences key used by MonitorWorker.kt on the native side
  static const _nativeKey = 'monitored_services';

  Future<List<MonitoredService>> loadServices() => _db.loadServices();

  Future<void> saveServices(List<MonitoredService> services) async {
    await _db.saveAllServices(services);
    await _syncToPrefs(services);
  }

  Future<void> addService(MonitoredService service) async {
    await _db.upsertService(service);
    await _syncToPrefs(await _db.loadServices());
  }

  Future<void> removeService(MonitoredService service) async {
    await _db.removeService(service);
    await _syncToPrefs(await _db.loadServices());
  }

  Future<void> updateService(MonitoredService service) async {
    await _db.upsertService(service);
    await _syncToPrefs(await _db.loadServices());
  }

  /// Keeps flutter.monitored_services in SharedPreferences so MonitorWorker
  /// can read it on device boot without needing Flutter running.
  Future<void> _syncToPrefs(List<MonitoredService> services) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nativeKey, MonitoredService.listToJson(services));
  }
}
