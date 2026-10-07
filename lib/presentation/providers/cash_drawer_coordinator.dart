import 'dart:developer' as developer;
import 'dart:typed_data';

import '../../data/database/database_service.dart';
import '../../data/models/sale.dart';
import '../../data/models/shop_settings.dart';
import '../../data/services/cash_drawer_service.dart';

/// Bridges a completed sale to exactly one cash-drawer pulse.
///
/// This is the only place allowed to decide *whether* a pulse happens. The POS
/// screen simply reports "the sale is saved" and lets this decide, so the
/// checkout code can never grow its own drawer logic and drift out of sync.
class CashDrawerCoordinator {
  factory CashDrawerCoordinator() => _instance;

  CashDrawerCoordinator._internal();
  static final CashDrawerCoordinator _instance = CashDrawerCoordinator._internal();

  final CashDrawerService _drawer = CashDrawerService();
  final DatabaseService _db = DatabaseService();

  /// Returns the pulse bytes to prepend to this sale's receipt, or null when no
  /// pulse is owed.
  ///
  /// This is the normal path: the drawer kick and the bill go to Windows as one
  /// print job, so the drawer and the receipt reach the customer together. It
  /// sends nothing and writes nothing — the caller must call
  /// [recordEmbeddedPulse] once the combined job has actually been accepted, so
  /// a rejected job still leaves the pulse owed.
  Future<Uint8List?> pulseForReceipt({
    required Sale sale,
    required bool isCardOnly,
    required ShopSettings settings,
  }) async {
    try {
      return await _drawer.pulseBytesForSale(
        alreadyHandled: await _db.wasDrawerCommandSent(sale.id),
        isCardOnly: isCardOnly,
        settings: settings,
      );
    } catch (e) {
      // A drawer-bookkeeping problem must never block the customer's receipt.
      developer.log(
        'pulseForReceipt failed: $e',
        name: 'CashDrawerCoordinator',
      );
      return null;
    }
  }

  /// Records that a pulse travelling inside the receipt job was accepted.
  ///
  /// Only called after the combined job succeeds. If it fails the pulse never
  /// left the app, so the caller falls back to [openAfterSale], which sends it
  /// on its own with `ignorePrinterStatus` so an empty paper roll or a jam
  /// cannot leave the cash shut in the till.
  Future<void> recordEmbeddedPulse({
    required Sale sale,
    required bool isCardOnly,
    required String printerName,
  }) async {
    try {
      await _db.upsertDrawerEvent(
        saleId: sale.id,
        invoiceNumber: sale.invoiceNumber,
        isCardOnly: isCardOnly,
        status: 'sent',
        printerName: printerName,
        errorMessage: '',
      );
    } catch (e) {
      developer.log(
        'recordEmbeddedPulse failed: $e',
        name: 'CashDrawerCoordinator',
      );
    }
  }

  /// Opens the drawer for a sale that has already been stored.
  ///
  /// Safe to call repeatedly: the `drawer_events` row makes the pulse happen at
  /// most once per sale, even if the cashier taps twice or the app is restarted
  /// before the receipt is printed.
  Future<DrawerResult> openAfterSale({
    required Sale sale,
    required bool isCardOnly,
    required ShopSettings settings,
  }) async {
    if (!settings.cashDrawerEnabled) {
      return const DrawerResult(DrawerOutcome.disabled);
    }

    try {
      final alreadySent = await _db.wasDrawerCommandSent(sale.id);
      final result = await _drawer.openForSale(
        alreadyHandled: alreadySent,
        isCardOnly: isCardOnly,
        settings: settings,
      );

      // Only real attempts are persisted. "Disabled" and "already handled"
      // rows would be noise, and a failure row is kept so the POS can offer a
      // drawer-only retry that still can never double-pop a successful sale.
      if (result.outcome == DrawerOutcome.sent ||
          result.outcome == DrawerOutcome.failed) {
        await _db.upsertDrawerEvent(
          saleId: sale.id,
          invoiceNumber: sale.invoiceNumber,
          isCardOnly: isCardOnly,
          status: result.wasSent ? 'sent' : 'failed',
          printerName: result.printerName,
          errorMessage: result.wasSent ? '' : result.message,
        );
      }
      return result;
    } catch (e) {
      // Never let drawer bookkeeping escape into the sale path.
      developer.log('openAfterSale failed: $e', name: 'CashDrawerCoordinator');
      return DrawerResult(
        DrawerOutcome.failed,
        message: 'The cash drawer did not get the open command.',
      );
    }
  }

  /// Re-sends the pulse for a sale whose earlier attempt failed.
  ///
  /// Guarded by [wasDrawerCommandSent] so "Retry drawer" can never pop the
  /// drawer for a sale that already succeeded, and it never touches the sale.
  Future<DrawerResult> retryForSale({
    required Sale sale,
    required ShopSettings settings,
  }) async {
    if (await _db.wasDrawerCommandSent(sale.id)) {
      return const DrawerResult(
        DrawerOutcome.alreadyHandled,
        message: 'This drawer was already opened for this sale.',
      );
    }
    final result = await _drawer.openManually(settings);
    await _db.upsertDrawerEvent(
      saleId: sale.id,
      invoiceNumber: sale.invoiceNumber,
      isCardOnly: false,
      status: result.wasSent ? 'sent' : 'failed',
      printerName: result.printerName,
      errorMessage: result.wasSent ? '' : result.message,
    );
    return result;
  }

  /// Settings-screen diagnostic. No sale, no stock change, no report change.
  Future<DrawerResult> testOpen(ShopSettings settings) =>
      _drawer.openManually(settings);
}
