import 'dart:async';

import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';

import '../l10n/labels.dart';
import '../models/daily_routine.dart';
import '../models/sale_row.dart';
import '../services/supabase_client.dart';

/// Owner-facing live dashboard — reads the shop's REAL summaries from
/// Supabase (daily_routines + recent sales). No login, no invented numbers.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _ShopData {
  const _ShopData({required this.routines, required this.sales});

  final List<DailyRoutine> routines;
  final List<SaleRow> sales;
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  static const _brandGreen = Color(0xFF00843D);

  bool _sinhala = false;
  DateTime? _fetchedAt;
  Future<_ShopData>? _future;
  Timer? _autoTimer;

  /// How often the dashboard silently refreshes. Each background pull is
  /// ~10 KB, so even left open all day it stays well inside the free-tier
  /// Supabase egress budget.
  static const _autoRefresh = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreLanguage();
    _future = _load();
    _autoTimer = Timer.periodic(_autoRefresh, (_) => _refreshSilent());
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pull fresh data the moment the owner returns to the app, so they never
    // have to tap refresh after coming back to the phone.
    if (state == AppLifecycleState.resumed) {
      _refreshSilent();
    }
  }

  /// Background refresh that only applies when fresh data actually arrives —
  /// a momentary network blip never blanks the dashboard.
  Future<void> _refreshSilent() async {
    try {
      final data = await _load();
      if (mounted) {
        setState(() => _future = Future.value(data));
      }
    } catch (_) {
      // Keep showing the last good data.
    }
  }

  Future<void> _restoreLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool('sinhala') ?? false;
    if (mounted && saved != _sinhala) {
      setState(() => _sinhala = saved);
    }
  }

  Future<_ShopData> _load() async {
    final client = SupabaseClient();
    try {
      final results = await Future.wait([
        client.fetchRoutines(),
        client.fetchRecentSales(),
      ]);
      _fetchedAt = DateTime.now();
      return _ShopData(
        routines: results[0] as List<DailyRoutine>,
        sales: results[1] as List<SaleRow>,
      );
    } finally {
      client.close();
    }
  }

  Future<void> _reload() async {
    final future = _load();
    setState(() => _future = future);
    try {
      await future;
    } catch (_) {
      // The FutureBuilder renders the error view; nothing else to do here.
    }
  }

  void _toggleLanguage() async {
    setState(() => _sinhala = !_sinhala);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sinhala', _sinhala);
  }

  String _money(double v) =>
      'Rs. ${NumberFormat('#,##0.00', 'en_US').format(v)}';

  String _todayKey() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      body: SafeArea(
        child: FutureBuilder<_ShopData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return _loadingView();
            }
            if (snapshot.hasError) {
              return _errorView(snapshot.error!);
            }
            final data = snapshot.data!;
            return _dashboard(data);
          },
        ),
      ),
    );
  }

  // ── Views ────────────────────────────────────────────────────────────────

  Widget _loadingView() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _brandLogo(size: 56, radius: 16),
            const SizedBox(height: 14),
            const CircularProgressIndicator(color: _brandGreen),
            const SizedBox(height: 14),
            Text(tr('loading', sinhala: _sinhala)),
          ],
        ),
      );

  /// The shop's logo in a small white tile — the same treatment the Windows
  /// POS uses in its sidebar.
  Widget _brandLogo({required double size, double radius = 8}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFE8EBEF)),
      ),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(size * 0.08),
      child: Image.asset(
        'assets/images/randil_logo.png',
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Icon(Icons.storefront),
      ),
    );
  }

  Widget _errorView(Object error) {
    final isNetwork = isNetworkError(error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              tr('errorTitle', sinhala: _sinhala),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isNetwork
                  ? tr('errorMsg', sinhala: _sinhala)
                  : '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _brandGreen),
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: Text(tr('retry', sinhala: _sinhala)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashboard(_ShopData data) {
    DailyRoutine? today;
    for (final r in data.routines) {
      if (r.dateKey == _todayKey()) {
        today = r;
        break;
      }
    }
    final hasData = data.routines.isNotEmpty;

    return RefreshIndicator(
      color: _brandGreen,
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 24,
        ),
        children: [
          _header(
            today: today,
            salesCount: today?.salesCount ?? 0,
          ),
          const SizedBox(height: 14),
          if (!hasData)
            _noDataCard()
          else ...[
            _splitRow(today),
            const SizedBox(height: 14),
            _costsCard(today),
            const SizedBox(height: 14),
            if (today != null && today.topProducts.isNotEmpty)
              _topProductsCard(today.topProducts),
            const SizedBox(height: 14),
            _trendCard(data.routines),
            const SizedBox(height: 14),
            _recentBillsCard(data.sales),
          ],
          const SizedBox(height: 16),
          _updatedCaption(),
        ],
      ),
    );
  }

  Widget _updatedCaption() {
    final t = _fetchedAt;
    if (t == null) return const SizedBox.shrink();
    final hm = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    return Center(
      child: Text(
        '${tr('lastUpdated', sinhala: _sinhala)} $hm',
        style: const TextStyle(color: Colors.black38, fontSize: 11),
      ),
    );
  }

  Widget _header({DailyRoutine? today, required int salesCount}) {
    final gross = today?.gross ?? 0;
    final discount = today?.discount ?? 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF00A34E), _brandGreen],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _brandLogo(size: 34, radius: 9),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr('app', sinhala: _sinhala),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tr('today', sinhala: _sinhala),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: _toggleLanguage,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: const Size(48, 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
                child: Text(
                  _sinhala ? 'EN' : 'සිං',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: _reload,
                color: Colors.white,
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            tr('todayIncome', sinhala: _sinhala),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            _money(today?.net ?? 0),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _headerStat(
                label: tr('salesCount', sinhala: _sinhala),
                value: '$salesCount',
              ),
              _headerStat(
                label: tr('gross', sinhala: _sinhala),
                value: _money(gross),
              ),
              _headerStat(
                label: tr('discount', sinhala: _sinhala),
                value: _money(discount),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerStat({required String label, required String value}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _noDataCard() => _card(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.cloud_sync_outlined, size: 44, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              tr('noDataTitle', sinhala: _sinhala),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              tr('noDataMsg', sinhala: _sinhala),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, height: 1.45),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _brandGreen),
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: Text(tr('refresh', sinhala: _sinhala)),
            ),
          ],
        ),
      );

  Widget _splitRow(DailyRoutine? today) {
    final items = [
      (
        tr('cash', sinhala: _sinhala),
        today?.cashAmt ?? 0,
        Icons.payments_outlined,
      ),
      (
        tr('card', sinhala: _sinhala),
        today?.cardAmt ?? 0,
        Icons.credit_card,
      ),
      (
        tr('mixed', sinhala: _sinhala),
        today?.mixedAmt ?? 0,
        Icons.swap_horiz,
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _card(
              padding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(items[i].$3, size: 18, color: _brandGreen),
                  const SizedBox(height: 8),
                  Text(
                    items[i].$2 == 0 ? 'Rs. 0.00' : _money(items[i].$2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[i].$1,
                    style: const TextStyle(color: Colors.black45, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _costsCard(DailyRoutine? today) {
    final rows = [
      (
        tr('refunds', sinhala: _sinhala),
        today?.refundsAmt ?? 0,
        const Color(0xFFD32F2F),
      ),
      (
        tr('expenses', sinhala: _sinhala),
        today?.expensesAmt ?? 0,
        const Color(0xFFF57C00),
      ),
      (
        tr('wastage', sinhala: _sinhala),
        today?.wastageAmt ?? 0,
        const Color(0xFF7B1FA2),
      ),
    ];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              tr('todayCosts', sinhala: _sinhala),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: r.$3,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.$1,
                      style: const TextStyle(color: Colors.black87),
                    ),
                  ),
                  Text(
                    r.$2 == 0 ? 'Rs. 0.00' : _money(r.$2),
                    style: TextStyle(
                      color: r.$3,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _topProductsCard(List<TopProduct> top) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              tr('topProducts', sinhala: _sinhala),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          for (var i = 0; i < top.length && i < 5; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == 0 ? _brandGreen : const Color(0xFFE8F3EE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: i == 0 ? Colors.white : _brandGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      top[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black87),
                    ),
                  ),
                  Text(
                    top[i].qty % 1 == 0
                        ? top[i].qty.toStringAsFixed(0)
                        : top[i].qty.toStringAsFixed(2),
                    style: const TextStyle(
                      color: _brandGreen,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _trendCard(List<DailyRoutine> routines) {
    final days = routines.reversed.take(7).toList();
    final anyValue = days.any((d) => d.net > 0);
    double maxY = 0;
    for (final d in days) {
      if (d.net > maxY) maxY = d.net;
    }
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text(
              tr('trend', sinhala: _sinhala),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          if (!anyValue)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                tr('noDataTitle', sinhala: _sinhala),
                style: const TextStyle(color: Colors.black45),
              ),
            )
          else ...[
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  maxY: maxY * 1.25,
                  alignment: BarChartAlignment.spaceAround,
                  barGroups: [
                    for (var i = 0; i < days.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: days[i].net,
                            color: days[i].net > 0
                                ? _brandGreen
                                : const Color(0xFFCFD8D3),
                            width: 16,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5),
                            ),
                          ),
                        ],
                      ),
                  ],
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= days.length) {
                            return const SizedBox.shrink();
                          }
                          final date = DateTime.tryParse(days[i].dateKey);
                          if (date == null) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              dayShort(date, sinhala: _sinhala),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.black45,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchCallback: (event, response) {
                      final spot = response?.spot;
                      if (event is FlTapUpEvent && spot != null) {
                        final i = spot.touchedBarGroupIndex;
                        if (i >= 0 && i < days.length) {
                          _showDaySheet(days[i]);
                        }
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _weekStrip(days),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// Compact 7-day totals computed on the phone from the routine rows it
  /// already downloaded — zero extra egress.
  Widget _weekStrip(List<DailyRoutine> days) {
    var net = 0.0;
    var sales = 0;
    for (final d in days) {
      net += d.net;
      sales += d.salesCount;
    }
    final avg = days.isEmpty ? 0.0 : net / days.length;
    final cells = [
      (tr('weekTotal', sinhala: _sinhala), _money(net)),
      (tr('salesCount', sinhala: _sinhala), '$sales'),
      (tr('perDay', sinhala: _sinhala), _money(avg)),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7F4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0EBE5)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: _VDivider(),
              ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    cells[i].$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cells[i].$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black45,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Full breakdown for one day, opened by tapping a bar in the trend chart.
  void _showDaySheet(DailyRoutine d) {
    final parsed = DateTime.tryParse(d.dateKey);
    final title = parsed == null
        ? d.dateKey
        : DateFormat(
            _sinhala ? 'd MMMM yyyy' : 'EEE, d MMM yyyy',
            _sinhala ? 'si' : 'en_US',
          ).format(parsed);
    final showCosts =
        d.refundsAmt != 0 || d.expensesAmt != 0 || d.wastageAmt != 0;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('dayDetail', sinhala: _sinhala),
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (d.salesCount == 0) ...[
                const SizedBox(height: 10),
                Text(
                  tr('noSales', sinhala: _sinhala),
                  style: const TextStyle(color: Colors.black45),
                ),
              ],
              const SizedBox(height: 14),
              _detailRow(
                tr('salesCount', sinhala: _sinhala),
                '${d.salesCount}',
                bold: true,
              ),
              _detailRow(tr('gross', sinhala: _sinhala), _money(d.gross)),
              _detailRow(tr('discount', sinhala: _sinhala), _money(d.discount)),
              _detailRow(
                tr('net', sinhala: _sinhala),
                _money(d.net),
                bold: true,
                accent: true,
              ),
              _detailRow(tr('cash', sinhala: _sinhala), _money(d.cashAmt)),
              _detailRow(tr('card', sinhala: _sinhala), _money(d.cardAmt)),
              _detailRow(tr('mixed', sinhala: _sinhala), _money(d.mixedAmt)),
              if (showCosts) ...[
                _detailRow(
                  tr('refunds', sinhala: _sinhala),
                  _money(d.refundsAmt),
                  red: true,
                ),
                _detailRow(
                  tr('expenses', sinhala: _sinhala),
                  _money(d.expensesAmt),
                  red: true,
                ),
                _detailRow(
                  tr('wastage', sinhala: _sinhala),
                  _money(d.wastageAmt),
                  red: true,
                ),
              ],
              if (d.grnCount > 0)
                _detailRow(
                  '${tr('grns', sinhala: _sinhala)} ($d.grnCount)',
                  _money(d.grnValue),
                ),
              if (d.topProducts.isNotEmpty) ...[
                const Divider(height: 24),
                Text(
                  tr('topProducts', sinhala: _sinhala),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                for (var i = 0; i < d.topProducts.length && i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            d.topProducts[i].name,
                            style: const TextStyle(color: Colors.black87),
                          ),
                        ),
                        Text(
                          d.topProducts[i].qty % 1 == 0
                              ? d.topProducts[i].qty.toStringAsFixed(0)
                              : d.topProducts[i].qty.toStringAsFixed(2),
                          style: const TextStyle(
                            color: _brandGreen,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value, {
    bool bold = false,
    bool accent = false,
    bool red = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.black54)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: red
                  ? const Color(0xFFD32F2F)
                  : accent
                      ? _brandGreen
                      : Colors.black87,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentBillsCard(List<SaleRow> sales) {
    final shown = sales.take(15).toList();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              tr('recentBills', sinhala: _sinhala),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                tr('noBills', sinhala: _sinhala),
                style: const TextStyle(color: Colors.black45),
              ),
            )
          else
            for (final s in shown)
              InkWell(
                onTap: () => _showBillSheet(s),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long, size: 20, color: _brandGreen),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.billNumber.isEmpty ? s.id : '#${s.billNumber}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              _billTime(s),
                              style: const TextStyle(
                                color: Colors.black45,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _money(s.amount),
                        style: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: Colors.black26,
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _billTime(SaleRow s) {
    final t = s.timestamp;
    if (t == null) return s.paymentMethod;
    final local = t.toLocal();
    final hm = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    final hh = '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}';
    return '$hh $hm · ${s.paymentMethod}';
  }

  String _n(double v) => NumberFormat('#,##0.00', 'en_US').format(v);

  /// Itemised view of one bill (items + cashier). The per-line JSON is only
  /// fetched when this sheet opens, keeping the recent-bills refresh light.
  void _showBillSheet(SaleRow s) {
    final client = SupabaseClient();
    final detail = client.fetchSaleDetail(s.id).whenComplete(client.close);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: FutureBuilder<Map<String, dynamic>?>(
            future: detail,
            builder: (context, snapshot) {
              final detailRow = snapshot.data;
              final cashier =
                  detailRow == null ? '' : '${detailRow['cashier'] ?? ''}'.trim();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('billDetail', sinhala: _sinhala),
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.billNumber.isEmpty ? s.id : '#${s.billNumber}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        _money(s.amount),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _brandGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _billTime(s),
                    style: const TextStyle(color: Colors.black45, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${s.itemsCount} ${tr('products', sinhala: _sinhala)}',
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: CircularProgressIndicator(color: _brandGreen),
                      ),
                    )
                  else if (snapshot.hasError)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        tr('errorMsg', sinhala: _sinhala),
                        style: const TextStyle(
                          color: Colors.black45,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else ...[
                    if (cashier.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _detailRow(
                        tr('cashier', sinhala: _sinhala),
                        cashier,
                      ),
                    ],
                    const Divider(height: 24),
                    ..._billItemRows(detailRow),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _billItemRows(Map<String, dynamic>? row) {
    final items = row == null
        ? const <SaleItem>[]
        : decodeItems('${row['items_json'] ?? ''}');
    if (items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            tr('noItems', sinhala: _sinhala),
            style: const TextStyle(color: Colors.black45, fontSize: 12),
          ),
        ),
      ];
    }
    return [
      for (final it in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  it.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '${it.qty % 1 == 0 ? it.qty.toStringAsFixed(0) : it.qty.toStringAsFixed(2)} × ${_n(it.price)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ),
              SizedBox(
                width: 86,
                child: Text(
                  _money(it.lineTotal),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EBEF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Thin vertical divider used inside the week-totals strip of the trend card.
class _VDivider extends StatelessWidget {
  const _VDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 26, color: const Color(0xFFDDE7E1));
}