import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/responsive.dart';
import '../../../data/database/database_service.dart';
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

  /// Always-focused box at the top of the Receive tab. A hand-held scanner
  /// "types" the barcode and presses Enter, which fires [_handleScan] — the
  /// item is added straight to the GRN, no dropdown, no extra dialog.
  final TextEditingController _scanController = TextEditingController();
  final FocusNode _scanFocus = FocusNode();
  String? _lastScan;

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
    _scanController.dispose();
    _scanFocus.dispose();
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
                                onChanged: (value) {
                                  setState(() => _supplierId = value);
                                  // Keep the scanner working: after choosing a
                                  // supplier, put the cursor back in the scan box.
                                  _scanFocus.requestFocus();
                                },
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
          _scanField(),
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
                    label: const Text('Add Item (manual)'),
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
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: [
                    for (var i = 0; i < _lines.length; i++)
                      DataRow(cells: [
                        DataCell(Text(_lines[i].product.name)),
                        DataCell(Text(
                          _lines[i].batchNumber.isEmpty
                              ? _grnNumberController.text
                              : _lines[i].batchNumber,
                        )),
                        DataCell(Text(_lines[i].product.isBreakBulk
                            ? _lines[i]
                                .product
                                .stockLabel(_lines[i].quantity)
                            : fmtQty(_lines[i].quantity))),
                        DataCell(Text(
                            '$symbol ${_lines[i].costPrice.toStringAsFixed(2)}')),
                        DataCell(Text(
                            '$symbol ${_lines[i].sellingPrice.toStringAsFixed(2)}')),
                        DataCell(Text(
                            '$symbol ${_lines[i].lineTotal.toStringAsFixed(2)}')),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Edit quantity / prices / expiry',
                              icon: const Icon(Icons.edit_outlined,
                                  color: PosAppTheme.accentBlue),
                              onPressed: () => _addItemDialog(products,
                                  initialProduct: _lines[i].product,
                                  replaceIndex: i),
                            ),
                            IconButton(
                              tooltip: 'Remove',
                              icon: const Icon(Icons.delete_outline,
                                  color: PosAppTheme.dangerRed),
                              onPressed: () =>
                                  setState(() => _lines.removeAt(i)),
                            ),
                          ],
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

  // ── Add / edit item dialog ─────────────────────────────────────
  Future<void> _addItemDialog(List<Product> products,
      {Product? initialProduct, int? replaceIndex}) async {
    final existing = replaceIndex != null ? _lines[replaceIndex] : null;
    Product? selected = existing?.product ?? initialProduct;

    // The dropdown's value must be one of its items. A scanned product may not
    // be in the in-memory list yet, so fold it in — otherwise Flutter throws.
    final dropdownItems = <Product>[...products];
    if (selected != null &&
        !dropdownItems.any((p) => p.id == selected!.id)) {
      dropdownItems.add(selected);
    }

    final qtyController = TextEditingController(
      text: existing != null ? fmtQty(existing.quantity) : '1',
    );
    final costController = TextEditingController(
      text: (existing?.costPrice ?? initialProduct?.buyingPrice ?? 0)
          .toStringAsFixed(2),
    );
    final sellController = TextEditingController(
      text: (existing?.sellingPrice ?? initialProduct?.sellingPrice ?? 0)
          .toStringAsFixed(2),
    );
    final batchController =
        TextEditingController(text: existing?.batchNumber ?? '');
    DateTime? expiry = existing?.expiryDate;

    // GRN stock is kept in the product's own unit (boxes). Break-bulk items
    // may be received as whole boxes OR as loose pieces out of an opened box;
    // whichever the owner types, it is converted to boxes before saving so the
    // system stock always balances against the physical shelf.
    var usePieces = false;

    String qtyHint(Product p) => usePieces
        ? 'Loose pieces received — becomes ${p.stockLabel(0)}'
        : 'Whole boxes received — ${p.piecesPerBox} pieces per box';
    String qtyPreview(Product p, String text) {
      final typed = double.tryParse(text.trim()) ?? 0;
      if (typed <= 0) return '';
      final boxQty =
          usePieces ? typed.round() / p.piecesPerBox : typed;
      return '= ${p.stockLabel(boxQty)}';
    }

    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add Item to GRN' : 'Edit GRN Item'),
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
                      for (final p in dropdownItems)
                        DropdownMenuItem(value: p, child: Text(p.name)),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        selected = value;
                        usePieces = false;
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
                          onChanged: (_) => setDialogState(() {}),
                          decoration: InputDecoration(
                            labelText: usePieces && selected != null &&
                                    selected!.isBreakBulk
                                ? 'Quantity (pieces) *'
                                : 'Quantity (boxes) *',
                            helperText: selected != null &&
                                    selected!.isBreakBulk
                                ? qtyPreview(selected!, qtyController.text)
                                : null,
                            prefixIcon: const Icon(Icons.inventory),
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
                  if (selected != null && selected!.isBreakBulk) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            usePieces
                                ? qtyHint(selected!)
                                : '${selected!.piecesPerBox} pieces per box'
                                    ' — a partly-open box is entered as its'
                                    ' box fraction (5 left of 20 = 0.25)',
                            style: const TextStyle(
                                color: PosAppTheme.textGray, fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: PosAppTheme.lightGreen,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: PosAppTheme.primaryGreen),
                          ),
                          child: InkWell(
                            onTap: () => setDialogState(() {
                              usePieces = !usePieces;
                              final typed =
                                  double.tryParse(qtyController.text.trim()) ??
                                      0;
                              qtyController.text = usePieces
                                  ? fmtQty(typed * selected!.piecesPerBox)
                                  : fmtQty(typed / selected!.piecesPerBox);
                            }),
                            child: Text(
                              usePieces ? 'In pieces' : 'In boxes',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: PosAppTheme.primaryGreen),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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
                // Loose pieces become their fraction of a box (stock is kept
                // in boxes) so the total cost/price stays correct.
                final boxQty = usePieces && selected!.isBreakBulk
                    ? qty.round() / selected!.piecesPerBox
                    : qty;
                if (boxQty <= 0 || cost < 0 || sell < 0) {
                  showTopSnackBar(context, 
                    const SnackBar(
                      content: Text('Enter a valid quantity, cost and price'),
                    ),
                  );
                  return;
                }
                final line = _GrnLine(
                  product: selected!,
                  quantity: boxQty,
                  costPrice: cost,
                  sellingPrice: sell,
                  batchNumber: batchController.text.trim(),
                  expiryDate: expiry,
                );
                setState(() {
                  if (replaceIndex != null) {
                    _lines[replaceIndex] = line;
                  } else {
                    _lines.add(line);
                  }
                });
                Navigator.pop(dialogContext, true);
              },
              child: Text(replaceIndex != null ? 'Save' : 'Add'),
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

  /// A permanently-visible scan box at the top of the Receive tab. A barcode
  /// scanner behaves like a keyboard: it drops the code into the focused field
  /// and presses Enter, which fires [_handleScan] — the item lands in the GRN
  /// immediately. No product dropdown, no second dialog.
  Widget _scanField() {
    final last = _lastScan;
    return Card(
      color: PosAppTheme.lightGreen.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _scanController,
              focusNode: _scanFocus,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: _handleScan,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                labelText: 'Scan barcode to receive',
                hintText:
                    'Scan an item — it is added straight away (scan again for more)',
                prefixIcon: Icon(Icons.qr_code_scanner),
                border: InputBorder.none,
              ),
            ),
            if (last != null)
              Padding(
                padding: const EdgeInsets.only(left: 44, bottom: 6),
                child: Text(
                  last,
                  style: const TextStyle(
                    fontSize: 12,
                    color: PosAppTheme.textGray,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Resolves a scanned code and drops the item straight into the GRN with the
  /// product's current buying/selling price. Scanning the same product again
  /// simply adds another unit.
  Future<void> _handleScan(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return;
    final products = context.read<ProductProvider>().allProducts;
    final match = await _resolveGrnProduct(products, code);
    if (!mounted) return;
    _scanController.clear();
    _scanFocus.requestFocus();

    if (match == null) {
      setState(() => _lastScan = 'No product found for "$code"');
      _snack('No product found for "$code"');
      return;
    }

    setState(() {
      final idx = _lines.indexWhere(
          (l) => l.product.id == match.id && l.batchNumber.isEmpty);
      if (idx >= 0) {
        final existing = _lines[idx];
        _lines[idx] = _GrnLine(
          product: existing.product,
          quantity: existing.quantity + 1,
          costPrice: existing.costPrice,
          sellingPrice: existing.sellingPrice,
          batchNumber: existing.batchNumber,
          expiryDate: existing.expiryDate,
        );
      } else {
        _lines.add(_GrnLine(
          product: match,
          quantity: 1,
          costPrice: match.buyingPrice,
          sellingPrice: match.sellingPrice,
        ));
      }
      final total = _lines
          .where((l) => l.product.id == match.id)
          .fold<double>(0, (sum, l) => sum + l.quantity);
      _lastScan = 'Added ${match.name} — ${fmtQty(total)} in this GRN';
    });
  }

  /// Resolves [code] to a product using the same lookup the POS uses: exact
  /// barcode first, then the product name, then a leading-zero-tolerant match
  /// (a scale label item `00010` and a product barcode `0000010` are the same
  /// item). Falls back to the database so a freshly added product is found
  /// even if the local in-memory list is not refreshed yet.
  Future<Product?> _resolveGrnProduct(
      List<Product> products, String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    final stripped = trimmed.replaceFirst(RegExp(r'^0+'), '');
    Product? zeroPadded;
    for (final p in products) {
      final b = p.barcode.trim().toLowerCase();
      if (b == lower || p.name.toLowerCase() == lower) return p;
      if (stripped.isNotEmpty) {
        final bStripped = b.replaceFirst(RegExp(r'^0+'), '');
        if (bStripped == stripped) zeroPadded ??= p;
      }
    }
    if (zeroPadded != null) return zeroPadded;
    try {
      final direct = await DatabaseService().getProductByCode(trimmed);
      if (direct != null) return direct;
      return await DatabaseService().getProductByBarcodeLoose(trimmed);
    } catch (_) {
      return null;
    }
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
