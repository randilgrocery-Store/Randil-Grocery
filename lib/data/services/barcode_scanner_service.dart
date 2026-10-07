import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Which physical scanner is in use.
///
/// The shop runs two USB HID barcode scanners at the same time:
///
///  * **Counter scanner** — Unitech MS838-2UCBOS-G / MS838-2D Bacoustic,
///    used by the cashier to scan goods into a bill on the POS screen.
///  * **Stock scanner** — Zebra DS9308 2D Varcode, used while receiving a
///    delivery on the GRN screen.
///
/// Both devices are keyboard-wedge scanners: they type the barcode at
/// impossible typing speed and finish with Enter. Windows therefore delivers
/// their input as ordinary key events, which is why a plain TextField with
/// `onSubmitted` already works. This service exists to make that reliable and
/// to guarantee that only the *active* screen reacts — otherwise a scan meant
/// for the counter would be interpreted by the GRN form behind it.
enum ScannerZone { none, counter, stock }

/// Coordinates the two scanners.
///
/// Exactly one screen may own the scanners at a time. When a new screen claims
/// ownership the previous owner is released, so a scan is never handled twice
/// and never silently dropped into an inactive form.
class BarcodeScannerService {
  BarcodeScannerService._internal();
  static final BarcodeScannerService instance = BarcodeScannerService._internal();

  int? _ownerToken;
  FocusNode? _focusNode;
  Future<void> Function(String barcode)? _handler;

  /// The last barcode that was dispatched, and when. Only the *same* barcode is
  /// suppressed inside [duplicateWindowMs] — see [submit].
  String? _lastCode;
  int _lastHandledAtMs = 0;

  ScannerZone get zone => _ownerToken == null ? ScannerZone.none : _zone;
  ScannerZone _zone = ScannerZone.none;

  bool get hasOwner => _ownerToken != null;

  /// Shortest gap allowed between two scanner keystrokes before the input is
  /// treated as a real hardware scan rather than human typing.
  static const int maxKeyGapMs = 40;

  /// A scan must be at least this long to be trusted. Real retail barcodes are
  /// longer, and this stops stray keypresses from triggering a lookup.
  static const int minBarcodeLength = 4;

  /// How long the *same* barcode is ignored when it arrives twice.
  ///
  /// One physical scan can be reported twice: once by the field's
  /// `onSubmitted` and once by the root key listener. Only that duplicate is
  /// filtered. A different barcode is never suppressed, so two items scanned
  /// back to back both reach the cart.
  static const int duplicateWindowMs = 400;

