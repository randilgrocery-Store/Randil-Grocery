import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:win32/win32.dart';
import '../../../data/services/display_service.dart';
import '../../widgets/custom_widgets.dart';

class CustomerDisplayScreen extends StatefulWidget {
  final String windowId;
  const CustomerDisplayScreen({super.key, required this.windowId});

  @override
  State<CustomerDisplayScreen> createState() => _CustomerDisplayScreenState();
}

class _CustomerDisplayScreenState extends State<CustomerDisplayScreen> {
  List<dynamic> _cartItems = [];
  double _total = 0.0;
  double _subtotal = 0.0;
  double _discount = 0.0;
  String _status = 'Welcome to Randil Grocery!';

  // Idle promo slideshow (only while the cart is empty)
  Timer? _promoTimer;
  int _promoIndex = 0;
  static const _promos = [
    (
      icon: Icons.eco,
      title: 'Fresh vegetables, every morning',
      sub: 'Straight from the market to your basket',
    ),
    (
      icon: Icons.rice_bowl,
      title: 'Rice, dhal & grains by the kilo',
      sub: 'Weighed right in front of you — fair price per kg',
    ),
    (
      icon: Icons.local_offer,
      title: 'Best prices in town',
      sub: 'Daily deals on your everyday essentials',
    ),
    (
      icon: Icons.favorite,
      title: 'Thank you for shopping with us',
      sub: 'Randil Grocery — good things, fresh daily',
    ),
  ];

