import 'package:flutter_test/flutter_test.dart';
import 'package:service_keeper/models/monitored_service.dart';
import 'package:service_keeper/services/backup_service.dart';

void main() {
  group('AppBackupSettings', () {
    test('toJson includes all fields', () {
      const s = AppBackupSettings(
        useAppColors: true,
        globalIntervalEnabled: false,
        defaultCheckInterval: 30,
        useMaterialYou: true,
      );
      final json = s.toJson();
      expect(json['use_app_colors'], true);
      expect(json['global_interval_enabled'], false);
      expect(json['default_check_interval'], 30);
      expect(json['use_material_you'], true);
    });

    test('fromJson round-trips', () {
      const original = AppBackupSettings(
        useAppColors: true,
        globalIntervalEnabled: false,
        defaultCheckInterval: 60,
        useMaterialYou: false,
      );
      final restored = AppBackupSettings.fromJson(original.toJson());
      expect(restored, original);
    });

    test('fromJson uses defaults for missing keys', () {
      final s = AppBackupSettings.fromJson({});
      expect(s.useAppColors, false);
      expect(s.globalIntervalEnabled, true);
      expect(s.defaultCheckInterval, 15);
      expect(s.useMaterialYou, false);
    });
  });

  group('BackupService.encode / decode', () {
    BackupData _makeData({List<MonitoredService>? services}) {
      return BackupData(
        version: BackupService.currentVersion,
        exportedAt: DateTime(2025, 6, 1, 12),
        services: services ?? [
          const MonitoredService(
            packageName: 'com.example.app',
            serviceClass: 'com.example.app.MyService',
            displayLabel: 'My Service',
            appName: 'Example',
            intervalMinutes: 15,
            enabled: true,
            notificationsEnabled: true,
            appRestartEnabled: false,
          ),
        ],
        a11yMonitoredKeys: {'com.example.app/com.example.app.A11yService'},
        notifMonitoredKeys: {'com.example.app/com.example.app.NotifService'},
        a11yNotifOffKeys: {},
        notifListenerNotifOffKeys: {},
        settings: const AppBackupSettings(
          useAppColors: true,
          globalIntervalEnabled: true,
          defaultCheckInterval: 30,
        ),
        auditLog: [],
      );
    }

    test('encode produces valid JSON with version 3', () {
      final json = BackupService.encode(_makeData());
      expect(json, contains('"version":3'));
      expect(json, contains('"appSettings"'));
      expect(json, contains('"services"'));
    });

    test('decode round-trips all fields', () {
      final original = _makeData();
      final restored = BackupService.decode(BackupService.encode(original));

      expect(restored.version, BackupService.currentVersion);
      expect(restored.services.length, 1);
      expect(restored.services[0].packageName, 'com.example.app');
      expect(restored.services[0].enabled, true);
      expect(restored.a11yMonitoredKeys, {'com.example.app/com.example.app.A11yService'});
      expect(restored.notifMonitoredKeys, {'com.example.app/com.example.app.NotifService'});
      expect(restored.settings.useAppColors, true);
      expect(restored.settings.defaultCheckInterval, 30);
    });

    test('decode version 1 — no a11y/notif keys, default settings', () {
      const v1 = '{"version":1,"services":[{"packageName":"com.a","serviceClass":"com.a.S","displayLabel":"S","intervalMinutes":15,"enabled":true,"notificationsEnabled":true,"appRestartEnabled":false}]}';
      final data = BackupService.decode(v1);
      expect(data.version, 1);
      expect(data.a11yMonitoredKeys, isEmpty);
      expect(data.notifMonitoredKeys, isEmpty);
      expect(data.settings, const AppBackupSettings());
    });

    test('decode version 2 — has a11y/notif keys, default settings', () {
      final v2 = '{"version":2,"exportedAt":"2025-01-01T00:00:00.000","services":[],'
          '"a11yMonitoredKeys":["com.foo/com.foo.A"],'
          '"notifMonitoredKeys":[],"a11yNotifOffKeys":[],'
          '"notifListenerNotifOffKeys":[],"auditLog":[]}';
      final data = BackupService.decode(v2);
      expect(data.a11yMonitoredKeys, {'com.foo/com.foo.A'});
      expect(data.settings, const AppBackupSettings());
    });
  });

  group('BackupService.findMissingPackages', () {
    test('returns packages not in installed set', () {
      final services = [
        const MonitoredService(packageName: 'com.installed', serviceClass: 'com.installed.S', displayLabel: 'S', intervalMinutes: 15),
        const MonitoredService(packageName: 'com.missing', serviceClass: 'com.missing.S', displayLabel: 'S', intervalMinutes: 15),
      ];
      final missing = BackupService.findMissingPackages(services, {'com.installed'});
      expect(missing, {'com.missing'});
    });

    test('returns empty when all installed', () {
      final services = [
        const MonitoredService(packageName: 'com.a', serviceClass: 'com.a.S', displayLabel: 'S', intervalMinutes: 15),
      ];
      expect(BackupService.findMissingPackages(services, {'com.a'}), isEmpty);
    });

    test('returns empty for empty service list', () {
      expect(BackupService.findMissingPackages([], {'com.a'}), isEmpty);
    });
  });

  group('BackupService.disableMissingServices', () {
    test('disables services for missing packages', () {
      final services = [
        const MonitoredService(packageName: 'com.missing', serviceClass: 'com.missing.S', displayLabel: 'S', intervalMinutes: 15, enabled: true),
        const MonitoredService(packageName: 'com.present', serviceClass: 'com.present.S', displayLabel: 'S', intervalMinutes: 15, enabled: true),
      ];
      final result = BackupService.disableMissingServices(services, {'com.missing'});
      expect(result.length, 2);
      expect(result.firstWhere((s) => s.packageName == 'com.missing').enabled, false);
      expect(result.firstWhere((s) => s.packageName == 'com.present').enabled, true);
    });

    test('preserves non-missing service fields', () {
      final services = [
        const MonitoredService(
          packageName: 'com.present',
          serviceClass: 'com.present.S',
          displayLabel: 'My Service',
          intervalMinutes: 30,
          enabled: true,
          notificationsEnabled: false,
          appRestartEnabled: true,
        ),
      ];
      final result = BackupService.disableMissingServices(services, {});
      expect(result[0].intervalMinutes, 30);
      expect(result[0].notificationsEnabled, false);
      expect(result[0].appRestartEnabled, true);
    });

    test('clears runtime state for missing services', () {
      final services = [
        MonitoredService(
          packageName: 'com.missing',
          serviceClass: 'com.missing.S',
          displayLabel: 'S',
          intervalMinutes: 15,
          enabled: true,
          wasRunning: true,
          lastChecked: DateTime(2025),
          lastRestarted: DateTime(2025),
        ),
      ];
      final result = BackupService.disableMissingServices(services, {'com.missing'});
      expect(result[0].wasRunning, isNull);
      expect(result[0].lastChecked, isNull);
      expect(result[0].lastRestarted, isNull);
    });

    test('no-op when missingPackages is empty', () {
      final services = [
        const MonitoredService(packageName: 'com.a', serviceClass: 'com.a.S', displayLabel: 'S', intervalMinutes: 15),
      ];
      final result = BackupService.disableMissingServices(services, {});
      expect(identical(result, services), true);
    });
  });

  group('BackupService.filterKeysForMissing', () {
    test('removes keys for missing packages', () {
      final keys = {
        'com.missing/com.missing.A',
        'com.present/com.present.A',
      };
      final result = BackupService.filterKeysForMissing(keys, {'com.missing'});
      expect(result, {'com.present/com.present.A'});
    });

    test('no-op when no missing packages', () {
      final keys = {'com.a/com.a.S', 'com.b/com.b.S'};
      final result = BackupService.filterKeysForMissing(keys, {});
      expect(identical(result, keys), true);
    });

    test('returns empty set when all keys are for missing packages', () {
      final keys = {'com.missing/com.missing.A'};
      expect(BackupService.filterKeysForMissing(keys, {'com.missing'}), isEmpty);
    });
  });
}
