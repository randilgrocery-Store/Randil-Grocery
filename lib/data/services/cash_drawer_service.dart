import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../models/shop_settings.dart';
import 'windows_printer_service.dart';

/// Outcome of a single drawer command attempt.
///
/// [wasSent] is what the software can actually promise: the bytes were handed
/// to Windows. It is deliberately NOT called [opened] because a typical drawer
/// has no open/closed sensor, so the app can never confirm the mechanism moved.
enum DrawerOutcome { sent, alreadyHandled, disabled, busy, failed, notConfigured }

class DrawerResult {
  const DrawerResult(this.outcome, {this.message = '', this.printerName = ''});

  final DrawerOutcome outcome;

  /// Safe, cashier-facing text. Never contains payment or customer data.
  final String message;
  final String printerName;

  /// True only when a pulse was actually transmitted for this sale.
  bool get wasSent => outcome == DrawerOutcome.sent;

  /// True when nothing went wrong (including "nothing to do" cases).
  bool get isOk =>
      outcome == DrawerOutcome.sent ||
      outcome == DrawerOutcome.alreadyHandled ||
      outcome == DrawerOutcome.disabled;

  /// A real hardware failure that the operator may want to retry by hand.
  bool get needsAttention => outcome == DrawerOutcome.failed;
}

/// Central owner of every cash-drawer command.
///
/// Hardware: the shop uses a 3282 5kg steel drawer wired to the receipt printer
/// with an RJ11/RJ12 cable. Such drawers are opened by the printer's cash-drawer
/// output, which the ESC/POS `ESC p m t1 t2` command drives. Windows therefore
/// delivers the pulse to the *print spooler* of the selected receipt printer,
/// which is why this service only needs a printer name — the drawer itself is
/// dumb and needs no driver.
///
/// Design rules (see CASH_DRAWER_INTEGRATION_PLAN.md):
///  * at most one pulse per completed sale, ever;
///  * a drawer problem must never undo, duplicate or retry the sale;
///  * a pulse is only attempted after the sale is safely stored.
class CashDrawerService {
  factory CashDrawerService() => _instance;

  CashDrawerService._internal();
  static final CashDrawerService _instance = CashDrawerService._internal();

  final WindowsPrinterService _printer = WindowsPrinterService();

  /// Guards against a double tap / double Enter sending two pulses.
  bool _inFlight = false;

  String? lastError;

  /// Builds the raw ESC/POS drawer-open command.
  ///
  /// `ESC p m t1 t2`
  ///  * `m`  selects the drawer pin: 0 = pin 2 (default), 1 = pin 5.
  ///  * `t1` pulse-on  time in **2 ms units** (ESC/POS encodes it this way).
  ///  * `t2` pulse-off time in **2 ms units**.
  ///
  /// 120 ms on / 240 ms off (t1 = 60, t2 = 120) sits in the middle of the range
  /// every common metal drawer is specified for, so it opens reliably without
  /// cooking the solenoid.
  @visibleForTesting
  static Uint8List buildOpenCommand({
    required int pin,
    required int pulseOnMs,
    required int pulseOffMs,
  }) {
    final m = pin == 5 ? 0x01 : 0x00;
    final t1 = _toEscPosTime(pulseOnMs);
    final t2 = _toEscPosTime(pulseOffMs);
    return Uint8List.fromList(<int>[0x1B, 0x70, m, t1, t2]);
  }

  /// ESC/POS encodes the two pulse durations in 2 ms units, one byte each.
  static int _toEscPosTime(int milliseconds) {
    final units = (milliseconds / 2).round();
    return units.clamp(0, 255);
  }

  /// Resolves the printer that drives the drawer, falling back to the receipt
  /// printer when no dedicated drawer printer was chosen.
  static String resolvePrinterName(ShopSettings settings) {
    final drawerPrinter = settings.cashDrawerPrinterName.trim();
    if (drawerPrinter.isNotEmpty) return drawerPrinter;
    return settings.printerName.trim();
  }

