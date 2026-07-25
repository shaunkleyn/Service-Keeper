import 'dart:typed_data';
import 'package:animated_toggle_switch/animated_toggle_switch.dart';
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
  bool shouldRebuild(_AppGroupCardHeaderDelegate old) => true;

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
                          Text(
                            appName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: fg,
                            ),
                          ),
                          Text(
                            subtitle,
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

    Color indicatorFor(int value, {Color? bg, Color? fg}) {
      final Color color1;
      switch (value) {
        case 0:
          color1 = current == 0 ? bg ?? cs.outlineVariant : fg ?? cs.secondaryContainer;
          break;
        case 1:
          color1 = hasIssue ? cs.errorContainer : (current >= 1 ? fg ?? cs.secondaryContainer : bg ?? cs.secondaryContainer);
          break;
        default:
          color1 = (current >= 2 ? bg ?? cs.secondaryContainer : fg ?? cs.secondaryContainer);
          break;
      }
      return color1;
    }

    Widget iconFor(int value, {Color? bg, Color? fg}) {
      final IconData icon;
      final Color color;

      switch (value) {
        case 0:
          icon = current == 0 ? Icons.block_outlined : Icons.check_circle;
          color = current == 0 ? fg ?? cs.onSurfaceVariant : fg ?? Colors.green;
          break;
        case 1:
          icon = current >= 1 ? Icons.visibility : Icons.visibility_off;
          color = current >= 1 ? fg ?? Colors.green : bg ?? cs.onSurfaceVariant;
        default:
          icon = current >= 2 ? Icons.notifications : Icons.notifications_off;
          color = current >= 2 ? fg ?? Colors.green : bg ?? cs.onSurfaceVariant;
      }

      return Icon(icon, size: 16, color: color);
    }

    return AnimatedToggleSwitch<int>.size(
      current: current,
      values: const [0, 1, 2],
      height: 32,
      indicatorSize: const Size(20, 20),
      borderWidth: 2,
      spacing: 10,
      iconOpacity: 1.0,
      selectedIconScale: 1.0,
      loading: false,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      animationDuration: const Duration(milliseconds: 250),
      style: ToggleStyle(
        backgroundColor: appColor != null
            ? fg.withValues(alpha: 0.3)
            : cs.surfaceContainerLow,
        borderColor: ThemeData.estimateBrightnessForColor(appColor ?? cs.surfaceContainerLow) ==
                Brightness.dark
            ? Colors.white24
            : Colors.black26,
        borderRadius: BorderRadius.circular(20),
        indicatorBorderRadius: BorderRadius.circular(20),
      ),
      // styleBuilder: (value) => ToggleStyle(indicatorColor: indicatorFor(value, bg: appColor, fg: fg)),
      styleBuilder: (value) => ToggleStyle(indicatorColor: indicatorFor(value, bg: appColor, fg: fg), ),
      iconBuilder: (value) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: iconFor(value, bg: appColor, fg: appColor != null ? fg : null),
      ),
      onChanged: onGroupStateChanged!,
    );
  }
}
