/// Design token constants for spacing, icon sizes, and layout dimensions.
///
/// Only values that appear in 2+ places OR have a clear semantic meaning
/// are defined here. Single-use inline values are left at their call sites.
abstract final class AppSpacing {
  // Base scale
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  // Screen / layout
  static const double screenPadding = 16;
  static const double cardPadding = 12;
  static const double cardPaddingLg = 14;

  // Icon sizes
  static const double iconXs = 11;
  static const double iconSm = 12;
  static const double iconMd = 16;
  static const double iconLg = 18;
  static const double iconXl = 20;

  // Component-specific
  static const double statusDotSize = 8;
  static const double avatarRadius = 20;
}
