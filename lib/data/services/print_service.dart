import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import '../models/sale.dart';
import '../models/shop_settings.dart';
import 'windows_printer_service.dart';

class PrintService {
  factory PrintService() => _instance;

  PrintService._internal();
  static final PrintService _instance = PrintService._internal();

  /// Software developer details printed at the bottom of every bill.
  static const String developerName = 'Jerusha Tech Solutions';
  static const String developerPhone = '070 3027 611';
  static const String developerEmail = 'jerushasharon1999@gmail.com';

  Uint8List? _logoRasterCache;
  int? _logoRasterWidth;

  /// Converts a PNG logo into an ESC/POS raster (GS v 0) bitmap, centered
  /// on the receipt header. Returns null when the image cannot be decoded.
  Uint8List? buildLogoRaster(Uint8List pngBytes, {required int maxWidthDots}) {
    if (_logoRasterCache != null && _logoRasterWidth == maxWidthDots) {
      return _logoRasterCache;
    }
    try {
      final decoded = img.decodeImage(pngBytes);
      if (decoded == null) return null;

      // Trim near-white borders so the logo fills the receipt width instead
      // of wasting raster rows on empty margins.
      final cropped = _cropNearWhite(decoded) ?? decoded;

      // Keep the raster within the printer's receive buffer: oversized bitmaps
      // can be dropped silently, which shows up as "the logo doesn't print"
      // while the rest of the bill is fine. 256 dots is a good balance.
      const maxHeightDots = 256;
      var targetW = maxWidthDots;
      if (cropped.width < targetW) targetW = cropped.width;
      var targetH = (cropped.height * targetW / cropped.width).round();
      if (targetH > maxHeightDots) {
        targetH = maxHeightDots;
        targetW = (cropped.width * targetH / cropped.height)
            .round()
            .clamp(1, maxWidthDots)
            .toInt();
      }
      if (targetW < 1 || targetH < 1) return null;

      final resized = img.copyResize(
        cropped,
        width: targetW,
        height: targetH,
        interpolation: img.Interpolation.average,
      );

      final bytesPerRow = (targetW + 7) ~/ 8;
      final data = <int>[];
      for (var y = 0; y < targetH; y++) {
        for (var bx = 0; bx < bytesPerRow; bx++) {
          var byte = 0;
          for (var bit = 0; bit < 8; bit++) {
            final x = bx * 8 + bit;
            if (x >= targetW) continue;
            final p = resized.getPixel(x, y);
            final a = p.a.toInt();
            final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
            if (a > 128 && lum < 160) byte |= (0x80 >> bit);
          }
          data.add(byte);
        }
      }

      final raster = Uint8List.fromList(<int>[
        0x1D, 0x76, 0x30, 0x00, // GS v 0 m=0
        bytesPerRow & 0xFF, (bytesPerRow >> 8) & 0xFF,
        targetH & 0xFF, (targetH >> 8) & 0xFF,
        ...data,
      ]);
      _logoRasterCache = raster;
      _logoRasterWidth = maxWidthDots;
      return raster;
    } catch (_) {
      return null;
    }
  }

  /// Returns a copy of [image] with near-white borders removed, or null when
  /// the whole image is blank.
  img.Image? _cropNearWhite(img.Image image) {
    var minX = image.width;
    var minY = image.height;
    var maxX = -1;
    var maxY = -1;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        if (p.a.toInt() <= 128) continue;
        final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        if (lum < 235) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < minX || maxY < minY) return null;

