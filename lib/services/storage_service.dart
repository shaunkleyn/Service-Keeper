import 'package:shared_preferences/shared_preferences.dart';
import '../models/monitored_service.dart';

class StorageService {
  static const _key = 'monitored_services';

  Future<List<MonitoredService>> loadServices() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return MonitoredService.listFromJson(raw);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveServices(List<MonitoredService> services) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, MonitoredService.listToJson(services));
  }

  Future<void> addService(MonitoredService service) async {
    final list = await loadServices();
    if (!list.contains(service)) {
      list.add(service);
      await saveServices(list);
    }
  }

  Future<void> removeService(MonitoredService service) async {
    final list = await loadServices();
    list.remove(service);
    await saveServices(list);
  }

  Future<void> updateService(MonitoredService service) async {
    final list = await loadServices();
    final idx = list.indexOf(service);
    if (idx >= 0) {
      list[idx] = service;
    } else {
      list.add(service);
    }
    await saveServices(list);
  }
}
