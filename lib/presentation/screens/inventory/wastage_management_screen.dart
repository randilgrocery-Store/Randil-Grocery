import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/models/product.dart';
import '../../../data/models/product_batch.dart';
import '../../../data/models/wastage.dart';
import '../../providers/auth_provider.dart';
import '../../providers/batch_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/wastage_provider.dart';
import '../../widgets/custom_widgets.dart';

class WastageManagementScreen extends StatefulWidget {
  const WastageManagementScreen({super.key});

  @override
  State<WastageManagementScreen> createState() =>
      _WastageManagementScreenState();
}

class _WastageManagementScreenState extends State<WastageManagementScreen> {
  static const _reasons = [
    'Expired',
    'Damaged',
    'Spilled',
    'Stolen',
    'Recalled',
    'Other',
  ];

  Map<String, dynamic>? _report;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WastageProvider>().loadWastages();
      _loadReport();
    });
  }

  Future<void> _loadReport() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final report = await context
        .read<WastageProvider>()
        .getWastageReport(start, end.subtract(const Duration(seconds: 1)));
    if (mounted) {
      setState(() => _report = report);
    }
  }

  Product? _productById(String id) {
    for (final p in context.read<ProductProvider>().allProducts) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Human-readable wasted quantity. Break-bulk stock is kept in boxes, so a
  /// 0.3-box loss of a 10-piece product reads as "3 pieces" (or "1 box + 5
  /// pieces" when more than a box was lost).
  String _wastageQtyLabel(Wastage w, Product? product) {
    if (product != null && product.isBreakBulk) {
      return product.stockLabel(w.quantity);
    }
    return '${fmtQty(w.quantity)} ${w.quantity == 1 ? 'unit' : 'units'}';
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardHeroPanel(
              title: 'Wastage Tracking',
              subtitle: 'Record and monitor spoiled, damaged or lost stock',
              icon: Icons.eco_outlined,
              colors: [Color(0xFFFF512F), Color(0xFFDD2476)],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _showAddWastageDialog(context),
                  icon: const Icon(Icons.delete_sweep),
                  label: const Text('Record Wastage'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PosAppTheme.dangerRed,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SummaryRow(report: _report),
            const SizedBox(height: 16),
            Expanded(
              child: Consumer<WastageProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final wastages = provider.wastages;
                  if (wastages.isEmpty) {
                    return const EmptyState(
                      icon: Icons.eco_outlined,
                      title: 'No Wastage Recorded',
                      message: 'Tap "Record Wastage" to log damaged or expired stock',
                    );
                  }
                  return ListView.separated(
                    itemCount: wastages.length,
                    separatorBuilder: (_, __) => const Divider(height: 14),
                    itemBuilder: (context, index) {
                      final w = wastages[index];
                      final byId = {
                        for (final p in context
                            .read<ProductProvider>()
                            .allProducts)
                          p.id: p,
                      };
                      return GroceryCard(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: PosAppTheme.dangerRed.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.delete_sweep,
                                  color: PosAppTheme.dangerRed,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      w.productName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${w.reason}  •  ${_wastageQtyLabel(w, byId[w.productId])}'
                                      '${w.batchNumber.isNotEmpty ? '  •  Batch ${w.batchNumber}' : ''}'
                                      '  •  ${DateFormat('MMM dd, yyyy').format(w.wastageDate)}',
                                      style: const TextStyle(
                                        color: PosAppTheme.textGray,
                                        fontSize: 11,
                                      ),
                                    ),
                                    if (w.notes.isNotEmpty)
                                      Text(
                                        w.notes,
                                        style: const TextStyle(
                                          color: PosAppTheme.textGray,
                                          fontSize: 11,
                                        ),
                                      ),
                                    if (w.recordedBy.isNotEmpty)
                                      Text(
                                        'Recorded by: ${w.recordedBy}',
                                        style: const TextStyle(
                                          color: PosAppTheme.textGray,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Rs. ${w.lossValue.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: PosAppTheme.dangerRed,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Edit this wastage record',
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(Icons.edit_outlined,
                                            size: 18),
                                        color: PosAppTheme.primaryGreen,
                                        onPressed: () =>
                                            _showEditWastageDialog(context, w),
                                      ),
                                      IconButton(
                                        tooltip: 'Remove this wastage record',
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(Icons.delete_outline,
                                            size: 18),
                                        color: PosAppTheme.dangerRed,
                                        onPressed: () =>
                                            _confirmDeleteWastage(context, w),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      );

  void _showEditWastageDialog(BuildContext context, Wastage w) {
    final product = _productById(w.productId);
    final isBreakBulk = product?.isBreakBulk ?? false;
    final ppb = product != null && product.piecesPerBox > 1
        ? product.piecesPerBox
        : 1;
    final qtyCtrl = TextEditingController(
      text: isBreakBulk
          ? '${(w.quantity * ppb).round()}'
          : w.quantity.toString(),
    );
    final notesCtrl = TextEditingController(text: w.notes);
    String selectedReason = w.reason;
    DateTime selectedDate = w.wastageDate;
    bool wasteInPieces = isBreakBulk;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Wastage'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (ctx, setState) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      w.productName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GroceryTextField(
                    controller: qtyCtrl,
                    label: isBreakBulk
                        ? (wasteInPieces ? 'Pieces *' : 'Boxes *')
                        : 'Quantity *',
                    hint: isBreakBulk
                        ? (wasteInPieces
                            ? 'Loose pieces wasted'
                            : 'Whole boxes wasted')
                        : 'Units wasted',
                    prefixIcon: Icons.numbers,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  if (isBreakBulk) ...[
                    const SizedBox(height: 8),
                    _UnitToggle(
                      pieces: wasteInPieces,
                      piecesPerBox: ppb,
                      onChanged: (nowPieces) {
                        setState(() {
                          final typed =
                              double.tryParse(qtyCtrl.text.trim());
                          if (typed != null && typed > 0) {
                            qtyCtrl.text = fmtQty(nowPieces
                                ? typed * ppb
                                : typed / ppb);
                          }
                          wasteInPieces = nowPieces;
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedReason,
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                      prefixIcon: Icon(Icons.report_problem),
                    ),
                    items: _reasons
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) selectedReason = v;
                    },
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => selectedDate = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Date',
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        DateFormat('MMM dd, yyyy').format(selectedDate),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GroceryTextField(
                    controller: notesCtrl,
                    label: 'Notes (optional)',
                    hint: 'Any additional details',
                    prefixIcon: Icons.notes,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
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
                    backgroundColor: Color(0xFFD32F2F),
                  ),
                );
                return;
              }
              // Stock is kept in boxes; pieces become a fraction of a box.
              final boxQty =
                  isBreakBulk && wasteInPieces ? qty.round() / ppb : qty;
              Navigator.pop(ctx);
              final updated = await context
                  .read<WastageProvider>()
                  .updateWastage(
                    id: w.id,
                    quantity: boxQty,
                    reason: selectedReason,
                    notes: notesCtrl.text.trim(),
                    wastageDate: selectedDate,
                  );
              if (!context.mounted) return;
              showTopSnackBar(
                context,
                SnackBar(
                  content: Text(updated != null
                      ? 'Wastage updated'
                      : 'Could not update the wastage record'),
                  backgroundColor: updated != null
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFFD32F2F),
                ),
              );
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteWastage(BuildContext context, Wastage w) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this wastage record?'),
        content: Text(
          '${w.productName} — ${_wastageQtyLabel(w, _productById(w.productId))} '
          '(Rs. ${w.lossValue.toStringAsFixed(2)}) will be put back on the shelf.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: PosAppTheme.dangerRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await context.read<WastageProvider>().deleteWastage(w.id);
    if (!mounted) return;
    showTopSnackBar(
      context,
      SnackBar(
        content: Text(ok
            ? 'Wastage record removed, stock restored'
            : 'Could not remove the wastage record'),
        backgroundColor: ok ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F),
      ),
    );
  }

  void _showAddWastageDialog(BuildContext context) {
    final qtyCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final scanCtrl = TextEditingController();
    Product? selectedProduct;
    ProductBatch? selectedBatch;
    String selectedReason = _reasons.first;
    DateTime selectedDate = DateTime.now();
    bool wasteInPieces = true;
    final recordedBy =
        context.read<AuthProvider>().currentUser?.fullName ?? 'Cashier';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Wastage'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (ctx, setState) => Consumer2<ProductProvider,
                  BatchProvider>(
                builder: (context, productProvider, batchProvider, _) {
                  final products = productProvider.allProducts;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: scanCtrl,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Scan barcode',
                          hintText:
                              'Scan or type the barcode to pick the product',
                          prefixIcon: Icon(Icons.barcode_reader),
                        ),
                        onSubmitted: (value) async {
                          final code = value.trim();
                          if (code.isEmpty) return;
                          Product? found;
                          try {
                            found =
                                await productProvider.getProductByCode(code) ??
                                    await productProvider
                                        .getProductByBarcodeLoose(code);
                          } catch (_) {}
                          if (found == null) {
                            showTopSnackBar(context, 
                              const SnackBar(
                                content:
                                    Text('No product matches that barcode'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }
                          Product? inList;
                          for (final p in products) {
                            if (p.id == found.id) {
                              inList = p;
                              break;
                            }
                          }
                          final resolved = inList ?? found;
                          setState(() {
                            selectedProduct = resolved;
                            selectedBatch = null;
                            wasteInPieces = true;
                            qtyCtrl.clear();
                          });
                          scanCtrl.clear();
                          if (inList != null) {
                            await batchProvider.loadBatchesForProduct(inList.id);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<Product>(
                        key: ValueKey(
                            'wastage-product-${selectedProduct?.id ?? ''}'),
                        initialValue: selectedProduct,
                        hint: const Text('Select Product *'),
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Product',
                          prefixIcon: Icon(Icons.production_quantity_limits),
                        ),
                        items: products
                            .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                            .toList(),
                        onChanged: (value) async {
                          setState(() {
                            selectedProduct = value;
                            selectedBatch = null;
                            wasteInPieces = true;
                            qtyCtrl.clear();
                          });
                          if (value != null) {
                            await batchProvider.loadBatchesForProduct(value.id);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      if (selectedProduct != null && batchProvider.batches.isNotEmpty) ...[
                        DropdownButtonFormField<ProductBatch>(
                          initialValue: selectedBatch,
                          hint: const Text('Batch (optional)'),
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Deduct from batch',
                            prefixIcon: Icon(Icons.view_agenda),
                          ),
                          items: batchProvider.batches
                              .map((b) => DropdownMenuItem(
                                    value: b,
                                    child: Text(
                                        '${b.batchNumber} (${fmtQty(b.quantity)} left)'),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() => selectedBatch = value);
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      GroceryTextField(
                        controller: qtyCtrl,
                        label:
                            selectedProduct?.isBreakBulk == true
                                ? (wasteInPieces ? 'Pieces *' : 'Boxes *')
                                : 'Quantity *',
                        hint:
                            selectedProduct?.isBreakBulk == true
                                ? (wasteInPieces
                                    ? 'Loose pieces wasted'
                                    : 'Whole boxes wasted')
                                : 'Units wasted',
                        prefixIcon: Icons.numbers,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                      if (selectedProduct?.isBreakBulk == true) ...[
                        const SizedBox(height: 8),
                        _UnitToggle(
                          pieces: wasteInPieces,
                          piecesPerBox: selectedProduct!.piecesPerBox,
                          onChanged: (nowPieces) {
                            setState(() {
                              final typed =
                                  double.tryParse(qtyCtrl.text.trim());
                              if (typed != null && typed > 0) {
                                qtyCtrl.text = fmtQty(nowPieces
                                    ? typed * selectedProduct!.piecesPerBox
                                    : typed /
                                        selectedProduct!.piecesPerBox);
                              }
                              wasteInPieces = nowPieces;
                            });
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedReason,
                        decoration: const InputDecoration(
                          labelText: 'Reason',
                          prefixIcon: Icon(Icons.report_problem),
                        ),
                        items: _reasons
                            .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) selectedReason = v;
                        },
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setState(() => selectedDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Date',
                            prefixIcon: Icon(Icons.calendar_today),
                          ),
                          child: Text(
                            DateFormat('MMM dd, yyyy').format(selectedDate),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      GroceryTextField(
                        controller: notesCtrl,
                        label: 'Notes (optional)',
                        hint: 'Any additional details',
                        prefixIcon: Icons.notes,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (selectedProduct == null || qtyCtrl.text.isEmpty) {
                showTopSnackBar(context, 
                  const SnackBar(
                    content: Text('Please select a product and enter quantity'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              final qty = double.tryParse(qtyCtrl.text.trim());
              if (qty == null || qty <= 0) {
                showTopSnackBar(context, 
                  const SnackBar(
                    content: Text('Please enter a valid quantity'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              // Stock is kept in boxes; loose pieces become a fraction of a box.
              final breakBulk = selectedProduct!.isBreakBulk;
              final ppb = selectedProduct!.piecesPerBox > 1
                  ? selectedProduct!.piecesPerBox
                  : 1;
              final boxQty =
                  breakBulk && wasteInPieces ? qty.round() / ppb : qty;
              final available =
                  selectedBatch?.quantity ?? selectedProduct!.quantity;
              if (boxQty > available + 0.0001) {
                showTopSnackBar(context, 
                  SnackBar(
                    content: Text(
                        'Quantity exceeds available stock'
                        ' (${selectedProduct!.stockLabel(available)})'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              try {
                final wastage =
                    await context.read<WastageProvider>().addWastage(
                          productId: selectedProduct!.id,
                          productName: selectedProduct!.name,
                          quantity: boxQty,
                          reason: selectedReason,
                          batchId: selectedBatch?.id ?? '',
                          batchNumber: selectedBatch?.batchNumber ?? '',
                          notes: notesCtrl.text.trim(),
                          recordedBy: recordedBy,
                          wastageDate: selectedDate,
                        );
                await context.read<ProductProvider>().loadProducts();
                if (context.mounted) {
                  Navigator.pop(ctx);
                  showTopSnackBar(context, 
                    SnackBar(
                      content: Text(wastage == null
                          ? 'Product no longer exists · refresh the product list'
                          : 'Wastage recorded successfully'),
                      backgroundColor: wastage == null
                          ? PosAppTheme.warningOrange
                          : Colors.green,
                    ),
                  );
                  await _loadReport();
                }
              } catch (e) {
                if (context.mounted) {
                  showTopSnackBar(context, 
                    SnackBar(
                      content: Text('Error recording wastage: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style:
                ElevatedButton.styleFrom(backgroundColor: PosAppTheme.dangerRed),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.report});

  final Map<String, dynamic>? report;

  @override
  Widget build(BuildContext context) {
    final totalUnits = (report?['totalUnits'] as num?) ?? 0;
    final totalLoss = (report?['totalLoss'] as num?)?.toDouble() ?? 0.0;
    final byReason = (report?['byReason'] as Map?) ?? const {};
    final topReason = byReason.isEmpty
        ? '—'
        : (byReason as Map<String, dynamic>).entries.reduce(
            (a, b) => (b.value as num) > (a.value as num) ? b : a,
          ).key;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.delete_sweep,
            label: "Today's Units Wasted",
            value: fmtQty(totalUnits),
            color: PosAppTheme.dangerRed,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.money_off,
            label: "Today's Loss (Cost)",
            value: 'Rs. ${totalLoss.toStringAsFixed(2)}',
            color: const Color(0xFFE67E22),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.report_problem,
            label: 'Top Reason',
            value: topReason,
            color: PosAppTheme.accentBlue,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => GroceryCard(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: PosAppTheme.textGray,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// "Pieces / Boxes" switch for wastage on a break-bulk product (stock is kept
/// in boxes, but loose single pieces are the usual thing wasted).
class _UnitToggle extends StatelessWidget {
  const _UnitToggle({
    required this.pieces,
    required this.piecesPerBox,
    required this.onChanged,
  });

  final bool pieces;
  final int piecesPerBox;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget button(String label, bool selected, VoidCallback onTap) => Expanded(
          child: Material(
            color: selected
                ? PosAppTheme.primaryGreen.withOpacity(0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected
                        ? PosAppTheme.primaryGreen
                        : Colors.grey.shade400,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? PosAppTheme.primaryGreen
                        : PosAppTheme.textGray,
                  ),
                ),
              ),
            ),
          ),
        );

    return Row(
      children: [
        button('Pieces', pieces, () => onChanged(true)),
        const SizedBox(width: 8),
        button('Boxes', !pieces, () => onChanged(false)),
        const SizedBox(width: 8),
        Text(
          '$piecesPerBox per box',
          style: const TextStyle(color: PosAppTheme.textGray, fontSize: 11),
        ),
      ],
    );
  }
}