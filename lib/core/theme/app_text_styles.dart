import 'package:flutter/material.dart';

/// Named text style helpers for patterns repeated 3+ times across the app.
///
/// Each method returns the structural shape of the style (size, weight, style)
/// without a color — callers supply color at the use site via `.copyWith(color: ...)`.
abstract final class AppTextStyles {
  /// 11 px body-small — used for service class names, stat labels, badge subtitles.
  static TextStyle? tinyLabel(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11);

  /// 11 px body-small, semibold — used for status chips, health labels.
  static TextStyle? tinyLabelBold(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          );

  /// 10 px body-small — used for timestamps, last-checked lines, meta rows.
  static TextStyle? metaLabel(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10);

  /// 10 px body-small, italic — used for next-check countdown and error hints.
  static TextStyle? metaLabelItalic(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 10,
            fontStyle: FontStyle.italic,
          );

  /// 10 px body-small, semibold — used for status-chip text inside small badges.
  static TextStyle? metaLabelBold(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w600,
          );
}
