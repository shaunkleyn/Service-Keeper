import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:service_keeper/core/services/app_info_service.dart';

/// Centralized cache for app icons and derived accent colors.
///
/// Icons are persisted in SharedPreferences under `app_icon_v1_<pkg>` (base64
/// PNG) and colors under `app_color_v1_<pkg>` (ARGB int), matching the keys
/// used across the codebase before this service was introduced.
class AppIconCache {
  AppIconCache._();
  static final AppIconCache instance = AppIconCache._();

  final _appInfo = AppInfoService();

  // In-memory caches populated on each call.
  final Map<String, Uint8List?> _icons = {};
  final Map<String, Color> _colors = {};

  /// Returns the cached icon bytes for [packageName], or null if unavailable.
  Uint8List? getIcon(String packageName) => _icons[packageName];

  /// Returns the cached accent color for [packageName], or null if not yet
  /// generated.
  Color? getColor(String packageName) => _colors[packageName];

  /// Loads icons for [packages] from SharedPreferences (fast path) and fetches
  /// any missing ones from native via [AppInfoService]. Persists newly fetched
  /// icons to SharedPreferences.
  ///
  /// Returns a map of packageName -> icon bytes (null if unavailable).
  Future<Map<String, Uint8List?>> fetchIcons(
    Set<String> packages, {
    void Function(String pkg, Uint8List bytes)? onFetched,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Load from prefs first.
    final result = <String, Uint8List?>{};
    for (final pkg in packages) {
      final b64 = prefs.getString('app_icon_v1_$pkg');
      if (b64 != null) {
        final bytes = base64Decode(b64);
        result[pkg] = bytes;
        _icons[pkg] = bytes;
      }
    }

    // Fetch missing icons from native.
    final missing = packages.where((p) => !result.containsKey(p)).toSet();
    for (final pkg in missing) {
      final bytes = await _appInfo.getAppIcon(pkg);
      result[pkg] = bytes;
      _icons[pkg] = bytes;
      if (bytes != null) {
        await prefs.setString('app_icon_v1_$pkg', base64Encode(bytes));
        onFetched?.call(pkg, bytes);
      }
    }

    return result;
  }

  /// Generates accent colors for all packages currently in the icon cache.
  /// Colors are read from SharedPreferences first, then derived via
  /// [PaletteGenerator] if absent or stale. Calls [onColor] each time a color
  /// becomes available (so the caller can trigger a `setState`).
  Future<void> generateColors({
    required void Function(String pkg, Color color) onColor,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Phase 1: serve any already-persisted colors immediately.
    for (final pkg in _icons.keys) {
      if (_colors.containsKey(pkg)) {
        onColor(pkg, _colors[pkg]!);
        continue;
      }
      final cached = prefs.getInt('app_color_v1_$pkg');
      if (cached != null) {
        final color = Color(cached);
        _colors[pkg] = color;
        onColor(pkg, color);
      }
    }

    // Phase 2: generate colors from palette for any package not yet cached.
    for (final pkg in _icons.keys) {
      final bytes = _icons[pkg];
      if (bytes == null) continue;
      try {
        final palette = await PaletteGenerator.fromImageProvider(
          MemoryImage(bytes),
          maximumColorCount: 16,
        );
        final color = palette.vibrantColor?.color ??
            palette.lightVibrantColor?.color ??
            palette.dominantColor?.color;
        if (color != null) {
          final existing = prefs.getInt('app_color_v1_$pkg');
          if (existing != color.toARGB32()) {
            await prefs.setInt('app_color_v1_$pkg', color.toARGB32());
          }
          _colors[pkg] = color;
          onColor(pkg, color);
        }
      } catch (_) {}
    }
  }

  /// Clears the in-memory caches (does not touch SharedPreferences).
  void clear() {
    _icons.clear();
    _colors.clear();
  }
}
