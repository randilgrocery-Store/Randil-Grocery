import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/sale.dart';
import '../../components/app_card.dart';
import '../../components/app_data_table.dart';
import '../../components/app_states.dart';
import '../../components/kpi_card.dart';
import '../../components/section_header.dart';
import '../../components/skeleton_loader.dart';
import '../../components/status_badge.dart';
import '../../providers/dashboard_range_controller.dart';
import '../../providers/product_provider.dart';
import '../../providers/profit_loss_provider.dart';
import '../../providers/reload_card_provider.dart';
import '../../providers/repack_provider.dart';
import '../../providers/reports_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/wastage_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_money.dart';
import '../../theme/app_tokens.dart';
import '../../theme/app_typography.dart';
import '../../widgets/live_clock.dart';
import '../../widgets/profit_loss_panel.dart';

/// The admin dashboard.
///
/// Everything on this screen is computed from real data:
///   * sales for the selected + previous period (`ReportsProvider`),
///   * one business-wide Profit & Loss calculation pumped through two
///     [ProfitLossProvider] instances (current + previous period),
///   * the stock-health view on [ProductProvider.reorderCandidates].
///
/// The range selector drives a single [DashboardRangeController] that every
/// date boundary on the page reads, so "vs previous period" always compares
/// like against like.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.onNavigateToPos,
    this.onNavigateToRefunds,
    this.onNavigateToInventory,
    this.onNavigateToReports,
    this.onNavigateToSettings,
  });

  final VoidCallback? onNavigateToPos;
  final VoidCallback? onNavigateToRefunds;
  final VoidCallback? onNavigateToInventory;
  final VoidCallback? onNavigateToReports;
  final VoidCallback? onNavigateToSettings;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------

  final DashboardRangeController _range = DashboardRangeController();

  /// Business-wide P&L for the selected period. This instance is injected into
  /// the widget tree (ChangeNotifierProvider.value) so the existing
  /// [ProfitLossPanel] and the net-profit KPI both read it.
  final ProfitLossProvider _currentPl = ProfitLossProvider();

  /// The period before the selected one — a SECOND provider instance because
  /// [ProfitLossProvider] is a single-buffer provider.
  final ProfitLossProvider _prevPl = ProfitLossProvider();

  late Future<List<Sale>> _salesFuture;
  late Future<List<Sale>> _prevSalesFuture;
  DateTime _lastRefreshed = DateTime.now();
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _configureMoney();
    _salesFuture = _loadSales();
    _prevSalesFuture = _loadPreviousSales();
    // The P&L instances are not in the widget's ancestor tree (they're
    // injected BELOW via ChangeNotifierProvider.value for ProfitLossPanel), so
    // the KPI row listens to them directly instead of using context.watch.
    _currentPl.addListener(_onPlChanged);
    _prevPl.addListener(_onPlChanged);
    unawaited(_refresh(silent: true));
  }

  @override
  void dispose() {
    _range.dispose();
    _currentPl.removeListener(_onPlChanged);
    _currentPl.dispose();
    _prevPl.removeListener(_onPlChanged);
    _prevPl.dispose();
    super.dispose();
  }

  void _onPlChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// The dashboard renders money though [AppMoney]; the prefix is derived from
  /// the shop settings, which the shell loads before this screen mounts.
  void _configureMoney() {
    final settings = context.read<SettingsProvider>().settings;
    AppMoney.configure(currencySymbol: settings.currencySymbol);
  }

  // -------------------------------------------------------------------------
  // Data loading
  // -------------------------------------------------------------------------

  Future<List<Sale>> _loadSales() {
    final reports = context.read<ReportsProvider>();
    final now = DateTime.now();
    return reports.getSalesByDateRange(
      _range.rangeStart(now),
      _range.rangeEnd(now),
    );
  }

  Future<List<Sale>> _loadPreviousSales() {
    final reports = context.read<ReportsProvider>();
    final now = DateTime.now();
    return reports.getSalesByDateRange(
      _range.previousPeriodStart(now),
      _range.previousPeriodEnd(now),
    );
  }

  /// Reloads products, the daily/monthly reports and BOTH Profit & Loss
  /// buffers, then re-points the sales futures.
  ///
  /// [silent] (the LiveClock minute hook and the initial load) skips the
  /// visible spinner so the page only flashes when the user asked for it.
  Future<void> _refresh({bool silent = false}) async {
    if (_refreshing) {
      return;
    }
    if (!silent) {
      setState(() => _refreshing = true);
    }
    try {
      final now = DateTime.now();
      await context.read<ProductProvider>().loadProducts();
      // Operations overview (all-time reload ledger, production & wastage).
      unawaited(context.read<ReloadCardProvider>().loadCards());
      unawaited(context.read<RepackProvider>().loadAll());
      unawaited(context.read<WastageProvider>().loadWastages());
      final reports = context.read<ReportsProvider>();
      await reports.generateDailyReport(now);
      await reports.generateMonthlyReport(now.year, now.month);
      await _currentPl.refresh(_range.rangeStart(now), _range.rangeEnd(now));
      await _prevPl.refresh(
        _range.previousPeriodStart(now),
        _range.previousPeriodEnd(now),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _lastRefreshed = DateTime.now();
        _salesFuture = _loadSales();
        _prevSalesFuture = _loadPreviousSales();
      });
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _onRangeChanged() {
    final now = DateTime.now();
    setState(() {
      _salesFuture = _loadSales();
      _prevSalesFuture = _loadPreviousSales();
    });
    unawaited(_currentPl.load(_range.rangeStart(now), _range.rangeEnd(now)));
    unawaited(_prevPl.load(
      _range.previousPeriodStart(now),
      _range.previousPeriodEnd(now),
    ));
    return Future.value();
  }

  void _selectRange(DashboardRange range) {
    if (_range.selected == range && !_range.isCustom) {
      return;
    }
    _range.select(range);
    unawaited(_onRangeChanged());
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3, now.month, now.day),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: today.subtract(const Duration(days: 6)),
        end: today,
      ),
      helpText: 'Pick a sales range',
      saveText: 'Apply',
    );
    if (picked == null || !mounted) {
      return;
    }
    _range.selectCustom(picked.start, picked.end);
    unawaited(_onRangeChanged());
  }

  // -------------------------------------------------------------------------
  // Small derivations
  // -------------------------------------------------------------------------

  ({double revenue, double transactions, double items}) _tally(
      List<Sale> sales) {
    var revenue = 0.0;
    var transactions = 0.0;
    var items = 0.0;
    for (final s in sales) {
      revenue += s.totalAmount;
      transactions += 1;
      for (final item in s.items) {
        items += item.quantity;
      }
    }
    return (revenue: revenue, transactions: transactions, items: items);
  }

  /// Index of a sale's day inside a window of [days] starting at midnight on
  /// [windowStart], or null when the sale falls outside it.
  int? _dayIndex(DateTime saleDate, DateTime windowStart, int days) {
    final s = DateTime(saleDate.year, saleDate.month, saleDate.day);
    final diff = s.difference(windowStart).inDays;
    return (diff < 0 || diff >= days) ? null : diff;
  }

  /// Daily revenue totals across the selected period (for KPI sparklines).
  List<double> _dailyTotals(List<Sale> sales) {
    final now = DateTime.now();
    final start = _range.rangeStart(now);
    final days = _range.rangeEnd(now).difference(start).inDays + 1;
    final out = List<double>.filled(days, 0);
    for (final s in sales) {
      final idx = _dayIndex(s.saleDate, start, days);
      if (idx != null) {
        out[idx] += s.totalAmount;
      }
    }
    return out;
  }

  String _greeting(int hour) {
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }

  String _timeOf(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Payment label derived from the amounts actually stored on the bill
  /// (split payments are stored as `Cash + Card`), falling back to the stored
  /// method text.
  String _paymentLabel(Sale s) {
    if (s.isSplitPayment) return 'Cash + Card';
    final method = s.paymentMethod.toLowerCase();
    if (method.contains('card')) return 'Card';
    if (method.contains('cash')) return 'Cash';
    return s.paymentMethod.isEmpty ? 'Cash' : s.paymentMethod;
  }

  // -------------------------------------------------------------------------
  // Layout helpers
  // -------------------------------------------------------------------------

  Widget _rowOrStack(List<Widget> children,
      {double minRowWidth = AppBreakpoints.minSupportedWidth}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= minRowWidth) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _withGaps(children),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _withGaps(children),
        );
      },
    );
  }

  List<Widget> _withGaps(List<Widget> children) {
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        out.add(const SizedBox(
          width: AppSpacing.gutter,
          height: AppSpacing.gutter,
        ));
      }
      out.add(children[i]);
    }
    return out;
  }

  Widget _salesPane({
    required Future<List<Sale>> future,
    required Widget Function(BuildContext, List<Sale>) builder,
    double skeletonHeight = 180,
  }) {
    return FutureBuilder<List<Sale>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SkeletonBox(height: skeletonHeight);
        }
        if (snapshot.hasError) {
          return AppErrorState(
            message: 'Could not load sales for this range. Try again.',
            onRetry: () => setState(() {
              _salesFuture = _loadSales();
              _prevSalesFuture = _loadPreviousSales();
            }),
          );
        }
        return builder(context, snapshot.data ?? const <Sale>[]);
      },
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ProfitLossProvider>.value(
      value: _currentPl,
      child: ColoredBox(
        color: context.appColors.canvas,
        child: RefreshIndicator(
          onRefresh: () => _refresh(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: AppSpacing.md),
                _buildToolbar(),
                const SizedBox(height: AppSpacing.md),
                _buildKpiRow(),
                const SizedBox(height: AppSpacing.md),
                _buildChartRow(),
                const SizedBox(height: AppSpacing.md),
                _buildRowThree(),
                const SizedBox(height: AppSpacing.md),
                _buildRowFour(),
                const SizedBox(height: AppSpacing.md),
                _buildOperationsRow(),
                const SizedBox(height: AppSpacing.md),
                _buildQuickActions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final t = context.typography;
    final settings = context.watch<SettingsProvider>().settings;
    final now = DateTime.now();
    final shopName = settings.shopName.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Good ${_greeting(now.hour)}', style: t.h2),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                shopName.isEmpty ? 'Randil Grocery POS' : shopName,
                style: t.body,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        LiveClock(
          onMinute: () => unawaited(_refresh(silent: true)),
          lastUpdated: _lastRefreshed,
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    final colors = context.appColors;
    final t = context.typography;
    final selected = _range.selected;
    final isCustom = _range.isCustom;

    Widget chip(DashboardRange range, String label, VoidCallback onTap) {
      final active = selected == range;
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.base,
          curve: AppMotion.enter,
          height: AppSizes.minTapTarget - 6,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? colors.primary : colors.surface,
            borderRadius: AppRadius.pillRadius,
            border: Border.all(
              color: active ? colors.primary : colors.border,
            ),
          ),
          child: Text(
            label,
            style: t.label.copyWith(
              color: active ? colors.onPrimary : colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(DashboardRange.today, 'Today', () => _selectRange(DashboardRange.today)),
        const SizedBox(width: AppSpacing.xs),
        chip(DashboardRange.last7Days, '7D', () => _selectRange(DashboardRange.last7Days)),
        const SizedBox(width: AppSpacing.xs),
        chip(DashboardRange.last30Days, '30D', () => _selectRange(DashboardRange.last30Days)),
        const SizedBox(width: AppSpacing.xs),
        chip(DashboardRange.custom, isCustom ? 'Custom' : 'Custom…', _pickCustomRange),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            isCustom
                ? '${_range.fullLabel} · ${_dateShort(_range.customStart)} – '
                    '${_dateShort(_range.customEnd)}'
                : _range.fullLabel,
            style: t.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: _refreshing ? null : () => unawaited(_refresh()),
          icon: _refreshing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.refresh, size: 18),
          label: const Text('Refresh'),
        ),
      ],
    );
  }

  String _dateShort(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  // -------------------------------------------------------------------------
  // Row 1 — KPI
  // -------------------------------------------------------------------------

  Widget _buildKpiRow() {
    final t = context.typography;

    return FutureBuilder<List<Sale>>(
      future: _prevSalesFuture,
      builder: (context, prevSnap) {
        final prev = _tally(prevSnap.data ?? const <Sale>[]);

        return FutureBuilder<List<Sale>>(
          future: _salesFuture,
          builder: (context, currSnap) {
            if (currSnap.connectionState == ConnectionState.waiting) {
              return const SkeletonBox(height: 128);
            }
            final sales = currSnap.data ?? const <Sale>[];
            final current = _tally(sales);

            final netProfit = _currentPl.d('netProfit');
            final grossMarginPct = _currentPl.d('grossMarginPct');
            final netTrend = AppMoney.trend(
              current: netProfit,
              previous: _prevPl.d('netProfit'),
            );

            final cards = <Widget>[
              KpiCard(
                label: 'Revenue',
                value: AppMoney.format(current.revenue),
                icon: Icons.payments_outlined,
                tone: StatusTone.primary,
                trend: AppMoney.trend(
                  current: current.revenue,
                  previous: prev.revenue,
                ),
                trendCaption: 'vs previous period',
                secondary: Text(
                  '${AppMoney.integer(current.transactions)} bills',
                  style: t.caption,
                ),
                sparkline: _Sparkline(values: _dailyTotals(sales)),
              ),
              KpiCard(
                label: 'Net profit',
                value: AppMoney.format(netProfit),
                icon: Icons.trending_up,
                tone: netProfit >= 0 ? StatusTone.success : StatusTone.danger,
                trend: netTrend,
                trendCaption: 'vs previous period',
                secondary: Text(
                  '${AppMoney.percent(grossMarginPct / 100)} gross margin',
                  style: t.caption,
                ),
              ),
              KpiCard(
                label: 'Bills',
                value: AppMoney.integer(current.transactions),
                icon: Icons.receipt_long_outlined,
                tone: StatusTone.neutral,
                trend: AppMoney.trend(
                  current: current.transactions,
                  previous: prev.transactions,
                ),
                trendCaption: 'vs previous period',
              ),
              KpiCard(
                label: 'Items sold',
                value: AppMoney.integer(current.items),
                icon: Icons.shopping_basket_outlined,
                tone: StatusTone.neutral,
                trend: AppMoney.trend(
                  current: current.items,
                  previous: prev.items,
                ),
                trendCaption: 'vs previous period',
              ),
            ];

            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= AppBreakpoints.kpiRowFits) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < cards.length; i++) ...[
                        if (i > 0)
                          const SizedBox(width: AppSpacing.gutter),
                        Expanded(child: cards[i]),
                      ],
                    ],
                  );
                }
                return Wrap(
                  spacing: AppSpacing.gutter,
                  runSpacing: AppSpacing.gutter,
                  children: [
                    for (final card in cards)
                      SizedBox(
                        width:
                            (constraints.maxWidth - AppSpacing.gutter) / 2,
                        child: card,
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // Row 2 — Revenue trend + Profit & Loss
  // -------------------------------------------------------------------------

  Widget _buildChartRow() {
    return _rowOrStack([
      Expanded(flex: 3, child: _buildRevenueChart()),
      Expanded(flex: 2, child: _buildPlPanel()),
    ]);
  }

  Widget _buildRevenueChart() {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      clipContent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: 'Revenue trend',
            icon: Icons.show_chart,
            dense: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: AppSizes.chartHeight,
            child: _salesPane(
              future: _salesFuture,
              skeletonHeight: AppSizes.chartHeight,
              builder: (context, sales) => _buildLineChart(sales),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineChart(List<Sale> sales) {
    final colors = context.appColors;
    final t = context.typography;

    if (sales.isEmpty) {
      return AppEmptyState(
        icon: Icons.show_chart,
        title: 'No sales in this range',
        message: 'Bills recorded in ${_range.fullLabel} will appear here.',
        compact: true,
      );
    }

    final now = DateTime.now();
    final start = _range.rangeStart(now);
    final days = _range.rangeEnd(now).difference(start).inDays + 1;
    final totals = List<double>.filled(days, 0);
    for (final s in sales) {
      final idx = _dayIndex(s.saleDate, start, days);
      if (idx != null) {
        totals[idx] += s.totalAmount;
      }
    }

    final maxV = totals.reduce((a, b) => a > b ? a : b);
    final maxY = maxV <= 0 ? 100.0 : maxV * 1.15;
    final spots = <FlSpot>[
      for (var i = 0; i < totals.length; i++) FlSpot(i.toDouble(), totals[i]),
    ];
    final step = days > 7 ? (days / 6).ceil() : 1;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (totals.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        clipData: FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: colors.chartGrid, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) => Text(
                AppMoney.axis(value),
                style: t.caption.copyWith(color: colors.chartAxisText),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= days || i % step != 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xxs),
                  child: Text(
                    _dateShort(start.add(Duration(days: i))),
                    style: t.caption.copyWith(color: colors.chartAxisText),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: colors.primary,
            barWidth: 3,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: colors.primary.withValues(alpha: 0.10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlPanel() => ProfitLossPanel(
        rangeLabel: _range.fullLabel,
        isRefreshing: _refreshing,
        onRefresh: () => unawaited(_refresh()),
      );

  // -------------------------------------------------------------------------
  // Row 3 — Top selling · Inventory health · Needs reordering
  // -------------------------------------------------------------------------

  Widget _buildRowThree() {
    return _rowOrStack([
      Expanded(flex: 3, child: _buildTopSelling()),
      Expanded(flex: 2, child: _buildInventoryHealth()),
      Expanded(flex: 3, child: _buildReorderList()),
    ]);
  }

  Widget _buildTopSelling() {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: 'Top selling',
            subtitle: 'By revenue',
            icon: Icons.leaderboard,
          ),
          const SizedBox(height: AppSpacing.xs),
          _salesPane(
            future: _salesFuture,
            skeletonHeight: 220,
            builder: (context, sales) {
              final totals = <String, double>{};
              for (final s in sales) {
                for (final item in s.items) {
                  totals[item.productName] =
                      (totals[item.productName] ?? 0) + item.total;
                }
              }
              final ranked = totals.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              if (ranked.isEmpty) {
                return AppEmptyState(
                  icon: Icons.leaderboard_outlined,
                  title: 'No sales yet',
                  message: 'Sold items will rank here.',
                  compact: true,
                );
              }
              final bars = ranked.take(5).toList();
              final maxV = bars.first.value;
              return Column(
                children: [
                  for (var i = 0; i < bars.length; i++)
                    _topRow(i, bars[i].key, bars[i].value, maxV),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _topRow(int index, String name, double value, double maxV) {
    final colors = context.appColors;
    final t = context.typography;
    final pct = maxV <= 0 ? 0.0 : (value / maxV).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '${index + 1}',
              style: t.numberSm.copyWith(color: colors.textTertiary),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: t.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xxs),
                ClipRRect(
                  borderRadius: AppRadius.pillRadius,
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 5,
                    backgroundColor: colors.surfaceMuted,
                    color: colors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(AppMoney.format(value), style: t.numberSm),
        ],
      ),
    );
  }

  Widget _buildInventoryHealth() {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: 'Inventory health',
            subtitle: 'All products',
            icon: Icons.donut_small,
          ),
          const SizedBox(height: AppSpacing.sm),
          Consumer<ProductProvider>(
            builder: (context, products, _) {
              final colors = context.appColors;
              final t = context.typography;
              final all = products.allProducts;
              final reorder = products.reorderCandidates;
              final out = reorder.where((p) => p.quantity <= 0).length;
              final low = reorder.length - out;
              final normal = all.length - reorder.length;

              if (all.isEmpty) {
                return AppEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No products yet',
                  message: 'Add products, then restock status will appear here.',
                  compact: true,
                );
              }

              final sections = <PieChartSectionData>[
                if (normal > 0)
                  PieChartSectionData(
                    value: normal.toDouble(),
                    color: colors.success,
                    radius: 34,
                  ),
                if (low > 0)
                  PieChartSectionData(
                    value: low.toDouble(),
                    color: colors.warning,
                    radius: 34,
                  ),
                if (out > 0)
                  PieChartSectionData(
                    value: out.toDouble(),
                    color: colors.danger,
                    radius: 34,
                  ),
              ];

              return Column(
                children: [
                  SizedBox(
                    height: 150,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            sections: sections,
                            centerSpaceRadius: 44,
                            sectionsSpace: 2,
                            startDegreeOffset: -90,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${all.length}', style: t.numberLg),
                            Text('products', style: t.caption),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _legendRow(StatusTone.success, 'In stock', normal),
                  const SizedBox(height: AppSpacing.xxs),
                  _legendRow(StatusTone.warning, 'Low stock', low),
                  const SizedBox(height: AppSpacing.xxs),
                  _legendRow(StatusTone.danger, 'Out of stock', out),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _legendRow(StatusTone tone, String label, int count) {
    final t = context.typography;
    return Row(
      children: [
        StatusBadge(label: label, tone: tone, dense: true),
        const Spacer(),
        Text('$count', style: t.numberSm),
      ],
    );
  }

  Widget _buildReorderList() {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Consumer<ProductProvider>(
            builder: (context, products, _) {
              final t = context.typography;
              final reorder = products.reorderCandidates.toList()
                ..sort((a, b) => a.quantity.compareTo(b.quantity));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSectionHeader(
                    title: 'Needs reordering',
                    subtitle: reorder.isEmpty
                        ? 'All good'
                        : '${reorder.length} product${reorder.length == 1 ? '' : 's'} below reorder level',
                    icon: Icons.low_priority,
                    action: reorder.isEmpty
                        ? null
                        : StatusBadge(
                            label: '${reorder.length}',
                            tone: StatusTone.warning,
                            dense: true,
                          ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  if (reorder.isEmpty)
                    AppEmptyState(
                      icon: Icons.check_circle_outline,
                      title: 'Stock looks good',
                      message: 'Every product is above its reorder level.',
                      compact: true,
                    )
                  else ...[
                    for (final p in reorder.take(6))
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                p.name,
                                style: t.bodyStrong,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              '${AppMoney.integer(p.quantity)} left',
                              style: t.caption,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            StatusBadge(
                              label: p.quantity <= 0 ? 'Out' : 'Low',
                              tone: p.quantity <= 0
                                  ? StatusTone.danger
                                  : StatusTone.warning,
                              dense: true,
                            ),
                          ],
                        ),
                      ),
                    if (widget.onNavigateToInventory != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: widget.onNavigateToInventory,
                          icon: const Icon(Icons.inventory_2, size: 18),
                          label: const Text('Open inventory'),
                        ),
                      ),
                    ],
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Row 4 — Recent bills · Payment methods · Cashier leaderboard
  // -------------------------------------------------------------------------

  Widget _buildRowFour() {
    return _rowOrStack([
      Expanded(flex: 2, child: _buildRecentBills()),
      Expanded(
        flex: 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildPaymentMethods()),
            const SizedBox(height: AppSpacing.gutter),
            Expanded(child: _buildCashierLeaderboard()),
          ],
        ),
      ),
    ]);
  }

  Widget _buildRecentBills() {
    return AppCard(
      padding: EdgeInsets.zero,
      clipContent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: AppSectionHeader(
              title: 'Recent bills',
              subtitle: 'Latest transactions',
              icon: Icons.receipt_long_outlined,
              dense: true,
              action: widget.onNavigateToReports == null
                  ? null
                  : TextButton(
                      onPressed: widget.onNavigateToReports,
                      child: const Text('View all'),
                    ),
            ),
          ),
          _salesPane(
            future: _salesFuture,
            skeletonHeight: 320,
            builder: (context, sales) {
              final rows = [...sales]
                ..sort((a, b) => b.saleDate.compareTo(a.saleDate));

              return AppDataTable<Sale>(
                columns: [
                  AppTableColumn(
                    label: 'Invoice',
                    id: 'invoice',
                    builder: (c, s, i) => Text(
                      s.invoiceLabel,
                      style: c.typography.bodyStrong,
                    ),
                  ),
                  AppTableColumn(
                    label: 'Time',
                    id: 'time',
                    builder: (c, s, i) =>
                        Text(_timeOf(s.saleDate), style: c.typography.caption),
                  ),
                  AppTableColumn(
                    label: 'Cashier',
                    id: 'cashier',
                    builder: (c, s, i) => Text(
                      s.cashierName.isEmpty ? '—' : s.cashierName,
                      style: c.typography.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  AppTableColumn(
                    label: 'Items',
                    id: 'items',
                    numeric: true,
                    builder: (c, s, i) => Text(
                      AppMoney.integer(
                          s.items.fold(0.0, (sum, it) => sum + it.quantity)),
                      style: c.typography.numberTable,
                    ),
                  ),
                  AppTableColumn(
                    label: 'Total',
                    id: 'total',
                    numeric: true,
                    builder: (c, s, i) => Text(
                      AppMoney.format(s.totalAmount),
                      style: c.typography.numberTable,
                    ),
                  ),
                  AppTableColumn(
                    label: 'Payment',
                    id: 'payment',
                    builder: (c, s, i) =>
                        StatusBadge(label: _paymentLabel(s), dense: true),
                  ),
                ],
                rows: rows.take(8).toList(),
                sortBy: 'time',
                sortDescending: true,
                striped: true,
                emptyIcon: Icons.receipt_long_outlined,
                emptyTitle: 'No bills yet',
                emptyMessage:
                    'Bills recorded in ${_range.fullLabel} will appear here.',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethods() {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: 'Payment methods',
            icon: Icons.payments_outlined,
            dense: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          _salesPane(
            future: _salesFuture,
            skeletonHeight: 120,
            builder: (context, sales) {
              final colors = context.appColors;
              final t = context.typography;

              var cash = 0.0;
              var card = 0.0;
              var split = 0.0;
              var other = 0.0;
              for (final s in sales) {
                if (s.isSplitPayment) {
                  split += s.totalAmount;
                } else {
                  final m = s.paymentMethod.toLowerCase();
                  if (m.contains('cash')) {
                    cash += s.totalAmount;
                  } else if (m.contains('card')) {
                    card += s.totalAmount;
                  } else {
                    other += s.totalAmount;
                  }
                }
              }
              final total = cash + card + split + other;
              if (total <= 0) {
                return AppEmptyState(
                  icon: Icons.payments_outlined,
                  title: 'No payments yet',
                  message: 'Payments received in ${_range.fullLabel} '
                      'will break down here.',
                  compact: true,
                );
              }

              final segments = <({String label, double amount, double alpha})>[
                if (cash > 0) (label: 'Cash', amount: cash, alpha: 1.0),
                if (card > 0) (label: 'Card', amount: card, alpha: 0.72),
                if (split > 0)
                  (label: 'Cash + Card', amount: split, alpha: 0.5),
                if (other > 0) (label: 'Other', amount: other, alpha: 0.32),
              ];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: AppRadius.pillRadius,
                    child: SizedBox(
                      height: 10,
                      child: Row(
                        children: [
                          for (final seg in segments)
                            Expanded(
                              flex: (seg.amount / total * 1000).round(),
                              child: Container(
                                color: colors.primary
                                    .withValues(alpha: seg.alpha),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final seg in segments)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xxs),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(seg.label, style: t.body),
                          ),
                          Text(
                            AppMoney.percent(seg.amount / total),
                            style: t.numberSm,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(AppMoney.format(seg.amount),
                              style: t.numberSm),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCashierLeaderboard() {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: 'Cashier leaderboard',
            icon: Icons.emoji_events_outlined,
            dense: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          _salesPane(
            future: _salesFuture,
            skeletonHeight: 180,
            builder: (context, sales) {
              final map = <String, _CashierStats>{};
              for (final s in sales) {
                final key = s.cashierName.isEmpty ? 'Cashier' : s.cashierName;
                final stats = map.putIfAbsent(key, () => _CashierStats(key));
                stats.sales += 1;
                stats.revenue += s.totalAmount;
                stats.items += s.items.fold(0.0, (a, b) => a + b.quantity);
              }
              final ranked = map.values.toList()
                ..sort((a, b) => b.revenue.compareTo(a.revenue));
              if (ranked.isEmpty) {
                return AppEmptyState(
                  icon: Icons.emoji_events_outlined,
                  title: 'No sales yet',
                  message: 'Cashiers will rank here by revenue.',
                  compact: true,
                );
              }
              return Column(
                children: [
                  for (var i = 0;
                      i < ranked.take(5).length;
                      i++)
                    _rankRow(i, ranked[i]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _rankRow(int index, _CashierStats stats) {
    final colors = context.appColors;
    final t = context.typography;
    final medal = index < 3
        ? [colors.primary, colors.info, colors.warning][index]
        : colors.textTertiary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: medal.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: t.numberSm.copyWith(color: medal),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stats.name,
                  style: t.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${stats.sales} bills · ${AppMoney.integer(stats.items)} items',
                  style: t.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(AppMoney.compact(stats.revenue), style: t.numberSm),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Quick actions
  // -------------------------------------------------------------------------

  // -------------------------------------------------------------------------
  // Operations overview — Reload · Repack · Wastage (all-time)
  // -------------------------------------------------------------------------

  Widget _buildOperationsRow() {
    return _rowOrStack([
      Expanded(child: _buildReloadPanel()),
      Expanded(child: _buildRepackPanel()),
      Expanded(child: _buildWastagePanel()),
    ]);
  }

  Widget _buildReloadPanel() {
    final reload = context.watch<ReloadCardProvider>();
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: 'Reload credit',
            icon: Icons.sim_card_outlined,
            dense: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          _opsGrid([
            _OpsStat(
              label: 'Bought',
              value: AppMoney.format(reload.totalBoughtValue),
              icon: Icons.add_card,
            ),
            _OpsStat(
              label: 'Sold',
              value: AppMoney.format(reload.totalSoldValue),
              icon: Icons.currency_rupee,
            ),
            _OpsStat(
              label: 'Remaining',
              value: AppMoney.format(reload.remainingValue),
              icon: Icons.account_balance_wallet_outlined,
              tone: reload.remainingValue > 0
                  ? StatusTone.success
                  : StatusTone.neutral,
            ),
            _OpsStat(
              label: 'Profit',
              value: AppMoney.format(reload.totalProfit),
              icon: Icons.trending_up,
              tone: reload.totalProfit > 0
                  ? StatusTone.success
                  : StatusTone.danger,
            ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${reload.boughtCount} buys · ${reload.soldCount} sales to date',
            style: context.typography.caption,
          ),
        ],
      ),
    );
  }

  Widget _buildRepackPanel() {
    final repack = context.watch<RepackProvider>();
    final products = context.watch<ProductProvider>().allProducts;
    final produced = repack.productions
        .fold<double>(0, (s, p) => s + p.quantityProduced);
    final madeCost = repack.productions
        .fold<double>(0, (s, p) => s + p.totalComponentCost);
    final finishedIds = <String>{};
    for (final r in repack.recipes) {
      finishedIds.add(r.finishedProductId);
    }
    final onHand = products
        .where((p) => finishedIds.contains(p.id))
        .fold<double>(0, (s, p) => s + p.quantity);
    final lastRun = repack.productions.isEmpty
        ? null
        : repack.productions
            .map((p) => p.producedAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: 'Repack & production',
            icon: Icons.inventory_2_outlined,
            dense: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          _opsGrid([
            _OpsStat(
              label: 'Packed (all time)',
              value: '${AppMoney.integer(produced)} pcs',
              icon: Icons.widgets_outlined,
            ),
            _OpsStat(
              label: 'On hand now',
              value: _qtyString(onHand),
              icon: Icons.inventory_2,
              tone: onHand > 0 ? StatusTone.success : StatusTone.neutral,
            ),
            _OpsStat(
              label: 'Runs done',
              value: AppMoney.integer(repack.productions.length),
              icon: Icons.factory_outlined,
            ),
            _OpsStat(
              label: 'Made for',
              value: AppMoney.format(madeCost),
              icon: Icons.payments_outlined,
            ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${repack.recipes.length} recipes · last run '
            '${lastRun == null ? '—' : _dateShort(lastRun)}',
            style: context.typography.caption,
          ),
        ],
      ),
    );
  }

  Widget _buildWastagePanel() {
    final wastage = context.watch<WastageProvider>();
    final records = wastage.wastages;
    final qtyLost = records.fold<double>(0, (s, w) => s + w.quantity);
    final valueLost = records.fold<double>(0, (s, w) => s + w.lossValue);
    final lastEntry = records.isEmpty
        ? null
        : records
            .map((w) => w.wastageDate)
            .reduce((a, b) => a.isAfter(b) ? a : b);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: 'Wastage',
            icon: Icons.delete_forever_outlined,
            dense: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          _opsGrid([
            _OpsStat(
              label: 'Records',
              value: AppMoney.integer(records.length),
              icon: Icons.receipt_long,
            ),
            _OpsStat(
              label: 'Qty lost',
              value: _qtyString(qtyLost),
              icon: Icons.scale,
            ),
            _OpsStat(
              label: 'Worth lost',
              value: AppMoney.format(valueLost),
              icon: Icons.money_off,
              tone: valueLost > 0 ? StatusTone.danger : StatusTone.neutral,
            ),
            _OpsStat(
              label: 'Last entry',
              value: lastEntry == null ? '—' : _dateShort(lastEntry),
              icon: Icons.event,
            ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Stock written off as damaged / expired',
            style: context.typography.caption,
          ),
        ],
      ),
    );
  }

  /// 2×2 grid of mini stats for the operations panels.
  Widget _opsGrid(List<_OpsStat> stats) {
    assert(stats.length == 4);
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - AppSpacing.gutter) / 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(width: itemWidth, child: stats[0]),
                const SizedBox(width: AppSpacing.gutter),
                SizedBox(width: itemWidth, child: stats[1]),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                SizedBox(width: itemWidth, child: stats[2]),
                const SizedBox(width: AppSpacing.gutter),
                SizedBox(width: itemWidth, child: stats[3]),
              ],
            ),
          ],
        );
      },
    );
  }

  String _qtyString(double v) {
    if (v == v.roundToDouble()) return AppMoney.integer(v);
    return AppMoney.plain(v);
  }

  Widget _buildQuickActions() {
    final actions = <(IconData, String, VoidCallback?)>[
      (Icons.point_of_sale, 'New sale', widget.onNavigateToPos),
      (Icons.assignment_return, 'Refunds', widget.onNavigateToRefunds),
      (Icons.inventory_2, 'Inventory', widget.onNavigateToInventory),
      (Icons.assessment, 'Reports', widget.onNavigateToReports),
      (Icons.settings, 'Settings', widget.onNavigateToSettings),
    ].where((a) => a.$3 != null).toList();

    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final tiles = <Widget>[
          for (final a in actions) Expanded(child: _actionTile(a.$1, a.$2, a.$3!)),
        ];
        if (constraints.maxWidth >= AppBreakpoints.minSupportedWidth) {
          return Row(children: _withGaps(tiles));
        }
        return Wrap(
          spacing: AppSpacing.gutter,
          runSpacing: AppSpacing.gutter,
          children: [
            for (final a in actions)
              SizedBox(
                width: (constraints.maxWidth - AppSpacing.gutter) / 2,
                child: _actionTile(a.$1, a.$2, a.$3!),
              ),
          ],
        );
      },
    );
  }

  Widget _actionTile(IconData icon, String label, VoidCallback onTap) {
    final colors = context.appColors;
    final t = context.typography;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: AppSizes.kpiIconChip,
            height: AppSizes.kpiIconChip,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primarySoft,
              borderRadius: AppRadius.controlRadius,
            ),
            child: Icon(icon, size: 20, color: colors.onPrimarySoft),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(label, style: t.bodyStrong),
        ],
      ),
    );
  }
}

/// Per-cashier aggregation for the leaderboard.
class _CashierStats {
  _CashierStats(this.name);

  final String name;
  int sales = 0;
  double revenue = 0;
  double items = 0;
}

/// Tiny pure-painter sparkline for the KPI cards.
class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklinePainter(values, context.appColors.primary),
      size: const Size(double.infinity, 28),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.height <= 0) {
      return;
    }
    final maxV =
        values.reduce((a, b) => a > b ? a : b);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * i / (values.length - 1);
      final y = maxV <= 0
          ? size.height
          : size.height - (values[i] / maxV) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

/// A single compact metric tile used inside the dashboard operations panels
/// (Reload · Repack · Wastage).
class _OpsStat extends StatelessWidget {
  const _OpsStat({
    required this.label,
    required this.value,
    required this.icon,
    this.tone = StatusTone.neutral,
  });

  final String label;
  final String value;
  final IconData icon;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final t = context.typography;
    final accent = tone.fg(colors);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tone.bg(colors).withValues(alpha: 0.45),
        borderRadius: AppRadius.controlRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: accent),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  style: t.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: tone == StatusTone.neutral
                ? t.numberSm
                : t.numberSm.copyWith(color: accent),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}