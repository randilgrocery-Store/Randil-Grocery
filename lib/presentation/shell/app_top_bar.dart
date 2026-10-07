import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/product_batch.dart';
import '../components/app_card.dart';
import '../components/status_badge.dart';
import '../providers/batch_provider.dart';
import '../providers/network_provider.dart';
import '../providers/product_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

/// The shell's top bar: current screen title, LAN mode chip, stock alerts
/// bell, signed-in user and logout.
class AppTopBar extends StatefulWidget {
  const AppTopBar({
    super.key,
    required this.title,
    required this.userName,
    required this.isAdmin,
    required this.onLogout,
    required this.onOpenInventory,
  });

  /// Label of the screen currently shown in the content pane.
  final String title;
  final String userName;
  final bool isAdmin;
  final VoidCallback onLogout;

  /// Where to jump from the alerts panel when a stock row is tapped.
  final VoidCallback onOpenInventory;

  @override
  State<AppTopBar> createState() => _AppTopBarState();
}

class _AppTopBarState extends State<AppTopBar> {
  /// Expiring batches, loaded once (0 = nothing loaded yet, [] = none found).
  List<ProductBatch>? _expiring;

  @override
  void initState() {
    super.initState();
    _loadExpiringBatches();
  }

  Future<void> _loadExpiringBatches() async {
    if (!mounted) return;
    final expiring = await context.read<BatchProvider>().getExpiringBatches(30);
    if (!mounted) return;
    setState(() => _expiring = expiring);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typography = context.typography;

    return Container(
      height: AppSizes.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              widget.title,
              style: typography.h3,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(child: SizedBox.shrink()),
          const _NetworkChip(),
          const SizedBox(width: AppSpacing.xs),
          _AlertsBell(
            onOpenInventory: widget.onOpenInventory,
            expiringCount: _expiring?.length ?? 0,
            expiring: _expiring,
          ),
          const SizedBox(width: AppSpacing.xs),
          _UserChip(name: widget.userName, isAdmin: widget.isAdmin),
          const SizedBox(width: AppSpacing.xs),
          _LogoutButton(onLogout: widget.onLogout),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Network chip
// ---------------------------------------------------------------------------

class _NetworkChip extends StatelessWidget {
  const _NetworkChip();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Consumer<NetworkProvider>(
      builder: (context, network, _) {
        final (color, icon) = switch (network.mode) {
          NetworkMode.server => (colors.success, Icons.dns),
          NetworkMode.client => switch (network.connectState) {
              ClientConnectState.connected => (colors.success, Icons.wifi),
              ClientConnectState.connecting => (colors.warning, Icons.wifi_find),
              ClientConnectState.idle ||
              ClientConnectState.offline => (colors.danger, Icons.wifi_off),
            },
          NetworkMode.standalone => (colors.textTertiary, Icons.computer),
        };

        return Tooltip(
          message: 'LAN mode: ${network.mode.name}',
          child: ConstrainedBox(
            // A long status label must never push the top bar off-screen on a
            // narrow POS window; it ellipsizes instead.
            constraints: const BoxConstraints(maxWidth: 240),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                color: colors.softOf(color),
                borderRadius: AppRadius.pillRadius,
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      network.statusLabel,
                      style: context.typography.label.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Stock alerts bell
// ---------------------------------------------------------------------------

class _AlertsBell extends StatelessWidget {
  const _AlertsBell({
    required this.onOpenInventory,
    required this.expiring,
    required this.expiringCount,
  });

  final VoidCallback onOpenInventory;
  final List<ProductBatch>? expiring;
  final int expiringCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final low = context.select<ProductProvider, int>(
      (p) => p.reorderCandidates.length,
    );
    final total = low + expiringCount;

    return Tooltip(
      message: total == 0 ? 'No alerts' : '$total alert${total == 1 ? '' : 's'}',
      child: InkWell(
        borderRadius: AppRadius.controlRadius,
        onTap: () => _showAlerts(context),
        child: Container(
          width: AppSizes.topBarHeight - 12,
          height: AppSizes.topBarHeight - 12,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: AppRadius.controlRadius,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                total == 0 ? Icons.notifications_none : Icons.notifications,
                size: 22,
                color: total == 0 ? colors.textTertiary : colors.warning,
              ),
              if (total > 0)
                Positioned(
                  top: -2,
                  right: -4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.danger,
                      borderRadius: AppRadius.pillRadius,
                    ),
                    child: Text(
                      '$total',
                      style: context.typography.caption.copyWith(
                        color: colors.surface,
                        fontWeight: FontWeight.w700,
                        fontSize: 9,
                        fontFeatures: AppType.tabular,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAlerts(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _AlertsDialog(
        expiring: expiring ?? const [],
        onOpenInventory: onOpenInventory,
      ),
    );
  }
}

class _AlertsDialog extends StatelessWidget {
  const _AlertsDialog({required this.expiring, required this.onOpenInventory});

  final List<ProductBatch> expiring;
  final VoidCallback onOpenInventory;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typography = context.typography;

    final products = context.read<ProductProvider>();
    final reorder = products.reorderCandidates;
    final nameById = <String, String>{
      for (final p in products.allProducts) p.id: p.name,
    };

    Widget row(IconData icon, String title, String caption,
        {Widget? trailing}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Icon(icon, size: 18, color: colors.textTertiary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: typography.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(caption, style: typography.caption),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.sm),
              trailing,
            ],
          ],
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          clipContent: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('Stock alerts', style: typography.h3),
                  const Spacer(),
                  Text('${reorder.length + expiring.length}',
                      style: typography.numberSm.copyWith(
                        color: colors.textTertiary,
                      )),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(height: 1, color: colors.border),
              const SizedBox(height: AppSpacing.sm),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (reorder.isEmpty && expiring.isEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.lg),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_outline,
                                    size: 34, color: colors.success),
                                const SizedBox(height: AppSpacing.sm),
                                Text('All caught up', style: typography.h3),
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  'No low-stock items or batches expiring '
                                  'in the next 30 days.',
                                  style: typography.body,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (reorder.isNotEmpty) ...[
                        Row(
                          children: [
                            Text('LOW / OUT OF STOCK',
                                style: typography.overline
                                    .copyWith(color: colors.textTertiary)),
                            const Spacer(),
                            StatusBadge(
                              label: '${reorder.length}',
                              tone: StatusTone.warning,
                              dense: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        for (final p in reorder.take(30))
                          row(
                            Icons.inventory_2,
                            p.name,
                            '${p.quantity} in stock',
                            trailing: StatusBadge(
                              label: p.quantity <= 0 ? 'Out' : 'Low',
                              tone: p.quantity <= 0
                                  ? StatusTone.danger
                                  : StatusTone.warning,
                              dense: true,
                            ),
                          ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      if (expiring.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Text('EXPIRING IN 30 DAYS',
                                style: typography.overline
                                    .copyWith(color: colors.textTertiary)),
                            const Spacer(),
                            StatusBadge(
                              label: '${expiring.length}',
                              tone: StatusTone.danger,
                              dense: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        for (final b in expiring.take(30))
                          row(
                            Icons.event,
                            nameById[b.productId] ?? b.batchNumber,
                            b.expiryDate == null
                                ? 'No expiry date'
                                : 'Batch ${b.batchNumber} · expires '
                                    '${_date(b.expiryDate!)}',
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(height: 1, color: colors.border),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  if (reorder.isNotEmpty)
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onOpenInventory();
                      },
                      icon: const Icon(Icons.inventory_2, size: 18),
                      label: const Text('View stock'),
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ---------------------------------------------------------------------------
// User chip + logout
// ---------------------------------------------------------------------------

class _UserChip extends StatelessWidget {
  const _UserChip({required this.name, required this.isAdmin});

  final String name;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typography = context.typography;

    final initials = name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return Tooltip(
      message: '$name (${isAdmin ? 'Admin' : 'Cashier'})',
      child: ConstrainedBox(
        // A long user name must never push the top bar off-screen on a narrow
        // POS window; it ellipsizes instead.
        constraints: const BoxConstraints(maxWidth: 220),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: AppRadius.pillRadius,
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: CircleAvatar(
                  radius: 13,
                  backgroundColor: colors.primarySoft,
                  child: Text(
                    initials,
                    style: typography.caption.copyWith(
                      color: colors.onPrimarySoft,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  name,
                  style: typography.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoutButton extends StatefulWidget {
  const _LogoutButton({required this.onLogout});

  final VoidCallback onLogout;

  @override
  State<_LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<_LogoutButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final typography = context.typography;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: 'Log out',
        child: InkWell(
          borderRadius: AppRadius.controlRadius,
          onTap: widget.onLogout,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered ? colors.dangerSoft : Colors.transparent,
              borderRadius: AppRadius.controlRadius,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.logout,
                  size: 18,
                  color: _hovered ? colors.danger : colors.textTertiary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Logout',
                  style: typography.bodyStrong.copyWith(
                    color: _hovered ? colors.danger : colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}