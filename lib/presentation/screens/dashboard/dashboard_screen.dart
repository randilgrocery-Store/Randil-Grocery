import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/sale.dart';
import '../../providers/product_provider.dart';
import '../../providers/reports_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/custom_widgets.dart';

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

enum DashboardRange { today, last7Days, last30Days }

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Future<List<Sale>> _rangeSalesFuture;
  late Future<List<Sale>> _prevRangeSalesFuture;
  DashboardRange _selectedRange = DashboardRange.last7Days;
  DateTime _lastRefreshed = DateTime.now();
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..forward();

    _rangeSalesFuture = _loadSalesForRange(_selectedRange);
    _prevRangeSalesFuture = _loadPreviousPeriodSales(_selectedRange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshDashboard();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<List<Sale>> _loadSalesForRange(DashboardRange range) {
    final reportProvider = context.read<ReportsProvider>();
    final now = DateTime.now();
    final start = _rangeStart(range, now);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return reportProvider.getSalesByDateRange(start, end);
  }

  DateTime _rangeStart(DashboardRange range, DateTime now) {
    switch (range) {
      case DashboardRange.today:
        return DateTime(now.year, now.month, now.day);
      case DashboardRange.last7Days:
        return DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 6));
      case DashboardRange.last30Days:
        return DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 29));
    }
  }

  Future<List<Sale>> _loadPreviousPeriodSales(DashboardRange range) {
    final reportProvider = context.read<ReportsProvider>();
    final now = DateTime.now();
    final currentStart = _rangeStart(range, now);
    final prevStart =
        currentStart.subtract(Duration(days: _rangeDays(range)));
    final prevEnd =
        currentStart.subtract(const Duration(milliseconds: 1));
    return reportProvider.getSalesByDateRange(prevStart, prevEnd);
  }

  String _rangeLabel(DashboardRange range) {
    switch (range) {
      case DashboardRange.today:
        return 'Today';
      case DashboardRange.last7Days:
        return '7D';
      case DashboardRange.last30Days:
        return '30D';
    }
  }

  int _rangeDays(DashboardRange range) {
    switch (range) {
      case DashboardRange.today:
        return 1;
      case DashboardRange.last7Days:
        return 7;
      case DashboardRange.last30Days:
        return 30;
    }
  }

  Future<void> _refreshDashboard() async {
    if (_isRefreshing) {
      return;
    }

    setState(() {
      _isRefreshing = true;
    });

    try {
      final productProvider = context.read<ProductProvider>();
      final reportProvider = context.read<ReportsProvider>();
      final now = DateTime.now();

      await productProvider.loadProducts();
      await reportProvider.generateDailyReport(now);
      await reportProvider.generateMonthlyReport(now.year, now.month);

      if (!mounted) {
        return;
      }

      setState(() {
        _lastRefreshed = DateTime.now();
        _rangeSalesFuture = _loadSalesForRange(_selectedRange);
        _prevRangeSalesFuture = _loadPreviousPeriodSales(_selectedRange);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _changeRange(DashboardRange range) {
    if (_selectedRange == range) {
      return;
    }

    setState(() {
      _selectedRange = range;
      _rangeSalesFuture = _loadSalesForRange(range);
      _prevRangeSalesFuture = _loadPreviousPeriodSales(range);
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 1200;
          final isTablet = constraints.maxWidth >= 800;

          return RefreshIndicator(
            onRefresh: _refreshDashboard,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(isDesktop ? 24 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildWelcomeHeader(isDesktop: isDesktop),
                  const SizedBox(height: 16),
                  _buildRangeSelector(),
                  const SizedBox(height: 16),
                  _buildBusinessSnapshot(),
                  const SizedBox(height: 16),
                  _buildKeyMetrics(
                    crossAxisCount: isDesktop
                        ? 6
                        : isTablet
                            ? 3
                            : 2,
                  ),
                  const SizedBox(height: 16),
                  if (isDesktop)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: _buildRevenueTrendChart()),
                        const SizedBox(width: 16),
                        Expanded(flex: 1, child: _buildTopProductsChart()),
                      ],
                    )
                  else ...[
                    _buildRevenueTrendChart(),
                    const SizedBox(height: 16),
                    _buildTopProductsChart(),
                  ],
                  const SizedBox(height: 16),
                  if (isDesktop)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: _buildQuickActions(isDesktop)),
                        const SizedBox(width: 16),
                        Expanded(flex: 1, child: _buildInventoryHealthCard()),
                      ],
                    )
                  else ...[
                    _buildQuickActions(isDesktop),
                    const SizedBox(height: 16),
                    _buildInventoryHealthCard(),
                  ],
                  const SizedBox(height: 16),
                  if (isDesktop)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 1, child: _buildLowStockAlert()),
                        const SizedBox(width: 16),
                        Expanded(flex: 1, child: _buildCashierLeaderboard()),
                      ],
                    )
                  else ...[
                    _buildLowStockAlert(),
                    const SizedBox(height: 16),
                    _buildCashierLeaderboard(),
                  ],
                ],
              ),
            ),
          );
        },
      );

  Widget _buildWelcomeHeader({required bool isDesktop}) {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, _) {
        final shopName = settingsProvider.settings.shopName;
        final now = DateTime.now();
        final greeting = _greetingForHour(now.hour);
        final dateLabel = _formatHeaderDate(now);

        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0E7C70), Color(0xFF2FA98B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: PosAppTheme.primaryGreen.withOpacity(0.28),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -60,
                top: -70,
                child: _decorativeCircle(230, 0.07),
              ),
              Positioned(
                right: 90,
                bottom: -110,
                child: _decorativeCircle(190, 0.05),
              ),
              Positioned(
                left: -50,
                bottom: -60,
                child: _decorativeCircle(160, 0.04),
              ),
              Padding(
                padding: EdgeInsets.all(isDesktop ? 24 : 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$greeting 👋',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.92),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            shopName.isEmpty ? 'Randil Grocery' : shopName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isDesktop ? 26 : 21,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dateLabel,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildLastRefreshPill(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Consumer<ReportsProvider>(
                      builder: (context, reportsProvider, _) {
                        final report = reportsProvider.dailyReport;
                        final revenue =
                            (report?['totalRevenue'] as num?)?.toDouble() ?? 0;
                        final transactions =
                            (report?['totalTransactions'] as num?)?.toInt() ?? 0;
                        return _buildTodayStatBlock(
                            revenue, transactions,
                            onRefresh: _isRefreshing ? null : _refreshDashboard,
                            isRefreshing: _isRefreshing);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _decorativeCircle(double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(opacity),
      ),
    );
  }

  Widget _buildLastRefreshPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        'Live now • ${_lastRefreshed.toLocal().toIso8601String().split('T')[1].split('.').first}',
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }

  Widget _buildTodayStatBlock(double revenue, int transactions,
      {VoidCallback? onRefresh, required bool isRefreshing}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: onRefresh,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                ),
                icon: isRefreshing
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.monitor_heart,
                    color: Colors.white, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'TODAY',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Rs ${revenue.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$transactions sales today',
            style: TextStyle(color: Colors.white.withOpacity(0.88), fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _greetingForHour(int hour) {
    if (hour >= 5 && hour < 12) return 'Good Morning';
    if (hour >= 12 && hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _formatHeaderDate(DateTime date) {
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
      'Sunday'
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December'
    ];
    return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Widget _buildRangeSelector() {
    return Row(
      children: [
        const Text(
          'Range',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: DashboardRange.values.map((range) {
              final selected = _selectedRange == range;
              return GestureDetector(
                onTap: () => _changeRange(range),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? PosAppTheme.primaryGreen
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: PosAppTheme.primaryGreen
                                  .withOpacity(0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    _rangeLabel(range),
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildBusinessSnapshot() {
    return Consumer<ReportsProvider>(
      builder: (context, reportsProvider, _) {
        final report = reportsProvider.dailyReport;
        final revenue = (report?['totalRevenue'] as num?)?.toDouble() ?? 0;
        final transactions = (report?['totalTransactions'] as num?)?.toInt() ?? 0;
        final avgTicket = transactions > 0 ? revenue / transactions : 0;
        final itemsSold = (report?['totalItemsSold'] as num?)?.toInt() ?? 0;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Wrap(
            spacing: 20,
            runSpacing: 12,
            children: [
              _buildMiniStat('Today Revenue', 'Rs ${revenue.toStringAsFixed(0)}'),
              _buildMiniStat('Transactions', transactions.toString()),
              _buildMiniStat('Items Sold', itemsSold.toString()),
              _buildMiniStat('Average Bill', 'Rs ${avgTicket.toStringAsFixed(0)}'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiniStat(String title, String value) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: PosAppTheme.textGray),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyMetrics({required int crossAxisCount}) {
    return FutureBuilder<List<Sale>>(
      future: _prevRangeSalesFuture,
      builder: (context, prevSnapshot) {
        final prevSales = prevSnapshot.data ?? const <Sale>[];
        final prevRevenue = prevSales.fold<double>(
            0, (sum, sale) => sum + sale.totalAmount);
        return _buildMetricsGrid(prevRevenue, crossAxisCount);
      },
    );
  }

  Widget _buildMetricsGrid(double prevRevenue, int crossAxisCount) {
    return FutureBuilder<List<Sale>>(
      future: _rangeSalesFuture,
      builder: (context, snapshot) {
        final sales = snapshot.data ?? [];
        final productProvider = context.watch<ProductProvider>();
        final rangeStats = _calculateRangeStats(sales, productProvider);

        final cards = [
          _MetricData(
            icon: Icons.currency_rupee,
            label: 'Revenue',
            value: 'Rs ${rangeStats.revenue.toStringAsFixed(0)}',
            subtext: _rangeLabel(_selectedRange),
            delta: _deltaPercent(rangeStats.revenue, prevRevenue),
            gradient: const [Color(0xFF0F9B8E), Color(0xFF2BC0A1)],
          ),
          _MetricData(
            icon: Icons.receipt_long,
            label: 'Transactions',
            value: rangeStats.transactions.toString(),
            subtext: 'Sales Count',
            gradient: const [Color(0xFF4568DC), Color(0xFF5B86E5)],
          ),
          _MetricData(
            icon: Icons.stacked_line_chart,
            label: 'Profit Est.',
            value: 'Rs ${rangeStats.profit.toStringAsFixed(0)}',
            subtext: 'Estimated',
            gradient: const [Color(0xFF56AB2F), Color(0xFFA8E063)],
          ),
          _MetricData(
            icon: Icons.percent,
            label: 'Margin',
            value: '${rangeStats.margin.toStringAsFixed(1)}%',
            subtext: 'Gross Margin',
            gradient: const [Color(0xFFFC4A1A), Color(0xFFF7B733)],
          ),
          _MetricData(
            icon: Icons.shopping_cart_checkout,
            label: 'Units Sold',
            value: rangeStats.itemsSold.toString(),
            subtext: 'Across Sale Items',
            gradient: const [Color(0xFF4776E6), Color(0xFF8E54E9)],
          ),
          _MetricData(
            icon: Icons.warning_amber,
            label: 'Risk Items',
            value: '${productProvider.getLowStockCount() + productProvider.getOutOfStockCount()}',
            subtext: 'Inventory Risk',
            gradient: const [Color(0xFFE53935), Color(0xFFE35D5B)],
          ),
        ];

        return GridView.builder(
          itemCount: cards.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: crossAxisCount >= 4 ? 1.35 : 1.18,
          ),
          itemBuilder: (context, index) => _buildMetricCard(
            icon: cards[index].icon,
            label: cards[index].label,
            value: cards[index].value,
            subtext: cards[index].subtext,
            delta: cards[index].delta,
            gradient: LinearGradient(
              colors: cards[index].gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            delay: (index * 0.08).clamp(0.0, 0.5),
          ),
        );
      },
    );
  }

  _RangeStats _calculateRangeStats(List<Sale> sales, ProductProvider productProvider) {
    final productLookup = {for (final product in productProvider.allProducts) product.id: product};
    var revenue = 0.0;
    var cost = 0.0;
    var itemsSold = 0;

    for (final sale in sales) {
      revenue += sale.totalAmount;
      for (final item in sale.items) {
        itemsSold += item.quantity;
        final product = productLookup[item.productId];
        final buyingPrice = product?.buyingPrice ?? 0;
        cost += buyingPrice * item.quantity;
      }
    }

    final profit = revenue - cost;
    final margin = revenue > 0 ? (profit / revenue) * 100 : 0.0;

    return _RangeStats(
      revenue: revenue,
      cost: cost,
      profit: profit,
      margin: margin,
      itemsSold: itemsSold,
      transactions: sales.length,
    );
  }

  String? _deltaPercent(double current, double previous) {
    if (previous <= 0) return null;
    final delta = ((current - previous) / previous) * 100;
    final prefix = delta >= 0 ? '+' : '-';
    return '$prefix${delta.abs().toStringAsFixed(1)}%';
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required String subtext,
    required LinearGradient gradient,
    required double delay,
    String? delta,
  }) {
    final deltaUp = delta?.startsWith('+') ?? false;
    return ScaleTransition(
      scale: Tween(begin: 0.92, end: 1.0).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: Interval(
            delay,
            (delay + 0.35).clamp(0.0, 1.0).toDouble(),
            curve: Curves.easeOutCubic,
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: Colors.white, size: 18),
                  ),
                  if (delta != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (deltaUp ? Colors.white : Colors.black)
                            .withOpacity(0.22),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            deltaUp
                                ? Icons.trending_up
                                : Icons.trending_down,
                            size: 13,
                            color: Colors.white,
                          ),
                          Text(
                            delta,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtext,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRevenueTrendChart() {
    return FutureBuilder<List<Sale>>(
      future: _rangeSalesFuture,
      builder: (context, snapshot) {
        final sales = snapshot.data ?? [];
        final points = _buildRevenueSeriesForRange(sales);
        final maxY = points.isEmpty
            ? 100.0
            : (points.reduce((a, b) => a > b ? a : b) * 1.2).clamp(100, 999999).toDouble();

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Revenue Trend',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Range: ${_rangeLabel(_selectedRange)}',
                        style: const TextStyle(fontSize: 12, color: PosAppTheme.textGray),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: PosAppTheme.primaryGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _rangeLabel(_selectedRange),
                      style: const TextStyle(
                        color: PosAppTheme.primaryGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 250,
                child: points.isEmpty
                    ? const Center(child: Text('No sales in this range'))
                    : LineChart(
                        LineChartData(
                          minY: 0,
                          maxY: maxY,
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: maxY / 4,
                          ),
                          borderData: FlBorderData(
                            show: true,
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          titlesData: FlTitlesData(
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 56,
                                interval: maxY / 4,
                                getTitlesWidget: (value, _) => Text(
                                  'Rs ${value.toInt()}',
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: 1,
                                getTitlesWidget: (value, _) {
                                  final index = value.toInt();
                                  if (index < 0 || index >= points.length) {
                                    return const SizedBox.shrink();
                                  }
                                  final label = _xAxisLabel(index, points.length);
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      label,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: List.generate(
                                points.length,
                                (index) => FlSpot(index.toDouble(), points[index]),
                              ),
                              isCurved: true,
                              color: PosAppTheme.primaryGreen,
                              barWidth: 3,
                              dotData: FlDotData(
                                show: true,
                                getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                                  radius: 4,
                                  color: Colors.white,
                                  strokeColor: PosAppTheme.primaryGreen,
                                  strokeWidth: 2,
                                ),
                              ),
                              belowBarData: BarAreaData(
                                show: true,
                                gradient: LinearGradient(
                                  colors: [
                                    PosAppTheme.primaryGreen.withOpacity(0.25),
                                    PosAppTheme.primaryGreen.withOpacity(0.02),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
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
      },
    );
  }

  Widget _buildTopProductsChart() {
    return FutureBuilder<List<Sale>>(
      future: _rangeSalesFuture,
      builder: (context, snapshot) {
        final sales = snapshot.data ?? [];
        final breakdown = <String, int>{};
        for (final sale in sales) {
          for (final item in sale.items) {
            breakdown[item.productName] =
                (breakdown[item.productName] ?? 0) + item.quantity;
          }
        }

        final topItems = breakdown.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final visible = topItems.take(6).toList();
        final maxY = visible.isEmpty
            ? 8.0
            : (visible.first.value * 1.4).clamp(8, 9999).toDouble();

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Top-Selling Items',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Most moved items in ${_rangeLabel(_selectedRange)}',
                style: const TextStyle(fontSize: 12, color: PosAppTheme.textGray),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 240,
                child: visible.isEmpty
                    ? const Center(child: Text('No data to chart'))
                    : BarChart(
                        BarChartData(
                          maxY: maxY,
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: maxY / 4,
                          ),
                          borderData: FlBorderData(
                            show: true,
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          titlesData: FlTitlesData(
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 28,
                                interval: (maxY / 4)
                                    .clamp(1.0, double.infinity)
                                    .toDouble(),
                                getTitlesWidget: (value, _) => Text(
                                  value.toInt().toString(),
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, _) {
                                  final index = value.toInt();
                                  if (index < 0 || index >= visible.length) {
                                    return const SizedBox.shrink();
                                  }
                                  final name = visible[index].key;
                                  final short = name.length > 8
                                      ? '${name.substring(0, 8)}..'
                                      : name;
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(short, style: const TextStyle(fontSize: 10)),
                                  );
                                },
                              ),
                            ),
                          ),
                          barGroups: List.generate(
                            visible.length,
                            (index) => BarChartGroupData(
                              x: index,
                              barRods: [
                                BarChartRodData(
                                  toY: visible[index].value.toDouble(),
                                  width: 16,
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF1E88E5), Color(0xFF26C6DA)],
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<double> _buildRevenueSeriesForRange(List<Sale> sales) {
    final days = _rangeDays(_selectedRange);
    final values = List<double>.filled(days, 0);
    final start = _rangeStart(_selectedRange, DateTime.now());
    final daysList = List.generate(days, (index) => start.add(Duration(days: index)));

    for (final sale in sales) {
      for (var i = 0; i < daysList.length; i++) {
        final day = daysList[i];
        final sameDay = sale.saleDate.year == day.year &&
            sale.saleDate.month == day.month &&
            sale.saleDate.day == day.day;
        if (sameDay) {
          values[i] += sale.totalAmount;
          break;
        }
      }
    }

    return values;
  }

  String _xAxisLabel(int index, int totalPoints) {
    if (totalPoints == 1) {
      return 'Today';
    }

    final start = _rangeStart(_selectedRange, DateTime.now());
    final date = start.add(Duration(days: index));
    if (_selectedRange == DashboardRange.last7Days ||
        _selectedRange == DashboardRange.last30Days) {
      return '${date.day}/${date.month}';
    }
    return 'Today';
  }

  Widget _buildQuickActions(bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: isDesktop ? 3 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          children: [
            _buildActionButton(
              icon: Icons.point_of_sale,
              label: 'New Sale',
              color: const Color(0xFF667EEA),
              onTap: widget.onNavigateToPos,
            ),
            _buildActionButton(
              icon: Icons.assignment_return,
              label: 'Refund Center',
              color: const Color(0xFFE57373),
              onTap: widget.onNavigateToRefunds,
            ),
            _buildActionButton(
              icon: Icons.add_shopping_cart,
              label: 'Inventory',
              color: const Color(0xFF11998E),
              onTap: widget.onNavigateToInventory,
            ),
            _buildActionButton(
              icon: Icons.assessment,
              label: 'Reports',
              color: const Color(0xFFFFA500),
              onTap: widget.onNavigateToReports,
            ),
            _buildActionButton(
              icon: Icons.local_shipping,
              label: 'Reorder',
              color: const Color(0xFF26A69A),
              onTap: widget.onNavigateToInventory,
            ),
            _buildActionButton(
              icon: Icons.settings,
              label: 'Settings',
              color: const Color(0xFF764BA2),
              onTap: widget.onNavigateToSettings,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withOpacity(0.82)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.28),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 36),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInventoryHealthCard() {
    return Consumer<ProductProvider>(
      builder: (context, productProvider, child) {
        final totalProducts = productProvider.allProducts.length;
        final lowStockCount = productProvider.getLowStockCount();
        final outOfStockCount = productProvider.getOutOfStockCount();
        final normalStockCount =
            totalProducts - lowStockCount - outOfStockCount;

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Inventory Health',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                '$totalProducts products tracked',
                style: const TextStyle(fontSize: 12, color: PosAppTheme.textGray),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 190,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 34,
                    sections: [
                      PieChartSectionData(
                        color: const Color(0xFF11998E),
                        value: normalStockCount.toDouble().clamp(0, double.infinity),
                        title: normalStockCount.toString(),
                        radius: 56,
                        titleStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      PieChartSectionData(
                        color: const Color(0xFFFFA500),
                        value: lowStockCount.toDouble(),
                        title: lowStockCount.toString(),
                        radius: 56,
                        titleStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      PieChartSectionData(
                        color: const Color(0xFFF93B1D),
                        value: outOfStockCount.toDouble(),
                        title: outOfStockCount.toString(),
                        radius: 56,
                        titleStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildLegendItem('Normal Stock', const Color(0xFF11998E)),
              const SizedBox(height: 8),
              _buildLegendItem('Low Stock', const Color(0xFFFFA500)),
              const SizedBox(height: 8),
              _buildLegendItem('Out of Stock', const Color(0xFFF93B1D)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildLowStockAlert() {
    return Consumer<ProductProvider>(
      builder: (context, productProvider, child) {
        final lowStockProducts = productProvider.getLowStockProducts();
        if (lowStockProducts.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(
                  Icons.check_circle,
                  color: PosAppTheme.successGreen,
                  size: 48,
                ),
                const SizedBox(height: 10),
                const Text(
                  'All Items in Stock',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: PosAppTheme.warningOrange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.warning_amber,
                      color: PosAppTheme.warningOrange,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Low Stock Alert',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 280,
                child: ListView.separated(
                  itemCount: lowStockProducts.take(8).length,
                  separatorBuilder: (_, __) => Divider(
                    color: Colors.grey[200],
                    height: 16,
                  ),
                  itemBuilder: (context, index) {
                    final product = lowStockProducts[index];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: PosAppTheme.warningOrange.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'SKU: ${product.barcode}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: PosAppTheme.warningOrange,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${product.quantity}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.onNavigateToInventory,
                  icon: const Icon(Icons.inventory_2),
                  label: const Text('Open Inventory Management'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCashierLeaderboard() {
    return FutureBuilder<List<Sale>>(
      future: _rangeSalesFuture,
      builder: (context, snapshot) {
        final sales = snapshot.data ?? [];
        final leaderboard = <String, _CashierStats>{};

        for (final sale in sales) {
          final key = sale.cashierName;
          final stats = leaderboard[key] ?? _CashierStats(cashierName: key);
          stats.transactions += 1;
          stats.revenue += sale.totalAmount;
          stats.itemsSold += sale.items.fold(0, (sum, item) => sum + item.quantity);
          leaderboard[key] = stats;
        }

        final ranked = leaderboard.values.toList()
          ..sort((a, b) => b.revenue.compareTo(a.revenue));

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cashier Leaderboard',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Performance for ${_rangeLabel(_selectedRange)}',
                style: const TextStyle(fontSize: 12, color: PosAppTheme.textGray),
              ),
              const SizedBox(height: 12),
              if (ranked.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Center(child: Text('No cashier performance data yet')),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: ranked.take(5).length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final stats = ranked[index];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: index == 0
                            ? PosAppTheme.primaryGreen.withOpacity(0.08)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: PosAppTheme.primaryGreen.withOpacity(0.12),
                            child: Text('${index + 1}'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stats.cashierName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${stats.transactions} transactions • ${stats.itemsSold} items',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: PosAppTheme.textGray,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'Rs ${stats.revenue.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MetricData {
  _MetricData({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtext,
    required this.gradient,
    this.delta,
  });

  final IconData icon;
  final String label;
  final String value;
  final String subtext;
  final String? delta;
  final List<Color> gradient;
}

class _RangeStats {
  _RangeStats({
    required this.revenue,
    required this.cost,
    required this.profit,
    required this.margin,
    required this.itemsSold,
    required this.transactions,
  });

  final double revenue;
  final double cost;
  final double profit;
  final double margin;
  final int itemsSold;
  final int transactions;
}

class _CashierStats {
  _CashierStats({required this.cashierName});

  final String cashierName;
  int transactions = 0;
  double revenue = 0;
  int itemsSold = 0;
}
