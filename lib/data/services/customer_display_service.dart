import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import '../../presentation/providers/sales_provider.dart';

/// Owns the optional "Customer Display" window (second monitor) for the whole
/// app session.
///
/// The window is created ONCE when a user logs in and is kept alive for as
/// long as the app runs. It is never recreated, hidden or destroyed while
/// switching tabs, which keeps the main window responsive.
class CustomerDisplayService {
  CustomerDisplayService._();

  static final CustomerDisplayService instance = CustomerDisplayService._();

  WindowController? _window;
  SalesProvider? _salesProvider;
  bool _started = false;
  bool _hidden = false;

  bool get isConnected => _window != null && !_hidden;

  /// Reason the customer window failed to open/show, for user-facing errors.
  String? lastError;

  /// Starts the service. Should be called exactly once after login.
  Future<void> start({required SalesProvider salesProvider}) async {
    if (_salesProvider == null) {
      _salesProvider = salesProvider;
      salesProvider.addListener(_pushCart);
    }
    if (_started) return;
    _started = true;
    await _openWindow();
  }

  /// Opens (or re-shows) the customer display window.
  Future<bool> reopen() async {
    await _openWindow();
    return _window != null;
  }

  /// Hides the customer display window (if it is open/visible).
  Future<void> close() async {
    final window = _window;
    if (window == null || _hidden) return;
    _hidden = true;
    try {
      await window.hide();
    } catch (e) {
      debugPrint('CustomerDisplayService: failed to hide window: $e');
      _hidden = false;
    }
  }

  /// Opens the display if hidden, hides it if showing. Returns the new
  /// visibility state (`true` = showing).
  Future<bool> toggle() async {
    if (_window != null && !_hidden) {
      await close();
      return false;
    }
    await _openWindow();
    return isConnected;
  }

  Future<void> _openWindow() async {
    if (!Platform.isWindows) return;

    if (_window == null) {
      try {
        // Always create a dedicated customer window. getAll() also returns the
        // main window, which must never be reused/hidden as the display.
        _window = await WindowController.create(
          const WindowConfiguration(arguments: ''),
        );
      } catch (e) {
        debugPrint('CustomerDisplayService: failed to open window: $e');
        lastError = e.toString();
        _window = null;
        return;
      }
    }

    if (_hidden) {
      _hidden = false;
      try {
        await _window!.show();
      } catch (e) {
        debugPrint('CustomerDisplayService: failed to show window: $e');
      }
      return;
    }

    try {
      await _window!.show();

      // Opening the extra window can drop the main window out of fullscreen on
      // some Windows setups, so re-assert it now that the display exists.
      await _ensureMainFullScreen();
    } catch (e) {
      debugPrint('CustomerDisplayService: failed to show window: $e');
      lastError = e.toString();
      _window = null;
      return;
    }
    lastError = null;

    // The sub-window registers its channel handler asynchronously; retry the
    // initial push for a short while.
    for (var attempt = 0; attempt < 5; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final ok = await _pushCart();
      if (ok) break;
    }
  }

  /// Keeps the cashier window filling the primary display.
  Future<void> _ensureMainFullScreen() async {
    try {
      await windowManager.ensureInitialized();
      await windowManager.setFullScreen(true);
    } catch (e) {
      debugPrint('CustomerDisplayService: could not set fullscreen: $e');
    }
  }

  /// Pushes the current cart state to the customer display now.
  Future<bool> syncNow() => _pushCart();

  Future<bool> _pushCart() async {
    final window = _window;
    final provider = _salesProvider;
    if (window == null || _hidden || provider == null) return false;

    final cartData = {
      'items': provider.cartItems
          .map((item) => {
                'name': item.product.name,
                'quantity': item.quantity,
                'price': item.unitPrice,
                'total': item.total,
              })
          .toList(),
      'total': provider.total,
      'subtotal': provider.subtotal,
      'discount': provider.totalDiscount,
    };

    try {
      const channel = WindowMethodChannel(
        'pos_channel',
        mode: ChannelMode.unidirectional,
      );
      await channel.invokeMethod('updateCart', jsonEncode(cartData));
      return true;
    } catch (e) {
      debugPrint('CustomerDisplayService: update push failed: $e');
      return false;
    }
  }
}