import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Physical pixel bounds of a single display monitor.
class MonitorBounds {
  const MonitorBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.isPrimary,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;
  final bool isPrimary;

  int get width => right - left;
  int get height => bottom - top;

  @override
  String toString() =>
      'MonitorBounds($left,$top,$width x $height, primary: $isPrimary)';
}

/// Enumerates the connected displays so the app can decide where to place
/// the cashier and customer windows. All values are physical pixels.
class DisplayService {
  const DisplayService._();

  static List<MonitorBounds>? _collector;

  static int _monitorCallback(
    int hMonitor,
    int hdc,
    Pointer<NativeType> lprc,
    int lparam,
  ) {
    final info = calloc<MONITORINFO>();
    try {
      info.ref.cbSize = sizeOf<MONITORINFO>();
      if (GetMonitorInfo(hMonitor, info) != 0) {
        final r = info.ref.rcMonitor;
        _collector?.add(MonitorBounds(
          left: r.left,
          top: r.top,
          right: r.right,
          bottom: r.bottom,
          isPrimary: (info.ref.dwFlags & MONITORINFOF_PRIMARY) != 0,
        ));
      }
    } finally {
      calloc.free(info);
    }
    return 1;
  }

  static List<MonitorBounds> monitors() {
    final result = <MonitorBounds>[];
    _collector = result;
    try {
      final callback =
          Pointer.fromFunction<MONITORENUMPROC>(_monitorCallback, 0);
      EnumDisplayMonitors(0, nullptr, callback, 0);
    } finally {
      _collector = null;
    }
    return result;
  }

  /// The primary display, falling back to the first monitor found.
  static MonitorBounds? primary() {
    final all = monitors();
    if (all.isEmpty) return null;
    for (final m in all) {
      if (m.isPrimary) return m;
    }
    return all.first;
  }

  /// The first non-primary display, or null when only one screen is present.
  static MonitorBounds? secondary() {
    final all = monitors();
    for (final m in all) {
      if (!m.isPrimary) return m;
    }
    return null;
  }
}
