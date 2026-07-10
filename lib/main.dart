import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'screens/main_shell.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == 'serviceCheck' && inputData != null) {
      final pkg = inputData['packageName'] as String?;
      final cls = inputData['serviceClass'] as String?;
      final label = inputData['displayLabel'] as String? ?? '';
      final selfChain = inputData['selfChain'] as bool? ?? false;
      final intervalMinutes = inputData['intervalMinutes'] as int? ?? 15;

      if (pkg != null && cls != null) {
        await _checkAndRestart(pkg, cls, label);
      }

      // Re-schedule self for sub-15-min intervals
      if (selfChain && pkg != null && cls != null) {
        final tag = '${pkg}_${cls.replaceAll('.', '_')}';
        Workmanager().registerOneOffTask(
          '${tag}_once',
          'serviceCheck',
          tag: tag,
          initialDelay: Duration(minutes: intervalMinutes),
          inputData: inputData,
        );
      }
    }
    return Future.value(true);
  });
}

Future<void> _checkAndRestart(
    String packageName, String serviceClass, String label) async {
  // Native shell execution is not directly available in the Dart isolate;
  // the MonitorWorker.kt handles the actual Shizuku calls from WorkManager.
  // This Dart callback is a placeholder for any pure-Dart work.
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );

  runApp(const ServiceKeeperApp());
}

class ServiceKeeperApp extends StatelessWidget {
  const ServiceKeeperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Service Keeper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MainShell(),
    );
  }
}
