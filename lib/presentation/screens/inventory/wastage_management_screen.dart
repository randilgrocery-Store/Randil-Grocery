import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/models/product.dart';
import '../../../data/models/product_batch.dart';
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
                                      '${w.reason}  •  ${fmtQty(w.quantity)} units'
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
                              Text(
                                'Rs. ${w.lossValue.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: PosAppTheme.dangerRed,
                                ),
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

  void _showAddWastageDialog(BuildContext context) {
    final qtyCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    Product? selectedProduct;
    ProductBatch? selectedBatch;
    String selectedReason = _reasons.first;
    DateTime selectedDate = DateTime.now();
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
                      DropdownButtonFormField<Product>(
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
                        label: 'Quantity *',
                        hint: 'Units wasted',
                        prefixIcon: Icons.numbers,
                        keyboardType: TextInputType.number,
                      ),
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
              final available =
                  selectedBatch?.quantity ?? selectedProduct!.quantity;
              if (qty > available) {
                showTopSnackBar(context, 
                  SnackBar(
                    content: Text(
                        'Quantity exceeds available stock ($available units)'),
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
                          quantity: qty,
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