import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/responsive.dart';
import '../../../data/database/database_service.dart';
import '../../../data/models/shopping_bag.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/custom_widgets.dart';
import '../../widgets/date_range_filter_bar.dart';

/// Dedicated "Shopping Bags" section.
///
/// The shop buys bulk shopping bags at several prices and stocks the bundles.
/// From here the owner records what happened to each bundle — taken for the
/// shop's own use or sold to a customer — and sees the today's profit/loss.
///
/// Bags are tracked completely separately from grocery stock (their own
/// `shopping_bags` table) and are NOT connected to the Rs 3 / 5 / 10 / 20 retail
/// bag charge on the POS.
class ShoppingBagScreen extends StatefulWidget {
  const ShoppingBagScreen({super.key});

  @override
  State<ShoppingBagScreen> createState() => _ShoppingBagScreenState();
}

class _ShoppingBagScreenState extends State<ShoppingBagScreen> {
  final DatabaseService _db = DatabaseService();
  List<ShoppingBag> _bags = [];
  Map<String, dynamic> _summary = const {};
  bool _loading = true;

  DateRangePreset _preset = DateRangePreset.today;
  DateTimeRange? _customRange;

  DateWindow get _window =>
      DateRangeFilterBar.windowFor(_preset, custom: _customRange);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final window = _window;
    final bags = await _db.getShoppingBags();
    final summary = await _db.getShoppingBagSummary(
        window.effectiveStart, window.effectiveEnd);
    if (!mounted) return;
    setState(() {
      _bags = bags;
      _summary = summary;
      _loading = false;
    });
  }

  double _s(String key) => ((_summary[key] as num?)?.toDouble()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final responsive = context.responsive;
    final symbol = context.watch<SettingsProvider>().settings.currencySymbol;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopping Bags'),
        elevation: 2,
        actions: [
          IconButton(
            tooltip: 'Recent activity',
            icon: const Icon(Icons.history),
            onPressed: _showHistory,
          ),
        ],
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [PosAppTheme.primaryGreen, PosAppTheme.darkGreen],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: EdgeInsets.all(responsive.paddingMedium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DashboardHeroPanel(
                    title: 'Shopping Bags',
                    subtitle:
                        'Buy bulk bags, stock the bundles, then record bundles '
                        'used in the shop and bundles sold to customers',
                    icon: Icons.shopping_bag,
                    colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
                  ),
                  SizedBox(height: responsive.paddingMedium),
                  DateRangeFilterBar(
                    selectedPreset: _preset,
                    customRange: _customRange,
                    onSelected: (preset, custom) {
                      setState(() {
                        _preset = preset;
                        _customRange = custom;
                      });
                      _load();
                    },
                  ),
                  SizedBox(height: responsive.paddingMedium),
                  _summaryRow(symbol, responsive, _window.label),
                  SizedBox(height: responsive.paddingMedium),
                  Row(
                    children: [
                      Text(
                        'Bulk bag types',
                        style: TextStyle(
                          fontSize: responsive.heading2,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: () => _showBagDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Bag'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PosAppTheme.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: responsive.paddingMedium),
                  if (_bags.isEmpty)
                    Expanded(child: _emptyState(responsive))
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: _bags.length,
                        separatorBuilder: (_, __) =>
                            SizedBox(height: responsive.paddingSmall),
                        itemBuilder: (context, index) =>
                            _bagTile(_bags[index], symbol, responsive),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _emptyState(ResponsiveSize responsive) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_bag_outlined,
                size: responsive.iconLarge, color: PosAppTheme.textGray),
            SizedBox(height: responsive.paddingMedium),
            Text(
              'No bulk bags yet',
              style: TextStyle(
                fontSize: responsive.heading3,
                color: PosAppTheme.textGray,
              ),
            ),
            SizedBox(height: responsive.paddingSmall),
            Text(
              'Add a bulk bag you buy (e.g. "Big bag bundle") with its bundle '
              'buying price and selling price, then restock it.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: responsive.bodySmall,
                color: PosAppTheme.textGray,
              ),
            ),
          ],
        ),
      );

  Widget _summaryRow(
      String symbol, ResponsiveSize responsive, String periodLabel) {
    final stock = _bags.fold<double>(0, (s, b) => s + b.quantity);
    final stockValue =
        _bags.fold<double>(0, (s, b) => s + b.buyingPrice * b.quantity);
    final soldProfit = _s('soldValue') - _s('soldCost');
    return Wrap(
      spacing: responsive.paddingMedium,
      runSpacing: responsive.paddingSmall,
      children: [
        _summaryChip(
          '${_bags.length}',
          'Bag types',
          Icons.category,
          PosAppTheme.accentBlue,
          responsive,
        ),
        _summaryChip(
          fmtQty(stock),
          'Bundles in stock',
          Icons.inventory_2,
          PosAppTheme.primaryGreen,
          responsive,
        ),
        _summaryChip(
          '$symbol ${stockValue.toStringAsFixed(2)}',
          'Stock value (cost)',
          Icons.payments_outlined,
          PosAppTheme.warningOrange,
          responsive,
        ),
        _summaryChip(
          '${fmtQty(_s('soldQty'))} · $symbol '
          '${_s('soldValue').toStringAsFixed(2)}',
          'Sold to customers ($periodLabel)',
          Icons.sell_outlined,
          PosAppTheme.successGreen,
          responsive,
        ),
        _summaryChip(
          '$symbol ${soldProfit.toStringAsFixed(2)}',
          'Profit on bag sales ($periodLabel)',
          Icons.trending_up,
          PosAppTheme.successGreen,
          responsive,
        ),
        _summaryChip(
          '${fmtQty(_s('usedQty'))} · $symbol '
          '${_s('usedCost').toStringAsFixed(2)}',
          'Used in shop ($periodLabel)',
          Icons.storefront_outlined,
          PosAppTheme.dangerRed,
          responsive,
        ),
      ],
    );
  }

  Widget _summaryChip(String value, String label, IconData icon, Color color,
          ResponsiveSize responsive) =>
      GroceryCard(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: responsive.paddingMedium,
            vertical: responsive.paddingSmall,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: responsive.iconSmall),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value,
                      style: TextStyle(
                        fontSize: responsive.bodyLarge,
                        fontWeight: FontWeight.bold,
                        color: color,
                      )),
                  Text(label,
                      style: TextStyle(
                        fontSize: responsive.bodyTiny,
                        color: PosAppTheme.textGray,
                      )),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _bagTile(ShoppingBag bag, String symbol, ResponsiveSize responsive) {
    final out = bag.quantity <= 0;
    return GroceryCard(
      child: Padding(
        padding: EdgeInsets.all(responsive.paddingMedium),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: PosAppTheme.lightGreen,
                borderRadius: BorderRadius.circular(responsive.radiusSmall),
              ),
              child: const Icon(Icons.shopping_bag,
                  color: PosAppTheme.primaryGreen),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bag.label,
                      style: TextStyle(
                        fontSize: responsive.bodyLarge,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    'Buy $symbol ${bag.buyingPrice.toStringAsFixed(2)}  ·  '
                    'Sell $symbol ${bag.price.toStringAsFixed(2)}  ·  '
                    'Profit $symbol ${bag.profitPerBundle.toStringAsFixed(2)}/bundle',
                    style: TextStyle(
                      fontSize: responsive.bodyTiny,
                      color: PosAppTheme.textGray,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'In stock: ${fmtQty(bag.quantity)} bundles',
                    style: TextStyle(
                      fontSize: responsive.bodySmall,
                      fontWeight: FontWeight.bold,
                      color: out
                          ? PosAppTheme.dangerRed
                          : PosAppTheme.primaryGreen,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Restock (bought more bundles)',
              icon: const Icon(Icons.add_circle_outline,
                  color: PosAppTheme.successGreen),
              onPressed: () => _showQtyDialog(
                bag,
                title: 'Restock — ${bag.label}',
                hint: 'Bundles you bought',
                confirmLabel: 'Add to stock',
                onConfirm: (qty) async {
                  return _db.recordShoppingBagMovement(
                    bagId: bag.id,
                    quantity: qty,
                    type: 'restock',
                  );
                },
              ),
            ),
            IconButton(
              tooltip: 'Sell to customer',
              icon: Icon(Icons.sell_outlined,
                  color: out ? Colors.grey : PosAppTheme.successGreen),
              onPressed: out
                  ? null
                  : () => _showQtyDialog(
                        bag,
                        title: 'Sell to customer — ${bag.label}',
                        hint: 'Bundles sold ($symbol '
                            '${bag.price.toStringAsFixed(2)} each)',
                        confirmLabel: 'Record sale',
                        onConfirm: (qty) async {
                          return _db.recordShoppingBagMovement(
                            bagId: bag.id,
                            quantity: -qty,
                            type: 'customer_sell',
                          );
                        },
                      ),
            ),
            IconButton(
              tooltip: 'Use in shop (take from stock)',
              icon: Icon(Icons.remove_circle_outline,
                  color: out ? Colors.grey : PosAppTheme.warningOrange),
              onPressed: out
                  ? null
                  : () => _showQtyDialog(
                        bag,
                        title: 'Use in shop — ${bag.label}',
                        hint: 'Bundles taken for the shop',
                        confirmLabel: 'Take from stock',
                        onConfirm: (qty) async {
                          return _db.recordShoppingBagMovement(
                            bagId: bag.id,
                            quantity: -qty,
                            type: 'shop_use',
                          );
                        },
                      ),
            ),
            IconButton(
              tooltip: 'Edit bag',
              icon: const Icon(Icons.edit, color: PosAppTheme.accentBlue),
              onPressed: () => _showBagDialog(bag),
            ),
            IconButton(
              tooltip: 'Delete bag',
              icon: const Icon(Icons.delete, color: PosAppTheme.dangerRed),
              onPressed: () => _confirmDelete(bag),
            ),
          ],
        ),
      ),
    );
  }

  // ── Add / edit bag ────────────────────────────────────────────────────────

  void _showBagDialog([ShoppingBag? existing]) {
    final isEdit = existing != null;
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    final priceCtrl = TextEditingController(
        text: existing != null ? existing.price.toString() : '');
    final costCtrl = TextEditingController(
        text: existing != null ? existing.buyingPrice.toString() : '');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEdit ? 'Edit Bulk Bag' : 'Add Bulk Bag'),
        contentPadding: const EdgeInsets.all(20),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GroceryTextField(
                label: 'Name * (e.g. Big bag bundle)',
                controller: labelCtrl,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GroceryTextField(
                      label: 'Buying price / bundle *',
                      controller: costCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GroceryTextField(
                      label: 'Selling price / bundle *',
                      controller: priceCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Prices are for one whole bundle. Stock is counted in bundles, '
                'not single bags.',
                style: TextStyle(fontSize: 11, color: PosAppTheme.textGray),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final label = labelCtrl.text.trim();
              final price = double.tryParse(priceCtrl.text.trim());
              final cost = double.tryParse(costCtrl.text.trim());
              if (label.isEmpty ||
                  price == null ||
                  cost == null ||
                  price < 0 ||
                  cost < 0) {
                showTopSnackBar(
                  context,
                  const SnackBar(
                    content: Text('Enter a name and valid prices'),
                    backgroundColor: PosAppTheme.dangerRed,
                  ),
                );
                return;
              }
              if (isEdit) {
                final bag = ShoppingBag(
                  id: existing.id,
                  label: label,
                  price: price,
                  buyingPrice: cost,
                  quantity: existing.quantity,
                );
                await _db.upsertShoppingBag(bag);
              } else {
                await _db.upsertShoppingBag(ShoppingBag(
                  label: label,
                  price: price,
                  buyingPrice: cost,
                ));
              }
              if (!mounted) return;
              Navigator.pop(dialogContext);
              await _load();
              showTopSnackBar(
                context,
                SnackBar(
                  content: Text(isEdit ? 'Bag updated' : 'Bag added'),
                  backgroundColor: PosAppTheme.successGreen,
                ),
              );
            },
            child: Text(isEdit ? 'Update' : 'Add'),
          ),
        ],
      ),
    );
  }

  // ── Restock / sell / shop use ─────────────────────────────────────────────

  void _showQtyDialog(
    ShoppingBag bag, {
    required String title,
    required String hint,
    required String confirmLabel,
    required Future<bool> Function(double qty) onConfirm,
  }) {
    final qtyCtrl = TextEditingController(text: '1');
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: qtyCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Quantity (bundles)',
                helperText: hint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'In stock: ${fmtQty(bag.quantity)} bundles  ·  '
              'buy Rs ${bag.buyingPrice.toStringAsFixed(2)}/bundle · '
              'sell Rs ${bag.price.toStringAsFixed(2)}/bundle',
              style: const TextStyle(fontSize: 11, color: PosAppTheme.textGray),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final qty = double.tryParse(qtyCtrl.text.trim());
              if (qty == null || qty <= 0) {
                showTopSnackBar(
                  context,
                  const SnackBar(
                    content: Text('Enter a valid quantity'),
                    backgroundColor: PosAppTheme.dangerRed,
                  ),
                );
                return;
              }
              final ok = await onConfirm(qty);
              if (!context.mounted) return;
              Navigator.pop(dialogContext);
              await _load();
              if (!ok) {
                showTopSnackBar(
                  context,
                  const SnackBar(
                    content: Text('Not enough bundles in stock'),
                    backgroundColor: PosAppTheme.dangerRed,
                  ),
                );
                return;
              }
              showTopSnackBar(
                context,
                SnackBar(
                  content: Text('${fmtQty(qty)} × ${bag.label} done'),
                  backgroundColor: PosAppTheme.successGreen,
                ),
              );
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _showHistory() async {
    final rows = await _db.getShoppingBagUsageHistory(limit: 500);
    final window = _window;
    final visible = window.isAll
        ? rows
        : rows.where((u) => window.includes(u.createdAt)).toList();
    if (!mounted) return;
    final symbol = context.read<SettingsProvider>().settings.currencySymbol;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Bag activity · ${window.label}'),
        content: SizedBox(
          width: 480,
          height: 420,
          child: visible.isEmpty
              ? const Center(child: Text('No bag movements in this period'))
              : ListView.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final u = visible[index];
                    final isSell = u.type == 'customer_sell';
                    final isRestock = u.type == 'restock';
                    final label = isSell
                        ? 'Sold to customer'
                        : isRestock
                            ? 'Restocked'
                            : 'Used in shop';
                    final color = isSell
                        ? PosAppTheme.successGreen
                        : isRestock
                            ? PosAppTheme.accentBlue
                            : PosAppTheme.warningOrange;
                    final money = isSell ? u.value : (isRestock ? 0.0 : u.cost);
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isSell
                            ? Icons.sell_outlined
                            : isRestock
                                ? Icons.add_circle_outline
                                : Icons.storefront_outlined,
                        color: color,
                      ),
                      title: Text('${u.bagLabel} — $label'),
                      subtitle: Text(
                        '${fmtQty(u.quantity)} bundles · '
                        '${u.createdAt.toLocal().toString().substring(0, 16)}',
                      ),
                      trailing: money > 0
                          ? Text('$symbol ${money.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: color,
                              ))
                          : null,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(ShoppingBag bag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Bag'),
        content: Text('Delete "${bag.label}"? Sold/used history stays in the '
            'daily reports.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: PosAppTheme.dangerRed,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await _db.deleteShoppingBag(bag.id);
      if (!mounted) return;
      await _load();
      showTopSnackBar(
        context,
        const SnackBar(
          content: Text('Bag deleted'),
          backgroundColor: PosAppTheme.successGreen,
        ),
      );
    }
  }
}
