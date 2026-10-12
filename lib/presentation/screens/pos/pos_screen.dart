import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/constants/responsive.dart';
import '../../../core/utils/money_calculator.dart';
import '../../../data/database/database_service.dart';
import '../../../data/models/product.dart';
import '../../../data/models/shop_settings.dart';
import '../../../data/services/print_service.dart';
import '../../../data/services/scale_barcode.dart';
import '../../../data/services/sound_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cash_drawer_coordinator.dart';
import '../../providers/category_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/payment_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/sales_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/custom_widgets.dart';
import '../../widgets/payment_method_selector.dart';
import '../../widgets/product_image.dart';

// Intent classes for keyboard shortcuts
class ClearCartIntent extends Intent {
  const ClearCartIntent();
}

class ToggleFullScreenIntent extends Intent {
  const ToggleFullScreenIntent();
}

class ToggleDarkModeIntent extends Intent {
  const ToggleDarkModeIntent();
}

class HoldBillIntent extends Intent {
  const HoldBillIntent();
}

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  late TextEditingController _paymentController;
  late TextEditingController _cardAmountController;
  late TextEditingController _discountController;
  late TextEditingController _customDiscountController;
  late TextEditingController _searchController;
  final FocusNode _searchFocus = FocusNode();

  String? _selectedCustomerId;
  String? _selectedCategory;
  bool _isFullScreen = false;

  bool _handleGlobalKey(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f11) {
      unawaited(_toggleWindowFullScreen());
      return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _paymentController = TextEditingController();
    _cardAmountController = TextEditingController();
    _discountController = TextEditingController();
    _customDiscountController = TextEditingController();
    _searchController = TextEditingController();

    _paymentController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    _cardAmountController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    _searchController.addListener(() {
      _filterProducts();
      if (mounted) {
        setState(() {});
      }
    });

    HardwareKeyboard.instance.addHandler(_handleGlobalKey);

    // App starts in fullscreen; mirror the window state in POS layout state.
    unawaited(_syncWindowFullScreenState());
    _focusBarcode();
  }

  Future<void> _syncWindowFullScreenState() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return;
    }

    final isFullScreen = await windowManager.isFullScreen();
    if (!mounted) {
      return;
    }

    setState(() {
      _isFullScreen = isFullScreen;
    });
  }

  Future<void> _toggleWindowFullScreen() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      setState(() {
        _isFullScreen = !_isFullScreen;
      });
      return;
    }

    final isFullScreen = await windowManager.isFullScreen();
    if (isFullScreen) {
      await windowManager.setFullScreen(false);
      await windowManager.maximize();
      if (mounted) {
        setState(() {
          _isFullScreen = false;
        });
      }
      return;
    }

    await windowManager.setFullScreen(true);
    if (mounted) {
      setState(() {
        _isFullScreen = true;
      });
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);

    _paymentController.dispose();
    _cardAmountController.dispose();
    _discountController.dispose();
    _customDiscountController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Keeps keyboard/scanner input flowing into the barcode box so a scan works
  /// without the cashier having to click the field first.
  void _focusBarcode() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && !_searchFocus.hasFocus) {
        _searchFocus.requestFocus();
      }
    });
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    context.read<ProductProvider>().searchProducts(query);
  }

  /// Clears the scan/search box and puts the cursor back in it so the next
  /// scan starts on a clean field.
  ///
  /// Unfocusing before clearing resets the platform text-input connection; on
  /// Windows a stale composing region can otherwise repaint the just-scanned
  /// barcode back into the box a moment after [TextEditingController.clear].
  void _resetSearchBox() {
    _searchController.clear();
    _filterProducts();
    _searchFocus.unfocus();
    _focusBarcode();
  }

  Future<void> _handleBarcodeScan(String barcode) async {
    final code = barcode.trim();

    // Clear the box *before* doing any async work. The scanner has already
    // handed us the code, so the field no longer needs it, and this guarantees
    // the barcode can never be left sitting in the box if a later step
    // (product lookup, beep, network call) throws.
    _resetSearchBox();

    if (code.isEmpty) return;

    try {
      // A label from the weighing scale carries the item and its weight in one
      // barcode. Decode it first; if it is not a scale label, fall through to
      // the ordinary product lookup.
      if (await _tryAddScaleBarcode(code)) return;

      final productProvider = context.read<ProductProvider>();
      final product = await productProvider.getProductByCode(code);

      if (product != null && product.quantity > 0) {
        if (product.soldByWeight) {
          final weight = await _promptWeight(product);
          if (weight == null) return;
          await context
              .read<SalesProvider>()
              .addToCart(product, quantity: weight);
        } else if (product.isBreakBulk) {
          // Only the box carries a barcode; let the cashier pick a whole box
          // or single pieces taken from it.
          final loose = await _promptBoxOrSingle(product);
          if (loose == null) return; // cancelled
          await context
              .read<SalesProvider>()
              .addToCart(product, loose: loose);
        } else {
          await context.read<SalesProvider>().addToCart(product);
        }
        await SoundService.playBeep();
        _showSnackBar('${product.name} added to cart', isSuccess: true);
      } else {
        await SoundService.playError();
        _showSnackBar('Product not found or out of stock');
      }
    } finally {
      if (mounted) _resetSearchBox();
    }
  }

  /// Tries to read [code] as a barcode printed by the label scale (item + weight
  /// in one). Returns true when the scan was consumed by the scale path — even
  /// if it only reported "out of stock" — and false when [code] is an ordinary
  /// product barcode that should be looked up normally.
  Future<bool> _tryAddScaleBarcode(String code) async {
    // Read the label-scale layout fresh from the database on every scan. On a
    // cashier PC the layout is copied from the admin by the catalog sync, and
    // using a possibly-stale cached copy here is what let a freshly-synced
    // layout be ignored until the app was restarted.
    final providerSettings = context.read<SettingsProvider>().settings;
    ShopSettings settings;
    try {
      settings = await DatabaseService().getShopSettings();
    } catch (_) {
      settings = providerSettings;
    }
    if (!settings.scaleBarcodeEnabled) return false;
    // Cheap reject before doing any database work.
    if (code.length != settings.scaleBarcodeLength) return false;

    final config = ScaleBarcodeConfig(
      enabled: true,
      prefix: settings.scaleBarcodePrefix,
      totalLength: settings.scaleBarcodeLength,
      itemLength: settings.scaleBarcodeItemLength,
      priceMode: settings.scaleBarcodePriceMode,
      checkDigit: settings.scaleBarcodeCheckDigit,
    );

    final productProvider = context.read<ProductProvider>();
    for (final itemLength in ScaleBarcodeParser.candidateItemLengths(config)) {
      final parsed =
          ScaleBarcodeParser.decode(code, config, itemLength: itemLength);
      if (parsed == null) continue;

      final product = await _findScaleProduct(productProvider, parsed.itemCode);
      if (product == null) continue; // wrong split; try the next width

      if (product.quantity <= 0) {
        await SoundService.playError();
        _showSnackBar('${product.name} is out of stock');
        return true;
      }

      final double quantity;
      if (parsed.priceMode) {
        if (product.sellingPrice <= 0) continue;
        quantity = parsed.price / product.sellingPrice;
      } else {
        quantity = parsed.weightKg;
      }
      if (quantity <= 0) continue;

      await context
          .read<SalesProvider>()
          .addToCart(product, quantity: quantity);
      await SoundService.playBeep();
      final detail = parsed.priceMode
          ? 'Rs. ${parsed.price.toStringAsFixed(2)}'
          : '${MoneyCalculator.formatQty(quantity, byWeight: true)} kg';
      _showSnackBar('${product.name} added ($detail)', isSuccess: true);
      return true;
    }
    return false;
  }

  /// Finds the product whose code matches a scale label's item/PLU code,
  /// tolerating a scale that zero-pads the code (e.g. label `00101` → `101`).
  Future<Product?> _findScaleProduct(
    ProductProvider provider,
    String itemCode,
  ) async {
    final direct = await provider.getProductByCode(itemCode);
    if (direct != null) return direct;
    // The label and the product barcode may differ only in leading zeros (a
    // scale may zero-pad its PLU, and the item may be entered with a different
    // number of zeros), so fall back to a leading-zero-tolerant match.
    return provider.getProductByBarcodeLoose(itemCode);
  }

  void _sortProducts(String value) {
    final provider = context.read<ProductProvider>();
    switch (value) {
      case 'name':
        provider.sortByName();
        break;
      case 'category':
        provider.sortByCategory();
        break;
      case 'barcode':
        provider.sortByBarcode();
        break;
      default:
        provider.sortByName();
    }
  }

  Future<void> _processSale() async {
    final salesProvider = context.read<SalesProvider>();
    final paymentProvider = context.read<PaymentProvider>();
    final customerProvider = context.read<CustomerProvider>();

    if (salesProvider.cartItems.isEmpty) {
      _showSnackBar('Cart is empty');
      return;
    }

    final customer = _selectedCustomerId != null
        ? customerProvider.getCustomerById(_selectedCustomerId!)
        : null;
    final method = paymentProvider.selectedPaymentMethod;

    // Validate the payment, using the post-redemption total.
    double paymentAmount;
    double cashAmount = 0;
    double cardAmount = 0;
    if (method == PaymentMethod.card) {
      // Card payments are always for the exact total.
      paymentAmount = salesProvider.total;
      cardAmount = paymentAmount;
    } else if (method == PaymentMethod.split) {
      cashAmount =
          double.tryParse(_paymentController.text) ?? double.negativeInfinity;
      cardAmount = double.tryParse(_cardAmountController.text) ??
          double.negativeInfinity;
      if (cashAmount < 0 || cardAmount < 0) {
        _showSnackBar('Please enter the Cash and Card amounts');
        return;
      }
      paymentAmount = cashAmount + cardAmount;
      if (!MoneyCalculator.isPaymentSufficient(
        paymentAmount,
        salesProvider.total,
      )) {
        _showSnackBar(
          'Cash + Card is less than the total (need ${MoneyCalculator.formatCurrency(salesProvider.total)})',
        );
        return;
      }
    } else {
      if (_paymentController.text.isEmpty) {
        _showSnackBar('Please enter payment amount');
        return;
      }
      paymentAmount =
          double.tryParse(_paymentController.text) ?? double.negativeInfinity;
      if (paymentAmount < 0) {
        _showSnackBar('Invalid payment amount');
        return;
      }
      // Use precise money calculation for payment validation
      if (!MoneyCalculator.isPaymentSufficient(
        paymentAmount,
        salesProvider.total,
      )) {
        _showSnackBar(
          'Insufficient payment amount (need ${MoneyCalculator.formatCurrency(salesProvider.total)})',
        );
        return;
      }
      cashAmount = paymentAmount;
    }

    try {
      final authProvider = context.read<AuthProvider>();
      final user = authProvider.currentUser;

      if (user == null) {
        _showSnackBar('User not authenticated');
        return;
      }

      final saleTotal = salesProvider.total;

      // Trigger precise calculation path before processing to validate behavior.
      MoneyCalculator.calculateChange(paymentAmount, saleTotal);

      // Get payment method from PaymentProvider
      final paymentMethod =
          method == PaymentMethod.split ? 'Cash + Card' : method.displayName;
      final paymentNotes = _buildPaymentNotes(
        paymentProvider,
        cashPortion: cashAmount,
        cardPortion: cardAmount,
      );

      final ok = await salesProvider.processSale(
        cashierId: user.id,
        cashierName: user.fullName,
        amountReceived: paymentAmount,
        paymentMethod: paymentMethod,
        notes: paymentNotes,
        customerName: customer?.name ?? '',
        customerPhone: customer?.phone ?? '',
        cashAmount: cashAmount,
        cardAmount: cardAmount,
      );

      if (!ok) {
        if (mounted) {
          _showSnackBar(
            'Sale failed. Cart was kept - please check and retry.',
          );
        }
        return;
      }

      if (!mounted) return;

      if (customer != null) {
        await customerProvider.updateCustomerPurchaseStats(
          customerId: customer.id,
          amountSpent: saleTotal,
        );
      }

      if (!mounted) return;
      await SoundService.playSuccess();
      if (!mounted) return;

      // Show the bill preview immediately so the cashier can tap Print.
      final settingsProvider = context.read<SettingsProvider>();
      await _showDetailedBillDialog(salesProvider, settingsProvider);

      if (!mounted) return;

      // Refresh stock so the grid reflects the sale after the dialog closes.
      await context.read<ProductProvider>().loadProducts();
      if (!mounted) return;

      _showSnackBar('Sale completed successfully', isSuccess: true);

      _clearForm();
      // Reset payment method after sale
      paymentProvider.reset();
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error processing sale: $e');
      }
    }
  }

  String _buildPaymentNotes(
    PaymentProvider paymentProvider, {
    double cashPortion = 0,
    double cardPortion = 0,
  }) {
    final buffer = <String>[];
    if (paymentProvider.selectedPaymentMethod == PaymentMethod.split) {
      buffer.add('Cash: ${cashPortion.toStringAsFixed(2)}');
      buffer.add('Card: ${cardPortion.toStringAsFixed(2)}');
    }
    if (paymentProvider.paymentDetails.isNotEmpty) {
      buffer.addAll(paymentProvider.paymentDetails.entries
          .map((entry) => '${entry.key}: ${entry.value}'));
    }
    if (buffer.isEmpty) {
      return '';
    }
    return 'Payment method: ${paymentProvider.selectedPaymentMethod.displayName}\n${buffer.join(' | ')}';
  }

  void _clearForm() {
    if (!mounted) return;
    _paymentController.clear();
    _cardAmountController.clear();
    _discountController.clear();
    _customDiscountController.clear();
    _searchController.clear();
    context.read<ProductProvider>().clearFilter();
    setState(() {
      _selectedCustomerId = null;
      _selectedCategory = null;
    });
    context.read<SalesProvider>().clearCart();
    _focusBarcode();
  }

  /// Small toast shown as an overlay at the top-right of the screen (over
  /// the cart column) instead of a bottom snackbar.
  void _showSnackBar(String message, {bool isSuccess = false}) {
    if (!mounted) return;
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _PosToast(
        message: message,
        isSuccess: isSuccess,
      ),
    );
    overlay.insert(entry);
    Timer(const Duration(seconds: 3), () {
      if (entry.mounted) entry.remove();
    });
  }

  /// Bill discount dialog — accepts either an exact percentage or an exact
  /// rupee amount via a segmented toggle.
  Future<void> _showDiscountDialog() async {
    bool isPercent = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Bill Discount'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Percent'),
                    icon: Icon(Icons.percent, size: 18),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Amount (Rs)'),
                    icon: Icon(Icons.payments_outlined, size: 18),
                  ),
                ],
                selected: {isPercent},
                onSelectionChanged: (selection) {
                  setDialogState(() => isPercent = selection.first);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _customDiscountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: isPercent
                      ? 'Discount percentage (0-100)'
                      : 'Discount amount',
                  prefixText: isPercent ? '% ' : 'Rs ',
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => Navigator.pop(context, true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    final value = double.tryParse(_customDiscountController.text) ?? -1;
    _customDiscountController.clear();
    final sales = context.read<SalesProvider>();
    if (isPercent) {
      if (value >= 0 && value <= 100) {
        sales.applyQuickDiscount(value);
        _showSnackBar('Discount ${value.toStringAsFixed(1)}% applied',
            isSuccess: true);
      } else {
        _showSnackBar('Enter a percentage between 0 and 100');
      }
    } else {
      if (value >= 0 && value <= sales.subtotal) {
        sales.applyCustomDiscount(value);
        _showSnackBar('Discount of Rs ${value.toStringAsFixed(2)} applied',
            isSuccess: true);
      } else {
        _showSnackBar('Enter an amount between 0 and the subtotal');
      }
    }
  }

  Future<void> _showDetailedBillDialog(
    SalesProvider salesProvider,
    SettingsProvider settingsProvider,
  ) async {
    final lastSale = salesProvider.lastSale;
    if (lastSale == null) {
      _showSnackBar('No sale to show');
      return;
    }

    final printService = PrintService();
    final receiptText = printService.generateReceiptText(
      lastSale,
      settingsProvider.settings,
    );

    await showDialog(
      context: context,
      builder: (context) {
        final currency = settingsProvider.settings.currencySymbol;
        return AlertDialog(
          title: const Text('Bill Details'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Invoice: ${lastSale.invoiceLabel}'),
                Text('Cashier: ${lastSale.cashierName}'),
                Text('Items: ${lastSale.items.length}'),
                const SizedBox(height: 8),
                Text(
                  'Total: $currency ${lastSale.totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Paid: $currency ${lastSale.amountReceived.toStringAsFixed(2)}',
                ),
                Text(
                  'Change: $currency ${lastSale.balance.toStringAsFixed(2)}',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Choose how to complete this bill:',
                  style: TextStyle(
                    color: PosAppTheme.textGray,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Detailed Receipt Preview',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Complete Without Print'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: PosAppTheme.primaryGreen,
              ),
              autofocus: true,
              onPressed: () {
                Navigator.pop(context);
                _printBill(salesProvider, settingsProvider);
              },
              icon: const Icon(Icons.print),
              label: const Text('Print & Complete'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _printBill(
    SalesProvider salesProvider,
    SettingsProvider settingsProvider, {
    bool isReprint = false,
  }) async {
    try {
      final lastSale = salesProvider.lastSale;
      if (lastSale == null) {
        _showSnackBar('No sale to print');
        return;
      }

      final printService = PrintService();
      final printers = printService.listPrinters();
      final settings = settingsProvider.settings;

      // Determine which printer to use: the configured one if present and
      // available, otherwise the best receipt printer available.
      final printerName =
          printService.selectPrinter(printers, settings.printerName);

      if (printerName.isEmpty) {
        _showSnackBar('No printer found. Install your printer first.');
        return;
      }

      final ok = printService.printSale(
        lastSale,
        settings,
        printerName,
        logoBytes: await _loadLogoBytes(),
      );
      if (!ok) {
        await _showPrintFailureDialog(
          printService.lastPrintError ??
              'The bill could not be sent to the printer.',
          salesProvider,
          settingsProvider,
        );
        return;
      }

      // A job can be accepted by the spooler and still fail mid-print (paper
      // runs out, printer goes offline). Watch the printer briefly so that is
      // reported instead of a false success.
      final problem = await printService.verifyPrint(printerName);
      if (problem != null) {
        await _showPrintFailureDialog(
          problem,
          salesProvider,
          settingsProvider,
        );
        return;
      }

      // Pop the cash drawer now that the bill is safely out. Exactly-once per
      // sale is guaranteed by the drawer_events row, so a reprint or a double
      // tap can never open the till twice.
      if (!isReprint) {
        await CashDrawerCoordinator().openAfterSale(
          sale: lastSale,
          isCardOnly: !lastSale.isSplitPayment &&
              lastSale.paymentMethod == 'Card',
          settings: settings,
        );
      }

      _showSnackBar(
        isReprint ? 'Bill reprinted successfully' : 'Bill printed successfully',
        isSuccess: true,
      );
    } catch (e) {
      _showSnackBar('Error printing bill: $e');
    }
  }

  /// Shown when a bill does not print (e.g. the roll ran out mid-print). The
  /// cashier can fix the printer and reprint the last bill without redoing
  /// the sale.
  Future<void> _showPrintFailureDialog(
    String message,
    SalesProvider salesProvider,
    SettingsProvider settingsProvider,
  ) async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: Colors.red, size: 40),
        title: const Text('Bill not printed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            const Text(
              'Fix the printer, then tap "Reprint" to print the last bill '
              'again. The sale itself has been saved.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
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
              unawaited(
                _printBill(
                  salesProvider,
                  settingsProvider,
                  isReprint: true,
                ),
              );
            },
            icon: const Icon(Icons.print),
            label: const Text('Reprint'),
          ),
        ],
      ),
    );
  }

  void _reprintLastBill() {
    final salesProvider = context.read<SalesProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    if (salesProvider.lastSale == null) {
      _showSnackBar('No bill to reprint yet');
      return;
    }
    unawaited(
      _printBill(salesProvider, settingsProvider, isReprint: true),
    );
  }

  Future<Uint8List?> _loadLogoBytes() async {
    try {
      final data = await rootBundle.load('assets/images/randil_logo.png');
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _showHeldBillsDialog() async {
    final heldBills = context.read<SalesProvider>().heldBills;

    if (heldBills.isEmpty) {
      _showSnackBar('No held bills');
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Held Bills'),
        content: SizedBox(
          width: 400,
          child: ListView.builder(
            itemCount: heldBills.length,
            itemBuilder: (context, index) {
              final bill = heldBills[index];
              return Card(
                child: ListTile(
                  title: Text(bill.customerName ?? 'Bill ${index + 1}'),
                  subtitle: Text(
                    '${bill.items.length} items - Rs. ${bill.total.toStringAsFixed(2)}',
                  ),
                  trailing: PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: const Text('Resume'),
                        onTap: () {
                          context.read<SalesProvider>().resumeBill(bill);
                          Navigator.pop(context);
                          _showSnackBar('Bill resumed', isSuccess: true);
                        },
                      ),
                      PopupMenuItem(
                        child: const Text('Delete'),
                        onTap: () {
                          context.read<SalesProvider>().removeHeldBill(bill.id);
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
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

  @override
  Widget build(BuildContext context) => Shortcuts(
        shortcuts: {
          LogicalKeySet(LogicalKeyboardKey.escape): const ClearCartIntent(),
          LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.keyF):
              const ToggleFullScreenIntent(),
          LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.keyD):
              const ToggleDarkModeIntent(),
          LogicalKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.keyH):
              const HoldBillIntent(),
        },
        child: Actions(
          actions: {
            ClearCartIntent: CallbackAction<ClearCartIntent>(
              onInvoke: (intent) {
                context.read<SalesProvider>().clearCart();
                return null;
              },
            ),
            ToggleFullScreenIntent: CallbackAction<ToggleFullScreenIntent>(
              onInvoke: (intent) {
                unawaited(_toggleWindowFullScreen());
                return null;
              },
            ),
            ToggleDarkModeIntent: CallbackAction<ToggleDarkModeIntent>(
              onInvoke: (intent) {
                context.read<ThemeProvider>().toggleDarkMode();
                return null;
              },
            ),
            HoldBillIntent: CallbackAction<HoldBillIntent>(
              onInvoke: (intent) {
                context.read<SalesProvider>().holdBill();
                _showSnackBar('Bill held', isSuccess: true);
                return null;
              },
            ),
          },
          child: Scaffold(
            appBar: _buildAppBar(),
            body: _buildBody(),
          ),
        ),
      );

  PreferredSizeWidget _buildAppBar() => AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.shopping_basket, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Text(
              'RANDIL GROCERY POS',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                fontSize: 18,
              ),
            ),
          ],
        ),
        elevation: 0,
        backgroundColor: PosAppTheme.primaryGreen,
        actions: [
          Tooltip(
            message: 'Toggle Full-Screen (F11)',
            child: IconButton(
              icon: Icon(
                _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
              ),
              onPressed: () {
                unawaited(_toggleWindowFullScreen());
              },
            ),
          ),
          Tooltip(
            message: 'Reprint Last Bill',
            child: IconButton(
              icon: const Icon(Icons.receipt_long),
              onPressed: _reprintLastBill,
            ),
          ),
          Tooltip(
            message: 'View Held Bills',
            child: Consumer<SalesProvider>(
              builder: (context, salesProvider, _) => Badge(
                label: Text('${salesProvider.heldBills.length}'),
                backgroundColor: PosAppTheme.warningOrange,
                child: IconButton(
                  icon: const Icon(Icons.pause_circle_outline),
                  onPressed: _showHeldBillsDialog,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const VerticalDivider(
            color: Colors.white24,
            indent: 12,
            endIndent: 12,
          ),
          const SizedBox(width: 8),
          Consumer<AuthProvider>(
            builder: (context, auth, _) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  const Icon(Icons.account_circle_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    auth.currentUser?.fullName ?? 'Cashier',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _buildBody() {
    final isTablet = context.responsive.isTablet;

    if (isTablet || context.responsive.isMobile) {
      return _buildResponsiveLayout();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // On short windows fall back to the stacked, scrollable layout so
        // every control stays reachable on a touch screen without a mouse.
        if (constraints.maxHeight < 620) {
          return _buildResponsiveLayout();
        }
        return _buildDesktopLayout();
      },
    );
  }

  Widget _buildDesktopLayout() {
    final responsive = context.responsive;
    return Row(
      children: [
        // Left side - Products and Categories
        Expanded(
          flex: responsive.productListFlex,
          child: _buildProductSection(),
        ),
        // Right side - Cart and Payment
        Expanded(
          flex: responsive.cartFlex,
          child: _buildCartSection(),
        ),
      ],
    );
  }

  Widget _buildResponsiveLayout() => Column(
        children: [
          _buildCategoriesAndSearch(),
          Expanded(
            flex: 3,
            child: _buildProductsGrid(),
          ),
          const Divider(height: 2),
          Flexible(
            flex: 2,
            child: _buildCartSection(),
          ),
        ],
      );

  Widget _buildProductSection() => Column(
        children: [
          // Categories and Search
          _buildCategoriesAndSearch(),
          // Products Grid
          Expanded(
            child: _buildProductsGrid(),
          ),
        ],
      );

  Widget _buildProductsGrid() => Consumer<ProductProvider>(
        builder: (context, provider, _) {
          final products = provider.products;

          if (products.isEmpty) {
            return const Center(
              child: Text('No products available'),
            );
          }

          return GridView.builder(
            padding: EdgeInsets.all(context.responsive.paddingMedium),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: context.responsive.productGridColumns,
              childAspectRatio: 0.85,
              crossAxisSpacing: context.responsive.paddingSmall,
              mainAxisSpacing: context.responsive.paddingSmall,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) => _buildProductCard(products[index]),
          );
        },
      );

  Widget _buildCategoriesAndSearch() {
    final responsive = context.responsive;
    return Container(
      color: Theme.of(context).appBarTheme.backgroundColor,
      padding: EdgeInsets.all(responsive.paddingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            focusNode: _searchFocus,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: _handleBarcodeScan,
            style: TextStyle(fontSize: responsive.bodyMedium),
            decoration: InputDecoration(
              hintText: 'Scan barcode or search product...',
              prefixIcon: const Icon(Icons.barcode_reader),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _filterProducts();
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              contentPadding: EdgeInsets.symmetric(
                vertical: responsive.paddingSmall,
                horizontal: responsive.paddingMedium,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(responsive.radiusMedium),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          SizedBox(height: responsive.paddingMedium),
          Consumer<ProductProvider>(
            builder: (context, productProvider, _) => Align(
              alignment: Alignment.centerRight,
              child: DropdownButton<String>(
                value: productProvider.sortBy,
                items: const [
                  DropdownMenuItem(value: 'name', child: Text('Sort: Name')),
                  DropdownMenuItem(
                    value: 'category',
                    child: Text('Sort: Category'),
                  ),
                  DropdownMenuItem(
                    value: 'barcode',
                    child: Text('Sort: Barcode'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _sortProducts(value);
                  }
                },
              ),
            ),
          ),
          SizedBox(height: responsive.paddingMedium),
          SizedBox(
            height: responsive.buttonHeightMedium,
            child: Consumer<CategoryProvider>(
              builder: (context, categoryProvider, _) {
                final categories = [
                  {'id': 'All', 'name': 'All'},
                  ...categoryProvider.categories
                      .map((c) => {'id': c.id, 'name': c.name}),
                ];

                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final categoryId = category['id']!;
                    final categoryName = category['name']!;
                    final isSelected = _selectedCategory == categoryId ||
                        (_selectedCategory == null && categoryId == 'All');

                    return Padding(
                      padding: EdgeInsets.only(right: responsive.paddingSmall),
                      child: FilterChip(
                        selected: isSelected,
                        label: Text(
                          categoryName,
                          style: TextStyle(
                            fontSize: responsive.bodyMedium,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        onSelected: (selected) {
                          setState(() {
                            _selectedCategory = selected && categoryId != 'All'
                                ? categoryId
                                : null;
                          });
                          context
                              .read<ProductProvider>()
                              .filterByCategory(categoryId);
                        },
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
  }

  Future<void> _addProductToCart(dynamic product) async {
    if (product.quantity <= 0) {
      SoundService.playError();
      _showSnackBar('${product.name} is out of stock');
      return;
    }

    // Hard stop on expired stock: if the newest lot has already passed its
    // expiry, nothing on the shelf is safe to sell. Clear it with Wastage.
    final prodProvider = context.read<ProductProvider>();
    final latestExpiry = prodProvider.latestExpiryFor(product.id) ??
        (product.expiryDate as DateTime?);
    if (latestExpiry != null && latestExpiry.isBefore(DateTime.now())) {
      SoundService.playError();
      _showSnackBar(
        '${product.name} has expired — record it in Wastage before selling',
      );
      return;
    }

    // Weighed products (rice, dhal, vegetables...) are priced per kg, so the
    // cashier keys the weight instead of getting a fixed quantity of 1.
    double quantity = 1;
    bool loose = false;
    if (product.soldByWeight == true) {
      final weight = await _promptWeight(product);
      if (weight == null) return; // cashier cancelled
      quantity = weight;
    } else if (product.isBreakBulk) {
      // Only the box is barcoded, so ask whether this is a whole box or single
      // pieces taken from it.
      final choice = await _promptBoxOrSingle(product);
      if (choice == null) return; // cashier cancelled
      loose = choice;
    }

    await context
        .read<SalesProvider>()
        .addToCart(product, quantity: quantity, loose: loose);
    SoundService.playBeep();
    _showSnackBar('${product.name} added to cart', isSuccess: true);

    // Clear the search box after a product tapped from the filtered results so
    // the full grid returns and the next item starts from a clean search.
    if (_searchController.text.isNotEmpty) {
      _resetSearchBox();
    }
  }

  /// Big touch-friendly weight/quantity keypad for per-kg products.
  /// Returns the chosen weight in kg, or null when cancelled.
  Future<double?> _promptWeight(dynamic product) async {
    final controller = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('${product.name} (per kg)'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                    fontSize: 32, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: 'Weight (kg)',
                  hintText: 'e.g. 0.500',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) {
                  final w = double.tryParse(controller.text.trim());
                  if (w != null && w > 0) Navigator.pop(context, w);
                },
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final w in [0.1, 0.25, 0.5, 0.75, 1.0, 2.0, 5.0])
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context, w),
                      child: Text(
                          '${w % 1 == 0 ? w.toInt() : w} kg'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Stock: ${MoneyCalculator.formatQty(product.quantity, byWeight: true)} kg  ·  Rs. ${product.sellingPrice.toStringAsFixed(2)}/kg',
                style: const TextStyle(
                    color: PosAppTheme.textGray, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: PosAppTheme.primaryGreen),
            onPressed: () {
              final w = double.tryParse(controller.text.trim());
              if (w != null && w > 0) {
                Navigator.pop(context, w);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  /// Asks whether a break-bulk product (one whose only barcode is on the box)
  /// is being sold as a whole box or as single pieces taken from it. Returns
  /// `false` for a whole box, `true` for single pieces, or null when cancelled.
  Future<bool?> _promptBoxOrSingle(Product product) {
    final symbol = context.read<SettingsProvider>().settings.currencySymbol;
    final perBox = product.sellingPrice;
    final perPiece = product.loosePrice;
    final boxesAvailable = product.quantity.floor();
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(product.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Stock: ${product.stockLabel(product.quantity)}',
              style: const TextStyle(color: PosAppTheme.textGray, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _boxOrSingleButton(
                    title: 'Whole box',
                    subtitle: '$symbol ${perBox.toStringAsFixed(2)}'
                        '  ·  ${product.piecesPerBox} pcs',
                    icon: Icons.inventory_2_outlined,
                    onTap: boxesAvailable >= 1
                        ? () => Navigator.pop(context, false)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _boxOrSingleButton(
                    title: 'Single piece',
                    subtitle: '$symbol ${perPiece.toStringAsFixed(2)} / pc',
                    icon: Icons.local_mall_outlined,
                    onTap: () => Navigator.pop(context, true),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Quick "add a shopping bag to the bill" action.
  ///
  /// This is a simple retail bag charge (Rs 3 / 5 / 10 / 20) for the little bags
  /// a customer buys. It is intentionally NOT connected to the bulk "Shopping
  /// Bags" section — that section tracks whole bundles the owner buys, uses and
  /// resells, tracked separately from grocery stock. Here only the money goes on
  /// the bill; no stock anywhere is moved.
  Future<void> _showBagDialog() async {
    const tiers = <double>[3, 5, 10, 20];
    var selectedPrice = tiers.first;
    var qty = 1.0;
    final symbol = context.read<SettingsProvider>().settings.currencySymbol;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.shopping_bag, color: PosAppTheme.primaryGreen),
                SizedBox(width: 8),
                Text('Shopping Bag — Add to Bill'),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Pick the bag price and how many the customer needs '
                    '(a bundle can be rung up as a quantity).',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final price in tiers)
                    RadioListTile<double>(
                      value: price,
                      groupValue: selectedPrice,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '$symbol ${price.toStringAsFixed(0)} bag',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selectedPrice = value);
                        }
                      },
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.outlined(
                        onPressed: qty > 1
                            ? () => setDialogState(() => qty -= 1)
                            : null,
                        icon: const Icon(Icons.remove, size: 18),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          fmtQty(qty),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton.outlined(
                        onPressed: () => setDialogState(() => qty += 1),
                        icon: const Icon(Icons.add, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '$symbol ${(selectedPrice * qty).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: PosAppTheme.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Not needed'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  await context.read<SalesProvider>().addBagChargeToCart(
                        price: selectedPrice,
                        quantity: qty,
                      );
                  await SoundService.playBeep();
                  if (mounted) Navigator.pop(dialogContext);
                },
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: const Text('Add to Bill'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _boxOrSingleButton({
    required String title,
    required String subtitle,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    final colour =
        enabled ? PosAppTheme.primaryGreen : PosAppTheme.textGray;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: colour, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: colour, size: 28),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: enabled ? null : PosAppTheme.textGray),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: PosAppTheme.textGray, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showProductPreviewDialog(dynamic product) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Product Image Header
            Container(
              height: 250,
              width: 400,
              decoration: BoxDecoration(
                color: PosAppTheme.lightGreen,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: ProductImage(
                path: product.imagePath,
                fit: BoxFit.cover,
                placeholderIcon: Icons.image,
                placeholderColor: PosAppTheme.primaryGreen,
                placeholderSize: 80,
              ),
            ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Category: ${product.categoryName ?? "N/A"}',
                    style: const TextStyle(color: PosAppTheme.textGray),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Rs. ${product.sellingPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: PosAppTheme.primaryGreen,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: product.quantity > 0
                              ? Colors.green[50]
                              : Colors.red[50],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Stock: ${product.soldByWeight ? '${MoneyCalculator.formatQty(product.quantity, byWeight: true)} kg' : product.stockLabel(product.quantity)}',
                          style: TextStyle(
                            color: product.quantity > 0
                                ? Colors.green
                                : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PosAppTheme.primaryGreen,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: product.quantity > 0
                          ? () async {
                              Navigator.pop(context);
                              await _addProductToCart(product);
                            }
                          : null,
                      child: const Text(
                        'ADD TO CART',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
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

  Widget _buildProductCard(dynamic product) {
    final responsive = context.responsive;
    final isAvailable = product.quantity > 0;
    // Expiry warnings come from the item's closest stocked batch (the same
    // product received on different dates has different lots), falling back
    // to the product-level date if one was ever set. The card only turns red
    // when EVERY remaining lot is already expired — mixed lots with a fresh
    // one still on sale just show the "Exp:" badge.
    final prodProvider = context.read<ProductProvider>();
    final nextExpiry = prodProvider.soonestExpiryFor(product.id) ??
        (product.expiryDate as DateTime?);
    final latestExpiry = prodProvider.latestExpiryFor(product.id) ??
        (product.expiryDate as DateTime?);
    final now = DateTime.now();
    final isExpired =
        latestExpiry != null && latestExpiry.isBefore(now);
    final daysUntil = nextExpiry?.difference(now).inDays;
    final isExpiringSoon =
        !isExpired && daysUntil != null && daysUntil >= 0 && daysUntil <= 7;

    return GestureDetector(
      onTap: () => _addProductToCart(product),
      onLongPress: () => _showProductPreviewDialog(product),
      child: Card(
        elevation: isAvailable ? 2 : 0,
        color: isExpired
            ? Colors.red[50]
            : isExpiringSoon
                ? Colors.orange[50]
                : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color:
                      isAvailable ? PosAppTheme.lightGreen : Colors.grey[200],
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(responsive.radiusSmall),
                    topRight: Radius.circular(responsive.radiusSmall),
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Product Image or Placeholder
                    ProductImage(
                      path: product.imagePath,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholderIcon: Icons.image,
                      placeholderColor:
                          isAvailable ? PosAppTheme.primaryGreen : Colors.grey,
                      placeholderSize: responsive.iconLarge,
                    ),
                    if (isExpired)
                      Container(
                        color: Colors.red.withOpacity(0.5),
                        child: Center(
                          child: Text(
                            'EXPIRED',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: responsive.bodyMedium,
                            ),
                          ),
                        ),
                      )
                    else if (!isAvailable)
                      Container(
                        color: Colors.black.withOpacity(0.3),
                        child: Center(
                          child: Text(
                            'OUT OF STOCK',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: responsive.bodySmall,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Product Info
            Expanded(
              flex: 2,
              child: Padding(
                padding: EdgeInsets.all(responsive.paddingSmall),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Product Name
                    Text(
                      product.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: responsive.bodyMedium,
                        color: isExpired ? Colors.red : null,
                        decoration:
                            isExpired ? TextDecoration.lineThrough : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Price and Stock
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rs. ${product.sellingPrice.toStringAsFixed(2)}'
                          '${product.soldByWeight ? ' /kg' : ''}',
                          style: TextStyle(
                            color: PosAppTheme.primaryGreen,
                            fontWeight: FontWeight.bold,
                            fontSize: responsive.bodyMedium,
                          ),
                        ),
                        SizedBox(height: responsive.paddingXSmall),
                        if (isExpiringSoon)
                          Text(
                            'Exp: $daysUntil days',
                            style: TextStyle(
                              fontSize: responsive.bodyTiny,
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        else
                          Text(
                            isAvailable
                                ? 'Stock: ${product.soldByWeight ? '${MoneyCalculator.formatQty(product.quantity, byWeight: true)} kg' : product.stockLabel(product.quantity)}'
                                : 'Out of Stock',
                            style: TextStyle(
                              fontSize: responsive.bodySmall,
                              color: isAvailable
                                  ? PosAppTheme.textGray
                                  : PosAppTheme.dangerRed,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartSection() {
    final responsive = context.responsive;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Column(
        children: [
          // ── Cart Header ────────────────────────────────
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: responsive.paddingMedium,
              vertical: responsive.paddingSmall,
            ),
            color: PosAppTheme.primaryGreen,
            child: Row(
              children: [
                const Icon(Icons.shopping_cart, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                const Text(
                  'Shopping Cart',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Consumer<SalesProvider>(
                  builder: (context, provider, _) => Text(
                    '· ${provider.cartItems.length} item${provider.cartItems.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: _showBagDialog,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.shopping_bag, size: 16),
                  label: const Text(
                    'Bag',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                const Spacer(),
                Consumer<SalesProvider>(
                  builder: (context, provider, _) => Text(
                    MoneyCalculator.formatCurrency(provider.total),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Cart Items (scrollable list only) ──────────
          Expanded(
            flex: 2,
            child: _buildCartItems(),
          ),
          // ── Payment Panel (fixed, never scrolls) ───────
          Expanded(
            flex: 5,
            child: _buildPaymentSection(),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItems() => Consumer<SalesProvider>(
        builder: (context, salesProvider, _) {
          if (salesProvider.cartItems.isEmpty) {
            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxHeight < 110) {
                  return Center(
                    child: Text(
                      'Cart is Empty',
                      style: TextStyle(
                        fontSize: context.responsive.bodySmall,
                        color: PosAppTheme.textGray,
                      ),
                    ),
                  );
                }

                return Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: EdgeInsets.all(context.responsive.paddingLarge),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shopping_cart_outlined,
                            size: context.responsive.iconLarge,
                            color: PosAppTheme.textGray,
                          ),
                          SizedBox(height: context.responsive.paddingMedium),
                          Text(
                            'Cart is Empty',
                            style: TextStyle(
                              fontSize: context.responsive.bodyMedium,
                              color: PosAppTheme.textGray,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          }

          return ListView.builder(
            padding: EdgeInsets.all(context.responsive.paddingSmall),
            itemCount: salesProvider.cartItems.length,
            itemBuilder: (context, index) => _buildCartItemTile(
              salesProvider.cartItems[index],
              context,
            ),
          );
        },
      );

  Widget _buildCartItemTile(dynamic cartItem, BuildContext context) {
    final responsive = context.responsive;
    return Card(
      margin: EdgeInsets.symmetric(
        vertical: responsive.paddingXSmall,
        horizontal: 0,
      ),
      child: Padding(
        padding: EdgeInsets.all(responsive.paddingSmall),
        child: Column(
          children: [
            // Item Header with Image
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product Image
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: ProductImage(
                            path: cartItem.product.imagePath,
                            fit: BoxFit.cover,
                            width: 70,
                            height: 70,
                            placeholderIcon:
                                Icons.image_not_supported_outlined,
                            placeholderColor: Colors.grey[400],
                            placeholderSize: 30,
                          ),
                        ),
                ),
                SizedBox(width: responsive.paddingSmall),
                // Product Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cartItem.product.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: responsive.bodyMedium,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: responsive.paddingXSmall),
                      Text(
                        'Rs. ${cartItem.unitPrice.toStringAsFixed(2)}'
                        '${cartItem.product.soldByWeight ? ' /kg' : cartItem.loose ? ' /pc' : cartItem.isBox ? ' /box' : ''}',
                        style: TextStyle(
                          fontSize: responsive.bodySmall,
                          color: PosAppTheme.textGray,
                        ),
                      ),
                    ],
                  ),
                ),
                // Big, easy-to-hit remove control for touch screens —
                // deletes the whole line from the cart.
                Material(
                  color: PosAppTheme.dangerRed.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      context
                          .read<SalesProvider>()
                          .removeFromCart(cartItem.id);
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.delete_outline,
                        color: PosAppTheme.dangerRed,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Quantity Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  height: responsive.buttonHeightSmall,
                  child: Row(
                    children: [
                      IconButton(
                        iconSize: responsive.iconSmall,
                        icon: const Icon(Icons.remove),
                        onPressed: () {
                          final step =
                              cartItem.product.soldByWeight ? 0.25 : 1.0;
                          if (cartItem.quantity - step > 0) {
                            context
                                .read<SalesProvider>()
                                .updateCartItemQuantity(
                                  cartItem.id,
                                  cartItem.quantity - step,
                                );
                          } else {
                            // At the minimum quantity, minus removes the
                            // line entirely.
                            context
                                .read<SalesProvider>()
                                .removeFromCart(cartItem.id);
                          }
                        },
                      ),
                      InkWell(
                        onTap: cartItem.product.soldByWeight
                            ? () async {
                                final w =
                                    await _promptWeight(cartItem.product);
                                if (w != null) {
                                  await context
                                      .read<SalesProvider>()
                                      .updateCartItemQuantity(
                                        cartItem.id,
                                        w,
                                      );
                                }
                              }
                            : null,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: responsive.paddingSmall,
                          ),
                          child: Text(
                            _cartLineQtyLabel(cartItem),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: responsive.bodyMedium,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        iconSize: responsive.iconSmall,
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          final step =
                              cartItem.product.soldByWeight ? 0.25 : 1.0;
                          context.read<SalesProvider>().updateCartItemQuantity(
                                cartItem.id,
                                cartItem.quantity + step,
                              );
                        },
                      ),
                    ],
                  ),
                ),
                Text(
                  'Rs. ${cartItem.total.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: responsive.bodyMedium,
                    color: PosAppTheme.primaryGreen,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Cart-line quantity with its selling unit:
  /// "0.500 kg" (weight), "3 pcs" (loose pieces), "2 boxes" (whole boxes),
  /// or a plain number for ordinary products.
  String _cartLineQtyLabel(dynamic item) {
    if (item.product.soldByWeight == true) {
      return '${MoneyCalculator.formatQty(item.quantity, byWeight: true)} kg';
    }
    if (item.loose == true) {
      final n = MoneyCalculator.formatQty(item.quantity);
      return '$n pc${item.quantity == 1 ? '' : 's'}';
    }
    if (item.isBox == true) {
      final n = MoneyCalculator.formatQty(item.quantity);
      return '$n box${item.quantity == 1 ? '' : 'es'}';
    }
    return MoneyCalculator.formatQty(item.quantity);
  }

  Widget _buildPaymentSection() {
    final responsive = context.responsive;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            offset: const Offset(0, -4),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.all(responsive.paddingMedium),
              child: Consumer<SettingsProvider>(
                builder: (context, settingsProvider, _) {
                  final currency = settingsProvider.settings.currencySymbol;
                  return Consumer<SalesProvider>(
                    builder: (context, salesProvider, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Customer (optional, compact) ──────────
                        Consumer<CustomerProvider>(
                          builder: (context, custProv, _) {
                            return DropdownButtonFormField<String>(
                              initialValue: _selectedCustomerId,
                              isDense: true,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Customer (optional)',
                                prefixIcon: const Icon(Icons.person, size: 20),

                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              items: [
                                for (final c in custProv.customers)
                                  DropdownMenuItem(
                                    value: c.id,
                                    child: Text('${c.name}  (${c.phone})'),
                                  ),
                              ],
                              onChanged: (id) {
                                setState(() {
                                  _selectedCustomerId = id;
                                });
                              },
                            );
                          },
                        ),
                        SizedBox(height: responsive.paddingXSmall),
                        // ── Discount (exact % or exact Rs) ─────────
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: salesProvider.cartItems.isEmpty
                                    ? null
                                    : _showDiscountDialog,
                                icon: const Icon(Icons.percent, size: 18),
                                label: Text(
                                  salesProvider.totalDiscount > 0
                                      ? 'Discount: $currency ${salesProvider.totalDiscount.toStringAsFixed(2)}'
                                      : 'Add Discount',
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: PosAppTheme.primaryGreen,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                            if (salesProvider.totalDiscount > 0)
                              IconButton(
                                tooltip: 'Remove discount',
                                icon: const Icon(Icons.close, size: 18),
                                color: PosAppTheme.dangerRed,
                                onPressed: () => context
                                    .read<SalesProvider>()
                                    .setGlobalDiscount(0),
                              ),
                          ],
                        ),
                        SizedBox(height: responsive.paddingXSmall),
                        // ── Payment Method ─────────────────────────
                        if (salesProvider.totalDiscount != 0)
                          Padding(
                            padding: EdgeInsets.only(
                                bottom: responsive.paddingXSmall),
                            child: Text(
                              'Subtotal $currency ${salesProvider.subtotal.toStringAsFixed(2)}'
                              '   ·   Discount -$currency '
                              '${salesProvider.totalDiscount.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: responsive.bodyTiny,
                                color: PosAppTheme.textGray,
                              ),
                            ),
                          ),
                        Consumer<PaymentProvider>(
                          builder: (context, paymentProvider, _) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              PaymentMethodSelector(
                                selectedMethod:
                                    paymentProvider.selectedPaymentMethod,
                                onMethodSelected: (method) {
                                  paymentProvider.setPaymentMethod(method);
                                  setState(() {});
                                },
                                enabledMethods:
                                    paymentProvider.enabledPaymentMethods,
                              ),
                              if (paymentProvider.selectedPaymentMethod !=
                                  PaymentMethod.cash)
                                PaymentMethodDetailsForm(
                                  paymentMethod:
                                      paymentProvider.selectedPaymentMethod,
                                  onDetailsChanged: (details) {
                                    paymentProvider.setPaymentDetails(details);
                                  },
                                ),
                            ],
                          ),
                        ),
                        SizedBox(height: responsive.paddingXSmall),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          _buildPaymentFooter(responsive),
        ],
      ),
    );
  }

  /// Pinned footer: total, amount entry, change and Pay / Hold / Clear are
  /// always visible — nothing in the payment bar ever requires scrolling.
  Widget _buildPaymentFooter(ResponsiveSize responsive) {
    return Consumer3<SalesProvider, PaymentProvider, SettingsProvider>(
      builder: (context, salesProvider, paymentProvider, settingsProvider, _) {
        final method = paymentProvider.selectedPaymentMethod;
        final isSplit = method == PaymentMethod.split;
        final cashEntry = double.tryParse(_paymentController.text) ?? 0;
        final cardEntry =
            isSplit ? (double.tryParse(_cardAmountController.text) ?? 0) : 0;
        final received = cashEntry + cardEntry;
        final total = salesProvider.total;
        final change = MoneyCalculator.calculateChange(received, total);
        final hasPayment = _paymentController.text.isNotEmpty ||
            isSplit && _cardAmountController.text.isNotEmpty;
        final isValidPayment =
            MoneyCalculator.isPaymentSufficient(received, total);
        final currency = settingsProvider.settings.currencySymbol;

        return Container(
          padding: EdgeInsets.all(responsive.paddingMedium),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'TOTAL DUE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: PosAppTheme.textGray,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  Text(
                    '$currency ${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: PosAppTheme.primaryGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // ── Amount entry (always visible) ─────────────────
              if (method == PaymentMethod.card)
                _buildCardExactBox(currency, total)
              else
                _buildAmountFields(currency, isSplit, responsive),
              if (isSplit && cashEntry > 0 && cashEntry < total)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Card must cover at least $currency '
                    '${(total - cashEntry).clamp(0.0, total).toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: PosAppTheme.textGray,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              if (hasPayment)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Text(
                        'Paid $currency ${received.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Change: $currency ${change.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isValidPayment
                              ? PosAppTheme.successGreen
                              : PosAppTheme.dangerRed,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: PosAppTheme.primaryGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed:
                    salesProvider.cartItems.isEmpty ? null : _processSale,
                icon: const Icon(Icons.point_of_sale, size: 22),
                label: Text(
                  'Pay  ·  $currency ${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: salesProvider.cartItems.isEmpty
                          ? null
                          : () {
                              salesProvider.holdBill();
                              _showSnackBar('Bill held successfully',
                                  isSuccess: true);
                              _clearForm();
                            },
                      icon: const Icon(Icons.pause, size: 18),
                      label: Text(
                        'Hold Bill',
                        style: TextStyle(fontSize: responsive.bodySmall),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: salesProvider.cartItems.isEmpty
                          ? null
                          : () {
                              salesProvider.clearCart();
                              _clearForm();
                            },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(
                        'Clear',
                        style: TextStyle(fontSize: responsive.bodySmall),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Prominent, filled input for the cash portion of the payment. Styled to be
  /// impossible to miss, with the currency prefix built in.
  Widget _buildAmountField({
    required TextEditingController controller,
    required String label,
    required String currency,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEFF7F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PosAppTheme.primaryGreen, width: 1.6),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: Colors.black87,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          prefixText: '$currency ',
          prefixStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: PosAppTheme.primaryGreen,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          focusedBorder: InputBorder.none,
          enabledBorder: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildAmountFields(
    String currency,
    bool isSplit,
    ResponsiveSize responsive,
  ) {
    return Row(
      children: [
        Expanded(
          child: _buildAmountField(
            controller: _paymentController,
            label: isSplit ? 'Cash Amount' : 'Amount Received',
            currency: currency,
          ),
        ),
        if (isSplit) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _buildAmountField(
              controller: _cardAmountController,
              label: 'Card Amount',
              currency: currency,
            ),
          ),
        ],
      ],
    );
  }

  /// Card payments always charge the exact total, shown prominently.
  Widget _buildCardExactBox(String currency, double total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: PosAppTheme.accentBlue.withOpacity(0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: PosAppTheme.accentBlue.withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Row(
            children: [
              Icon(
                Icons.credit_card,
                color: PosAppTheme.accentBlue,
                size: 22,
              ),
              SizedBox(width: 8),
              Text(
                'Card — charge the exact total',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          Text(
            '$currency ${total.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: PosAppTheme.accentBlue,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact toast that floats at the top-right of the POS screen (above the
/// cart column). Inserted as an [OverlayEntry] by `_showSnackBar`.
class _PosToast extends StatefulWidget {
  const _PosToast({required this.message, required this.isSuccess});

  final String message;
  final bool isSuccess;

  @override
  State<_PosToast> createState() => _PosToastState();
}

class _PosToastState extends State<_PosToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isSuccess
        ? PosAppTheme.successGreen
        : PosAppTheme.dangerRed;
    return Positioned(
      top: 72,
      right: 16,
      child: FadeTransition(
        opacity: _controller,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.15, -0.1),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: _controller,
            curve: Curves.easeOutCubic,
          )),
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 320),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.isSuccess
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
