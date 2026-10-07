import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/responsive.dart';
import '../../../data/models/goods_received_note.dart';
import '../../../data/models/product.dart';
import '../../../data/models/supplier.dart';
import '../../providers/auth_provider.dart';
import '../../providers/grn_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/supplier_provider.dart';
import '../../widgets/custom_widgets.dart';

class GrnScreen extends StatefulWidget {
  const GrnScreen({super.key});

  @override
  State<GrnScreen> createState() => _GrnScreenState();
}

class _GrnScreenState extends State<GrnScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _grnNumberController;
  late final TextEditingController _notesController;

  String? _supplierId;
  final List<_GrnLine> _lines = [];
  bool _saving = false;
  bool _grnRequired = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _grnNumberController = TextEditingController();
    _notesController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProductProvider>().loadProducts();
      context.read<SupplierProvider>().loadSuppliers();
      context.read<GrnProvider>().loadNotes();
      _refreshGrnNumber();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _grnNumberController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _refreshGrnNumber() async {
    final number = await context.read<GrnProvider>().nextGrnNumber();
    if (mounted) {
      _grnNumberController.text = number;
    }
  }

  double get _goodsTotal =>
      _lines.fold<double>(0, (sum, line) => sum + line.lineTotal);

  double get _totalUnits =>
      _lines.fold<double>(0, (sum, line) => sum + line.quantity);

  /// Shows how much the shop already owes the selected supplier so the
  /// person receiving goods can see the running balance at a glance.
  Widget _supplierOutstandingBanner() {
    final provider = context.watch<SupplierProvider>();
    final owed = provider.outstandingFor(_supplierId!);
    final supplier = provider.suppliers
        .where((s) => s.id == _supplierId)
        .firstOrNull;
    final hasDebt = owed > 0.005;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: hasDebt
            ? Colors.red.withOpacity(0.08)
            : Colors.green.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasDebt ? Colors.red.shade200 : Colors.green.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasDebt ? Icons.warning_amber : Icons.check_circle,
            size: 20,
            color: hasDebt ? Colors.red[700] : Colors.green[700],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasDebt
                  ? 'Still owe ${supplier?.name ?? 'supplier'}: Rs. ${owed.toStringAsFixed(2)}'
                  : '${supplier?.name ?? 'Supplier'} is fully paid',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: hasDebt ? Colors.red[700] : Colors.green[700],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final responsive = context.responsive;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Goods Received Notes (GRN)'),
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF134E5E), Color(0xFF71B280)],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<ProductProvider>().loadProducts();
              context.read<SupplierProvider>().loadSuppliers();
              context.read<GrnProvider>().loadNotes();
            },
          ),
          const SizedBox(width: 12),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Receive Goods'),
            Tab(text: 'GRN History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildReceiveTab(responsive),
          _buildHistoryTab(responsive),
        ],
      ),
    );
  }

  // ── Receive tab ────────────────────────────────────────────────
  Widget _buildReceiveTab(ResponsiveSize responsive) {
    final products = context.watch<ProductProvider>().allProducts;
    final suppliers = context.watch<SupplierProvider>().suppliers;
    final settings = context.watch<SettingsProvider>().settings;
    final symbol = settings.currencySymbol;

    return SingleChildScrollView(
      padding: EdgeInsets.all(responsive.paddingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardHeroPanel(
            title: _grnRequired ? 'Receive Stock (GRN)' : 'Manual Stock In',
            subtitle: _grnRequired
                ? 'Record goods received with their own cost and selling price. '
                    'Old stock keeps its price; new stock sells at the new price.'
                : 'Add stock without a supplier GRN. Enter buying price and '
                    'quantity; stock is added and reduced again when sold.',
            icon: Icons.inventory,
            colors: const [Color(0xFF134E5E), Color(0xFF71B280)],
          ),
          SizedBox(height: responsive.paddingMedium),
          Card(
            color: _grnRequired
                ? null
                : PosAppTheme.lightGreen.withValues(alpha: 0.35),
            child: SwitchListTile(
              value: _grnRequired,
              onChanged: (value) => setState(() {
                _grnRequired = value;
                if (!value) _supplierId = null;
              }),
              secondary: Icon(
                _grnRequired ? Icons.description : Icons.bolt,
                color: PosAppTheme.primaryGreen,
              ),
              title: const Text('GRN Required'),
              subtitle: Text(
                _grnRequired
                    ? 'Full goods received note with supplier.'
                    : 'Off: quick manual stock entry (no supplier needed).',
              ),
            ),
          ),
          SizedBox(height: responsive.paddingMedium),
          Card(
            child: Padding(
              padding: EdgeInsets.all(responsive.paddingMedium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _grnRequired
                            ? DropdownButtonFormField<String>(
                                initialValue: _supplierId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Supplier *',
                                  prefixIcon: Icon(Icons.business),
                                ),
                                items: [
                                  for (final Supplier s in suppliers)
                                    DropdownMenuItem(
                                      value: s.id,
                                      child: Text(s.name),
                                    ),
                                ],
                                onChanged: (value) =>
                                    setState(() => _supplierId = value),
                              )
                            : TextField(
                                readOnly: true,
                                decoration: const InputDecoration(
                                  labelText: 'Supplier',
                                  hintText: 'Manual stock in — no supplier',
                                  prefixIcon: Icon(Icons.person_off),
                                ),
                              ),
                      ),
                      SizedBox(width: responsive.paddingSmall),
                      Expanded(
                        child: TextField(
                          controller: _grnNumberController,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: _grnRequired
                                ? 'GRN Number'
                                : 'Reference Number',
                            prefixIcon: const Icon(Icons.numbers),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: responsive.paddingSmall),
                  if (_supplierId != null) _supplierOutstandingBanner(),
                  if (_supplierId != null)
                    SizedBox(height: responsive.paddingSmall),
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      prefixIcon: Icon(Icons.notes),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: responsive.paddingMedium),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Items (${_lines.length})',
                style: TextStyle(
                  fontSize: responsive.heading3,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: products.isEmpty
                        ? null
                        : () => _addItemDialog(products),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Item'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _lines.isEmpty
                        ? null
                        : () => _scanItemDialog(products),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_lines.isEmpty)
            Card(
              child: Padding(
                padding: EdgeInsets.all(responsive.paddingLarge),
                child: Center(
                  child: Text(
                    'No items added yet. Tap "Add Item" to receive stock.',
                    style: TextStyle(color: PosAppTheme.textGray),
                  ),
                ),
              ),
            )
          else
            Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Product')),
                    DataColumn(label: Text('Batch')),
                    DataColumn(label: Text('Qty')),
                    DataColumn(label: Text('Cost')),
                    DataColumn(label: Text('Sell')),
                    DataColumn(label: Text('Total')),
                    DataColumn(label: Text('')),
                  ],
                  rows: [
                    for (final line in _lines)
                      DataRow(cells: [
                        DataCell(Text(line.product.name)),
                        DataCell(Text(
                          line.batchNumber.isEmpty
                              ? _grnNumberController.text
                              : line.batchNumber,
                        )),
                        DataCell(Text(fmtQty(line.quantity))),
                        DataCell(Text('$symbol ${line.costPrice.toStringAsFixed(2)}')),
                        DataCell(
                            Text('$symbol ${line.sellingPrice.toStringAsFixed(2)}')),
                        DataCell(
                            Text('$symbol ${line.lineTotal.toStringAsFixed(2)}')),
                        DataCell(IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: PosAppTheme.dangerRed),
                          onPressed: () => setState(() => _lines.remove(line)),
                        )),
                      ]),
                  ],
                ),
              ),
            ),
          SizedBox(height: responsive.paddingMedium),
          Card(
            child: Padding(
              padding: EdgeInsets.all(responsive.paddingMedium),
              child: Column(
                children: [
                  _summaryRow('Total Units', fmtQty(_totalUnits)),
                  const Divider(),
                  _summaryRow(
                    'Goods Total',
                    '$symbol ${_goodsTotal.toStringAsFixed(2)}',
                    bold: true,
                  ),
                  SizedBox(height: responsive.paddingMedium),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PosAppTheme.primaryGreen,
                        padding: EdgeInsets.symmetric(
                          vertical: responsive.paddingMedium,
                        ),
                      ),
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(
                        _saving
                            ? 'Saving...'
                            : (_grnRequired
                                ? 'Save GRN & Update Stock'
                                : 'Add Stock (No GRN)'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: bold ? PosAppTheme.primaryGreen : null,
            ),
          ),
        ],
      );

  // ── History tab ────────────────────────────────────────────────
  Widget _buildHistoryTab(ResponsiveSize responsive) {
    final provider = context.watch<GrnProvider>();
    final settings = context.watch<SettingsProvider>().settings;
    final symbol = settings.currencySymbol;

    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.notes.isEmpty) {
      return const Center(child: Text('No goods received yet.'));
    }

    return ListView.builder(
      padding: EdgeInsets.all(responsive.paddingMedium),
      itemCount: provider.notes.length,
      itemBuilder: (context, index) {
        final grn = provider.notes[index];
        return Card(
          child: ExpansionTile(
            leading: const CircleAvatar(
              backgroundColor: PosAppTheme.lightGreen,
              child: Icon(Icons.inventory, color: PosAppTheme.primaryGreen),
            ),
            title: Text(grn.grnNumber),
            subtitle: Text(
              '${grn.supplierName} • ${grn.items.length} items • '
              '$symbol ${grn.total.toStringAsFixed(2)} • '
              '${grn.receivedDate.toLocal().toString().split('.').first}',
            ),
            children: [
              Padding(
                padding: EdgeInsets.all(responsive.paddingSmall),
                child: DataTable(
                  columnSpacing: 16,
                  columns: const [
                    DataColumn(label: Text('Product')),
                    DataColumn(label: Text('Qty')),
                    DataColumn(label: Text('Cost')),
                    DataColumn(label: Text('Sell')),
                  ],
                  rows: [
                    for (final item in grn.items)
                      DataRow(cells: [
                        DataCell(Text(item.productName)),
                        DataCell(Text(fmtQty(item.quantity))),
                        DataCell(Text(item.costPrice.toStringAsFixed(2))),
                        DataCell(Text(item.sellingPrice.toStringAsFixed(2))),
                      ]),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Add item dialog ────────────────────────────────────────────
  Future<void> _addItemDialog(List<Product> products,
      {Product? initialProduct}) async {
    Product? selected = initialProduct;
    final qtyController = TextEditingController(text: '1');
    final costController = TextEditingController(
      text: initialProduct?.buyingPrice.toStringAsFixed(2) ?? '',
    );
    final sellController = TextEditingController(
      text: initialProduct?.sellingPrice.toStringAsFixed(2) ?? '',
    );
    final batchController = TextEditingController();
    DateTime? expiry;

    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Item to GRN'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Product>(
                    isExpanded: true,
                    value: selected,
                    decoration: const InputDecoration(
                      labelText: 'Product *',
                      prefixIcon: Icon(Icons.inventory_2),
                    ),
                    items: [
                      for (final p in products)
                        DropdownMenuItem(value: p, child: Text(p.name)),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        selected = value;
                        if (value != null) {
                          costController.text =
                              value.buyingPrice.toStringAsFixed(2);
                          sellController.text =
                              value.sellingPrice.toStringAsFixed(2);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: batchController,
                    decoration: const InputDecoration(
                      labelText: 'Batch Number (optional)',
                      hintText: 'Defaults to the GRN number',
                      prefixIcon: Icon(Icons.numbers),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: qtyController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Quantity *',
                            prefixIcon: Icon(Icons.inventory),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: costController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Cost Price *',
                            prefixIcon: Icon(Icons.payments),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: sellController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Selling Price *',
                      helperText: 'The price this stock will be sold at',
                      prefixIcon: Icon(Icons.sell),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          expiry == null
                              ? 'No expiry date'
                              : 'Expiry: ${expiry!.toString().split(' ')[0]}',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 3650)),
                          );
                          if (picked != null) {
                            setDialogState(() => expiry = picked);
                          }
                        },
                        icon: const Icon(Icons.calendar_today),
                        label: const Text('Expiry'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selected == null) return;
                final qty = double.tryParse(qtyController.text) ?? 0;
                final cost = double.tryParse(costController.text) ?? -1;
                final sell = double.tryParse(sellController.text) ?? -1;
                if (qty <= 0 || cost < 0 || sell < 0) {
                  showTopSnackBar(context, 
                    const SnackBar(
                      content: Text('Enter a valid quantity, cost and price'),
                    ),
                  );
                  return;
                }
                setState(() {
                  _lines.add(_GrnLine(
                    product: selected!,
                    quantity: qty,
                    costPrice: cost,
                    sellingPrice: sell,
                    batchNumber: batchController.text.trim(),
                    expiryDate: expiry,
                  ));
                });
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    qtyController.dispose();
    costController.dispose();
    sellController.dispose();
    batchController.dispose();
  }

  /// Quick "scan" dialog: type or scan a barcode and add that product with its
  /// current prices pre-filled.
  Future<void> _scanItemDialog(List<Product> products) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Scan / Enter Item Code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Barcode or item code',
            prefixIcon: Icon(Icons.qr_code_scanner),
          ),
          onSubmitted: (value) async {
            final code = value.trim().toLowerCase();
            final match = products.cast<Product?>().firstWhere(
                  (p) =>
                      p!.barcode.toLowerCase() == code ||
                      p.name.toLowerCase() == code,
                  orElse: () => null,
                );
            if (match == null) {
              showTopSnackBar(context, 
                const SnackBar(content: Text('No matching product found')),
              );
              return;
            }
            Navigator.pop(dialogContext);
            await _addItemDialog(products, initialProduct: match);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _save() async {
    if (_grnRequired && _supplierId == null) {
      _snack('Please select a supplier');
      return;
    }
    if (_lines.isEmpty) {
      _snack('Add at least one item');
      return;
    }

    final suppliers = context.read<SupplierProvider>().suppliers;
    final matching = suppliers.where((s) => s.id == _supplierId);
    final supplierName = matching.isNotEmpty
        ? matching.first.name
        : (_grnRequired ? 'Unknown' : 'Manual Stock In');

    setState(() => _saving = true);
    try {
      final user = context.read<AuthProvider>().currentUser;
      final grn = GoodsReceivedNote(
        grnNumber: _grnNumberController.text,
        supplierId: _supplierId ?? '',
        supplierName: supplierName,
        receivedBy: user?.fullName ?? '',
        notes: _notesController.text.trim(),
        items: _lines
            .map((line) => GrnItem(
                  productId: line.product.id,
                  productName: line.product.name,
                  barcode: line.product.barcode,
                  quantity: line.quantity,
                  costPrice: line.costPrice,
                  sellingPrice: line.sellingPrice,
                  batchNumber: line.batchNumber,
                  expiryDate: line.expiryDate,
                ))
            .toList(),
      );

      await context.read<GrnProvider>().saveGrn(grn);
      await context.read<ProductProvider>().loadProducts();

      if (!mounted) return;
      setState(() {
        _lines.clear();
        _supplierId = null;
        _notesController.clear();
        _saving = false;
      });
      await _refreshGrnNumber();
      _snack(
        _grnRequired
            ? 'GRN saved and stock updated'
            : 'Stock added (no GRN)',
        success: true,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Failed to save GRN: $e');
    }
  }

  void _snack(String message, {bool success = false}) {
    showTopSnackBar(context, 
      SnackBar(
        content: Text(message),
        backgroundColor:
            success ? PosAppTheme.successGreen : PosAppTheme.dangerRed,
      ),
    );
  }
}

class _GrnLine {
  _GrnLine({
    required this.product,
    required this.quantity,
    required this.costPrice,
    required this.sellingPrice,
    this.batchNumber = '',
    this.expiryDate,
  });

  final Product product;
  final double quantity;
  final double costPrice;
  final double sellingPrice;
  final String batchNumber;
  final DateTime? expiryDate;

  double get lineTotal => quantity * costPrice;
}