  /// Claims the scanners for [token].
  ///
  /// [focusNode] is refocused automatically so the operator never has to click
  /// the input box between scans — this is what makes hands-free scanning
  /// reliable.
  void claim({
    required int token,
    required ScannerZone zone,
    required FocusNode focusNode,
    required Future<void> Function(String barcode) onBarcode,
  }) {
    _ownerToken = token;
    _zone = zone;
    _focusNode = focusNode;
    _handler = onBarcode;
    // A newly opened screen must not inherit the previous screen's
    // de-duplication state, or its first scan could be swallowed.
    _lastCode = null;
    _lastHandledAtMs = 0;
    // Listening at the hardware level is what makes a scan land even when the
    // search box has lost focus.
    _installKeyHandler();

    // Give the field focus after the current frame so it does not steal focus
    // from a dialog that is still opening.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_ownerToken != token) return;
      if (focusNode.canRequestFocus && !focusNode.hasFocus) {
        focusNode.requestFocus();
      }
    });
  }

  /// Releases ownership if [token] still owns it. Safe to call from dispose.
  void release(int token) {
    if (_ownerToken != token) return;
    _ownerToken = null;
    _zone = ScannerZone.none;
    _focusNode = null;
    _handler = null;
    _lastCode = null;
    _lastHandledAtMs = 0;
    _removeKeyHandler();
  }

  /// Temporarily stops dispatching — used while a modal dialog is open so the
  /// dialog's own field is the only thing interpreting keys. [release] is
  /// unaffected, so a screen that is merely showing a dialog keeps ownership.
  void setSuspended(bool suspended) {
    _suspended = suspended;
    if (!suspended) {
      refocus();
    }
  }

  bool _suspended = false;

  // ---------------------------------------------------------------------------
  // Focus-independent capture.
  //
  // A keyboard-wedge scanner delivers keystrokes to whatever has focus. When the
  // search box does not hold focus - because the cashier clicked a product card,
  // tabbed away, or a dialog left focus on nothing - the barcode is typed into
  // the void: nothing reaches `onSubmitted` and the item never lands in the cart.
  //
  // The buffer below listens at the hardware level instead, so a scan is caught
  // no matter where focus happens to be. It only accepts input that arrives at
  // scanner speed, so ordinary typing is never mistaken for a scan. When the
  // search box *does* have focus the same barcode is reported twice (once here,
  // once by `onSubmitted`); the duplicate filter in `submit` absorbs that.
  // ---------------------------------------------------------------------------

  final StringBuffer _scanBuffer = StringBuffer();
  final List<int> _scanKeyGapsMs = <int>[];
  int _lastScanKeyAtMs = 0;
  bool _keyHandlerInstalled = false;

  bool _handleScannerKeys(KeyEvent event) {
    final owner = _ownerToken;
    if (owner == null || _suspended) return false;

    if (event is! KeyDownEvent) return false;

    // Never treat our own modifier combinations as barcode characters.
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isShiftPressed) {
      return false;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final code = _scanBuffer.toString();
      _scanBuffer.clear();
      _scanKeyGapsMs.clear();
      _lastScanKeyAtMs = 0;
      if (code.length >= minBarcodeLength && looksLikeScannerInput(_scanKeyGapsMs)) {
        unawaited(submit(code));
      }
      return false;
    }

    final char = _characterFor(event.character);
    if (char == null) return false;

    // A pause longer than a human keystroke means the previous burst is over.
    final gap = _lastScanKeyAtMs == 0 ? 0 : now - _lastScanKeyAtMs;
    if (_lastScanKeyAtMs != 0 && gap > maxKeyGapMs) {
      _scanBuffer.clear();
      _scanKeyGapsMs.clear();
    }
    _lastScanKeyAtMs = now;
    _scanKeyGapsMs.add(gap);

    // Guard against a runaway buffer if Enter never arrives.
    if (_scanBuffer.length > 64) {
      _scanBuffer.clear();
      _scanKeyGapsMs.clear();
    }
    _scanBuffer.write(char);
    return false;
  }

  /// The character a key event produced, or null when the key is not text.
  static String? _characterFor(String? character) {
    if (character == null || character.isEmpty) return null;
    final code = character.codeUnitAt(0);
    // Printable ASCII only: barcodes are digits and upper-case letters.
    if (code >= 0x20 && code <= 0x7E) return character;
    return null;
  }

  void _installKeyHandler() {
    if (_keyHandlerInstalled) return;
    _keyHandlerInstalled = true;
    HardwareKeyboard.instance.addHandler(_handleScannerKeys);
  }

  void _removeKeyHandler() {
    if (!_keyHandlerInstalled) return;
    _keyHandlerInstalled = false;
    HardwareKeyboard.instance.removeHandler(_handleScannerKeys);
    _scanBuffer.clear();
    _scanKeyGapsMs.clear();
    _lastScanKeyAtMs = 0;
  }

  /// Routes one completed (Enter-terminated) barcode.
  ///
  /// [viaField] marks a report that came from the owning screen's own
  /// TextField. It is accepted for call-site clarity; the duplicate filter
  /// below is keyed on the barcode itself, so it does not depend on knowing
  /// which path a scan arrived by.
  Future<void> submit(String raw, {bool viaField = false}) async {
    final code = raw.trim();
    if (code.length < minBarcodeLength) return;

    final handler = _handler;
    if (handler == null || _suspended) return;

    // The same scan can reach us twice within a few hundred milliseconds (once
    // from the field's onSubmitted, once from the root key listener). Ignore
    // that repeat so an item is never added to the cart twice.
    //
    // Only the SAME barcode is suppressed: this used to be a plain time window,
    // which silently dropped any second item scanned within 400 ms and so lost
    // sales at a busy counter.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (code == _lastCode && now - _lastHandledAtMs < duplicateWindowMs) {
      return;
    }
    _lastCode = code;
    _lastHandledAtMs = now;

    try {
      await handler(code);
    } catch (e, stack) {
      developer.log(
        'Barcode handler failed for "$code": $e',
        name: 'BarcodeScannerService',
        stackTrace: stack,
      );
    }
  }

  /// Re-requests focus for the owning screen. Called after a dialog closes.
  void refocus() {
    final node = _focusNode;
    if (node == null || !node.canRequestFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!node.hasFocus) node.requestFocus();
    });
  }

  /// True when [keyGapMs] is fast enough to be a hardware scanner rather than a
  /// person typing. Exposed for tests.
  @visibleForTesting
  static bool looksLikeScannerInput(List<int> keyGapsMs) {
    if (keyGapsMs.isEmpty) return false;
    return keyGapsMs.every((gap) => gap <= maxKeyGapMs);
  }

  /// Test-only: installs an owner without needing a FocusNode or a live
  /// binding, so the routing and de-duplication rules can be unit tested.
  @visibleForTesting
  void claimForTesting({
    required int token,
    required Future<void> Function(String barcode) onBarcode,
  }) {
    _ownerToken = token;
    _zone = ScannerZone.counter;
    _focusNode = null;
    _handler = onBarcode;
    _lastCode = null;
    _lastHandledAtMs = 0;
  }

  /// Test-only: returns the singleton to a clean, unowned state.
  @visibleForTesting
  void resetForTesting() {
    _ownerToken = null;
    _zone = ScannerZone.none;
    _focusNode = null;
    _handler = null;
    _lastCode = null;
    _lastHandledAtMs = 0;
    _suspended = false;
    _removeKeyHandler();
  }
}
