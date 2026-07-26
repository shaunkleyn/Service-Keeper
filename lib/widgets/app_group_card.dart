import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Sliver-based expandable app group card.
/// Must be placed inside a [CustomScrollView]'s slivers list.
/// Caller owns the [expanded] state to preserve it across scroll recycling.
class AppGroupCard extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final String packageName;
  final String appName;
  final Uint8List? iconBytes;
  final Color? appColor;
  final String subtitle;

  /// 3-state toggle: 0 = disabled, 1 = monitor (silent), 2 = notify.
  /// Pass null to hide the toggle entirely.
  final int? groupState;
  final bool hasIssue;
  final void Function(int)? onGroupStateChanged;

  final List<PopupMenuEntry<String>> menuItems;
  final void Function(String) onMenuSelected;
  final List<Widget> children;

  /// Optional widget to override the default icon/avatar.
  final Widget? icon;

  /// Called on long-press (normal mode) or on tap (selection mode).
  final VoidCallback? onSelect;

  final bool isInSelectionMode;
  final bool isSelected;
  final bool isPartiallySelected;

  const AppGroupCard({
    super.key,
    required this.expanded,
    required this.onToggleExpanded,
    required this.packageName,
    required this.appName,
    this.iconBytes,
    this.appColor,
    required this.subtitle,
    this.groupState,
    this.hasIssue = false,
    this.onGroupStateChanged,
    required this.menuItems,
    required this.onMenuSelected,
    required this.children,
    this.icon,
    this.onSelect,
    this.isInSelectionMode = false,
    this.isSelected = false,
    this.isPartiallySelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    final bodyBg = appColor == null
        ? theme.colorScheme.surfaceContainerLow
        : Color.alphaBlend(
            appColor!.withValues(alpha: dark ? 0.22 : 0.10),
            dark ? const Color(0xFF1C1C1C) : Colors.white,
          );

    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(
          pinned: expanded,
          delegate: _AppGroupCardHeaderDelegate(
            expanded: expanded,
            onToggleExpanded: onToggleExpanded,
            packageName: packageName,
            appName: appName,
            iconBytes: iconBytes,
            appColor: appColor,
            subtitle: subtitle,
            groupState: groupState,
            hasIssue: hasIssue,
            onGroupStateChanged: onGroupStateChanged,
            menuItems: menuItems,
            onMenuSelected: onMenuSelected,
            icon: icon,
            onSelect: onSelect,
            isInSelectionMode: isInSelectionMode,
            isSelected: isSelected,
            isPartiallySelected: isPartiallySelected,
          ),
        ),
        if (expanded && children.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                child: ColoredBox(
                  color: bodyBg,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < children.length; i++) ...[
                        children[i],
                        if (i < children.length - 1)
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: theme.colorScheme.outlineVariant
                                .withValues(alpha: 0.5),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AppGroupCardHeaderDelegate extends SliverPersistentHeaderDelegate {
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final String packageName;
  final String appName;
  final Uint8List? iconBytes;
  final Color? appColor;
  final String subtitle;
  final int? groupState;
  final bool hasIssue;
  final void Function(int)? onGroupStateChanged;
  final List<PopupMenuEntry<String>> menuItems;
  final void Function(String) onMenuSelected;
  final Widget? icon;
  final VoidCallback? onSelect;
  final bool isInSelectionMode;
  final bool isSelected;
  final bool isPartiallySelected;

  const _AppGroupCardHeaderDelegate({
    required this.expanded,
    required this.onToggleExpanded,
    required this.packageName,
    required this.appName,
    this.iconBytes,
    this.appColor,
    required this.subtitle,
    this.groupState,
    this.hasIssue = false,
    this.onGroupStateChanged,
    required this.menuItems,
    required this.onMenuSelected,
    this.icon,
    this.onSelect,
    this.isInSelectionMode = false,
    this.isSelected = false,
    this.isPartiallySelected = false,
  });

  @override
  double get minExtent => 80;
  @override
  double get maxExtent => 80;

  @override
bool shouldRebuild(_AppGroupCardHeaderDelegate old) =>
    expanded != old.expanded ||
    packageName != old.packageName ||
    appName != old.appName ||
    iconBytes != old.iconBytes ||
    appColor != old.appColor ||
    subtitle != old.subtitle ||
    groupState != old.groupState ||
    hasIssue != old.hasIssue ||
    icon != old.icon ||
    isInSelectionMode != old.isInSelectionMode ||
    isSelected != old.isSelected ||
    isPartiallySelected != old.isPartiallySelected;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);

    final Color? headerFg = appColor == null
        ? null
        : (ThemeData.estimateBrightnessForColor(appColor!) == Brightness.dark
            ? Colors.white
            : Colors.black87);

    final dark = theme.brightness == Brightness.dark;

    final bodyBg = appColor == null
        ? theme.colorScheme.surfaceContainerLow
        : Color.alphaBlend(
            appColor!.withValues(alpha: dark ? 0.22 : 0.10),
            dark ? const Color(0xFF1C1C1C) : Colors.white,
          );

    Color bgColor = appColor ?? theme.colorScheme.surfaceContainerHighest;
    if (isSelected || isPartiallySelected) {
      bgColor = Color.alphaBlend(
          theme.colorScheme.primary.withValues(alpha: 0.15), bgColor);
    }
    final fg = headerFg ?? theme.colorScheme.onSurface;

    final cardRadius = BorderRadius.only(
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: expanded ? Radius.zero : const Radius.circular(12),
      bottomRight: expanded ? Radius.zero : const Radius.circular(12),
    );

    final Widget avatar = icon ??
        (iconBytes != null
            ? CircleAvatar(
                radius: 20,
                backgroundImage: MemoryImage(iconBytes!),
                backgroundColor: Colors.transparent,
              )
            : CircleAvatar(
                radius: 20,
                backgroundColor: appColor ?? theme.colorScheme.primaryContainer,
                child: Text(
                  packageName.isNotEmpty
                      ? packageName.split('.').last[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                      color: headerFg ?? theme.colorScheme.onPrimaryContainer),
                ),
              ));

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          color: bgColor,
          borderRadius: cardRadius,
          elevation: overlapsContent ? 4 : 1,
          shadowColor: Colors.black26,
          child: InkWell(
            borderRadius: cardRadius,
            onTap: isInSelectionMode && onSelect != null
                ? onSelect
                : onToggleExpanded,
            onLongPress: !isInSelectionMode ? onSelect : null,
            child: SizedBox(
              height: 72,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    if (isInSelectionMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: isPartiallySelected
                            ? Icon(Icons.indeterminate_check_box_outlined,
                                color: fg, size: 20)
                            : (isSelected
                                ? Icon(Icons.check_box, color: fg, size: 20)
                                : Icon(Icons.check_box_outline_blank,
                                    color: fg.withValues(alpha: 0.5), size: 20)),
                      ),
                    avatar,
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Tooltip(
                            message: appName,
                            waitDuration: const Duration(milliseconds: 350),
                            child: Text(
                              appName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: fg,
                              ),
                            ),
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                              color: headerFg?.withValues(alpha: 0.75) ??
                                  theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (groupState != null && onGroupStateChanged != null)
                      _buildToggle(theme, fg, bodyBg, appColor: appColor),
                    if (menuItems.isNotEmpty)
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, size: 20, color: fg),
                        padding: EdgeInsets.zero,
                        onSelected: onMenuSelected,
                        itemBuilder: (_) => menuItems,
                      ),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.expand_more, color: fg),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToggle(ThemeData theme, Color fg, Color bodyBg, {Color? appColor}) {
    final cs = theme.colorScheme;
    final current = groupState!;

    final Color pillColor = switch (current) {
      0 => Colors.transparent, // cs.error,
      1 => hasIssue ? cs.errorContainer : cs.tertiary,
      _ => cs.primary,
    };
    final Color onPill = switch (current) {
      0 => cs.onError,
      1 => hasIssue ? cs.onErrorContainer : cs.onTertiary,
      _ => cs.onPrimary,
    };

    final headerBg = appColor ?? cs.surfaceContainerLow;
    final bool darkHeader = ThemeData.estimateBrightnessForColor(headerBg) == Brightness.dark;
    final Color trackBg = appColor != null
        ? (darkHeader ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.10))
        : cs.surfaceContainerLow;
    final Color borderColor = darkHeader
        ? Colors.white.withValues(alpha: 0.40)
        : Colors.black.withValues(alpha: current == 0 ? 0.5 : 0.22);
    final Color dimColor = appColor != null
        ? (darkHeader ? Colors.white.withValues(alpha: 0.50) : Colors.black.withValues(alpha: 0.38))
        : cs.onSurfaceVariant.withValues(alpha: 0.6);

    final icons = [
      current >= 1 ? Icons.check_circle_outline : Icons.block_outlined,
      Icons.visibility,
      Icons.notifications_active,
    ];
    const tooltips = ['Disabled', 'Monitor only', 'Monitor & notify'];

    // Track geometry: pill and thumb are inset from the border by trackPad,
    // producing the gap that makes the pill look like a thumb inside the track.
    const totalWidth = 36.0 * 3;
    const height = 34.0;
    const trackPad = 1.0;
    final thumbSize = height - (current == 0 ? 12.0 : 8.0 * trackPad);             // 28 — fills inner height
    const slotWidth = (totalWidth - 2 * trackPad) / 3;  // 34 — inner slot width
    final thumbLeft = trackPad + slotWidth * current + (slotWidth - thumbSize) / 2;

    return SizedBox(
      width: totalWidth,
      height: height,
      child: Stack(
        children: [
          // Track border + background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: trackBg,
                borderRadius: BorderRadius.circular(height / 2),
                border: Border.all(color: borderColor, width: 1.5),
              ),
            ),
          ),
          // Growing fill pill — inset from track by trackPad on all sides
          Positioned(
            left: trackPad,
            top: trackPad,
            bottom: trackPad,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: slotWidth * (current + 1),
              decoration: BoxDecoration(
                color: pillColor,
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
          // Sliding thumb — white circle on top of pill
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            left: thumbLeft,
            top: height / 2 - thumbSize / 2,
            child: Container(
              width: thumbSize,
              height: thumbSize,
              decoration: BoxDecoration(
                color: current == 0 ? Colors.black54 : Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: current > 0 ? Colors.black.withOpacity(0.22) : Colors.transparent,
                    blurRadius: current == 0 ? 0 : 4,
                    spreadRadius: current == 0 ? 0 : 1,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          // Icons — span the inner area so each sits centered in its slot
          Positioned(
            left: trackPad, // slight nudge to center the first icon in the pill
            top: 0,
            right: trackPad,
            bottom: 0,
            child: Row(
              children: List.generate(3, (i) => Tooltip(
                message: tooltips[i],
                waitDuration: const Duration(milliseconds: 350),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onGroupStateChanged!(i),
                  child: SizedBox(
                    width: slotWidth,
                    child: Icon(
                      icons[i],
                      size: 15,
                      // on pill (not thumb): onPill; on thumb: pillColor on white; off: dim
                      color: i < current || i == 0
                          ? onPill
                          : (i == current ? pillColor : dimColor),
                    ),
                  ),
                ),
              )),
            ),
          ),
        ],
      ),
    );
  }
}