    const pad = 4;
    minX = (minX - pad).clamp(0, image.width - 1).toInt();
    minY = (minY - pad).clamp(0, image.height - 1).toInt();
    maxX = (maxX + pad).clamp(0, image.width - 1).toInt();
    maxY = (maxY + pad).clamp(0, image.height - 1).toInt();
    final w = maxX - minX + 1;
    final h = maxY - minY + 1;
    if (w < 8 || h < 8) return null;
    return img.copyCrop(image, x: minX, y: minY, width: w, height: h);
  }

  int _logoWidthDots(int paperWidthMm) => paperWidthMm >= 72 ? 384 : 256;

  /// Generate receipt text for the on-screen bill preview / plain-text output.
  String generateReceiptText(
    Sale sale,
    ShopSettings settings, {
    bool includeBreaks = true,
  }) {
    final buffer = StringBuffer();
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final cols = _charsForPaperWidth(settings.paperWidth);
    final symbol = settings.currencySymbol;

    final taxAmount = settings.enableTax && settings.taxPercentage > 0
        ? (sale.totalAmount * settings.taxPercentage) / 100
        : 0.0;
    final qty = sale.items.fold<int>(0, (sum, item) => sum + item.quantity);
    final layout = _itemLayout(cols);

    // ---- Header ----
    if (includeBreaks) {
      buffer.writeln(_center(settings.shopName.toUpperCase(), width: cols));
      if (settings.address.isNotEmpty) {
        buffer.writeln(_center(settings.address, width: cols));
      }
      if (settings.phone.isNotEmpty) {
        buffer.writeln(_center('Phone: ${settings.phone}', width: cols));
      }
      buffer.writeln(_repeat('=', cols));
      buffer.writeln(_center('SALES RECEIPT', width: cols));
      buffer.writeln(_repeat('=', cols));
    }

    // ---- Bill info ----
    buffer.writeln(_pair('Invoice', sale.invoiceLabel, cols));
    buffer.writeln(_pair('Date', dateFormat.format(sale.saleDate), cols));
    buffer.writeln(_pair('Cashier', sale.cashierName, cols));
    buffer.writeln(_pair('Payment', sale.paymentMethod, cols));
    if (sale.notes.trim().isNotEmpty) {
      buffer.writeln(_pair('Notes', sale.notes.trim(), cols));
    }
    buffer.writeln(_repeat('-', cols));

    // ---- Items ----
    buffer.writeln(layout.header);
    buffer.writeln(_repeat('-', cols));

    var lineNo = 1;
    for (final item in sale.items) {
      final name = item.productName.trim().isEmpty
          ? 'Item $lineNo'
          : item.productName.trim();
      for (final line in layout.lines(
        name,
        item.quantity,
        item.price.toStringAsFixed(2),
        item.total.toStringAsFixed(2),
      )) {
        buffer.writeln(line);
      }
      if (item.discount > 0) {
        buffer.writeln(_pair(
          '   Discount ${item.discount.toStringAsFixed(2)}%',
          '-${item.discountAmount.toStringAsFixed(2)}',
          cols,
        ));
      }
      lineNo++;
    }
    buffer.writeln(_repeat('-', cols));

    // ---- Totals ----
    buffer.writeln(
        _pair('Subtotal', _formatCurrency(sale.subtotal, symbol), cols));
    if (sale.totalDiscount > 0) {
      buffer.writeln(_pair(
          'Discount', '-${_formatCurrency(sale.totalDiscount, symbol)}', cols));
    }
    if (taxAmount > 0) {
      buffer.writeln(_pair('Tax (${settings.taxPercentage}%)',
          _formatCurrency(taxAmount, symbol), cols));
    }
    buffer.writeln(_repeat('=', cols));
    buffer.writeln(
        _pair('TOTAL', _formatCurrency(sale.totalAmount, symbol), cols));
    buffer.writeln(
        _pair('Paid', _formatCurrency(sale.amountReceived, symbol), cols));
    buffer.writeln(
        _pair('Change', _formatCurrency(sale.balance, symbol), cols));
    buffer.writeln(_repeat('=', cols));
    buffer.writeln(_pair('Items / Qty', '${sale.items.length} / $qty', cols));

    // ---- Footer ----
    if (includeBreaks) {
      buffer.writeln(_repeat('-', cols));
      buffer.writeln(_center('Thank You! Please Visit Again', width: cols));
      buffer.writeln(_center('System developed by', width: cols));
      buffer.writeln(_center(developerName, width: cols));
      buffer.writeln(_center('Tel: $developerPhone', width: cols));
      buffer.writeln(_center(developerEmail, width: cols));
    }

    return buffer.toString();
  }

  /// Generate a proper ESC/POS byte stream for a thermal printer.
  /// When [logoBytes] (a PNG) is supplied it is rasterised and printed
  /// centered at the top of the bill.
  List<int> generateEscPosCommands(Sale sale, ShopSettings settings,
      {Uint8List? logoBytes}) {
    final commands = <int>[];
    const esc = 0x1B;
    const gs = 0x1D;

    final cols = _charsForPaperWidth(settings.paperWidth);
    // Printable area in dots (203dpi): 80mm -> 576, 58mm -> 384
    final areaDots = _printAreaDots(settings.paperWidth);
    final symbol = settings.currencySymbol;

    // Initialize printer
    commands.addAll([esc, 0x40]);

    // Reset print mode (Font A, single height, normal size)
    commands.addAll([esc, 0x21, 0x00]);

    // Force the full printable width for the detected paper size
    commands.addAll([gs, 0x57, areaDots & 0xFF, (areaDots >> 8) & 0xFF]); // GS W nL nH

    // Helper to emit a line with an alignment command.
    // alignment: 0=left 1=center 2=right (ESC a n)
    List<int> aligned(String text, {int alignment = 0, bool bold = false}) {
      final out = <int>[];
      out.addAll([esc, 0x61, alignment]); // ESC a n
      if (bold) out.addAll(_escBold(true));
      final line = _truncate(text, cols);
      for (final rune in line.runes) {
        out.add(rune < 0x100 ? rune : 0x3F);
      }
      out.addAll(const [0x0A]); // line feed
      if (bold) out.addAll(_escBold(false));
      commands.addAll(out);
      return out;
    }

    // Emit a line in the smaller (Font B) size. Used for the developer credit
    // so it consumes as little paper as possible.
    List<int> alignedSmall(String text, {int alignment = 1}) {
      final out = <int>[];
      out.addAll([esc, 0x61, alignment]);
      out.addAll([esc, 0x4D, 0x01]); // ESC M 1 -> Font B (small)
      final line = _truncate(text, cols);
      for (final rune in line.runes) {
        out.add(rune < 0x100 ? rune : 0x3F);
      }
      out.addAll(const [0x0A]);
      out.addAll([esc, 0x4D, 0x00]); // restore Font A
      commands.addAll(out);
      return out;
    }

    // Emit a line in double width + double height for emphasis (shop name,
    // TOTAL). A double-size character occupies two columns, so the text is
    // clipped to half the paper width.
    List<int> big(String text, {int alignment = 1}) {
      final out = <int>[];
      out.addAll([esc, 0x61, alignment]);
      out.addAll([esc, 0x21, 0x30]); // ESC ! 0x30 -> double width + height
      final line = _truncate(text, cols ~/ 2);
      for (final rune in line.runes) {
        out.add(rune < 0x100 ? rune : 0x3F);
      }
      out.addAll(const [0x0A]);
      out.addAll([esc, 0x21, 0x00]); // restore normal size
      commands.addAll(out);
      return out;
    }

    // ---- Logo (centered) ----
    if (logoBytes != null) {
      final raster = buildLogoRaster(logoBytes,
          maxWidthDots: _logoWidthDots(settings.paperWidth));
      if (raster != null) {
        commands.addAll([esc, 0x61, 0x01]); // center
        commands.addAll(raster);
        commands.addAll([0x0A]);
      }
    }

    // ---- Header ----
    big(settings.shopName.toUpperCase(), alignment: 1);
    if (settings.address.isNotEmpty) {
      aligned(settings.address, alignment: 1);
    }
    if (settings.phone.isNotEmpty) {
      aligned('Phone: ${settings.phone}', alignment: 1);
    }
    aligned(_repeat('=', cols));
    aligned('SALES RECEIPT', alignment: 1, bold: true);
    aligned(_repeat('=', cols));

    // ---- Bill info ----
    aligned(_pair('Invoice', sale.invoiceLabel, cols));
    aligned(_pair(
        'Date', DateFormat('yyyy-MM-dd HH:mm:ss').format(sale.saleDate), cols));
    aligned(_pair('Cashier', sale.cashierName, cols));
    aligned(_pair('Payment', sale.paymentMethod, cols));
    if (sale.notes.trim().isNotEmpty) {
      aligned(_pair('Notes', sale.notes.trim(), cols));
    }
    aligned(_repeat('-', cols));

    // ---- Items ----
    final layout = _itemLayout(cols);
    aligned(layout.header, bold: true);
    aligned(_repeat('-', cols));

    var lineNo = 1;
    for (final item in sale.items) {
      final name = item.productName.trim().isEmpty
          ? 'Item $lineNo'
          : item.productName.trim();
      for (final line in layout.lines(
        name,
        item.quantity,
        item.price.toStringAsFixed(2),
        item.total.toStringAsFixed(2),
      )) {
        aligned(line);
      }
      if (item.discount > 0) {
        aligned(_pair(
          '   Discount ${item.discount.toStringAsFixed(2)}%',
          '-${item.discountAmount.toStringAsFixed(2)}',
          cols,
        ));
      }
      lineNo++;
    }
    aligned(_repeat('-', cols));

    // ---- Totals ----
    final tax = settings.enableTax && settings.taxPercentage > 0
        ? (sale.totalAmount * settings.taxPercentage) / 100
        : 0.0;
    final qty = sale.items.fold<int>(0, (sum, item) => sum + item.quantity);

    aligned(_pair('Subtotal', _formatCurrency(sale.subtotal, symbol), cols));
    if (sale.totalDiscount > 0) {
      aligned(_pair(
          'Discount', '-${_formatCurrency(sale.totalDiscount, symbol)}', cols));
    }
    if (tax > 0) {
      aligned(_pair('Tax (${settings.taxPercentage}%)',
          _formatCurrency(tax, symbol), cols));
    }
    aligned(_repeat('=', cols));
    big('TOTAL  ${_formatCurrency(sale.totalAmount, symbol)}');
    aligned(_repeat('=', cols));
    aligned(_pair('Paid', _formatCurrency(sale.amountReceived, symbol), cols));
    aligned(_pair('Change', _formatCurrency(sale.balance, symbol), cols));
    aligned(_repeat('=', cols));
    aligned(_pair('Items / Qty', '${sale.items.length} / $qty', cols));

    // ---- Footer ----
    aligned(_repeat('-', cols));
    aligned('Thank You! Please Visit Again', alignment: 1, bold: true);
    // Developer credit: same centered lines as before, but in the smaller
    // Font B so it uses as little paper as possible.
    alignedSmall('System developed by');
    alignedSmall(developerName);
    alignedSmall('Tel: $developerPhone');
    alignedSmall(developerEmail);

    // Feed + cut paper (GS V 66 n: full cut)
    commands.addAll([esc, 0x64, 0x03]); // 3 line feeds
    commands.addAll([gs, 0x56, 0x42, 0x00]); // full cut

    return commands;
  }

  /// Print a sale receipt to a specific printer.
  /// Returns true if the raw data was submitted to the printer.
  bool printSale(Sale sale, ShopSettings settings, String printerName,
      {Uint8List? logoBytes}) {
    final bytes = Uint8List.fromList(
        generateEscPosCommands(sale, settings, logoBytes: logoBytes));
    final printer = WindowsPrinterService();
    final ok = printer.printRaw(printerName, bytes);
    _lastPrintError = printer.lastError;
    return ok;
  }

  String? _lastPrintError;
  String? get lastPrintError => _lastPrintError;

  /// Print a plain-text sales summary (used by reports) to a printer.
  bool printPlainText(String text, String printerName) {
    final printer = WindowsPrinterService();
    final ok = printer.printText(printerName, text);
    _lastPrintError = printer.lastError;
    return ok;
  }

  /// Print a fixed-width text report (sales/profit summaries) using ESC/POS so
  /// the column alignment, paper width and auto-cut work on thermal printers
  /// instead of relying on the Windows driver's default text mode.
  bool printReport(
    String text,
    String printerName, {
    int paperWidthMm = 80,
  }) {
    final bytes = Uint8List.fromList(_escPosFromText(text, paperWidthMm));
    final printer = WindowsPrinterService();
    final ok = printer.printRaw(printerName, bytes);
    _lastPrintError = printer.lastError;
    return ok;
  }

  List<int> _escPosFromText(String text, int paperWidthMm) {
    const esc = 0x1B;
    const gs = 0x1D;
    final cols = _charsForPaperWidth(paperWidthMm);
    final areaDots = _printAreaDots(paperWidthMm);
    final out = <int>[esc, 0x40, esc, 0x21, 0x00];
    out.addAll([gs, 0x57, areaDots & 0xFF, (areaDots >> 8) & 0xFF]);
    for (final rawLine in text.split('\n')) {
      final line = _truncate(rawLine.replaceAll('\r', ''), cols);
      for (final rune in line.runes) {
        out.add(rune < 0x100 ? rune : 0x3F);
      }
      out.add(0x0A);
    }
    out.addAll([esc, 0x64, 0x04]);
    out.addAll([gs, 0x56, 0x42, 0x00]);
    return out;
  }

  /// List available Windows printers.
  List<String> listPrinters() => WindowsPrinterService().listPrinters();

  /// Watch the printer for a short window after a job was submitted so that
  /// failures which only appear mid-print (paper running out, going offline,
  /// ...) are reported instead of a false success. Returns a problem message
  /// when detected, otherwise null.
  Future<String?> verifyPrint(
    String printerName, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final printer = WindowsPrinterService();
    final problem =
        await printer.verifyPrinterHealth(printerName, timeout: timeout);
    if (problem != null) {
      _lastPrintError = problem;
    }
    return problem;
  }

  /// Select the best available printer for bill printing.
  /// Prefers the configured printer, then a receipt-themed printer name
  /// (contains xp / 80 / 58 / thermal / pos / receipt), otherwise falls back
  /// to the first available printer.
  String selectPrinter(List<String> printers, String configured) {
    final trimmed = configured.trim();
    if (trimmed.isNotEmpty && printers.contains(trimmed)) return trimmed;

    const keywords = ['xp', '80', '58', 'thermal', 'pos', 'receipt', 'esc', 'epson', 'star'];
    for (final p in printers) {
      final lower = p.toLowerCase();
      if (keywords.any(lower.contains)) return p;
    }
    return printers.isNotEmpty ? printers.first : '';
  }

  List<int> _escBold(bool on) => on ? const [0x1B, 0x45, 0x01] : const [0x1B, 0x45, 0x00];

  /// Format currency with symbol
  String _formatCurrency(double amount, String symbol) =>
      '$symbol ${amount.toStringAsFixed(2)}';

  /// Center text (truncates when longer than the line width)
  String _center(String text, {int width = 42}) {
    if (text.length >= width) return text.substring(0, width);
    final padding = ((width - text.length) / 2).ceil();
    return '${''.padRight(padding)}$text';
  }

  /// Repeat character
  String _repeat(String char, int count) => char * count;

  /// Printable dots for a paper width (mm) at 203 dpi (ESC/POS standard).
  int _printAreaDots(int paperWidthMm) {
    final normalized = paperWidthMm <= 0 ? 80 : paperWidthMm;
    // 80mm/78mm paper -> 576 dots (72mm printable), 58mm -> 384 dots (48mm)
    return normalized >= 72 ? 576 : 384;
  }

  /// Font-A characters per line derived from the printable dot width
  /// (Font A glyphs are 12 dots wide at 203dpi).
  /// 78mm/80mm -> 48 columns, 58mm -> 32 columns.
  int _charsForPaperWidth(int paperWidthMm) {
    final normalized = paperWidthMm <= 0 ? 80 : paperWidthMm;
    final dots = _printAreaDots(normalized);
    return (dots / 12).round().clamp(32, 64);
  }

  /// Build a left/right padded line: label aligned left, value aligned right
  /// so the numbers line up perfectly on the receipt.
  String _pair(String label, String value, int cols) {
    final avail = cols - value.length;
    if (avail <= 0) return _truncate(value, cols);
    var lbl = label;
    if (lbl.length > avail) lbl = lbl.substring(0, avail);
    return lbl.padRight(avail) + value;
  }

  /// Truncate a string so it fits within `max` characters.
  String _truncate(String text, int max) =>
      text.length <= max ? text : text.substring(0, max);

  /// Build the fixed-width item column layout for the given line width.
  _ItemLayout _itemLayout(int cols) {
    const qtyW = 4;
    const rateW = 9;
    const amtW = 11;
    final nameW = (cols - qtyW - rateW - amtW - 3).clamp(8, cols).toInt();
    return _ItemLayout(nameW: nameW, qtyW: qtyW, rateW: rateW, amtW: amtW);
  }

  /// Print receipt preview (HTML format for screen preview)
  String generateHtmlReceipt(Sale sale, ShopSettings settings) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

    return '''
    <html>
    <head>
      <style>
        body {
          font-family: 'Courier New', monospace;
          max-width: 400px;
          margin: 0;
          padding: 20px;
          background-color: #f5f5f5;
        }
        .receipt {
          background-color: white;
          padding: 20px;
          border-radius: 8px;
          box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .header {
          text-align: center;
          border-bottom: 1px dashed #333;
          padding-bottom: 10px;
          margin-bottom: 10px;
        }
        .header h2 {
          margin: 5px 0;
          font-size: 16px;
        }
        .header p {
          margin: 3px 0;
          font-size: 12px;
        }
        .receipt-id, .date, .cashier {
          font-size: 12px;
          margin: 3px 0;
        }
        .items-table {
          width: 100%;
          margin: 10px 0;
          border-collapse: collapse;
        }
        .items-table th {
          text-align: left;
          font-weight: bold;
          border-bottom: 1px solid #ddd;
          padding: 5px 0;
        }
        .items-table td {
          padding: 5px 0;
          font-size: 12px;
        }
        .item-name {
          width: 50%;
        }
        .item-qty {
          width: 20%;
          text-align: right;
        }
        .item-price {
          width: 30%;
          text-align: right;
        }
        .totals {
          border-top: 1px dashed #333;
          border-bottom: 2px solid #333;
          padding: 10px 0;
          margin: 10px 0;
        }
        .total-row {
          display: flex;
          justify-content: space-between;
          font-size: 12px;
          margin: 5px 0;
        }
        .final-total {
          font-weight: bold;
          font-size: 14px;
          margin-top: 5px;
        }
        .footer {
          text-align: center;
          margin-top: 10px;
          font-size: 12px;
          color: #666;
        }
      </style>
    </head>
    <body>
      <div class="receipt">
        <div class="header">
          <h2>${settings.shopName}</h2>
          <p>${settings.address}</p>
          ${settings.phone.isNotEmpty ? '<p>Phone: ${settings.phone}</p>' : ''}
        </div>

        <div class="receipt-id">Invoice: ${sale.invoiceLabel}</div>
        <div class="date">Date: ${dateFormat.format(sale.saleDate)}</div>
        <div class="cashier">Cashier: ${sale.cashierName}</div>

        <table class="items-table">
          <thead>
            <tr>
              <th class="item-name">Item</th>
              <th class="item-qty">Qty</th>
              <th class="item-price">Price</th>
            </tr>
          </thead>
          <tbody>
            ${sale.items.map((item) => '''
              <tr>
                <td class="item-name">${item.productName}</td>
                <td class="item-qty">${item.quantity}</td>
                <td class="item-price">${settings.currencySymbol} ${item.total.toStringAsFixed(2)}</td>
              </tr>
              ${item.discount > 0 ? '<tr><td colspan="3"><small>Discount: -${settings.currencySymbol} ${item.discountAmount.toStringAsFixed(2)}</small></td></tr>' : ''}
            ''').join('')}
          </tbody>
        </table>

        <div class="totals">
          <div class="total-row">
            <span>Subtotal</span>
            <span>${settings.currencySymbol} ${sale.subtotal.toStringAsFixed(2)}</span>
          </div>
          ${sale.totalDiscount > 0 ? '''
            <div class="total-row">
              <span>Total Discount</span>
              <span>-${settings.currencySymbol} ${sale.totalDiscount.toStringAsFixed(2)}</span>
            </div>
          ''' : ''}
          <div class="total-row final-total">
            <span>TOTAL</span>
            <span>${settings.currencySymbol} ${sale.totalAmount.toStringAsFixed(2)}</span>
          </div>
          <div class="total-row">
            <span>Amount Received</span>
            <span>${settings.currencySymbol} ${sale.amountReceived.toStringAsFixed(2)}</span>
          </div>
          <div class="total-row">
            <span>Change</span>
            <span>${settings.currencySymbol} ${sale.balance.toStringAsFixed(2)}</span>
          </div>
        </div>

        <div class="footer">
          <p>Thank You!</p>
          <p>Visit Again ${DateTime.now().year}</p>
        </div>
      </div>
    </body>
    </html>
    ''';
  }
}

