import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/models/sale.dart';
import '../../../data/services/print_service.dart';
import '../../providers/sales_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/custom_widgets.dart';

/// Bill history with daily total tracking. Lists every completed sale with
/// search, a daily revenue total, and one-tap reprint of any bill.
class BillHistoryScreen extends StatefulWidget {
  const BillHistoryScreen({super.key});

  @override
  State<BillHistoryScreen> createState() => _BillHistoryScreenState();
}

class _BillHistoryScreenState extends State<BillHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  DateTime? _selectedDailyDate;

  /// True when the daily filter is active ("today" mode), otherwise shows all.
  bool _dailyMode = false;
  List<Sale> _allSales = [];
  bool _loading = true;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSales() async {
    setState(() => _loading = true);
    final sales = await context.read<SalesProvider>().getAllSales();
    if (!mounted) {
      return;
    }
    setState(() {
      _allSales = List<Sale>.from(sales)
        ..sort((a, b) => b.saleDate.compareTo(a.saleDate));
      _loading = false;
    });
  }

  List<Sale> get _filteredSales {
    final query = _searchController.text.trim().toLowerCase();
    return _allSales.where((sale) {
      if (_dailyMode) {
        if (_selectedDailyDate == null) {
          return false;
        }
        final local = sale.saleDate.toLocal();
        final d = _selectedDailyDate!;
        if (local.year != d.year ||
            local.month != d.month ||
            local.day != d.day) {
          return false;
        }
      }
      if (query.isEmpty) {
        return true;
      }
      return sale.invoiceLabel.toLowerCase().contains(query) ||
          sale.cashierName.toLowerCase().contains(query) ||
          sale.paymentMethod.toLowerCase().contains(query) ||
          sale.notes.toLowerCase().contains(query) ||
          DateFormat('yyyy-MM-dd').format(sale.saleDate).contains(query);
    }).toList();
  }

  double get _filteredTotal =>
      _filteredSales.fold(0.0, (sum, s) => sum + s.totalAmount);

  Future<Uint8List?> _loadLogoBytes() async {
    try {
      final data = await rootBundle.load('assets/images/randil_logo.png');
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _reprintBill(Sale sale) async {
    if (_printing) {
      return;
    }
    setState(() => _printing = true);
    try {
      final printService = PrintService();
      final settings = context.read<SettingsProvider>().settings;
      final printers = printService.listPrinters();
      final printerName =
          printService.selectPrinter(printers, settings.printerName);

      if (printerName.isEmpty) {
        if (mounted) {
          _showToast('No printer found. Install your printer first.',
              isError: true);
        }
        return;
      }

      final ok = printService.printSale(
        sale,
        settings,
        printerName,
        logoBytes: await _loadLogoBytes(),
      );
      if (!ok) {
        if (mounted) {
          _showToast(printService.lastPrintError ?? 'Could not print the bill.',
              isError: true);
        }
        return;
      }

      final problem = await printService.verifyPrint(printerName);
      if (problem != null) {
        if (mounted) {
          _showToast(problem, isError: true);
        }
        return;
      }

      if (mounted) {
        _showToast('Bill ${sale.invoiceLabel} reprinted successfully');
      }
    } catch (e) {
      if (mounted) {
        _showToast('Error printing bill: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _printing = false);
      }
    }
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFD32F2F) : null,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showBillDialog(Sale sale) async {
    final settings = context.read<SettingsProvider>().settings;
    final printService = PrintService();
    final receiptText = printService.generateReceiptText(sale, settings);

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Bill ${sale.invoiceLabel}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Date: ${DateFormat('yyyy-MM-dd HH:mm').format(sale.saleDate)}',
                ),
                Text('Cashier: ${sale.cashierName}'),
                Text('Payment: ${sale.paymentMethod}'),
                const SizedBox(height: 12),
                Container(
                  height: 320,
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Image.asset(
                          'assets/images/randil_logo.png',
                          height: 64,
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          receiptText,
                          style: const TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: PosAppTheme.primaryGreen,
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              _reprintBill(sale);
            },
            icon: const Icon(Icons.print),
            label: const Text('Reprint'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDailyDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDailyDate = picked;
        _dailyMode = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Bill History'),
          elevation: 0,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F9D58), Color(0xFF2BB673)],
              ),
            ),
          ),
          actions: [
            IconButton(
              onPressed: _loadSales,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DashboardHeroPanel(
                title: 'Bill History & Daily Totals',
                subtitle: 'Browse past bills, track daily revenue, and reprint any bill',
                icon: Icons.receipt_long,
                colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
              ),
              const SizedBox(height: 12),
              // Daily total strip
              GroceryCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _dailyMode && _selectedDailyDate != null
                                ? 'Daily Total — ${DateFormat('MMM dd, yyyy').format(_selectedDailyDate!)}'
                                : 'Showing All Bills',
                            style: const TextStyle(
                              fontSize: 13,
                              color: PosAppTheme.textGray,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${context.watch<SettingsProvider>().settings.currencySymbol} ${_filteredTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: PosAppTheme.primaryGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bills',
                          style: TextStyle(
                            fontSize: 13,
                            color: PosAppTheme.textGray,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${_filteredSales.length}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: PosAppTheme.accentBlue,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Search + daily filter
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Search invoice, cashier, or date',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.clear),
                              )
                            : null,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('Daily'),
                  ),
                  if (_dailyMode) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _dailyMode = false;
                        _selectedDailyDate = null;
                      }),
                      icon: const Icon(Icons.close),
                      label: const Text('Clear'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredSales.isEmpty
                        ? const EmptyState(
                            title: 'No bills found',
                            message: 'No sales match the current filter.',
                            icon: Icons.receipt_long,
                          )
                        : ListView.separated(
                            itemCount: _filteredSales.length,
                            separatorBuilder: (_, __) => const SizedBox(
                              height: 8,
                            ),
                            itemBuilder: (context, index) {
                              final sale = _filteredSales[index];
                              final symbol = context
                                  .read<SettingsProvider>()
                                  .settings
                                  .currencySymbol;
                              return GroceryCard(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              sale.invoiceLabel,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${DateFormat('yyyy-MM-dd HH:mm').format(sale.saleDate)}  •  ${sale.cashierName}  •  ${sale.paymentMethod}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: PosAppTheme.textGray,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${sale.items.length} item(s)',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: PosAppTheme.textGray,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '$symbol ${sale.totalAmount.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color:
                                                  PosAppTheme.primaryGreen,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                tooltip: 'View Bill',
                                                icon: const Icon(
                                                  Icons.visibility,
                                                  size: 20,
                                                ),
                                                onPressed: () =>
                                                    _showBillDialog(sale),
                                              ),
                                              IconButton(
                                                tooltip: 'Reprint Bill',
                                                icon: _printing
                                                    ? const SizedBox(
                                                        width: 18,
                                                        height: 18,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                      )
                                                    : const Icon(
                                                        Icons.print,
                                                        size: 20,
                                                      ),
                                                onPressed: _printing
                                                    ? null
                                                    : () => _reprintBill(sale),
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
                          ),
              ),
            ],
          ),
        ),
      );
}