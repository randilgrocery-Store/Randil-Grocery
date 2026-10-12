import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../data/database/database_service.dart';
import '../../../data/models/expense.dart';
import '../../../data/models/product_batch.dart';
import '../../../data/models/reload_card.dart';
import '../../../data/models/wastage.dart';
import '../../../data/services/print_service.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/custom_widgets.dart';

/// Printable history reports: expired items, reload cards, wastage and
/// expenses, each scoped to a single day or a whole month like the main
/// reports. Loads straight from the local database and prints to the shop's
/// configured thermal printer.
class HistoryReportsPanel extends StatefulWidget {
  const HistoryReportsPanel({super.key});

  @override
  State<HistoryReportsPanel> createState() => _HistoryReportsPanelState();
}

class _HistoryReportsPanelState extends State<HistoryReportsPanel> {
  final DatabaseService _db = DatabaseService();

  bool _monthly = false;
  DateTime _date = DateTime.now();

  Map<String, dynamic>? _wastageReport;
  List<Expense> _expenses = const [];
  List<ReloadCard> _reloads = const [];
  List<(ProductBatch, String)> _expiryRows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) get _range {
    if (_monthly) {
      final start = DateTime(_date.year, _date.month, 1);
      final end = (_date.month == 12)
          ? DateTime(_date.year + 1, 1, 1)
          : DateTime(_date.year, _date.month + 1, 1);
      return (start, end);
    }
    final start = DateTime(_date.year, _date.month, _date.day);
    return (start, start.add(const Duration(days: 1)));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final range = _range;
    try {
      final results = await Future.wait([
        _db.getWastageReport(range.$1, range.$2),
        _db.getExpensesByDateRange(range.$1, range.$2),
        _db.getAllReloadCards(),
        _db.getExpiryOverview(),
      ]);
      if (!mounted) return;
      setState(() {
        _wastageReport = results[0] as Map<String, dynamic>;
        _expenses = (results[1] as List).cast<Expense>();
        _reloads = (results[2] as List).cast<ReloadCard>();
        _expiryRows = (results[3] as List)
            .cast<(ProductBatch, String)>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  static DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  static int daysLeft(DateTime expiry) =>
      _dayStart(expiry).difference(_dayStart(DateTime.now())).inDays;

  List<(ProductBatch, String)> get _expiringRows => _expiryRows
      .where((row) {
        final expiry = row.$1.expiryDate;
        if (expiry == null) return false;
        final days = daysLeft(expiry);
        return days <= 30;
      })
      .toList();

  List<ReloadCard> get _reloadsInRange {
    final range = _range;
    return _reloads.where((c) {
      final stamp = c.usedAt ?? c.createdAt;
      return !stamp.isBefore(range.$1) && stamp.isBefore(range.$2);
    }).toList();
  }

  // ------------------------------------------------------------------------
  // Printing
  // ------------------------------------------------------------------------

  Future<void> _send(String text) async {
    final settings = context.read<SettingsProvider>().settings;
    final printService = PrintService();
    final printers = printService.listPrinters();
    final printerName =
        printService.selectPrinter(printers, settings.printerName);
    if (!mounted) return;
    if (printerName.isEmpty) {
      showTopSnackBar(
        context,
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
    if (!mounted) return;
    showTopSnackBar(
      context,
      SnackBar(
        content: Text(ok
            ? 'Report printed successfully'
            : 'Print failed: ${printService.lastPrintError ?? 'Unknown error'}'),
        backgroundColor: ok ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F),
      ),
    );
  }

  int get _cols {
    final settings = context.read<SettingsProvider>().settings;
    return settings.paperWidth >= 72 ? 48 : 32;
  }

  String _center(String text) {
    final cols = _cols;
    if (text.length >= cols) return text.substring(0, cols);
    final pad = ((cols - text.length) / 2).ceil();
    return '${' ' * pad}$text';
  }

  String _pair(String label, String value) {
    final cols = _cols;
    final avail = cols - value.length;
    if (avail <= 0) {
      return value.length > cols ? value.substring(0, cols) : value;
    }
    final lbl = label.length > avail ? label.substring(0, avail) : label;
    return lbl.padRight(avail) + value;
  }

  String _rule() => '=' * _cols;

  String _dash() => '-' * _cols;

  String _header(String title, String period) {
    final settings = context.read<SettingsProvider>().settings;
    final text = StringBuffer()
      ..writeln(_center(settings.shopName.toUpperCase()))
      ..writeln(_center(settings.address))
      ..writeln(_center('Tel: ${settings.phone}'))
      ..writeln(_rule())
      ..writeln(_center(title))
      ..writeln(_center(period));
    return text.toString();
  }

  String _footer() {
    final text = StringBuffer()
      ..writeln(_rule())
      ..writeln(_center('End of Report'))
      ..writeln('')
      ..writeln(_center('System developed by'))
      ..writeln(_center(PrintService.developerName))
      ..writeln(_center('Tel: ${PrintService.developerPhone}'))
      ..writeln(_center(PrintService.developerEmail));
    return text.toString();
  }

  String get _periodLabel {
    if (_monthly) {
      return DateFormat('MMM yyyy').format(DateTime(_date.year, _date.month));
    }
    return DateFormat('yyyy-MM-dd').format(_date);
  }

  void _printExpired() async {
    final rows = _expiringRows;
    final buffer = StringBuffer(_header('EXPIRED ITEMS REPORT',
        'As of ${DateFormat('yyyy-MM-dd').format(DateTime.now())}'))
      ..writeln(_pair('Items', '${rows.length}'));
    var units = 0.0;
    for (final row in rows) {
      units += row.$1.quantity;
      final expiry = row.$1.expiryDate!;
      final days = daysLeft(expiry);
      final daysLabel = days < 0 ? 'expired' : days == 0 ? 'today' : '$days d';
      buffer
        ..writeln(_dash())
        ..writeln('${row.$2}  [${row.$1.batchNumber}]')
        ..writeln(_pair(
          '  ${DateFormat('yyyy-MM-dd').format(expiry)} ($daysLabel)',
          '${fmtQty(row.$1.quantity)} u',
        ));
    }
    buffer
      ..writeln(_rule())
      ..writeln(_pair('Total units', fmtQty(units)))
      ..writeln(_footer());
    await _send(buffer.toString());
  }

  void _printReloads() async {
    final rows = _reloadsInRange;
    final settings = context.read<SettingsProvider>().settings;
    final symbol = settings.currencySymbol;
    final buffer = StringBuffer(_header('RELOAD HISTORY', _periodLabel));
    var soldValue = 0.0;
    var profit = 0.0;
    var sold = 0;
    var bought = 0;
    for (final c in rows) {
      final stamp = c.usedAt ?? c.createdAt;
      final date = DateFormat('yyyy-MM-dd HH:mm').format(stamp);
      if (c.status.toLowerCase() == 'sold') {
        sold++;
        soldValue += c.value;
        profit += c.value - c.cost;
      } else {
        bought++;
      }
      buffer
        ..writeln(_dash())
        ..writeln(_pair(date, c.status.toUpperCase()))
        ..writeln(_pair('${c.cardNumber} (${c.supplier})',
            '$symbol ${c.value.toStringAsFixed(2)}'))
        ..writeln('  ${(c.customerName ?? '').isNotEmpty ? c.customerName : ''}');
    }
    buffer
      ..writeln(_rule())
      ..writeln(_pair('Bought', '$bought'))
      ..writeln(_pair('Sold', '$sold'))
      ..writeln(_pair('Value sold', '$symbol ${soldValue.toStringAsFixed(2)}'))
      ..writeln(_pair('Profit', '$symbol ${profit.toStringAsFixed(2)}'))
      ..writeln(_footer());
    await _send(buffer.toString());
  }

  void _printWastage() async {
    final report = _wastageReport;
    if (report == null) return;
    final wastages = (report['wastages'] as List).cast<Wastage>();
    final settings = context.read<SettingsProvider>().settings;
    final symbol = settings.currencySymbol;
    // Break-bulk stock lives in boxes; show loose losses as pieces on the
    // printed sheet instead of decimals like "0.3 u".
    final products = await _db.getAllProducts();
    final productById = {for (final p in products) p.id: p};
    final buffer = StringBuffer(_header('WASTAGE REPORT', _periodLabel));
    for (final w in wastages) {
      final product = productById[w.productId];
      final qtyLabel = product != null && product.isBreakBulk
          ? product.stockLabel(w.quantity)
          : '${fmtQty(w.quantity)} u';
      buffer
        ..writeln(_dash())
        ..writeln(_pair(
            '${DateFormat('yyyy-MM-dd').format(w.wastageDate)} ${w.productName}',
            qtyLabel))
        ..writeln(_pair('  ${w.reason}', '$symbol ${w.lossValue.toStringAsFixed(2)}'));
    }
    buffer
      ..writeln(_rule())
      ..writeln(_pair('Total units', fmtQty(report['totalUnits'] as num)))
      ..writeln(_pair('Total loss',
          '$symbol ${(report['totalLoss'] as num).toStringAsFixed(2)}'))
      ..writeln(_footer());
    await _send(buffer.toString());
  }

  void _printExpenses() async {
    final settings = context.read<SettingsProvider>().settings;
    final symbol = settings.currencySymbol;
    final buffer = StringBuffer(_header('EXPENSE REPORT', _periodLabel));
    var total = 0.0;
    for (final e in _expenses) {
      total += e.amount;
      buffer
        ..writeln(_dash())
        ..writeln(
            '${DateFormat('yyyy-MM-dd HH:mm').format(e.expenseDate)} '
            '${e.description}')
        ..writeln(_pair('  ${e.category}', '$symbol ${e.amount.toStringAsFixed(2)}'));
    }
    buffer
      ..writeln(_rule())
      ..writeln(_pair('Total expenses',
          '$symbol ${total.toStringAsFixed(2)}'))
      ..writeln(_footer());
    await _send(buffer.toString());
  }

  // ------------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GroceryCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _monthly
                      ? 'Month: ${DateFormat('MMM yyyy').format(DateTime(_date.year, _date.month))}'
                      : 'Date: ${DateFormat('MMM dd, yyyy').format(_date)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Daily')),
                        ButtonSegment(value: true, label: Text('Monthly')),
                      ],
                      selected: {_monthly},
                      onSelectionChanged: (value) {
                        setState(() => _monthly = value.first);
                        _load();
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Choose date / month',
                      icon: const Icon(Icons.calendar_today),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() => _date = picked);
                          _load();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            _reportCard(
              icon: Icons.event_busy,
              color: PosAppTheme.dangerRed,
              title: 'Expired Items',
              subtitle:
                  '${_expiringRows.length} items expired or due within 30 days '
                  '(${fmtQty(_expiringRows.fold<double>(0, (a, r) => a + r.$1.quantity))} units)',
              onPrint: _printExpired,
              preview: _expiringRows.take(6).map(
                (r) => '${r.$2} [${r.$1.batchNumber}] '
                    '${DateFormat('yyyy-MM-dd').format(r.$1.expiryDate!)} '
                    '— ${fmtQty(r.$1.quantity)} u',
              ),
            ),
            _reportCard(
              icon: Icons.sim_card_outlined,
              color: PosAppTheme.primaryGreen,
              title: 'Reload History',
              subtitle:
                  '${_reloadsInRange.length} events in period',
              onPrint: _printReloads,
              preview: _reloadsInRange.take(6).map(
                (c) => '${DateFormat('yyyy-MM-dd').format(c.usedAt ?? c.createdAt)} '
                    '${c.cardNumber} — Rs. ${c.value.toStringAsFixed(2)} (${c.status})',
              ),
            ),
            _reportCard(
              icon: Icons.delete_sweep,
              color: PosAppTheme.warningOrange,
              title: 'Wastage',
              subtitle:
                  '$wastageCount records '
                  '· ${fmtQty(totalWastageUnits)} units '
                  '· Rs. ${totalWastageLoss.toStringAsFixed(2)} loss',
              onPrint: _printWastage,
              preview: wastagePreview,
            ),
            _reportCard(
              icon: Icons.money_off,
              color: PosAppTheme.accentBlue,
              title: 'Expenses',
              subtitle:
                  '${_expenses.length} records '
                  '· Rs. ${_expenses.fold<double>(0, (a, e) => a + e.amount).toStringAsFixed(2)} total',
              onPrint: _printExpenses,
              preview: _expenses.take(6).map(
                (e) =>
                    '${DateFormat('yyyy-MM-dd').format(e.expenseDate)} '
                    '${e.description} — Rs. ${e.amount.toStringAsFixed(2)}',
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Helpers referenced above keep the build method readable.
  Map<String, dynamic>? get report => _wastageReport;
  int get wastageCount =>
      ((report?['wastages'] as List?) ?? const []).length;
  double get totalWastageUnits =>
      ((report?['totalUnits'] as num?) ?? 0).toDouble();
  double get totalWastageLoss =>
      ((report?['totalLoss'] as num?) ?? 0).toDouble();
  Iterable<String> get wastagePreview => ((report?['wastages'] as List?) ?? const [])
      .cast<dynamic>()
      .take(6)
      .map((w) {
        final ww = w as Wastage;
        return '${DateFormat('yyyy-MM-dd').format(ww.wastageDate)} '
            '${ww.productName} — ${fmtQty(ww.quantity)} u '
            '(Rs. ${ww.lossValue.toStringAsFixed(2)})';
      });

  Widget _reportCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onPrint,
    required Iterable<String> preview,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GroceryCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: PosAppTheme.textGray,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: onPrint,
                  icon: const Icon(Icons.print, size: 18),
                  label: const Text('Print'),
                ),
              ],
            ),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 6),
              for (final line in preview.take(4))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: PosAppTheme.textGray,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}