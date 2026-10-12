/// Decodes the in-store barcode printed on labels by a label-printing
/// weighing scale (e.g. the Budry Electronics ABD-90 at the shop).
///
/// A scale labels a weighed item (bananas, bites mixture, rice...) with a
/// barcode that carries three things:
///
///   * a **prefix** that tells the POS "a scale made this" (usually `2`),
///   * the **item / PLU code** the shopkeeper programmed on the scale, and
///   * the **weight** (or price) the scale just measured.
///
/// The default layout is the common 12-digit format
///
///   `2` + `PPPPP` (item) + `WWWWW` (grams) + `C` (check digit)
///
/// so scanning `2 10012 00500 7` adds item `10012` at `0.500 kg`.
///
/// Everything is configurable in Settings → Label scale because scale
/// manufacturers split the digits differently; the configured split is tried
/// first and a few neighbouring item-code lengths are used as a fallback so a
/// mis-set split never blocks a sale.
class ScaleBarcodeConfig {
  const ScaleBarcodeConfig({
    this.enabled = false,
    this.prefix = '2',
    this.totalLength = 12,
    this.itemLength = 5,
    this.priceMode = false,
    this.checkDigit = true,
  });

  /// Master switch. When false the POS ignores scale decoding entirely.
  final bool enabled;

  /// Leading digit(s) that mark a scale barcode (default `2`).
  final String prefix;

  /// Total number of digits the scale prints.
  final int totalLength;

  /// Number of digits reserved for the item / PLU code.
  final int itemLength;

  /// When true the encoded value is a **price** (minor units, /100); when
  /// false it is a **weight in grams** (/1000 → kg). Weighed grocery items
  /// use weight mode.
  final bool priceMode;

  /// Whether the last digit is an EAN/UPC check digit (default yes).
  final bool checkDigit;

  int get prefixLength => prefix.length;

  /// Number of digits in the value (weight/price) region for [itemLength].
  int valueLengthFor(int itemLength) =>
      totalLength - prefixLength - itemLength - (checkDigit ? 1 : 0);
}

/// One successfully decoded scale barcode.
class ScaleBarcode {
  const ScaleBarcode({
    required this.raw,
    required this.itemCode,
    required this.value,
    required this.priceMode,
  });

  final String raw;
  final String itemCode;
  final int value;
  final bool priceMode;

  /// Weight in kilograms when [priceMode] is false (the value is grams).
  double get weightKg => value / 1000.0;

  /// Encoded amount when [priceMode] is true (the value is minor units).
  double get price => value / 100.0;
}

/// Pure, dependency-free decoder so it can be unit-tested exhaustively.
class ScaleBarcodeParser {
  ScaleBarcodeParser._();

  static final RegExp _digitsOnly = RegExp(r'^[0-9]+$');

  /// Decodes [raw] using [config]. Pass [itemLength] to override the configured
  /// item-code width (used by the fallback search in the POS and the Settings
  /// test box). Returns null when [raw] is not a valid scale barcode.
  static ScaleBarcode? decode(
    String raw,
    ScaleBarcodeConfig config, {
    int? itemLength,
  }) {
    if (!config.enabled) return null;

    final code = raw.trim();
    if (code.length != config.totalLength) return null;
    if (!_digitsOnly.hasMatch(code)) return null;

    final prefixLen = config.prefixLength;
    if (prefixLen > 0 && !code.startsWith(config.prefix)) return null;

    final il = itemLength ?? config.itemLength;
    final vl = config.valueLengthFor(il);
    if (il < 1 || vl < 1) return null;
    if (prefixLen + il + vl > code.length) return null;

    final itemCode = code.substring(prefixLen, prefixLen + il);
    final value = int.tryParse(
      code.substring(prefixLen + il, prefixLen + il + vl),
    );
    if (value == null) return null;

    return ScaleBarcode(
      raw: code,
      itemCode: itemCode,
      value: value,
      priceMode: config.priceMode,
    );
  }

  /// Item-code widths worth trying, the configured one first, so an
  /// incorrectly configured split still resolves when the product exists.
  static List<int> candidateItemLengths(ScaleBarcodeConfig config) {
    final prefixLen = config.prefixLength;
    final maxItem =
        config.totalLength - prefixLen - (config.checkDigit ? 1 : 0) - 1;
    final result = <int>[];
    void add(int length) {
      if (length >= 1 && length <= maxItem && !result.contains(length)) {
        result.add(length);
      }
    }

    add(config.itemLength);
    for (var length = 4; length <= 8; length++) {
      add(length);
    }
    return result;
  }
}
