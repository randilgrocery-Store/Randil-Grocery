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

  /// ---- Single source of truth for the shell's screens ----
  ///
  /// The screen labels/icons live here (not in `home_screen.dart`) so the
  /// sidebar groups, the Ctrl+K palette and the shell body can never drift
  /// apart. Adding a screen means adding it here; a missing or duplicate group
  /// index fails loudly via [coversEveryScreen] and the accompanying test.
  static const adminLabels = <String>[
    'Dashboard',
    'POS',
    'Inventory',
    'GRN',
    'Batches',
    'Expiry',
    'Purchase Orders',
    'Suppliers',
    'Refunds',
    'Customers',
    'Expenses',
    'Wastage',
    'Production',
    'Reload',
    'Reports',
    'Settings',
    'Shopping Bags',
  ];

  static const adminIcons = <IconData>[
    Icons.dashboard,
    Icons.point_of_sale,
    Icons.inventory_2,
    Icons.assignment_turned_in,
    Icons.view_agenda,
    Icons.event_busy,
    Icons.local_shipping,
    Icons.business,
    Icons.assignment_return,
    Icons.people,
    Icons.receipt_long,
    Icons.delete_sweep,
    Icons.factory,
    Icons.sim_card,
    Icons.assessment,
    Icons.settings,
    Icons.shopping_bag,
  ];

  static const cashierLabels = <String>[
    'Dashboard',
    'POS',
    'GRN',
    'Expiry',
    'Refunds',
    'Expenses',
    'Reload',
    'Profile',
  ];

  static const cashierIcons = <IconData>[
    Icons.dashboard,
    Icons.point_of_sale,
    Icons.assignment_turned_in,
    Icons.event_busy,
    Icons.assignment_return,
    Icons.receipt_long,
    Icons.sim_card,
    Icons.person,
  ];

  /// Admin screen groups. Indices into [adminLabels]; every index must appear
  /// exactly once (enforced by `navigation_sections_test.dart`).
  static const adminSections = <SidebarSection>[
    SidebarSection('Dashboard', [0]),
    SidebarSection('Sales', [1, 7, 8, 9]), // POS, Suppliers, Customers, Refunds
    SidebarSection('Inventory', [2, 3, 4, 5, 6, 12, 16]), // Inventory, GRN,
    // Batches, Expiry, Purchase Orders, Production, Shopping Bags
    SidebarSection('Finance', [10, 11, 13, 14]), // Expenses, Wastage, Reload,
    // Reports
    SidebarSection('System', [15]), // Settings
  ];

  /// Cashier screen groups. Indices into [cashierLabels].
  static const cashierSections = <SidebarSection>[
    SidebarSection('Dashboard', [0]),
    SidebarSection('Sales', [1, 4]), // POS, Refunds
    SidebarSection('Inventory', [2, 3]), // GRN, Expiry
    SidebarSection('Account', [5, 6, 7]), // Expenses, Reload, Profile
  ];

  /// True when [sections] lists every index `0..count-1` exactly once. Guards
  /// against a screen disappearing from the sidebar (the bug where Settings was
  /// dropped when Expiry/Expenses shifted the indices).
  static bool coversEveryScreen(List<SidebarSection> sections, int count) {
    final seen = <int>[for (final s in sections) ...s.indices];
    if (seen.length != count) return false;
    final unique = seen.toSet();
    if (unique.length != count) return false;
    for (var i = 0; i < count; i++) {
      if (!unique.contains(i)) return false;
    }
    return true;
  }

  static List<SidebarSection> sectionsFor(bool isAdmin) {
    assert(
      coversEveryScreen(
        isAdmin ? adminSections : cashierSections,
        (isAdmin ? adminLabels : cashierLabels).length,
      ),
      'Sidebar groups must cover every screen index exactly once.',
    );
    return isAdmin ? adminSections : cashierSections;
  }

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