import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/responsive.dart';
import '../../../data/database/database_service.dart';
import '../../../data/models/shopping_bag.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/custom_widgets.dart';

/// Dedicated "Shopping Bags" section.
///
/// Bags are tracked completely separately from grocery stock (their own
/// `shopping_bags` table): this screen manages the bag tiers and keeps the
/// daily ledger of how bags were used — sold to customers vs used for the
/// shop's own packing. Both numbers also appear on the dashboard's
/// Profit & Loss panel.
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd =
        DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final bags = await _db.ensureDefaultShoppingBags();
    final summary = await _db.getShoppingBagSummary(dayStart, dayEnd);
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
                        'Sell bags to customers and record bags used in the shop '
                        '— tracked separately from grocery stock',
                    icon: Icons.shopping_bag,
                    colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
                  ),
                  SizedBox(height: responsive.paddingMedium),
                  _summaryRow(symbol, responsive),
                  SizedBox(height: responsive.paddingMedium),
                  Row(
                    children: [
                      Text(
                        'Bag tiers',
                        style: TextStyle(
                          fontSize: responsive.heading2,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: () => _showBagDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Tier'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PosAppTheme.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: responsive.paddingMedium),
                  if (_bags.isEmpty)
                    Expanded(child: _emptyState(responsive))
                  else ...[
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
              'No bag tiers yet',
              style: TextStyle(
                fontSize: responsive.heading3,
                color: PosAppTheme.textGray,
              ),
            ),
            SizedBox(height: responsive.paddingSmall),
            Text(
              'Add a bag tier (e.g. Rs 5 bag) with its buying and selling price.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: responsive.bodySmall,
                color: PosAppTheme.textGray,
              ),
            ),
          ],
        ),
      );

  Widget _summaryRow(String symbol, ResponsiveSize responsive) {
    final stock = _bags.fold<double>(0, (s, b) => s + b.quantity);
    final stockValue =
        _bags.fold<double>(0, (s, b) => s + b.buyingPrice * b.quantity);
    return Wrap(
      spacing: responsive.paddingMedium,
      runSpacing: responsive.paddingSmall,
      children: [
        _summaryChip(
          '${_bags.length}',
          'Bag tiers',
          Icons.category,
          PosAppTheme.accentBlue,
          responsive,
        ),
        _summaryChip(
          fmtQty(stock),
          'Bags in stock',
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
          'Sold today (value)',
          Icons.sell_outlined,
          PosAppTheme.successGreen,
          responsive,
        ),
        _summaryChip(
          '${fmtQty(_s('usedQty'))} · $symbol '
          '${_s('usedCost').toStringAsFixed(2)}',
          'Shop use today (cost)',
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
                    'Profit $symbol ${bag.profitPerBag.toStringAsFixed(2)}/bag',
                    style: TextStyle(
                      fontSize: responsive.bodyTiny,
                      color: PosAppTheme.textGray,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'In stock: ${fmtQty(bag.quantity)}',
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
              tooltip: 'Restock',
              icon: const Icon(Icons.add_circle_outline,
                  color: PosAppTheme.successGreen),
              onPressed: () => _showQtyDialog(
                bag,
                title: 'Restock — ${bag.label}',
                confirmLabel: 'Add to stock',
                onConfirm: (qty) async {
                  final ok = await _db.recordShoppingBagMovement(
                    bagId: bag.id,
                    quantity: qty,
                    type: 'restock',
                  );
                  return ok;
                },
              ),
            ),
            IconButton(
              tooltip: 'Shop use (take from stock)',
              icon: Icon(Icons.remove_circle_outline,
                  color: out ? Colors.grey : PosAppTheme.warningOrange),
              onPressed: out
                  ? null
                  : () => _showQtyDialog(
                        bag,
                        title: 'Shop use — ${bag.label}',
                        confirmLabel: 'Take from stock',
                        onConfirm: (qty) async {
                          final ok = await _db.recordShoppingBagMovement(
                            bagId: bag.id,
                            quantity: -qty,
                            type: 'shop_use',
                          );
                          return ok;
                        },
                      ),
            ),
            IconButton(
              tooltip: 'Edit tier',
              icon: const Icon(Icons.edit, color: PosAppTheme.accentBlue),
              onPressed: () => _showBagDialog(bag),
            ),
            IconButton(
              tooltip: 'Delete tier',
              icon: const Icon(Icons.delete, color: PosAppTheme.dangerRed),
              onPressed: () => _confirmDelete(bag),
            ),
          ],
        ),
      ),
    );
  }

  // ── Add / edit tier ───────────────────────────────────────────────────────

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
        title: Text(isEdit ? 'Edit Bag Tier' : 'Add Bag Tier'),
        contentPadding: const EdgeInsets.all(20),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GroceryTextField(
                label: 'Label * (e.g. Rs 5 bag)',
                controller: labelCtrl,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GroceryTextField(
                      label: 'Selling price *',
                      controller: priceCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GroceryTextField(
                      label: 'Buying / cost price *',
                      controller: costCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
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
              if (label.isEmpty || price == null || cost == null || price < 0 || cost < 0) {
                showTopSnackBar(
                  context,
                  const SnackBar(
                    content: Text('Enter a label and valid prices'),
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
                  content: Text(isEdit ? 'Bag tier updated' : 'Bag tier added'),
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

  // ── Restock / shop use ────────────────────────────────────────────────────

  void _showQtyDialog(
    ShoppingBag bag, {
    required String title,
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
              decoration: const InputDecoration(
                labelText: 'Quantity (bags)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'In stock: ${fmtQty(bag.quantity)}  ·  '
              'Sell Rs ${bag.price.toStringAsFixed(2)}/bag · '
              'cost Rs ${bag.buyingPrice.toStringAsFixed(2)}/bag',
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
                    content: Text('Not enough bags in stock'),
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

  Future<void> _confirmDelete(ShoppingBag bag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Bag Tier'),
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
          content: Text('Bag tier deleted'),
          backgroundColor: PosAppTheme.successGreen,
        ),
      );
    }
  }
}