  /// Sends one drawer pulse for a completed sale.
  ///
  /// [alreadyHandled] is supplied by the caller from the persisted
  /// `drawer_events` row so that exactly-once survives an app restart: after a
  /// crash between "pulse sent" and "receipt printed", relaunching the POS will
  /// not pop the drawer for the same sale again.
  Future<DrawerResult> openForSale({
    required bool alreadyHandled,
    required bool isCardOnly,
    required ShopSettings settings,
  }) async {
    if (!settings.cashDrawerEnabled) {
      return const DrawerResult(DrawerOutcome.disabled);
    }
    // Split payments always include cash, so they are never "card only".
    if (isCardOnly && !settings.cashDrawerOpenOnCardOnly) {
      return const DrawerResult(DrawerOutcome.disabled);
    }
    if (alreadyHandled) {
      return const DrawerResult(DrawerOutcome.alreadyHandled);
    }
    return _pulse(settings);
  }

  /// Fires one pulse with no sale attached — used by the "Test drawer" button
  /// in Settings and by the manual "Open drawer" button on the POS screen.
  /// Never touches sales, stock or reports.
  Future<DrawerResult> openManually(ShopSettings settings) => _pulse(settings);

  /// Returns the pulse bytes a receipt should carry, or null when no pulse is
  /// owed for this sale.
  ///
  /// This is the "drawer and bill together" path. The pulse is NOT sent here:
  /// it is prepended to the receipt bytes so Windows receives the drawer kick
  /// and the bill as one spooler job. Two separate jobs race — the receipt can
  /// come out first, or a mid-print error can swallow one half — and the
  /// customer is then handed a bill with the till still shut, or a drawer with
  /// no bill explaining the money in it.
  ///
  /// Nothing is recorded either: the caller owns the `drawer_events` row and
  /// must only write it once the combined job has actually been accepted.
  Future<Uint8List?> pulseBytesForSale({
    required bool alreadyHandled,
    required bool isCardOnly,
    required ShopSettings settings,
  }) async {
    if (!settings.cashDrawerEnabled) return null;
    // Split payments always include cash, so they are never "card only".
    if (isCardOnly && !settings.cashDrawerOpenOnCardOnly) return null;
    if (alreadyHandled) return null;
    if (resolvePrinterName(settings).isEmpty) return null;

    final bytes = buildOpenCommand(
      pin: settings.cashDrawerPin,
      pulseOnMs: settings.cashDrawerPulseOnMs,
      pulseOffMs: settings.cashDrawerPulseOffMs,
    );
    // Deliberately nothing between the pulse and the receipt. There is no
    // standard ESC/POS "wait" command, and the tempting ones are destructive:
    // `ESC t n` selects the international character set, so using it as a dwell
    // would silently change the glyphs on the customer's receipt. Thermal
    // firmware runs `ESC p` on its drawer output and keeps printing, so the
    // solenoid is already moving by the time the first text byte lands.
    return bytes;
  }

  Future<DrawerResult> _pulse(ShopSettings settings) async {
    if (_inFlight) {
      return const DrawerResult(
        DrawerOutcome.busy,
        message: 'Cash drawer command is already running.',
      );
    }

    final printerName = resolvePrinterName(settings);
    if (printerName.isEmpty) {
      lastError = 'No printer selected for the cash drawer.';
      return const DrawerResult(
        DrawerOutcome.notConfigured,
        message: 'No receipt printer is selected. '
            'Set one in Settings > Printer.',
      );
    }

    _inFlight = true;
    try {
      final command = buildOpenCommand(
        pin: settings.cashDrawerPin,
        pulseOnMs: settings.cashDrawerPulseOnMs,
        pulseOffMs: settings.cashDrawerPulseOffMs,
      );

      // `ignorePrinterStatus: true` — an empty paper roll or a printer jam must
      // not stop the drawer from opening after a paid sale.
      final ok = await Future<bool>.sync(
        () => _printer.printRaw(
          printerName,
          command,
          ignorePrinterStatus: true,
        ),
      );

      if (!ok) {
        lastError = _printer.lastError ?? 'Unknown printer error.';
        developer.log(
          'Cash drawer pulse failed: $lastError',
          name: 'CashDrawerService',
        );
        return DrawerResult(
          DrawerOutcome.failed,
          message: 'The cash drawer did not get the open command. '
              'Check the RJ11 cable and that the receipt printer is on.',
          printerName: printerName,
        );
      }

      lastError = null;
      return DrawerResult(DrawerOutcome.sent, printerName: printerName);
    } catch (e) {
      lastError = '$e';
      developer.log('Cash drawer pulse threw: $e', name: 'CashDrawerService');
      return DrawerResult(
        DrawerOutcome.failed,
        message: 'The cash drawer did not get the open command.',
        printerName: printerName,
      );
    } finally {
      _inFlight = false;
    }
  }
}