/// Fixed-width column layout for the receipt item table.
class _ItemLayout {
  const _ItemLayout({
    required this.nameW,
    required this.qtyW,
    required this.rateW,
    required this.amtW,
  });

  final int nameW;
  final int qtyW;
  final int rateW;
  final int amtW;

  String get header {
    final buf = StringBuffer()
      ..write('ITEM'.padRight(nameW))
      ..write('QTY'.padLeft(qtyW))
      ..write(' ')
      ..write('RATE'.padLeft(rateW))
      ..write(' ')
      ..write('AMOUNT'.padLeft(amtW));
    return buf.toString();
  }

  String row(String name, int qty, String rate, String amount) {
    final n = name.length > nameW
        ? name.substring(0, nameW)
        : name.padRight(nameW);
    final buf = StringBuffer()
      ..write(n)
      ..write(qty.toString().padLeft(qtyW))
      ..write(' ')
      ..write(rate.padLeft(rateW))
      ..write(' ')
      ..write(amount.padLeft(amtW));
    return buf.toString();
  }

  /// One or more aligned lines for an item. Long names wrap onto the next
  /// line(s); the quantity/rate/amount always print on the final line so the
  /// columns stay lined up.
  List<String> lines(String name, int qty, String rate, String amount) {
    final clean = name.trim();
    if (clean.length <= nameW) {
      return [row(clean, qty, rate, amount)];
    }
    final chunks = <String>[];
    var i = 0;
    while (i < clean.length) {
      final end = (i + nameW > clean.length) ? clean.length : i + nameW;
      chunks.add(clean.substring(i, end));
      i = end;
    }
    final result = <String>[];
    for (var j = 0; j < chunks.length - 1; j++) {
      result.add(chunks[j].padRight(nameW));
    }
    result.add(row(chunks.last, qty, rate, amount));
    return result;
  }
}

