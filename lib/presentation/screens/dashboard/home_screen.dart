import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../data/models/sale.dart';
import '../../../data/models/user.dart';
import '../../../data/services/customer_display_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/network_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/refund_return_provider.dart';
import '../../providers/reports_provider.dart';
import '../../providers/sales_provider.dart';
import '../../providers/settings_provider.dart';
import '../../shell/app_sidebar.dart';
import '../../shell/app_top_bar.dart';
import '../../shell/command_palette.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/custom_widgets.dart';
import '../admin/customer_management_screen.dart';
import '../admin/repack_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../inventory/batch_management_screen.dart';
import '../inventory/grn_screen.dart';
import '../inventory/inventory_screen.dart';
import '../inventory/purchase_order_screen.dart';
import '../inventory/wastage_management_screen.dart';
import '../pos/pos_screen.dart';
import '../refunds/refund_return_screen.dart';
import '../reload_cards/reload_card_screen.dart';
import '../reports/expense_management_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';
import '../supplier/supplier_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _sidebarCollapsed = false;
  late AnimationController _pageTransitionController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Future<void> _initFuture;

  // Admin screens order
  final List<String> _adminNavLabels = [
    'Dashboard',
    'POS',
    'Inventory',
    'GRN',
    'Batches',
    'Purchase Orders',
    'Suppliers',
    'Refunds',
    'Customers',
    'Expenses',
    'Wastage',
    'Production',
    'Reload',
    'Reports',
    'Settings',
  ];

  final List<IconData> _adminNavIcons = [
    Icons.dashboard,
    Icons.point_of_sale,
    Icons.inventory_2,
    Icons.assignment_turned_in,
    Icons.view_agenda,
    Icons.local_shipping,
    Icons.business,
    Icons.assignment_return,
    Icons.people,
    Icons.receipt_long,
    Icons.delete_sweep,
    Icons.factory,
    Icons.sim_card,
    Icons.assessment,
    Icons.settings,
  ];

  // Cashier screens
  final List<String> _cashierNavLabels = [
    'Dashboard',
    'POS',
    'GRN',
    'Refunds',
    'Profile',
  ];
  final List<IconData> _cashierNavIcons = [
    Icons.dashboard,
    Icons.point_of_sale,
    Icons.assignment_turned_in,
    Icons.assignment_return,
    Icons.person,
  ];

  @override
  void initState() {
    super.initState();
    _pageTransitionController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _pageTransitionController, curve: Curves.easeIn),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0.2, 0), end: Offset.zero).animate(
      CurvedAnimation(
          parent: _pageTransitionController, curve: Curves.easeOutCubic),
    );

    _initFuture = _initializeData();

    // Start the customer display window once (never touched on tab switches).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final salesProvider = context.read<SalesProvider>();
      unawaited(CustomerDisplayService.instance.start(salesProvider: salesProvider));
    });
  }

  @override
  void dispose() {
    _pageTransitionController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    final productProvider = context.read<ProductProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    final customerProvider = context.read<CustomerProvider>();
    final reportProvider = context.read<ReportsProvider>();

    // Yield OUT of the build/layout phase before any provider notifies: the
    // loaders call notifyListeners() synchronously when they start, and
    // notifying while the framework is mid-build throws "setState() called
    // during build" (blanked the home/dashboard on entry).
    await Future<void>.microtask(() {});

    // Reload the grid/selectors whenever the LAN catalog sync refreshes data.
    final networkProvider = context.read<NetworkProvider>();
    networkProvider.onCatalogSynced = () {
      if (!mounted) {
        return;
      }
      unawaited(productProvider.loadProducts());
      unawaited(customerProvider.loadCustomers());
      unawaited(context.read<CategoryProvider>().loadCategories());
    };

    await productProvider.loadProducts();
    await settingsProvider.loadSettings();
    await customerProvider.loadCustomers();
    await reportProvider.generateDailyReport(DateTime.now());
    await context.read<RefundReturnProvider>().loadRefunds();
  }

  void _handleNavigation(int index) {
    final user = context.read<AuthProvider>().currentUser;
    final isAdmin = user?.role == UserRole.admin;
    final maxIndex = (isAdmin ? _adminNavLabels.length : _cashierNavLabels.length) - 1;
    final nextIndex = index.clamp(0, maxIndex);

    _pageTransitionController.forward(from: 0);
    setState(() {
      _selectedIndex = nextIndex;
    });

    if (nextIndex == 0) {
      _refreshDashboard();
    }
  }

  void _toggleSidebar() {
    setState(() {
      _sidebarCollapsed = !_sidebarCollapsed;
    });
  }

  /// Ctrl+K command palette. Navigates to whichever screen the user picked.
  Future<void> _openCommandPalette() async {
    final authProvider = context.read<AuthProvider>();
    final isAdmin = authProvider.currentUser?.role == UserRole.admin;
    final navLabels = isAdmin ? _adminNavLabels : _cashierNavLabels;
    final navIcons = isAdmin ? _adminNavIcons : _cashierNavIcons;

    final target = await showDialog<int>(
      context: context,
      builder: (_) => AppCommandPalette(
        isAdmin: isAdmin,
        labels: navLabels,
        icons: navIcons,
        selectedIndex: _selectedIndex,
      ),
    );
    if (target != null && mounted) {
      _handleNavigation(target);
    }
  }

  void _refreshDashboard() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        final productProvider = context.read<ProductProvider>();
        final reportProvider = context.read<ReportsProvider>();
        final refundProvider = context.read<RefundReturnProvider>();
        productProvider.loadProducts();
        reportProvider.generateDailyReport(DateTime.now());
        refundProvider.loadRefunds();
      }
    });
  }

  List<Widget> _getAdminScreens() => [
        DashboardScreen(
          onNavigateToPos: () => _handleNavigation(1),
          onNavigateToRefunds: () => _handleNavigation(7),
          onNavigateToInventory: () => _handleNavigation(2),
          onNavigateToReports: () => _handleNavigation(13),
          onNavigateToSettings: () => _handleNavigation(14),
        ),
        const PosScreen(),
        const InventoryScreen(),
        const GrnScreen(),
        const BatchManagementScreen(),
        const PurchaseOrderScreen(),
        const SupplierScreen(),
        const RefundReturnScreen(),
        const CustomerManagementScreen(),
        const ExpenseManagementScreen(),
        const WastageManagementScreen(),
        const RepackScreen(),
        const ReloadCardScreen(),
        const ReportsScreen(),
        const SettingsScreen(),
      ];

  List<Widget> _getCashierScreens() => [
        CashierDashboardScreen(
          onNavigateToPos: () => _handleNavigation(1),
          onNavigateToRefunds: () => _handleNavigation(3),
        ),
        const PosScreen(),
        const GrnScreen(),
        const RefundReturnScreen(),
        const ProfileScreen(),
      ];

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.appColors.danger,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      if (mounted) {
        await context.read<AuthProvider>().logout();
        Navigator.of(context).pushReplacementNamed('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          final user = authProvider.currentUser;
          final isAdmin = user?.role == UserRole.admin;

          final navLabels = isAdmin ? _adminNavLabels : _cashierNavLabels;
          final navIcons = isAdmin ? _adminNavIcons : _cashierNavIcons;
          final screens = isAdmin ? _getAdminScreens() : _getCashierScreens();
          final safeIndex = _selectedIndex.clamp(0, navLabels.length - 1);

          if (_selectedIndex != safeIndex) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              setState(() {
                _selectedIndex = safeIndex;
              });
            });
          }

          return WillPopScope(
            onWillPop: () async => false,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(
                  LogicalKeyboardKey.keyK,
                  control: true,
                ): _openCommandPalette,
              },
              child: Focus(
                autofocus: true,
                child: Scaffold(
                  body: LayoutBuilder(
                    builder: (context, constraints) {
                      // Auto-collapse the rail on narrow windows; the manual
                      // toggle stays free once the window is wide enough.
                      final autoCollapsed = constraints.maxWidth <
                          AppBreakpoints.sidebarAutoCollapseBelow;
                      final collapsed = _sidebarCollapsed || autoCollapsed;

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppSidebar(
                            isAdmin: isAdmin,
                            labels: navLabels,
                            icons: navIcons,
                            selectedIndex: safeIndex,
                            collapsed: collapsed,
                            onToggleCollapsed: _toggleSidebar,
                            onSelect: _handleNavigation,
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                AppTopBar(
                                  title: navLabels[safeIndex],
                                  userName: user?.fullName ?? 'User',
                                  isAdmin: isAdmin,
                                  onLogout: _handleLogout,
                                  onOpenInventory: () =>
                                      _handleNavigation(isAdmin ? 2 : 2),
                                ),
                                Expanded(
                                  child: FutureBuilder<void>(
                                    future: _initFuture,
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return const Center(
                                          child: CircularProgressIndicator(),
                                        );
                                      }
                                      if (snapshot.hasError) {
                                        return Center(
                                          child: Text(
                                            'Error: ${snapshot.error}',
                                          ),
                                        );
                                      }
                                      return SlideTransition(
                                        position: _slideAnimation,
                                        child: FadeTransition(
                                          opacity: _fadeAnimation,
                                          child: screens[safeIndex],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      );
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          final user = authProvider.currentUser;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DashboardHeroPanel(
                  title: 'User Profile',
                  subtitle: 'Your account information and role access summary',
                  icon: Icons.person,
                  colors: [Color(0xFF4776E6), Color(0xFF8E54E9)],
                ),
                const SizedBox(height: 24),
                Center(
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: PosAppTheme.primaryGreen.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person,
                      color: PosAppTheme.primaryGreen,
                      size: 60,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                GroceryCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _ProfileItem(
                          label: 'Full  Name',
                          value: user?.fullName ?? '-',
                        ),
                        const Divider(),
                        _ProfileItem(
                          label: 'Username',
                          value: user?.username ?? '-',
                        ),
                        const Divider(),
                        _ProfileItem(
                          label: 'Role',
                          value: user?.role == UserRole.admin
                              ? 'Administrator'
                              : 'Cashier',
                        ),
                        const Divider(),
                        _ProfileItem(
                          label: 'Account Status',
                          value:
                              user?.isActive ?? false ? 'Active' : 'Inactive',
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

class _ProfileItem extends StatelessWidget {
  const _ProfileItem({
    required this.label,
    required this.value,
  });
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: PosAppTheme.textGray,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: PosAppTheme.textDark,
              ),
            ),
          ],
        ),
      );
}

class CashierDashboardScreen extends StatefulWidget {
  const CashierDashboardScreen({
    required this.onNavigateToPos,
    required this.onNavigateToRefunds,
    super.key,
  });

  final VoidCallback onNavigateToPos;
  final VoidCallback onNavigateToRefunds;

  @override
  State<CashierDashboardScreen> createState() => _CashierDashboardScreenState();
}

class _CashierDashboardScreenState extends State<CashierDashboardScreen>
    with SingleTickerProviderStateMixin {
  late Future<List<Sale>> _salesFuture;
  late AnimationController _entranceController;
  late Animation<double> _heroAnim;
  late Animation<double> _kpiAnim;
  late Animation<double> _stockAnim;
  late Animation<double> _hourAnim;
  late Animation<double> _payAnim;
  late Animation<double> _recentAnim;
  bool _customerDisplayOn = CustomerDisplayService.instance.isConnected;

  Animation<double> _step(Animation<double> parent, double start, double end) =>
      CurvedAnimation(
        parent: parent,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      );

  Widget _reveal(Animation<double> anim, Widget child) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.14), end: Offset.zero)
              .animate(anim),
          child: child,
        ),
      );

  @override
  void initState() {
    super.initState();
    _salesFuture = context.read<SalesProvider>().getAllSales();
    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..forward();
    _heroAnim = _step(_entranceController, 0.0, 0.35);
    _kpiAnim = _step(_entranceController, 0.2, 0.5);
    _stockAnim = _step(_entranceController, 0.32, 0.6);
    _hourAnim = _step(_entranceController, 0.42, 0.72);
    _payAnim = _step(_entranceController, 0.55, 0.85);
    _recentAnim = _step(_entranceController, 0.68, 1.0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RefundReturnProvider>().loadRefunds();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await context.read<RefundReturnProvider>().loadRefunds();
    if (!mounted) {
      return;
    }
    setState(() {
      _salesFuture = context.read<SalesProvider>().getAllSales();
    });
  }

  Future<void> _toggleCustomerDisplay() async {
    final on = await CustomerDisplayService.instance.toggle();
    if (!mounted) {
      return;
    }
    setState(() {
      _customerDisplayOn = on;
    });
    if (on) {
      unawaited(CustomerDisplayService.instance.syncNow());
    }
    if (mounted) {
      final err = CustomerDisplayService.instance.lastError;
      showTopSnackBar(context,
        SnackBar(
          content: Text(on
              ? 'Customer Display is now showing on the second screen'
              : err != null
                  ? 'Customer Display could not open: $err'
                  : 'Customer Display closed'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthProvider>().currentUser;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));

    return RefreshIndicator(
      onRefresh: _refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<List<Sale>>(
              future: _salesFuture,
              builder: (context, snapshot) {
                final sales = snapshot.data ?? const <Sale>[];
                final myTodaySales = sales.where((sale) {
                  final saleDate = sale.saleDate;
                  return sale.cashierId == user?.id &&
                      saleDate.isAfter(
                          todayStart.subtract(const Duration(milliseconds: 1))) &&
                      saleDate.isBefore(tomorrowStart);
                }).toList();

                final totalAmount = myTodaySales.fold<double>(
                  0,
                  (sum, sale) => sum + sale.totalAmount,
                );
                final itemsSold = myTodaySales.fold<double>(
                  0,
                  (sum, sale) => sum +
                      sale.items.fold<double>(
                          0, (s, item) => s + item.quantity),
                );

                return Consumer<RefundReturnProvider>(
                  builder: (context, refundProvider, _) {
                    final lowStockCount =
                        context.read<ProductProvider>().getLowStockCount();
                    final outOfStockCount =
                        context.read<ProductProvider>().getOutOfStockCount();

                    final myPendingReturns = refundProvider.refunds.where((refund) {
                      if (refund.status != 'Pending') {
                        return false;
                      }
                      final userId = user?.id ?? '';
                      final userName = user?.fullName.toLowerCase() ?? '';
                      if (userId.isNotEmpty && refund.requesterId == userId) {
                        return true;
                      }
                      return userName.isNotEmpty &&
                          refund.requesterName.toLowerCase() == userName;
                    }).length;

                    final myRequestsToday = refundProvider.refunds.where((refund) {
                      final requestDate = refund.requestDate;
                      final isToday = requestDate
                              .isAfter(todayStart.subtract(const Duration(milliseconds: 1))) &&
                          requestDate.isBefore(tomorrowStart);
                      if (!isToday) {
                        return false;
                      }
                      final userId = user?.id ?? '';
                      final userName = user?.fullName.toLowerCase() ?? '';
                      if (userId.isNotEmpty && refund.requesterId == userId) {
                        return true;
                      }
                      return userName.isNotEmpty &&
                          refund.requesterName.toLowerCase() == userName;
                    }).length;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _reveal(
                          _heroAnim,
                          _buildCashierHero(
                            user: user,
                            dateLabel: _headerDate(now),
                            todaySales: myTodaySales,
                            itemsSold: itemsSold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _reveal(
                          _kpiAnim,
                          _buildKpiRow(
                            salesCount: myTodaySales.length,
                            revenue: totalAmount,
                            itemsSold: itemsSold,
                            pendingReturns: myPendingReturns,
                            requestsToday: myRequestsToday,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (lowStockCount + outOfStockCount > 0) ...[
                          _reveal(
                            _stockAnim,
                            _buildStockBanner(
                                low: lowStockCount, out: outOfStockCount),
                          ),
                          const SizedBox(height: 12),
                        ],
                        _reveal(_hourAnim, _buildHourlyChart(myTodaySales)),
                        const SizedBox(height: 14),
                        _reveal(_payAnim, _buildPaymentSplit(myTodaySales)),
                        const SizedBox(height: 14),
                        _reveal(
                            _recentAnim, _buildRecentSales(myTodaySales)),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCashierHero({
    required User? user,
    required String dateLabel,
    required List<Sale> todaySales,
    required double itemsSold,
  }) {
    final total = todaySales.fold<double>(
        0, (sum, sale) => sum + sale.totalAmount);
    final hasName = user?.fullName.trim().isNotEmpty ?? false;
    final initial = hasName ? user!.fullName.trim()[0].toString().toUpperCase() : '?';
    final name = hasName ? user!.fullName : 'Cashier';

    return Container(
      padding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F7B6F), Color(0xFF2FB28C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: PosAppTheme.primaryGreen.withOpacity(0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -50,
            top: -60,
            child: _heroCircle(210, 0.07),
          ),
          Positioned(
            left: -40,
            bottom: -70,
            child: _heroCircle(180, 0.05),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: PosAppTheme.primaryGreen,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_greetingForHour(DateTime.now().hour)} 👋',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.92),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          dateLabel,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Text(
                      'CASHIER',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "TODAY'S REVENUE",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Rs ${total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${todaySales.length} sales',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.94),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${fmtQty(itemsSold)} items sold',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ElevatedButton.icon(
                    onPressed: widget.onNavigateToPos,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: PosAppTheme.primaryGreen,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.point_of_sale),
                    label: const Text('Start Billing'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _toggleCustomerDisplay,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: _customerDisplayOn
                          ? Colors.white.withOpacity(0.18)
                          : Colors.transparent,
                      side: BorderSide(color: Colors.white.withOpacity(0.7)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: Icon(
                        _customerDisplayOn ? Icons.tv_off : Icons.tv),
                    label: Text(_customerDisplayOn
                        ? 'Close Customer Display'
                        : 'Open Customer Display'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroCircle(double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(opacity),
      ),
    );
  }

  Widget _buildKpiRow({
    required int salesCount,
    required double revenue,
    required double itemsSold,
    required int pendingReturns,
    required int requestsToday,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 4
            : (constraints.maxWidth >= 700 ? 2 : 1);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: columns == 1 ? 3.2 : 2.4,
          ),
          itemCount: 4,
          itemBuilder: (context, index) => switch (index) {
            0 => _kpiCard(
                icon: Icons.receipt_long,
                label: 'Sales Today',
                value: '$salesCount',
                color: PosAppTheme.accentBlue,
              ),
            1 => _kpiCard(
                icon: Icons.payments,
                label: 'Revenue Today',
                value: 'Rs ${revenue.toStringAsFixed(0)}',
                color: PosAppTheme.primaryGreen,
              ),
            2 => _kpiCard(
                icon: Icons.shopping_basket,
                label: 'Items Sold',
                value: fmtQty(itemsSold),
                color: PosAppTheme.warningOrange,
              ),
            _ => _kpiCard(
                icon: Icons.assignment_return,
                label: 'Pending Returns',
                value: '$pendingReturns',
                color: PosAppTheme.dangerRed,
                sub: '$requestsToday mine today',
              ),
          },
        );
      },
    );
  }

  Widget _kpiCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    String? sub,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withOpacity(0.75)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      fontSize: 12, color: PosAppTheme.textGray),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: PosAppTheme.textDark,
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    sub,
                    style: const TextStyle(
                        fontSize: 10, color: PosAppTheme.textGray),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockBanner({required int low, required int out}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6A00), Color(0xFFF7B733)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF6A00).withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$low item(s) low on stock and $out item(s) out of stock — '
              'please check inventory.',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHourlyChart(List<Sale> sales) {
    final buckets = List<double>.filled(24, 0);
    for (final sale in sales) {
      buckets[sale.saleDate.hour] += sale.totalAmount;
    }
    final maxValue = buckets.reduce((a, b) => a > b ? a : b);
    final hasData = maxValue > 0;
    final rawMax = maxValue * 1.25;
    final maxY = hasData && rawMax >= 10 ? rawMax : 10.0;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Today's Sales by Hour",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            "How today's revenue built up hour by hour",
            style: TextStyle(fontSize: 12, color: PosAppTheme.textGray),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: hasData
                ? BarChart(
                    BarChartData(
                      maxY: maxY,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxY / 4,
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 52,
                            interval: maxY / 4,
                            getTitlesWidget: (value, meta) => Text(
                              value >= 1000
                                  ? 'Rs ${(value / 1000).toStringAsFixed(1)}k'
                                  : 'Rs ${value.toInt()}',
                              style: const TextStyle(fontSize: 9),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i % 3 != 0) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '$i:00',
                                  style: const TextStyle(fontSize: 9),
                                ),
                              );
                            },
                          ),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                              BarTooltipItem(
                            '${group.x.toInt()}:00\n'
                            'Rs ${rod.toY.toStringAsFixed(2)}',
                            const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                      barGroups: List.generate(
                        24,
                        (i) => BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: buckets[i],
                              width: 8,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : const Center(
                    child: Text(
                      'No sales yet today',
                      style: TextStyle(color: PosAppTheme.textGray),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSplit(List<Sale> sales) {
    final totals = <String, double>{};
    for (final sale in sales) {
      final key = sale.paymentMethod.trim().toLowerCase();
      totals[key] = (totals[key] ?? 0) + sale.totalAmount;
    }
    final total = totals.values.fold<double>(0, (a, b) => a + b);
    const labelColors = {
      'cash': Color(0xFF11998E),
      'card': Color(0xFF4568DC),
      'cash + card': Color(0xFF8E54E9),
      'cash+card': Color(0xFF8E54E9),
    };
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payments Today',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            "How today's takings were paid",
            style: TextStyle(fontSize: 12, color: PosAppTheme.textGray),
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            const Center(
              child: Text(
                'No payments yet today',
                style: TextStyle(color: PosAppTheme.textGray),
              ),
            )
          else
            ...entries.map((entry) {
              final color = labelColors[entry.key] ?? PosAppTheme.primaryGreen;
              final percent = total > 0 ? (entry.value / total) * 100 : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _capitalize(entry.key),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          'Rs ${entry.value.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 44,
                          child: Text(
                            '${percent.toStringAsFixed(0)}%',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: total > 0
                            ? (entry.value / total).clamp(0, 1)
                            : 0,
                        minHeight: 8,
                        backgroundColor: color.withOpacity(0.15),
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRecentSales(List<Sale> sales) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Today's Sales",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: PosAppTheme.primaryGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${sales.length} bills',
                  style: const TextStyle(
                    color: PosAppTheme.primaryGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (sales.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No sales recorded yet for today.',
                  style: TextStyle(color: PosAppTheme.textGray),
                ),
              ),
            )
          else
            ...sales.take(5).map((sale) {
              final time = sale.saleDate.toLocal();
              final hh = time.hour.toString().padLeft(2, '0');
              final mm = time.minute.toString().padLeft(2, '0');
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: PosAppTheme.accentBlue.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.receipt_long,
                        size: 18,
                        color: PosAppTheme.accentBlue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sale.invoiceLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '$hh:$mm • ${sale.items.length} items',
                            style: const TextStyle(
                              fontSize: 11,
                              color: PosAppTheme.textGray,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Rs ${sale.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: PosAppTheme.primaryGreen,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  String _greetingForHour(int hour) {
    if (hour >= 5 && hour < 12) return 'Good Morning';
    if (hour >= 12 && hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _headerDate(DateTime date) {
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
      'Sunday'
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December'
    ];
    return '${weekdays[date.weekday - 1]}, ${date.day} '
        '${months[date.month - 1]} ${date.year}';
  }

  String _capitalize(String value) => value.isEmpty
      ? value
      : value[0].toUpperCase() + value.substring(1);
}
