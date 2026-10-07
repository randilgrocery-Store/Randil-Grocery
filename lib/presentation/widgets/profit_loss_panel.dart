import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/profit_loss_provider.dart';
import 'custom_widgets.dart';

/// Admin-only panel showing the profit and loss of the *whole* system for the
/// chosen period: billing, goods received, wastage, refunds, expenses and
/// supplier payments - one honest number at the bottom.
class ProfitLossPanel extends StatelessWidget {
  const ProfitLossPanel({
    super.key,
    required this.rangeLabel,
    required this.isRefreshing,
    required this.onRefresh,
  });

  final String rangeLabel;
  final bool isRefreshing;
  final VoidCallback onRefresh;

  static const Color _green = Color(0xFF1B873B);
  static const Color _red = Color(0xFFC62828);
  static const Color _blue = Color(0xFF1565C0);
  static const Color _amber = Color(0xFFB26A00);

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfitLossProvider>(
      builder: (context, pl, _) {
        final ready = pl.data != null;

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          // The admin dashboard pins this card beside the Revenue chart, so when
          // a bounded height is imposed (wide windows) the tall detail scrolls
          // inside the card instead of spilling next to / under the chart; the
          // stacked (narrow) layout stays at natural height.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final content = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(context),
                  const SizedBox(height: 16),
                  if (!ready)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    _netBanner(context, pl),
                    const SizedBox(height: 18),
                    _sectionLabel(context, 'Money In', Icons.savings_outlined,
                        _green),
                    _line(context, 'Sales revenue', pl.d('revenue'),
                        hint: '${pl.i('bills')} bills'),
                    _line(context, 'Discounts (already deducted at billing)', -pl.d('discounts'),
                        negative: true, muted: true),
                    _line(context, 'Net sales taken', pl.d('revenue') - pl.d('discounts'),
                        bold: true),
                    _line(context, 'Cash / Card',
                        0,
                        hint: 'Cash ${_rs(pl.d('cashSales'))}  •  '
                            'Card ${_rs(pl.d('cardSales'))}',
                        icon: Icons.payments_outlined),
                    const SizedBox(height: 10),
                    _sectionLabel(context, 'Cost of the goods sold',
                        Icons.inventory_2_outlined, _amber),
                    _line(context, 'Cost of items sold', -pl.d('cogs'),
                        negative: true, hint: '${_qty(pl.d('itemsSold'))} items'),
                    _line(context, 'Gross profit', pl.d('grossProfit'),
                        bold: true,
                        hint: '${pl.d('grossMarginPct').toStringAsFixed(1)}% margin'),
                    const SizedBox(height: 10),
                    _sectionLabel(context, 'Running costs', Icons.money_off,
                        _red),
                    _line(context, 'Wastage loss', -pl.d('wastageLoss'),
                        negative: true,
                        hint: '${pl.i('wastageCount')} entries • '
                            '${_qty(pl.d('wastageUnits'))} units'),
                    _line(context, 'Refunds (already deducted from sales)', -pl.d('refundLoss'),
                        negative: true,
                        hint: pl.d('refundPending') > 0
                            ? '${pl.i('refundCount')} paid • '
                                '${_rs(pl.d('refundPending'))} still to pay'
                            : '${pl.i('refundCount')} refunds'),
                    _line(context, 'Shop expenses', -pl.d('expenseTotal'),
                        negative: true,
                        hint: '${pl.i('expenseCount')} entries'),
                    if (pl.expensesByCategory.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _expenseChips(context, pl.expensesByCategory),
                    ],
                    const SizedBox(height: 14),
                    _totalRow(context, pl),
                    const SizedBox(height: 16),
                    _sectionLabel(context, 'Money in and out of the till',
                        Icons.swap_horiz, _blue),
                    _line(context, 'Stock received from suppliers',
                        pl.d('purchaseTotal'),
                        hint: '${pl.i('purchaseCount')} goods received notes'),
                    _line(context, 'Paid to suppliers', pl.d('supplierPaid'),
                        hint: 'Cash ${_rs(pl.d('supplierPaidCash'))} • '
                            'Cheque ${_rs(pl.d('supplierPaidCheque'))}',
                        icon: Icons.payments_outlined),
                    _line(context, 'Still owed to suppliers',
                        pl.d('supplierOutstanding'),
                        hint: 'Outstanding balance',
                        icon: Icons.account_balance_wallet_outlined),
                    _line(context, 'Stock on hand (cost value)', pl.d('stockValue'),
                        hint: '${pl.i('stockItems')} items in stock',
                        icon: Icons.warehouse_outlined),
                    const SizedBox(height: 16),
                    _sectionLabel(context, 'How each part performed',
                        Icons.grid_view_rounded, _blue),
                    const SizedBox(height: 10),
                    _moduleTiles(context, pl),
                  ],
                ],
              );
              if (constraints.hasBoundedHeight) {
                return SingleChildScrollView(child: content);
              }
              return content;
            },
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: PosAppTheme.primaryGreen.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.account_balance_wallet,
              color: PosAppTheme.primaryGreen, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Profit & Loss',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              Text(
                'Every part of the system • $rangeLabel',
                style: const TextStyle(
                    fontSize: 12, color: PosAppTheme.textGray),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: isRefreshing ? null : onRefresh,
          icon: Icon(Icons.refresh,
              size: 16, color: isRefreshing ? Colors.grey : PosAppTheme.primaryGreen),
          label: const Text('Recalculate', style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: Size.zero,
          ),
        ),
        const Tooltip(
          message: 'Only the owner (admin) can see profit and loss',
          child: Icon(Icons.admin_panel_settings, size: 18, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _netBanner(BuildContext context, ProfitLossProvider pl) {
    final net = pl.d('netProfit');
    final isLoss = net < 0;
    final color = isLoss ? _red : _green;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.16), color.withOpacity(0.05)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: color.withOpacity(0.15),
            child: Icon(isLoss ? Icons.trending_down : Icons.trending_up,
                color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLoss ? 'The shop is running at a loss' : 'The shop is making money',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  isLoss ? 'Net Loss for $rangeLabel' : 'Net Profit for $rangeLabel',
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ],
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: net.abs()),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => Text(
              _rs(value),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(
    BuildContext context,
    String label,
    double amount, {
    String? hint,
    IconData? icon,
    bool negative = false,
    bool bold = false,
    bool muted = false,
  }) {
    final isLoss = amount < 0;
    final color = amount == 0
        ? PosAppTheme.textGray
        : (isLoss ? _red : (bold ? _green : Theme.of(context).textTheme.bodyLarge?.color));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: PosAppTheme.textGray),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                    color: muted ? PosAppTheme.textGray : null,
                  ),
                ),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      hint,
                      style: const TextStyle(
                          fontSize: 11, color: PosAppTheme.textGray),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              amount == 0 ? '—' : _rs(amount.abs()),
              style: TextStyle(
                fontSize: bold ? 16 : 14,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
                color: negative ? _red : color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(BuildContext context, ProfitLossProvider pl) {
    final net = pl.d('netProfit');
    final isLoss = net < 0;
    final color = isLoss ? _red : _green;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLoss ? 'NET LOSS' : 'NET PROFIT',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: color,
                    letterSpacing: 0.6,
                  ),
                ),
                Text(
                  isLoss
                      ? 'Spending is higher than what the shop earned'
                      : 'What the shop earned after every cost',
                  style: const TextStyle(
                      fontSize: 11, color: PosAppTheme.textGray),
                ),
              ],
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: net.abs()),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => Text(
              _rs(value),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _expenseChips(
      BuildContext context, Map<String, double> byCategory) {
    final entries = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in entries.take(6))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withOpacity(0.06)
                  : PosAppTheme.bgColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Text(
              '${entry.key}: ${_rs(entry.value)}',
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
      ],
    );
  }

  Widget _moduleTiles(BuildContext context, ProfitLossProvider pl) {
    final tiles = <Widget>[
      _tile(
        context,
        icon: Icons.point_of_sale,
        color: pl.d('grossProfit') >= 0 ? _green : _red,
        title: 'Billing',
        value: _rs(pl.d('grossProfit')),
        caption: 'profit on ${pl.i('bills')} bills • '
            '${_rs(pl.d('revenue'))} sales',
      ),
      _tile(
        context,
        icon: Icons.local_shipping,
        color: _blue,
        title: 'Goods Received',
        value: _rs(pl.d('purchaseTotal')),
        caption: '${pl.i('purchaseCount')} deliveries into stock',
      ),
      _tile(
        context,
        icon: Icons.delete_sweep,
        color: pl.d('wastageLoss') > 0 ? _red : _green,
        title: 'Wastage',
        value: _rs(pl.d('wastageLoss')),
        caption: '${pl.i('wastageCount')} entries lost',
      ),
      _tile(
        context,
        icon: Icons.assignment_return,
        color: pl.d('refundLoss') > 0 ? _red : _green,
        title: 'Refunds',
        value: _rs(pl.d('refundLoss')),
        caption: pl.d('refundPending') > 0
            ? '${_rs(pl.d('refundPending'))} awaiting payout'
            : '${pl.i('refundCount')} refunds paid',
      ),
      _tile(
        context,
        icon: Icons.receipt_long,
        color: pl.d('expenseTotal') > 0 ? _amber : _green,
        title: 'Expenses',
        value: _rs(pl.d('expenseTotal')),
        caption: '${pl.i('expenseCount')} running costs',
      ),
      _tile(
        context,
        icon: Icons.handshake,
        color: pl.d('supplierOutstanding') > 0 ? _amber : _green,
        title: 'Suppliers',
        value: _rs(pl.d('supplierOutstanding')),
        caption: 'owed • paid ${_rs(pl.d('supplierPaid'))}',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 560
                ? 2
                : 1;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.9,
          children: tiles,
        );
      },
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required String caption,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withOpacity(0.05)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.13),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10.5, color: PosAppTheme.textGray),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static final NumberFormat _money = NumberFormat('#,##0.00');

  static String _rs(double value) => 'Rs ${_money.format(value)}';

  static String _qty(double value) => fmtQty(value);
}