  @override
  void initState() {
    super.initState();

    // Listen for messages from the main window using the new API
    const channel = WindowMethodChannel(
      'pos_channel',
      mode: ChannelMode.unidirectional,
    );
    channel.setMethodCallHandler((call) async {
      if (call.method == 'updateCart') {
        try {
          final data = jsonDecode(call.arguments as String);
          setState(() {
            _cartItems = data['items'] as List<dynamic>;
            _total = (data['total'] as num).toDouble();
            _subtotal = (data['subtotal'] as num).toDouble();
            _discount = (data['discount'] as num).toDouble();
            _status = _cartItems.isEmpty
                ? 'Welcome to Randil Grocery!'
                : 'Processing your order...';
          });
        } catch (e) {
          // Ignore malformed update and keep current state
        }
        return 'Success';
      }
      return null;
    });

    // Fill the secondary display (falls back to the primary when no second
    // screen is attached) once the first frame has been rendered.
    WidgetsBinding.instance.addPostFrameCallback((_) => _configureWindow());

    // Rotate the idle promo cards every 6 seconds.
    _promoTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (_cartItems.isEmpty && mounted) {
        setState(() => _promoIndex = (_promoIndex + 1) % _promos.length);
      }
    });
  }

  @override
  void dispose() {
    _promoTimer?.cancel();
    super.dispose();
  }

  /// Finds this window's native handle. The desktop_multi_window plugin
  /// registers its windows under a dedicated Win32 class name, which makes it
  /// unambiguous from the main application window.
  int _findOwnWindow() {
    final className = 'FLUTTER_MULTI_WINDOW_WIN32_WINDOW'.toNativeUtf16();
    try {
      return FindWindow(className, nullptr);
    } finally {
      calloc.free(className);
    }
  }

  /// Moves the customer window onto the secondary monitor and expands it to a
  /// true borderless fullscreen.
  ///
  /// The move is done in two steps: first the window is relocated at its
  /// current size so Windows finishes the per-monitor DPI change, then it is
  /// sized to the monitor's exact physical bounds (any resolution/scaling).
  Future<void> _configureWindow() async {
    if (!Platform.isWindows) return;
    try {
      final target = DisplayService.secondary() ?? DisplayService.primary();
      if (target == null) return;

      final handle = _findOwnWindow();
      if (handle == 0) return;

      // Keep the customer screen out of the taskbar / alt-tab list.
      final exStyle = GetWindowLongPtr(handle, GWL_EXSTYLE);
      SetWindowLongPtr(
        handle,
        GWL_EXSTYLE,
        (exStyle | WS_EX_TOOLWINDOW) & 0xFFFFFFFF,
      );

      // Remove the title bar / border so the client area is the whole window.
      final style = GetWindowLongPtr(handle, GWL_STYLE);
      SetWindowLongPtr(
        handle,
        GWL_STYLE,
        ((style & ~WS_OVERLAPPEDWINDOW) | WS_POPUP) & 0xFFFFFFFF,
      );

      // Step 1: relocate (keep size) and let the DPI change settle.
      SetWindowPos(
        handle,
        HWND_TOP,
        target.left,
        target.top,
        0,
        0,
        SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED,
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));

      // Step 2: fill the target monitor's physical bounds.
      SetWindowPos(
        handle,
        HWND_TOP,
        target.left,
        target.top,
        target.width,
        target.height,
        SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED,
      );
    } catch (_) {
      // Window placement is best-effort; the display still shows windowed.
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep the layout readable from small kiosk screens up to 4K panels.
        final scale = (constraints.maxHeight / 1080).clamp(0.85, 1.8);
        final panelWidth =
            (constraints.maxWidth * 0.34).clamp(360.0, 760.0).toDouble();
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            backgroundColor: const Color(0xFFF4F7F6),
            body: Row(
              children: [
                // Left side: Item list or Welcome
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Image.asset(
                                'assets/images/randil_logo.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Shopping Cart',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: PosAppTheme.primaryGreen,
                                    ),
                                  ),
                                  Text(
                                    'Randil Grocery',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Expanded(
                          child: _cartItems.isEmpty
                              ? _buildWelcomeView()
                              : _buildCartListView(),
                        ),
                      ],
                    ),
                  ),
                ),
                // Right side: Totals and Branding
                Container(
                  width: panelWidth,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [PosAppTheme.primaryGreen, Color(0xFF0B6E5D)],
                    ),
                  ),
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.asset(
                              'assets/images/randil_logo.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'RANDIL GROCERY',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Good things, fresh daily',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                      _buildTotalSection(),
                      Text(
                        _status,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.white70,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWelcomeView() {
    final promo = _promos[_promoIndex];
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/images/randil_logo.png',
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Welcome to Randil Grocery!',
            style: TextStyle(
              fontSize: 30,
              color: PosAppTheme.primaryGreen,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Your order will appear here',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 36),
          // Rotating promo card — crossfades every few seconds while idle.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 700),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.25),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                    parent: anim, curve: Curves.easeOutCubic)),
                child: child,
              ),
            ),
            child: _PromoCard(
              key: ValueKey(_promoIndex),
              icon: promo.icon,
              title: promo.title,
              sub: promo.sub,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartListView() {
    return ListView.builder(
      itemCount: _cartItems.length,
      itemBuilder: (context, index) {
        final item = _cartItems[index];
        // Newest item slides in; existing rows stay put.
        final isNew = index == _cartItems.length - 1;
        final card = Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['name'],
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Qty: ${fmtQty(item['quantity'] as num)} x Rs. ${item['price'].toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'Rs. ${item['total'].toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: PosAppTheme.primaryGreen,
                ),
              ),
            ],
          ),
        );
        if (!isNew) return card;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(24 * (1 - t), 0),
              child: Transform.scale(
                scale: 0.96 + 0.04 * t,
                child: child,
              ),
            ),
          ),
          child: card,
        );
      },
    );
  }

  Widget _buildTotalSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          _buildSummaryRow('Subtotal', _subtotal),
          _buildSummaryRow('Discount', -_discount),
          const Divider(color: Colors.white24, height: 32),
          const Text(
            'TOTAL AMOUNT',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white70,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: _total),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text(
                'Rs. ${v.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 18, color: Colors.white70),
          ),
          Text(
            'Rs. ${amount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 18,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// One rotating idle promo slide on the customer-facing display.
class _PromoCard extends StatelessWidget {
  const _PromoCard({
    required this.icon,
    required this.title,
    required this.sub,
    super.key,
  });

  final IconData icon;
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: PosAppTheme.primaryGreen.withOpacity(0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: PosAppTheme.primaryGreen.withOpacity(0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: PosAppTheme.primaryGreen.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: PosAppTheme.primaryGreen, size: 30),
          ),
          const SizedBox(width: 18),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sub,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
