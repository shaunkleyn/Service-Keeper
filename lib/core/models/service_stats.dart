import 'package:flutter/material.dart';

enum ServiceHealth { excellent, good, fair, poor }

extension ServiceHealthX on ServiceHealth {
  String get label => switch (this) {
        ServiceHealth.excellent => 'Excellent',
        ServiceHealth.good => 'Good',
        ServiceHealth.fair => 'Fair',
        ServiceHealth.poor => 'Poor',
      };

  Color color(ColorScheme cs) => switch (this) {
        ServiceHealth.excellent => const Color(0xFF2E7D32),
        ServiceHealth.good => cs.primary,
        ServiceHealth.fair => const Color(0xFFE65100),
        ServiceHealth.poor => cs.error,
      };
}

class ServiceStats {
  final int restarts7d;
  final int restarts30d;
  final int appRestarts7d;
  final int appRestarts30d;
  final int failed7d;

  const ServiceStats({
    this.restarts7d = 0,
    this.restarts30d = 0,
    this.appRestarts7d = 0,
    this.appRestarts30d = 0,
    this.failed7d = 0,
  });

  bool get hasData => restarts30d > 0 || appRestarts30d > 0;
  bool get isFrequent => restarts7d >= 3;
  bool get triggeredAppRestart => appRestarts30d > 0;

  ServiceHealth get health {
    if (appRestarts7d > 0 || restarts7d >= 7) return ServiceHealth.poor;
    if (restarts7d >= 3) return ServiceHealth.fair;
    if (restarts7d >= 1) return ServiceHealth.good;
    return ServiceHealth.excellent;
  }
}

class AppStats {
  final Map<String, ServiceStats> byService;

  const AppStats({required this.byService});

  static const empty = AppStats(byService: {});

  bool get hasAnyData => byService.values.any((s) => s.hasData);

  int get totalRestarts7d =>
      byService.values.fold(0, (a, s) => a + s.restarts7d);
  int get totalRestarts30d =>
      byService.values.fold(0, (a, s) => a + s.restarts30d);
  int get totalAppRestarts7d =>
      byService.values.fold(0, (a, s) => a + s.appRestarts7d);
  int get totalAppRestarts30d =>
      byService.values.fold(0, (a, s) => a + s.appRestarts30d);
  int get frequentCount =>
      byService.values.where((s) => s.isFrequent).length;

  ServiceHealth get overallHealth {
    if (totalAppRestarts7d > 0) return ServiceHealth.poor;
    if (byService.values.any((s) => s.health == ServiceHealth.poor)) {
      return ServiceHealth.poor;
    }
    if (frequentCount > 0 || totalAppRestarts30d > 0) return ServiceHealth.fair;
    if (totalRestarts7d > 0) return ServiceHealth.good;
    return ServiceHealth.excellent;
  }

  List<String> get appRestartCauserClasses => byService.entries
      .where((e) => e.value.triggeredAppRestart)
      .map((e) => e.key)
      .toList();
}
