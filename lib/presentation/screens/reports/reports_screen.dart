import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/models/expense.dart';
import '../../../data/models/sale.dart';
import '../../../data/services/print_service.dart';
import '../../providers/expense_provider.dart';
import '../../providers/reports_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/custom_widgets.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late DateTime _selectedDate;
  late int _selectedYear;
  late int _selectedMonth;
  Map<String, dynamic>? _profitReport;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = now;
    _selectedYear = now.year;
    _selectedMonth = now.month;
    _loadReports();
  }

  Future<void> _loadReports() async {
    final reportProvider = context.read<ReportsProvider>();
    await reportProvider.generateDailyReport(_selectedDate);
    await reportProvider.generateMonthlyReport(_selectedYear, _selectedMonth);
    await _loadProfitReport();
  }

  Future<void> _loadProfitReport() async {
    final start = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final end = start.add(const Duration(days: 1));
    final expenseProvider = context.read<ExpenseProvider>();
    _profitReport = await expenseProvider.getProfitReport(start, end);
    if (mounted) {
      setState(() {});
    }
  }

  Future<List<Sale>> _getDailySales() {
    final start = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final end = start.add(const Duration(days: 1));
    return context.read<ReportsProvider>().getSalesByDateRange(start, end);
  }

  Future<List<Sale>> _getMonthlySales() {
    final start = DateTime(_selectedYear, _selectedMonth, 1);
    final end = (_selectedMonth == 12)
        ? DateTime(_selectedYear + 1, 1, 1)
        : DateTime(_selectedYear, _selectedMonth + 1, 1);
    return context.read<ReportsProvider>().getSalesByDateRange(start, end);
  }

  Future<void> _showSalesDetailDialog(String title, List<Sale> sales) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 760,
          child: sales.isEmpty
              ? const Center(child: Text('No sales records available.'))
              : ListView.separated(
                  itemCount: sales.length,
                  separatorBuilder: (_, __) => const Divider(height: 14),
                  itemBuilder: (context, index) {
                    final sale = sales[index];
                    final itemsText = sale.items
                        .map((item) =>
                            '${item.productName} x${item.quantity} (Rs. ${item.total.toStringAsFixed(2)})')
                        .join(', ');
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Invoice: ${sale.invoiceLabel}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Date: ${DateFormat('yyyy-MM-dd HH:mm').format(sale.saleDate)}',
                        ),
                        Text('Cashier: ${sale.cashierName}'),
                        Text(
                          'Total: Rs. ${sale.totalAmount.toStringAsFixed(2)} | Paid: Rs. ${sale.amountReceived.toStringAsFixed(2)} | Change: Rs. ${sale.balance.toStringAsFixed(2)}',
                        ),
                        const SizedBox(height: 4),
                        Text('Items: $itemsText'),
                      ],
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _printSalesSummary(String title, List<Sale> sales) async {
    final settings = context.read<SettingsProvider>().settings;
    final symbol = settings.currencySymbol;
    final cols = settings.paperWidth >= 72 ? 48 : 32;

    String center(String s) {
      if (s.length >= cols) return s.substring(0, cols);
      final pad = ((cols - s.length) / 2).ceil();
      return '${' ' * pad}$s';
    }

    String pair(String label, String value) {
      final avail = cols - value.length;
      if (avail <= 0) return value.length > cols ? value.substring(0, cols) : value;
      final lbl = label.length > avail ? label.substring(0, avail) : label;
      return lbl.padRight(avail) + value;
    }

    String rule(String c) => c * cols;

    double totalRevenue = 0;
    double cashTotal = 0;
    double cardTotal = 0;
    double discountTotal = 0;
    int totalItems = 0;
    final itemQty = <String, int>{};
    final itemRevenue = <String, double>{};

    for (final sale in sales) {
      totalRevenue += sale.totalAmount;
      discountTotal += sale.totalDiscount;
      if (sale.paymentMethod.toLowerCase().contains('card')) {
        cardTotal += sale.totalAmount;
      } else {
        cashTotal += sale.totalAmount;
      }
      for (final item in sale.items) {
        totalItems += item.quantity;
        itemQty[item.productName] =
            (itemQty[item.productName] ?? 0) + item.quantity;
        itemRevenue[item.productName] =
            (itemRevenue[item.productName] ?? 0) + item.total;
      }
    }

    final buffer = StringBuffer()
      ..writeln(center(settings.shopName.toUpperCase()))
      ..writeln(center(settings.address))
      ..writeln(center('Tel: ${settings.phone}'))
      ..writeln(rule('='))
      ..writeln(center(title))
      ..writeln(center(DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())))
      ..writeln(rule('='))
      ..writeln(pair('Transactions', '${sales.length}'))
      ..writeln(pair('Items Sold', '$totalItems'))
      ..writeln(rule('-'))
      ..writeln(pair('Revenue', '$symbol ${totalRevenue.toStringAsFixed(2)}'))
      ..writeln(pair('Cash', '$symbol ${cashTotal.toStringAsFixed(2)}'))
      ..writeln(pair('Card', '$symbol ${cardTotal.toStringAsFixed(2)}'))
      ..writeln(pair('Discounts', '$symbol ${discountTotal.toStringAsFixed(2)}'))
      ..writeln(rule('='))
      ..writeln('ITEMS SOLD')
      ..writeln(rule('-'));

    final itemEntries = itemQty.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (itemEntries.isEmpty) {
      buffer.writeln('No items sold');
    } else {
      for (final entry in itemEntries) {
        buffer.writeln(pair(
          '${entry.value} x ${entry.key}',
          '$symbol ${(itemRevenue[entry.key] ?? 0).toStringAsFixed(2)}',
        ));
      }
    }

    buffer
      ..writeln(rule('='))
      ..writeln('TRANSACTIONS')
      ..writeln(rule('-'));
    for (final sale in sales) {
      buffer
        ..writeln(pair(
          sale.invoiceLabel,
          '$symbol ${sale.totalAmount.toStringAsFixed(2)}',
        ))
        ..writeln(
          '  ${DateFormat('yyyy-MM-dd HH:mm').format(sale.saleDate)} | '
          '${sale.cashierName} | ${sale.paymentMethod}',
        );
    }

    buffer
      ..writeln(rule('='))
      ..writeln(center('End of Report'))
      ..writeln('')
      ..writeln(center('System developed by'))
      ..writeln(center(PrintService.developerName))
      ..writeln(center('Tel: ${PrintService.developerPhone}'))
      ..writeln(center(PrintService.developerEmail));

    await _sendReport(buffer.toString());
  }

  /// Print a page header in the middle of the configured paper width.
  String _center(String text, int cols) {
    if (text.length >= cols) return text.substring(0, cols);
    final pad = ((cols - text.length) / 2).ceil();
    return '${' ' * pad}$text';
  }

  String _pair(String label, String value, int cols) {
    final avail = cols - value.length;
    if (avail <= 0) return value.length > cols ? value.substring(0, cols) : value;
    final lbl = label.length > avail ? label.substring(0, avail) : label;
    return lbl.padRight(avail) + value;
  }

  /// Handles printer selection and sends a fixed-width report to the printer.
  Future<void> _sendReport(String text) async {
    final settings = context.read<SettingsProvider>().settings;
    final printService = PrintService();
    final printers = printService.listPrinters();
    final printerName =
        printService.selectPrinter(printers, settings.printerName);

    if (!mounted) {
      return;
    }
    if (printerName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No printer found. Install your printer first.'),
          backgroundColor: Color(0xFFD32F2F),
        ),
      );
      return;
    }

    final ok = printService.printReport(
      text,
      printerName,
      paperWidthMm: settings.paperWidth,
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Report printed successfully'
            : 'Print failed: ${printService.lastPrintError ?? 'Unknown error'}'),
        backgroundColor: ok ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F),
      ),
    );
  }

  Future<void> _printProfitReport() async {
    final report = _profitReport;
    if (report == null) {
      return;
    }
    final settings = context.read<SettingsProvider>().settings;
    final symbol = settings.currencySymbol;
    final cols = settings.paperWidth >= 72 ? 48 : 32;

    String money(String label, num value) =>
        _pair(label, '$symbol ${value.toStringAsFixed(2)}', cols);

    final buffer = StringBuffer()
      ..writeln(_center(settings.shopName.toUpperCase(), cols))
      ..writeln(_center(settings.address, cols))
      ..writeln(_center('Tel: ${settings.phone}', cols))
      ..writeln('=' * cols)
      ..writeln(_center('Profit & Expenses Report', cols))
      ..writeln(_center(
          DateFormat('yyyy-MM-dd').format(_selectedDate), cols))
      ..writeln('=' * cols)
      ..writeln(money('Revenue', report['totalRevenue'] as num))
      ..writeln(money('Cost of Goods (COGS)', report['totalCogs'] as num))
      ..writeln(money('Expenses', report['totalExpenses'] as num))
      ..writeln(money('Wastage Loss', report['totalWastage'] as num))
      ..writeln('-' * cols)
      ..writeln(money('Net Profit', report['netProfit'] as num))
      ..writeln('=' * cols)
      ..writeln('EXPENSE BREAKDOWN')
      ..writeln('-' * cols);

    final expenses = (report['expenses'] as List).cast<Expense>();
    if (expenses.isEmpty) {
      buffer.writeln('No expenses recorded');
    } else {
      for (final e in expenses) {
        buffer.writeln(_pair(
          '${e.category}: ${e.description}',
          '$symbol ${e.amount.toStringAsFixed(2)}',
          cols,
        ));
      }
    }

    buffer
      ..writeln('=' * cols)
      ..writeln(_center('End of Report', cols))
      ..writeln('')
      ..writeln(_center('System developed by', cols))
      ..writeln(_center(PrintService.developerName, cols))
      ..writeln(_center('Tel: ${PrintService.developerPhone}', cols))
      ..writeln(_center(PrintService.developerEmail, cols));

    await _sendReport(buffer.toString());
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DashboardHeroPanel(
                title: 'Reports & Analytics',
                subtitle: 'Daily and monthly performance with printable summaries',
                icon: Icons.assessment,
                colors: [Color(0xFF4A00E0), Color(0xFF8E2DE2)],
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: PosAppTheme.borderGray),
                ),
                child: const TabBar(
                  tabs: [
                    Tab(text: 'Daily Report'),
                    Tab(text: 'Monthly Report'),
                    Tab(text: 'Profit & Expenses'),
                  ],
                  labelColor: PosAppTheme.primaryGreen,
                  indicatorColor: PosAppTheme.primaryGreen,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: TabBarView(
                  children: [
                    // Daily Report
                    _buildDailyReport(),
                    // Monthly Report
                    _buildMonthlyReport(),
                    // Profit & Expenses
                    _buildProfitReport(),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildDailyReport() => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date Picker
            GroceryCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Date: ${DateFormat('MMM dd, yyyy').format(_selectedDate)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() {
                          _selectedDate = picked;
                        });
                        await _loadReports();
                      }
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('Select Date'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final sales = await _getDailySales();
                      if (!mounted) {
                        return;
                      }
                      await _showSalesDetailDialog(
                          'Daily Sales Details', sales);
                    },
                    icon: const Icon(Icons.visibility),
                    label: const Text('View'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final sales = await _getDailySales();
                      await _printSalesSummary('Daily Sales Report', sales);
                    },
                    icon: const Icon(Icons.print),
                    label: const Text('Print'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Daily Stats
            Consumer<ReportsProvider>(
              builder: (context, reportProvider, child) {
                final report = reportProvider.dailyReport;

                if (report == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                return Column(
                  children: [
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.1,
                      children: [
                        StatCard(
                          icon: Icons.trending_up,
                          label: 'Total Revenue',
                          value:
                              'Rs. ${(report['totalRevenue'] as num).toStringAsFixed(2)}',
                          color: PosAppTheme.successGreen,
                        ),
                        StatCard(
                          icon: Icons.receipt,
                          label: 'Transactions',
                          value:
                              (report['totalTransactions'] as int).toString(),
                          color: PosAppTheme.primaryGreen,
                        ),
                        StatCard(
                          icon: Icons.shopping_bag,
                          label: 'Items Sold',
                          value: (report['totalItemsSold'] as int).toString(),
                          color: PosAppTheme.accentBlue,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Items Breakdown
                    const SectionHeader(title: 'Items Breakdown'),
                    const SizedBox(height: 12),
                    GroceryCard(
                      child: (report['itemsBreakdown']
                                      as Map<dynamic, dynamic>?)
                                  ?.isEmpty ??
                              true
                          ? const Center(child: Text('No sales today'))
                          : Column(
                              children: (report['itemsBreakdown']
                                      as Map<dynamic, dynamic>)
                                  .entries
                                  .map(
                                    (entry) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(child: Text(entry.key)),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: PosAppTheme.primaryGreen
                                                  .withOpacity(0.2),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '${entry.value} units',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: PosAppTheme.primaryGreen,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      );

  Widget _buildMonthlyReport() => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month Picker
            GroceryCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Month: ${DateFormat('MMM yyyy').format(DateTime(_selectedYear, _selectedMonth))}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      // Simple month/year picker
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime(_selectedYear, _selectedMonth),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() {
                          _selectedYear = picked.year;
                          _selectedMonth = picked.month;
                        });
                        await _loadReports();
                      }
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('Select Month'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final sales = await _getMonthlySales();
                      if (!mounted) {
                        return;
                      }
                      await _showSalesDetailDialog(
                        'Monthly Sales Details',
                        sales,
                      );
                    },
                    icon: const Icon(Icons.visibility),
                    label: const Text('View'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final sales = await _getMonthlySales();
                      await _printSalesSummary('Monthly Sales Report', sales);
                    },
                    icon: const Icon(Icons.print),
                    label: const Text('Print'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Monthly Stats
            Consumer<ReportsProvider>(
              builder: (context, reportProvider, child) {
                final report = reportProvider.monthlyReport;

                if (report == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                final totalRevenue = report['totalRevenue'] as double;
                final daysInMonth =
                    DateTime(_selectedYear, _selectedMonth + 1, 0).day;
                final averageRevenue = totalRevenue / daysInMonth;

                return Column(
                  children: [
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.1,
                      children: [
                        StatCard(
                          icon: Icons.trending_up,
                          label: 'Total Revenue',
                          value: 'Rs. ${totalRevenue.toStringAsFixed(2)}',
                          color: PosAppTheme.successGreen,
                        ),
                        StatCard(
                          icon: Icons.trending_up,
                          label: 'Avg. Daily Revenue',
                          value: 'Rs. ${averageRevenue.toStringAsFixed(2)}',
                          color: PosAppTheme.accentBlue,
                        ),
                        StatCard(
                          icon: Icons.receipt,
                          label: 'Total Transactions',
                          value:
                              (report['totalTransactions'] as int).toString(),
                          color: PosAppTheme.primaryGreen,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Best Selling Items
                    const SectionHeader(title: 'Best Selling Items'),
                    const SizedBox(height: 12),
                    GroceryCard(
                      child: Column(
                        children: (report['bestSellingItems']
                                as List<MapEntry<String, int>>)
                            .map(
                              (entry) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(child: Text(entry.key)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: PosAppTheme.successGreen
                                            .withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(
                                          4,
                                        ),
                                      ),
                                      child: Text(
                                        '${entry.value} units',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: PosAppTheme.successGreen,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      );

  Widget _buildProfitReport() => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GroceryCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Profit: ${DateFormat('MMM dd, yyyy').format(_selectedDate)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Refresh',
                        icon: const Icon(Icons.refresh),
                        onPressed: () async {
                          await _loadProfitReport();
                        },
                      ),
                      ElevatedButton.icon(
                        onPressed:
                            _profitReport == null ? null : _printProfitReport,
                        icon: const Icon(Icons.print),
                        label: const Text('Print'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_profitReport == null)
              const Center(child: CircularProgressIndicator())
            else
              Column(
                children: [
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.3,
                    children: [
                      StatCard(
                        icon: Icons.trending_up,
                        label: 'Revenue',
                        value:
                            'Rs. ${(_profitReport!['totalRevenue'] as num).toStringAsFixed(2)}',
                        color: PosAppTheme.successGreen,
                      ),
                      StatCard(
                        icon: Icons.local_shipping_outlined,
                        label: 'COGS',
                        value:
                            'Rs. ${(_profitReport!['totalCogs'] as num).toStringAsFixed(2)}',
                        color: PosAppTheme.accentBlue,
                      ),
                      StatCard(
                        icon: Icons.money_off,
                        label: 'Expenses',
                        value:
                            'Rs. ${(_profitReport!['totalExpenses'] as num).toStringAsFixed(2)}',
                        color: PosAppTheme.warningOrange,
                      ),
                      StatCard(
                        icon: Icons.delete_sweep,
                        label: 'Wastage Loss',
                        value:
                            'Rs. ${(_profitReport!['totalWastage'] as num).toStringAsFixed(2)}',
                        color: PosAppTheme.dangerRed,
                      ),
                      StatCard(
                        icon: Icons.trending_down,
                        label: 'Net Profit',
                        value:
                            'Rs. ${(_profitReport!['netProfit'] as num).toStringAsFixed(2)}',
                        color: (_profitReport!['netProfit'] as num) >= 0
                            ? PosAppTheme.primaryGreen
                            : PosAppTheme.dangerRed,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const SectionHeader(title: 'Expense Breakdown'),
                  const SizedBox(height: 12),
                  GroceryCard(
                    child: (_profitReport!['expenses'] as List).isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('No expenses recorded for this day'),
                            ),
                          )
                        : Column(
                            children: (_profitReport!['expenses'] as List)
                                .cast<Expense>()
                                .map(
                                  (e) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                e.description,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                e.category,
                                                style: const TextStyle(
                                                  color:
                                                      PosAppTheme.textGray,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          'Rs. ${e.amount.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: PosAppTheme.dangerRed,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                ],
              ),
          ],
        ),
      );
}
