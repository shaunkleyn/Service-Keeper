import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:service_keeper/core/services/app_icon_cache.dart';
import 'package:service_keeper/core/theme/app_settings_notifier.dart';

/// Shared mixin for [AccessibilityMonitorScreen] and
/// [NotificationMonitorScreen].
///
/// Provides common state fields, lifecycle management, and icon/color helpers
/// so the two screens do not duplicate the same boilerplate.
///
/// Consumers must call [initMonitorScreen] from [State.initState] and
/// [disposeMonitorScreen] from [State.dispose]. The [onColorfulCardsToggled]
/// hook is invoked whenever the colorful-cards setting changes and
/// [useAppColors] is already updated before the call, so implementors can
/// trigger a rebuild or kick off color generation there.
mixin MonitorScreenMixin<T extends StatefulWidget> on State<T>,
    WidgetsBindingObserver {
  // ---- shared fields -------------------------------------------------------

  Map<String, Uint8List?> iconCache = {};
  Map<String, Color> colorCache = {};
  Map<String, bool> expandedGroups = {};
  bool useAppColors = false;
  bool loading = true;
  bool permInfoDismissed = false;
  bool revokeBannerDismissed = false;

  // ---- lifecycle -----------------------------------------------------------

  /// Call from [initState] after [super.initState()] and
  /// [WidgetsBinding.instance.addObserver(this)].
  void initMonitorScreen() {
    colorfulCardsNotifier.addListener(_onColorfulCardsChanged);
  }

  /// Call from [dispose] before [super.dispose()].
  void disposeMonitorScreen() {
    colorfulCardsNotifier.removeListener(_onColorfulCardsChanged);
  }

  void _onColorfulCardsChanged() {
    if (!mounted) return;
    setState(() => useAppColors = colorfulCardsNotifier.value);
    onColorfulCardsToggled();
  }

  /// Override to react when [useAppColors] changes (e.g. trigger color
  /// generation). The default implementation does nothing.
  void onColorfulCardsToggled() {}

  // ---- icon / color helpers ------------------------------------------------

  /// Fetches icons for [packages] using [AppIconCache] and updates
  /// [iconCache]. Triggers a rebuild each time a previously missing icon is
  /// fetched from native.
  Future<void> fetchIcons(Set<String> packages) async {
    final fetched = await AppIconCache.instance.fetchIcons(
      packages,
      onFetched: (pkg, bytes) {
        if (mounted) setState(() => iconCache[pkg] = bytes);
      },
    );

    // Apply the full batch result (includes prefs-cached icons).
    if (mounted) {
      setState(() => iconCache = {...iconCache, ...fetched});
    }
  }

  /// Generates accent colors via [AppIconCache] and updates [colorCache].
  /// Triggers a rebuild each time a color becomes available.
  Future<void> generateColors() async {
    await AppIconCache.instance.generateColors(
      onColor: (pkg, color) {
        if (mounted) setState(() => colorCache[pkg] = color);
      },
    );
  }
}
