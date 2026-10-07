import 'package:intl/intl.dart';

/// The ONE currency formatter used by the entire dashboard and shell.
///
/// ```
/// AppMoney.format(14770)      -> "Rs 14,770.00"
/// AppMoney.compact(14770)    -> "Rs 14.8K"
/// ```
///
/// The prefix is derived from `ShopSettings.currencySymbol` but always
/// rendered without a trailing dot ("Rs", never "Rs."). `ShopSettings` itself
/// is never modified — call [configure] once the settings are loaded.
///
/// Call [configure] from the presentation layer only (shell / dashboard).
/// Until it is called the formatter falls back to "Rs", so nothing can render
/// an empty or broken prefix.
abstract final class AppMoney {
  AppMoney._();

  static const String defaultPrefix = 'Rs';

  static String _prefix = defaultPrefix;

  /// Normalised currency prefix, e.g. `Rs`.
  static String get prefix => _prefix;

  static final NumberFormat _full = NumberFormat('#,##0.00');
  static final NumberFormat _whole = NumberFormat('#,##0');
  static final NumberFormat _oneDp = NumberFormat('#,##0.#');
  static final NumberFormat _twoDp = NumberFormat('#,##0.##');
  static final NumberFormat _pct = NumberFormat('#,##0.0');

  /// Feeds the shop's configured symbol into the formatter.
  ///
  /// * `null` / blank -> `Rs`
  /// * `"Rs."` / `"rs"` / `" Rs "` -> `Rs`
  /// * anything else is passed through, still with any trailing dot removed.
  static void configure({String? currencySymbol}) {
    _prefix = normalizePrefix(currencySymbol);
  }

  /// The normalisation rule, exposed so it can be unit-reasoned about.
  static String normalizePrefix(String? symbol) {
    if (symbol == null) return defaultPrefix;
    var s = symbol.trim();
    // Strip trailing dots, dashes and spaces ("Rs." -> "Rs").
    while (s.isNotEmpty) {
      final last = s[s.length - 1];
      if (last == '.' || last == ' ' || last == '-') {
        s = s.substring(0, s.length - 1);
      } else {
        break;
      }
    }
    s = s.trim();
    if (s.isEmpty) return defaultPrefix;
    if (s.toLowerCase() == 'rs') return 'Rs';
    return s;
  }

  /// Guards against NaN / infinity reaching the UI.
  static double _safe(num v) {
    final d = v.toDouble();
    if (d.isNaN) return 0;
    if (d == double.infinity) return 0;
    if (d == double.negativeInfinity) return 0;
    return d;
  }

  // -------------------------------------------------------------------------
  // Full precision
  // -------------------------------------------------------------------------

  /// `14,770.00` — no currency prefix.
  static String plain(num value) => _full.format(_safe(value));

  /// `Rs 14,770.00`
  static String format(num value) => '$_prefix ${plain(value)}';

  /// `1,240` — whole numbers with separators, for counts.
  static String integer(num value) => _whole.format(_safe(value));

  // -------------------------------------------------------------------------
  // Compact — for tiles, axis ticks and any tight space
  // -------------------------------------------------------------------------

  /// The suffix a compact value should carry, or `null` when the number is
  /// small enough to show in full.
  static String _suffixFor(double v) {
    final a = v.abs();
    if (a >= 10000000) return 'Cr';
    if (a >= 100000) return 'L';
    if (a >= 1000) return 'K';
    return '';
  }

  static double _scaled(double v) {
    final a = v.abs();
    if (a >= 10000000) return v / 10000000;
    if (a >= 100000) return v / 100000;
    if (a >= 1000) return v / 1000;
    return v;
  }

  /// `Rs 14.8K` · `Rs 1.23M`-style lakh/crore scaling where the locale uses it
  /// · `Rs 950` below a thousand.
  static String compact(num value) => '$_prefix ${compactPlain(value)}';

  /// Same as [compact] but without the currency prefix.
  ///
  /// K keeps 1 decimal, L/Cr keep 2 (trimmed), sub-thousand values are whole.
  static String compactPlain(num value) {
    final v = _safe(value);
    final suffix = _suffixFor(v);
    if (suffix.isEmpty) return _whole.format(v);
    final scaled = _scaled(v);
    return '${suffix == 'K' ? _oneDp.format(scaled) : _twoDp.format(scaled)}$suffix';
  }

  /// Chart-axis friendly: same rules as [compactPlain] but never carries a
  /// currency prefix, so ticks stay short.
  static String axis(num value) => compactPlain(value);

  // -------------------------------------------------------------------------
  // Deltas, percentages and counts
  //
  // CONTRACT: every "ratio" helper below returns a FRACTION (0.1234 == 12.34%)
  // and every "format" helper does the x100 itself. Never mix the two up.
  // -------------------------------------------------------------------------

  /// `+12.3%` / `-8.1%` / `0.0%` — takes a **fraction**.
  static String signedPercent(num fraction) {
    final v = _safe(fraction);
    final body = '${_pct.format((v * 100).abs())}%';
    if (v > 0) return '+$body';
    if (v < 0) return '-$body';
    return body;
  }

  /// `12.3%` — unsigned, for a profit-margin readout. Takes a **fraction**.
  static String percent(num fraction) =>
      '${_pct.format(_safe(fraction) * 100)}%';

  /// `part / total` as a fraction, or `null` when [total] is 0 so the caller
  /// can render "no prior data" instead of a fake 0%.
  static double? ratio(num part, num total) {
    final t = total.toDouble();
    if (t == 0 || t.isNaN) return null;
    return part / t;
  }

  /// Percentage of [part] out of [total], with a safe 0 fallback.
  static double ratioOrZero(num part, num total) => ratio(part, total) ?? 0;

  /// Relative change from [previous] to [current] as a **fraction**
  /// (0.20 == +20%). Returns `null` when there is no usable previous value
  /// (zero, null or non-finite).
  ///
  /// Returning `null` is deliberate: the caller must then show an explicit
  /// "no prior data" chip instead of an infinite or fabricated percentage.
  /// Feed the result straight into [signedPercent].
  static double? trend({required num current, required num? previous}) {
    if (previous == null) return null;
    final p = previous.toDouble();
    if (p == 0 || p.isNaN || p.isInfinite) return null;
    final c = current.toDouble();
    if (c.isNaN || c.isInfinite) return null;
    return (c - p) / p.abs();
  }
}
