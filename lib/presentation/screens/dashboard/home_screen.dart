import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../data/models/user.dart';
import '../../../data/services/customer_display_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/expense_provider.dart';
import '../../providers/grn_provider.dart';
import '../../providers/network_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/purchase_order_provider.dart';
import '../../providers/refund_return_provider.dart';
import '../../providers/reload_card_provider.dart';
import '../../providers/repack_provider.dart';
import '../../providers/reports_provider.dart';
import '../../providers/sales_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/supplier_provider.dart';
import '../../providers/wastage_provider.dart';
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
import '../inventory/expiry_screen.dart';
import '../inventory/grn_screen.dart';
import '../inventory/inventory_screen.dart';
import '../inventory/purchase_order_screen.dart';
import '../inventory/shopping_bag_screen.dart';
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
  bool _sidebarTouched = false;
  late AnimationController _pageTransitionController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Future<void> _initFuture;

  // Admin screens order.
  // These delegate to [AppSidebar], the single source of truth for the shell's
  // screens, so the labels, their icons and the sidebar's index-based groups
  // can never drift apart (a drift that once hid Settings from the sidebar).
  List<String> get _adminNavLabels => AppSidebar.adminLabels;
  List<IconData> get _adminNavIcons => AppSidebar.adminIcons;

  // Cashier screens
  List<String> get _cashierNavLabels => AppSidebar.cashierLabels;
  List<IconData> get _cashierNavIcons => AppSidebar.cashierIcons;

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
      unawaited(context.read<SupplierProvider>().loadSuppliers());
      // The admin PC may have pushed a new label-scale layout with the catalog.
      unawaited(context.read<SettingsProvider>().loadSettings());
    };

    // A sale pushed in from another terminal: refresh stock + today's figures
    // so this machine always shows the real, current numbers.
    networkProvider.onRemoteSaleReceived = () {
      if (!mounted) {
        return;
      }
      unawaited(productProvider.loadProducts());
      unawaited(reportProvider.generateDailyReport(DateTime.now()));
      unawaited(context.read<RefundReturnProvider>().loadRefunds());
    };

    // Mirrored data landed from the other PC: the whole shop's day — bills,
    // expenses, wastage, reload cards, refunds, repacks, goods received and
    // supplier payments — must repaint without the user touching anything.
    networkProvider.onFinancialsSynced = () {
      if (!mounted) {
        return;
      }
      unawaited(reportProvider.generateDailyReport(DateTime.now()));
      _reloadMirroredData();
    };

    await productProvider.loadProducts();
    await settingsProvider.loadSettings();
    await customerProvider.loadCustomers();
    await reportProvider.generateDailyReport(DateTime.now());
    await context.read<RefundReturnProvider>().loadRefunds();
  }

  /// Reloads every screen-level list fed by the LAN mirror. These are cheap
  /// local queries, called whenever the other PC's records land.
  void _reloadMirroredData() {
    if (!mounted) {
      return;
    }
    unawaited(context.read<WastageProvider>().loadWastages());
    unawaited(context.read<ReloadCardProvider>().loadCards());
    unawaited(context.read<RepackProvider>().loadAll());
    unawaited(context.read<RefundReturnProvider>().loadRefunds());
    unawaited(context.read<ExpenseProvider>().loadExpenses());
    unawaited(context.read<GrnProvider>().loadNotes());
    unawaited(context.read<PurchaseOrderProvider>().loadOrders());
    unawaited(context.read<SupplierProvider>().loadSuppliers());
    unawaited(context.read<CustomerProvider>().loadCustomers());
    unawaited(context.read<ProductProvider>().loadProducts());
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
      _sidebarTouched = true;
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
          onNavigateToRefunds: () => _handleNavigation(8),
          onNavigateToInventory: () => _handleNavigation(2),
          onNavigateToReports: () => _handleNavigation(14),
          onNavigateToSettings: () => _handleNavigation(15),
        ),
        const PosScreen(),
        const InventoryScreen(),
        const GrnScreen(),
        const BatchManagementScreen(),
        const ExpiryScreen(),
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
        const ShoppingBagScreen(),
      ];

  List<Widget> _getCashierScreens() => [
        CashierDashboardScreen(
          onNavigateToPos: () => _handleNavigation(1),
          onNavigateToRefunds: () => _handleNavigation(4),
        ),
        const PosScreen(),
        const GrnScreen(),
        const ExpiryScreen(),
        const RefundReturnScreen(),
        const ExpenseManagementScreen(),
        const ReloadCardScreen(),
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
                      // Auto-collapse the rail on narrow windows until the
                      // user touches the expand/collapse button — after that
                      // the manual choice always wins.
                      final autoCollapsed = constraints.maxWidth <
                          AppBreakpoints.sidebarAutoCollapseBelow;
                      final collapsed =
                          _sidebarTouched ? _sidebarCollapsed : autoCollapsed;

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
  late AnimationController _entranceController;
  late Animation<double> _heroAnim;
  bool _customerDisplayOn = CustomerDisplayService.instance.isConnected;

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
    _entranceController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();
    _heroAnim = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  /// Pull-to-refresh re-syncs the customer display with the POS cart so both
  /// screens always show the same content.
  Future<void> _refresh() async {
    await CustomerDisplayService.instance.syncNow();
    if (mounted) {
      setState(() {
        _customerDisplayOn = CustomerDisplayService.instance.isConnected;
      });
    }
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
    final err = CustomerDisplayService.instance.lastError;
    showTopSnackBar(
      context,
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

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthProvider>().currentUser;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: _reveal(
          _heroAnim,
          _buildCashierHero(user: user),
        ),
      ),
    );
  }

  /// Cashier home: greeting + big touch-friendly action buttons only.
  /// Business statistics / daily-sales analytics stay admin-only.
  Widget _buildCashierHero({required User? user}) {
    final hasName = user?.fullName.trim().isNotEmpty ?? false;
    final initial =
        hasName ? user!.fullName.trim()[0].toString().toUpperCase() : '?';
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
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _headerDate(DateTime.now()),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 13,
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
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton.icon(
                    onPressed: widget.onNavigateToPos,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: PosAppTheme.primaryGreen,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 18),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.point_of_sale, size: 26),
                    label: const Text('Start Billing'),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.onNavigateToRefunds,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withOpacity(0.7)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 18),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.assignment_return, size: 26),
                    label: const Text('Refunds'),
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
                          horizontal: 22, vertical: 18),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: Icon(
                        _customerDisplayOn ? Icons.tv_off : Icons.tv, size: 26),
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
}
