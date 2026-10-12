import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/responsive.dart';
import '../../../data/database/database_service.dart';
import '../../../data/models/product.dart';
import '../../providers/auth_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/custom_widgets.dart';

/// Dedicated section for shopping bags ("carrier bags").
///
/// Bags are ordinary [Product] rows that live in the reserved
/// [DatabaseService.shoppingBagCategoryName] category, so they share the exact
/// same machinery as every other item: stock counts, FIFO costing, bill
/// printing, profit & loss and LAN mirroring. This screen is only a focused
/// view on top of that so the shopkeeper can:
///
///  * add a bag with its buying price (cost per bundle) and selling price,
///  * top up stock,
///  * record bags taken out of stock for the shop's own use (a wastage at cost,
///    which flows into profit & loss as an expense).
class ShoppingBagScreen extends StatefulWidget {
  const ShoppingBagScreen({super.key});

  @override
  State<ShoppingBagScreen> createState() => _ShoppingBagScreenState();
}

class _ShoppingBagScreenState extends State<ShoppingBagScreen> {
  String _bagCategoryId = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final category =
        await DatabaseService().ensureShoppingBagCategory();
    if (!mounted) return;
    await context.read<CategoryProvider>().loadCategories();
    if (!mounted) return;
    setState(() => _bagCategoryId = category.id);
    await context.read<ProductProvider>().loadProducts();
  }

  List<Product> _bags() {
    if (_bagCategoryId.isEmpty) return const [];
    final all = context.read<ProductProvider>().allProducts;
    return all.where((p) => p.categoryId == _bagCategoryId).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  Widget build(BuildContext context) {
    final responsive = context.responsive;
    final currency = context.watch<SettingsProvider>().settings.currencySymbol;

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
        actions: [
          Tooltip(
            message: 'Add Shopping Bag',
            child: IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showAddBagDialog,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Consumer2<ProductProvider, CategoryProvider>(
        builder: (context, productProvider, categoryProvider, _) {
          final bags = _bags();
          return Padding(
            padding: EdgeInsets.all(responsive.paddingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DashboardHeroPanel(
                  title: 'Shopping Bags',
                  subtitle:
                      'Sell bag bundles to customers and track bags used in the shop',
                  icon: Icons.shopping_bag,
                  colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
                ),
                SizedBox(height: responsive.paddingMedium),
                Row(
                  children: [
                    Text(
                      'Bags',
                      style: TextStyle(
                        fontSize: responsive.heading2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _showAddBagDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Bag'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PosAppTheme.primaryGreen,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: responsive.paddingMedium),
                if (productProvider.isLoading && bags.isEmpty)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (bags.isEmpty)
                  Expanded(child: _emptyState(responsive))
                else ...[
                  _summaryRow(bags, currency, responsive),
                  SizedBox(height: responsive.paddingMedium),
                  Expanded(
                    child: ListView.separated(
                      itemCount: bags.length,
                      separatorBuilder: (_, __) =>
                          SizedBox(height: responsive.paddingSmall),
                      itemBuilder: (context, index) => _bagTile(
                        bags[index],
                        currency,
                        responsive,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState(ResponsiveSize responsive) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: responsive.iconLarge,
              color: PosAppTheme.textGray,
            ),
            SizedBox(height: responsive.paddingMedium),
            Text(
              'No Shopping Bags Yet',
              style: TextStyle(
                fontSize: responsive.heading3,
                color: PosAppTheme.textGray,
              ),
            ),
            SizedBox(height: responsive.paddingSmall),
            Text(
              'Add the bags your shop sells or uses, with a buying and selling price.',
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
    List<Product> bags,
    String currency,
    ResponsiveSize responsive,
  ) {
    var stockValue = 0.0;
    var stockUnits = 0.0;
    var potentialProfit = 0.0;
    for (final bag in bags) {
      stockUnits += bag.quantity;
      stockValue += bag.buyingPrice * bag.quantity;
      potentialProfit += (bag.sellingPrice - bag.buyingPrice) * bag.quantity;
    }
    return Wrap(
      spacing: responsive.paddingMedium,
      runSpacing: responsive.paddingSmall,
      children: [
        _summaryChip(
          '${bags.length}',
          'Bag type${bags.length == 1 ? '' : 's'}',
          Icons.category,
          PosAppTheme.accentBlue,
          responsive,
        ),
        _summaryChip(
          fmtQty(stockUnits),
          'Bags in stock',
          Icons.inventory_2,
          PosAppTheme.primaryGreen,
          responsive,
        ),
        _summaryChip(
          '$currency ${stockValue.toStringAsFixed(2)}',
          'Stock value (cost)',
          Icons.payments_outlined,
          PosAppTheme.warningOrange,
          responsive,
        ),
        _summaryChip(
          '$currency ${potentialProfit.toStringAsFixed(2)}',
          'Profit if all sold',
          Icons.trending_up,
          PosAppTheme.successGreen,
          responsive,
        ),
      ],
    );
  }

  Widget _summaryChip(
    String value,
    String label,
    IconData icon,
    Color color,
    ResponsiveSize responsive,
  ) =>
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
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: responsive.bodyLarge,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: responsive.bodyTiny,
                      color: PosAppTheme.textGray,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _bagTile(Product bag, String currency, ResponsiveSize responsive) {
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
              child: const Icon(Icons.shopping_bag, color: PosAppTheme.primaryGreen),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bag.name,
                    style: TextStyle(
                      fontSize: responsive.bodyLarge,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Buy $currency ${bag.buyingPrice.toStringAsFixed(2)}  •  '
                    'Sell $currency ${bag.sellingPrice.toStringAsFixed(2)}  •  '
                    'Profit $currency ${bag.profit.toStringAsFixed(2)}',
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
                      color: out ? PosAppTheme.dangerRed : PosAppTheme.primaryGreen,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Shop use (take from stock)',
              icon: Icon(
                Icons.remove_circle_outline,
                color: out ? Colors.grey : PosAppTheme.warningOrange,
              ),
              onPressed: out ? null : () => _showShopUseDialog(bag),
            ),
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit, color: PosAppTheme.accentBlue),
              onPressed: () => _showBagDialog(existing: bag),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete, color: PosAppTheme.dangerRed),
              onPressed: () => _confirmDelete(bag),
            ),
          ],
        ),
      ),
    );
  }

  // ── Add / edit ────────────────────────────────────────────────────────────

  void _showAddBagDialog() => _showBagDialog();

  void _showBagDialog({Product? existing}) {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final costCtrl = TextEditingController(
      text: existing != null ? existing.buyingPrice.toString() : '',
    );
    final sellCtrl = TextEditingController(
      text: existing != null ? existing.sellingPrice.toString() : '',
    );
    final qtyCtrl = TextEditingController(
      text: existing != null ? fmtQty(existing.quantity) : '0',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEdit ? 'Edit Shopping Bag' : 'Add Shopping Bag'),
        contentPadding: const EdgeInsets.all(20),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GroceryTextField(
                label: 'Bag name * (e.g. Small bag, Big bag, Bundle of 100)',
                controller: nameCtrl,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GroceryTextField(
                      label: 'Buying price *',
                      controller: costCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GroceryTextField(
                      label: 'Selling price *',
                      controller: sellCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GroceryTextField(
                label: isEdit ? 'Stock in hand *' : 'Opening stock *',
                controller: qtyCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final cost = double.tryParse(costCtrl.text.trim());
              final sell = double.tryParse(sellCtrl.text.trim());
              final qty = double.tryParse(qtyCtrl.text.trim());
              if (name.isEmpty || cost == null || sell == null || qty == null) {
                showTopSnackBar(
                  context,
                  const SnackBar(
                    content: Text('Please fill all fields with valid numbers'),
                    backgroundColor: PosAppTheme.dangerRed,
                  ),
                );
                return;
              }
              if (cost < 0 || sell < 0 || qty < 0) {
                showTopSnackBar(
                  context,
                  const SnackBar(
                    content: Text('Values cannot be negative'),
                    backgroundColor: PosAppTheme.dangerRed,
                  ),
                );
                return;
              }

              final productProvider = context.read<ProductProvider>();
              try {
                if (isEdit) {
                  await productProvider.updateProduct(
                    existing.copyWith(
                      name: name,
                      buyingPrice: cost,
                      sellingPrice: sell,
                      quantity: qty,
                      categoryId: _bagCategoryId,
                    ),
                  );
                } else {
                  final barcode = await _uniqueBagBarcode(name);
                  await productProvider.addProduct(
                    Product(
                      name: name,
                      barcode: barcode,
                      categoryId: _bagCategoryId,
                      buyingPrice: cost,
                      sellingPrice: sell,
                      quantity: qty,
                    ),
                  );
                }
                if (!mounted) return;
                Navigator.pop(context);
                showTopSnackBar(
                  context,
                  SnackBar(
                    content: Text(
                      isEdit ? 'Bag updated' : 'Bag added successfully',
                    ),
                    backgroundColor: PosAppTheme.successGreen,
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                showTopSnackBar(
                  context,
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: PosAppTheme.dangerRed,
                  ),
                );
              }
            },
            child: Text(isEdit ? 'Update' : 'Add'),
          ),
        ],
      ),
    );
  }

  /// Bags are not usually scanned, but every product still needs a unique
  /// barcode. Derive one from the name and fall back to a timestamp suffix.
  Future<String> _uniqueBagBarcode(String name) async {
    final base = name
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final prefix = base.isEmpty ? 'BAG' : 'BAG-$base';
    final provider = context.read<ProductProvider>();
    var candidate = prefix;
    var attempt = 1;
    while (await provider.getProductByBarcode(candidate) != null) {
      candidate = '$prefix-${DateTime.now().millisecondsSinceEpoch % 100000}-$attempt';
      attempt++;
      if (attempt > 5) break;
    }
    return candidate;
  }

  // ── Shop use ──────────────────────────────────────────────────────────────

  void _showShopUseDialog(Product bag) {
    final qtyCtrl = TextEditingController(text: '1');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Shop use — ${bag.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bags taken out of stock for the shop\'s own use. '
              'This reduces the bag stock and is counted as a cost in '
              'profit & loss.',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Quantity used',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
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
              final user = context.read<AuthProvider>().currentUser;
              final recorded = await DatabaseService().recordWastage(
                productId: bag.id,
                productName: bag.name,
                quantity: qty,
                reason: 'Shop use',
                recordedBy: user?.fullName ?? '',
              );
              if (!mounted) return;
              Navigator.pop(context);
              if (recorded == null) {
                showTopSnackBar(
                  context,
                  const SnackBar(
                    content: Text('Could not record shop use'),
                    backgroundColor: PosAppTheme.dangerRed,
                  ),
                );
                return;
              }
              await context.read<ProductProvider>().loadProducts();
              if (!mounted) return;
              showTopSnackBar(
                context,
                SnackBar(
                  content: Text('${fmtQty(qty)} × ${bag.name} recorded as shop use'),
                  backgroundColor: PosAppTheme.successGreen,
                ),
              );
            },
            icon: const Icon(Icons.check),
            label: const Text('Record'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Product bag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bag'),
        content: Text('Delete "${bag.name}"? Its sales history stays in reports.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: PosAppTheme.dangerRed,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await context.read<ProductProvider>().deleteProduct(bag.id);
      if (!mounted) return;
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
