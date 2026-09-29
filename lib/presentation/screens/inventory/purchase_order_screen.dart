import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/product.dart';
import '../../../data/models/purchase_order.dart';
import '../../../data/models/supplier.dart';
import '../../providers/product_provider.dart';
import '../../providers/purchase_order_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/supplier_provider.dart';
import '../../widgets/custom_widgets.dart';

class PurchaseOrderScreen extends StatefulWidget {
  const PurchaseOrderScreen({super.key});

  @override
  State<PurchaseOrderScreen> createState() => _PurchaseOrderScreenState();
}

class _PurchaseOrderScreenState extends State<PurchaseOrderScreen>
    with SingleTickerProviderStateMixin {
  int _tabIndex = 0;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductProvider>().loadProducts();
      context.read<SupplierProvider>().loadSuppliers();
      context.read<PurchaseOrderProvider>().loadOrders();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Product> get _restockCandidates {
    final products = context.read<ProductProvider>().allProducts;
    final list = products.where((p) {
      final threshold = p.reorderLevel ?? 10;
      return p.quantity <= threshold;
    }).toList();
    list.sort(
      (a, b) => (a.quantity - (a.reorderLevel ?? 10))
          .compareTo(b.quantity - (b.reorderLevel ?? 10)),
    );
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final symbol = settings.currencySymbol;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Restock & Purchase Orders'),
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF10599F), Color(0xFF1F8AC0)],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<PurchaseOrderProvider>().loadOrders();
              context.read<ProductProvider>().loadProducts();
            },
          ),
          IconButton(
            tooltip: 'New Purchase Order',
            icon: const Icon(Icons.add_shopping_cart),
            onPressed: () => _openNewOrderDialog(),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardHeroPanel(
              title: 'Restock Center',
              subtitle: 'Reorder low stock, create purchase orders, receive deliveries',
              icon: Icons.local_shipping,
              colors: [Color(0xFF23074D), Color(0xFF6D0EFF)],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildKpiChip(
                    title: 'Low Stock',
                    value: '${_restockCandidates.length}',
                    icon: Icons.warning_amber,
                    color: PosAppTheme.warningOrange,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Consumer<PurchaseOrderProvider>(
                    builder: (context, poProvider, _) => _buildKpiChip(
                      title: 'Pending Orders',
                      value: '${poProvider.pendingOrders.length}',
                      icon: Icons.receipt_long,
                      color: PosAppTheme.accentBlue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: PosAppTheme.primaryGreen,
                labelColor: PosAppTheme.primaryGreen,
                unselectedLabelColor: PosAppTheme.textGray,
                tabs: const [
                  Tab(text: 'Restock'),
                  Tab(text: 'Purchase Orders'),
                ],
                onTap: (index) => setState(() => _tabIndex = index),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _tabIndex == 0
                  ? _buildRestockTab(context, symbol)
                  : _buildOrdersTab(context, symbol),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiChip({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    title,
                    style: const TextStyle(fontSize: 12, color: PosAppTheme.textGray),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildRestockTab(BuildContext context, String symbol) {
    final candidates = _restockCandidates;
    if (candidates.isEmpty) {
      return const Center(
        child: Text('All stock levels are healthy'),
      );
    }
    return ListView.builder(
      itemCount: candidates.length,
      itemBuilder: (context, index) {
        final product = candidates[index];
        final threshold = product.reorderLevel ?? 10;
        final low = product.quantity <= threshold;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: ListTile(
            leading: Icon(
              low ? Icons.warning_amber : Icons.check_circle_outline,
              color: low ? PosAppTheme.warningOrange : PosAppTheme.successGreen,
            ),
            title: Text(product.name),
            subtitle: Text(
              'Stock: ${product.quantity}  |  Reorder level: $threshold  |  '
              'Cost: $symbol ${product.buyingPrice.toStringAsFixed(2)}',
            ),
            trailing: FilledButton.tonalIcon(
              onPressed: () => _openNewOrderDialog(prefillProductId: product.id),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Order'),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrdersTab(BuildContext context, String symbol) {
    return Consumer<PurchaseOrderProvider>(
      builder: (context, poProvider, _) {
        if (poProvider.isLoading && poProvider.orders.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (poProvider.orders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.receipt_long, size: 56, color: PosAppTheme.textGray),
                const SizedBox(height: 12),
                const Text('No purchase orders yet'),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _openNewOrderDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Create Purchase Order'),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          itemCount: poProvider.orders.length,
          itemBuilder: (context, index) {
            final order = poProvider.orders[index];
            final statusColor = order.isReceived
                ? PosAppTheme.successGreen
                : order.isCancelled
                    ? PosAppTheme.dangerRed
                    : PosAppTheme.warningOrange;
            final statusIcon = order.isReceived
                ? Icons.verified
                : order.isCancelled
                    ? Icons.cancel
                    : Icons.schedule;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            order.orderNumber,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Chip(
                          avatar: Icon(statusIcon, color: statusColor, size: 16),
                          label: Text(order.status),
                          labelStyle: TextStyle(color: statusColor, fontSize: 12),
                          backgroundColor: statusColor.withOpacity(0.1),
                          side: BorderSide(color: statusColor.withOpacity(0.4)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Supplier: ${order.supplierName}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    Text(
                      'Ordered: ${order.orderDate.toLocal().toString().split(' ').first}  |  '
                      '${order.items.length} line(s), ${order.totalItems} unit(s)',
                      style: const TextStyle(fontSize: 12, color: PosAppTheme.textGray),
                    ),
                    if (order.isReceived && order.receivedDate != null)
                      Text(
                        'Received: ${order.receivedDate!.toLocal().toString().split(' ').first}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: PosAppTheme.successGreen,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      'Total: $symbol ${order.total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (order.items.isNotEmpty && !order.isReceived) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceVariant
                              .withOpacity(0.4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final item in order.items)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  '${item.quantity} x ${item.productName}  '
                                  '($symbol ${item.costPrice.toStringAsFixed(2)} ea)',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (!order.isReceived && !order.isCancelled)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            FilledButton.icon(
                              onPressed: () => _confirmReceive(order),
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('Receive Delivery'),
                              style: FilledButton.styleFrom(
                                backgroundColor: PosAppTheme.successGreen,
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () => _confirmCancel(order),
                              icon: const Icon(Icons.close, size: 18),
                              label: const Text('Cancel'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: PosAppTheme.dangerRed,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmReceive(PurchaseOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Receive Delivery'),
        content: Text(
          'Add ${order.totalItems} unit(s) from ${order.orderNumber} to stock '
          'and create batches? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: PosAppTheme.successGreen,
            ),
            child: const Text('Receive'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await context.read<PurchaseOrderProvider>().receiveOrder(order);
        await context.read<ProductProvider>().loadProducts();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Delivery received - stock updated'),
              backgroundColor: PosAppTheme.successGreen,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to receive: $e')),
          );
        }
      }
    }
  }

  Future<void> _confirmCancel(PurchaseOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Purchase Order'),
        content: Text('Cancel ${order.orderNumber}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: PosAppTheme.dangerRed,
            ),
            child: const Text('Yes, cancel'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await context.read<PurchaseOrderProvider>().cancelOrder(order.id);
    }
  }

  void _openNewOrderDialog({String? prefillProductId}) {
    final products = context.read<ProductProvider>().allProducts;
    final suppliers = context.read<SupplierProvider>().suppliers;
    if (products.isEmpty || suppliers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add products and suppliers before creating an order'),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (_) => NewPurchaseOrderDialog(
        products: products,
        suppliers: suppliers,
        prefillProductId: prefillProductId,
      ),
    );
  }
}

class NewPurchaseOrderDialog extends StatefulWidget {
  const NewPurchaseOrderDialog({
    required this.products,
    required this.suppliers,
    this.prefillProductId,
    super.key,
  });

  final List<Product> products;
  final List<Supplier> suppliers;
  final String? prefillProductId;

  @override
  State<NewPurchaseOrderDialog> createState() => _NewPurchaseOrderDialogState();
}

class _NewPurchaseOrderDialogState extends State<NewPurchaseOrderDialog> {
  Supplier? _supplier;
  String? _selectedProductId;
  final TextEditingController _qtyController = TextEditingController(text: '1');
  final TextEditingController _costController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final List<PurchaseOrderItem> _items = [];

  @override
  void initState() {
    super.initState();
    if (widget.prefillProductId != null) {
      final product = widget.products
          .where((p) => p.id == widget.prefillProductId)
          .firstOrNull;
      if (product != null) {
        _selectedProductId = product.name.isEmpty
            ? widget.prefillProductId
            : product.id;
        _costController.text = product.buyingPrice.toStringAsFixed(2);
      }
    } else {
      _costController.text =
          widget.products.first.buyingPrice.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _costController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.read<SettingsProvider>().settings.currencySymbol;
    final total = _items.fold<double>(0, (sum, i) => sum + i.lineTotal);

    return AlertDialog(
      title: const Text('New Purchase Order'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Supplier', style: _labelStyle),
              const SizedBox(height: 6),
              DropdownButtonFormField<Supplier>(
                initialValue: _supplier,
                isExpanded: true,
                hint: const Text('Select supplier'),
                items: [
                  for (final s in widget.suppliers)
                    DropdownMenuItem(value: s, child: Text(s.name)),
                ],
                onChanged: (s) => setState(() => _supplier = s),
                decoration: _decoration,
              ),
              const SizedBox(height: 14),
              Text('Add Items', style: _labelStyle),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedProductId,
                      isExpanded: true,
                      hint: const Text('Product'),
                      items: [
                        for (final p in widget.products)
                          DropdownMenuItem(value: p.id, child: Text(p.name)),
                      ],
                      onChanged: (id) => setState(() {
                        _selectedProductId = id;
                        final product =
                            widget.products.where((p) => p.id == id).firstOrNull;
                        _costController.text = product != null
                            ? product.buyingPrice.toStringAsFixed(2)
                            : '';
                      }),
                      decoration: _decoration,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _qtyController,
                      keyboardType: TextInputType.number,
                      decoration: _decoration.copyWith(labelText: 'Qty'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _costController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: _decoration.copyWith(labelText: 'Cost'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _addItem,
                    icon: const Icon(Icons.add),
                    tooltip: 'Add to order',
                  ),
                ],
              ),
              if (_items.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceVariant
                        .withOpacity(0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < _items.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${_items[i].quantity} x ${_items[i].productName}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              Text(
                                '$symbol ${_items[i].lineTotal.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 13),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.remove_circle_outline,
                                    color: PosAppTheme.dangerRed, size: 20),
                                onPressed: () =>
                                    setState(() => _items.removeAt(i)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Order Total',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '$symbol ${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: PosAppTheme.primaryGreen,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: _decoration.copyWith(
                  labelText: 'Notes (optional)',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: const Text('Place Order'),
        ),
      ],
    );
  }

  TextStyle get _labelStyle => const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: PosAppTheme.textDark,
      );

  InputDecoration get _decoration => const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
      );

  void _addItem() {
    final product =
        widget.products.where((p) => p.id == _selectedProductId).firstOrNull;
    if (product == null) {
      _snack('Select a product');
      return;
    }
    final qty = int.tryParse(_qtyController.text);
    final cost = double.tryParse(_costController.text);
    if (qty == null || qty <= 0) {
      _snack('Enter a valid quantity');
      return;
    }
    if (cost == null || cost <= 0) {
      _snack('Enter a valid cost price');
      return;
    }
    setState(() {
      _items.add(PurchaseOrderItem(
        productId: product.id,
        productName: product.name,
        quantity: qty,
        costPrice: cost,
      ));
      _qtyController.text = '1';
    });
  }

  Future<void> _save() async {
    if (_supplier == null) {
      _snack('Select a supplier');
      return;
    }
    if (_items.isEmpty) {
      _snack('Add at least one item');
      return;
    }
    try {
      await context.read<PurchaseOrderProvider>().createOrder(
            supplierId: _supplier!.id,
            supplierName: _supplier!.name,
            items: List.of(_items),
            notes: _notesController.text,
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purchase order created'),
            backgroundColor: PosAppTheme.successGreen,
          ),
        );
      }
    } catch (e) {
      _snack('Failed to create order: $e');
    }
  }

  void _snack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}