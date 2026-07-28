import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Midpoint of the icon's cyan-teal gradient
const brandSeed = Color(0xFF00C4A8);

const _subThemes = FlexSubThemesData(
  interactionEffects: true,
  defaultRadius: 10,
  elevatedButtonRadius: 10,
  outlinedButtonRadius: 10,
  textButtonRadius: 10,
  filledButtonRadius: 10,
  cardRadius: 10,
  inputDecoratorRadius: 8,
  inputDecoratorUnfocusedHasBorder: true,
  dialogRadius: 16,
  bottomSheetRadius: 16,
  chipRadius: 8,
  switchSchemeColor: SchemeColor.primary,
  checkboxSchemeColor: SchemeColor.primary,
  radioSchemeColor: SchemeColor.primary,
  navigationBarSelectedLabelSchemeColor: SchemeColor.primary,
  navigationBarSelectedIconSchemeColor: SchemeColor.primary,
  navigationBarIndicatorSchemeColor: SchemeColor.primaryContainer,
);

ThemeData buildLightTheme(ColorScheme? dynamic, Color? seed) {
  final scheme = dynamic ??
      ColorScheme.fromSeed(
          seedColor: seed ?? brandSeed, brightness: Brightness.light);
  return FlexColorScheme.light(
    colorScheme: scheme,
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
    blendLevel: 5,
    subThemesData: _subThemes,
  ).toTheme.copyWith(
    textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
    extensions: [AppThemeExtension.light],
  );
}

ThemeData buildDarkTheme(ColorScheme? dynamic, Color? seed) {
  final scheme = dynamic ??
      ColorScheme.fromSeed(
          seedColor: seed ?? brandSeed, brightness: Brightness.dark);
  return FlexColorScheme.dark(
    colorScheme: scheme,
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
    blendLevel: 10,
    subThemesData: _subThemes,
  ).toTheme.copyWith(
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    extensions: [AppThemeExtension.dark],
  );
}

/// Semantic color tokens for the app.
///
/// Colors that already use [ColorScheme] values (e.g. error, tertiary) are
/// intentionally absent — resolve those directly from [Theme.of(context).colorScheme].
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  final Color serviceRunning;
  final Color serviceStopped;
  final Color serviceRestarting;
  final Color serviceFrequent;
  final Color bannerShizukuOk;
  final Color bannerShizukuWarn;
  final Color bannerBattery;
  final Color bannerNotification;
  final Color destructive;

  const AppThemeExtension({
    required this.serviceRunning,
    required this.serviceStopped,
    required this.serviceRestarting,
    required this.serviceFrequent,
    required this.bannerShizukuOk,
    required this.bannerShizukuWarn,
    required this.bannerBattery,
    required this.bannerNotification,
    required this.destructive,
  });

  @override
  AppThemeExtension copyWith({
    Color? serviceRunning,
    Color? serviceStopped,
    Color? serviceRestarting,
    Color? serviceFrequent,
    Color? bannerShizukuOk,
    Color? bannerShizukuWarn,
    Color? bannerBattery,
    Color? bannerNotification,
    Color? destructive,
  }) =>
      AppThemeExtension(
        serviceRunning: serviceRunning ?? this.serviceRunning,
        serviceStopped: serviceStopped ?? this.serviceStopped,
        serviceRestarting: serviceRestarting ?? this.serviceRestarting,
        serviceFrequent: serviceFrequent ?? this.serviceFrequent,
        bannerShizukuOk: bannerShizukuOk ?? this.bannerShizukuOk,
        bannerShizukuWarn: bannerShizukuWarn ?? this.bannerShizukuWarn,
        bannerBattery: bannerBattery ?? this.bannerBattery,
        bannerNotification: bannerNotification ?? this.bannerNotification,
        destructive: destructive ?? this.destructive,
      );

  @override
  AppThemeExtension lerp(AppThemeExtension? other, double t) {
    if (other == null) return this;
    return AppThemeExtension(
      serviceRunning: Color.lerp(serviceRunning, other.serviceRunning, t)!,
      serviceStopped: Color.lerp(serviceStopped, other.serviceStopped, t)!,
      serviceRestarting:
          Color.lerp(serviceRestarting, other.serviceRestarting, t)!,
      serviceFrequent: Color.lerp(serviceFrequent, other.serviceFrequent, t)!,
      bannerShizukuOk:
          Color.lerp(bannerShizukuOk, other.bannerShizukuOk, t)!,
      bannerShizukuWarn:
          Color.lerp(bannerShizukuWarn, other.bannerShizukuWarn, t)!,
      bannerBattery: Color.lerp(bannerBattery, other.bannerBattery, t)!,
      bannerNotification:
          Color.lerp(bannerNotification, other.bannerNotification, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
    );
  }

  static const light = AppThemeExtension(
    serviceRunning: Color(0xFF2E7D32),
    serviceStopped: Colors.grey,
    serviceRestarting: Colors.orange,
    serviceFrequent: Color(0xFFE65100),
    bannerShizukuOk: Colors.green,
    bannerShizukuWarn: Colors.orange,
    bannerBattery: Colors.deepOrange,
    bannerNotification: Colors.amber,
    destructive: Colors.red,
  );

  static const dark = AppThemeExtension(
    serviceRunning: Color(0xFF66BB6A),
    serviceStopped: Colors.grey,
    serviceRestarting: Colors.orange,
    serviceFrequent: Color(0xFFE65100),
    bannerShizukuOk: Color(0xFF66BB6A),
    bannerShizukuWarn: Colors.orange,
    bannerBattery: Colors.deepOrange,
    bannerNotification: Colors.amber,
    destructive: Color(0xFFEF5350),
  );
}

extension AppThemeX on BuildContext {
  AppThemeExtension get appTheme =>
      Theme.of(this).extension<AppThemeExtension>()!;
}
