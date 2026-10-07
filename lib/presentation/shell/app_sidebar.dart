import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

/// A nav group: several screens under one section title.
class SidebarSection {
  const SidebarSection(this.title, this.indices);

  final String title;

  /// Stable indices into the shell's screen list (`_adminNavLabels` /
  /// `_cashierNavLabels`), so the sidebar never renames or reorders screens.
  final List<int> indices;
}

/// The navigation rail for the POS shell.
///
/// Admin screens are grouped into Dashboard / Sales / Inventory / Finance /
/// System; cashier screens into Dashboard / Sales / Inventory / Account. The
/// selection state lives in the shell; this widget only renders.
///
/// Collapsed mode shows icons only (with tooltips), expanded shows icon +
/// label at 44px tap height.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.isAdmin,
    required this.labels,
    required this.icons,
    required this.selectedIndex,
    required this.onSelect,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final bool isAdmin;
  final List<String> labels;
  final List<IconData> icons;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  /// Admin screen groups. Shared with the Ctrl+K command palette.
  static const adminSections = <SidebarSection>[
    SidebarSection('Dashboard', [0]),
    SidebarSection('Sales', [1, 7, 8]),
    SidebarSection('Inventory', [2, 4, 3, 5, 6, 10]),
    SidebarSection('Finance', [9, 11]),
    SidebarSection('System', [12]),
  ];

  /// Cashier screen groups. Shared with the Ctrl+K command palette.
  static const cashierSections = <SidebarSection>[
    SidebarSection('Dashboard', [0]),
    SidebarSection('Sales', [1, 3]),
    SidebarSection('Inventory', [2]),
    SidebarSection('Account', [4]),
  ];

  static List<SidebarSection> sectionsFor(bool isAdmin) =>
      isAdmin ? adminSections : cashierSections;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typography = context.typography;
    final sections = AppSidebar.sectionsFor(isAdmin);

    return Container(
      width: collapsed ? AppSizes.sidebarCollapsed : AppSizes.sidebarExpanded,
      color: colors.surface,
      child: Column(
        children: [
          _SidebarHeader(collapsed: collapsed),
          Container(height: 1, color: colors.border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.sm,
                horizontal: AppSpacing.xs,
              ),
              children: [
                for (final section in sections) ...[
                  if (!collapsed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.sm,
                        AppSpacing.xs,
                        AppSpacing.sm,
                        AppSpacing.xxs,
                      ),
                      child: Text(
                        section.title.toUpperCase(),
                        style: typography.overline.copyWith(
                          color: colors.textTertiary,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  for (final index in section.indices)
                    _SidebarItem(
                      label: labels[index],
                      icon: icons[index],
                      selected: index == selectedIndex,
                      collapsed: collapsed,
                      onTap: () => onSelect(index),
                    ),
                ],
              ],
            ),
          ),
          Container(height: 1, color: colors.border),
          _SidebarItem(
            label: collapsed ? 'Expand' : 'Collapse',
            icon: collapsed ? Icons.menu : Icons.menu_open,
            selected: false,
            collapsed: collapsed,
            onTap: onToggleCollapsed,
          ),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typography = context.typography;

    return SizedBox(
      height: AppSizes.topBarHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? AppSpacing.sm : AppSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: AppRadius.controlRadius,
                border: Border.all(color: colors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/images/randil_logo.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.storefront,
                  size: 20,
                  color: colors.onPrimarySoft,
                ),
              ),
            ),
            if (!collapsed) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Randil Grocery', style: typography.title),
                    Text('POS', style: typography.caption),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typography = context.typography;

    final selected = widget.selected;
    final collapsed = widget.collapsed;

    final bg = selected ? colors.primarySoft : colors.surface;
    final fg = selected ? colors.onPrimarySoft : colors.textSecondary;
    final iconColor =
        selected ? colors.onPrimarySoft : (colors.textTertiary);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: collapsed ? widget.label : '',
        waitDuration: const Duration(milliseconds: 400),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            height: AppSizes.minTapTarget,
            margin: const EdgeInsets.symmetric(
              vertical: AppSpacing.xxs - 2,
              horizontal: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: selected || _hovered
                  ? (selected ? colors.primarySoft : colors.surfaceMuted)
                  : bg,
              borderRadius: AppRadius.controlRadius,
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: AppMotion.fast,
                  width: 3,
                  height: 22,
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm - 2),
                Icon(widget.icon, size: 20, color: iconColor),
                if (!collapsed) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (selected ? typography.bodyStrong : typography.body)
                          .copyWith(
                        color: fg,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ] else
                  const SizedBox(width: AppSpacing.xxs),
              ],
            ),
          ),
        ),
      ),
    );
  }
}