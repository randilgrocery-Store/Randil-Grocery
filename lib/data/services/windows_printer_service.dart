import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Sends raw ESC/POS bytes to a Windows thermal printer (e.g. Zenpert)
/// using the Windows Print Spooler API (winspool.drv). This works with any
/// USB/network ESC/POS receipt printer installed as a Windows printer.
///
/// The "RAW" datatype bypasses any printer driver processing and sends the
/// commands straight to the hardware, which is exactly what thermal receipt
/// printers expect.
class WindowsPrinterService {
  factory WindowsPrinterService() => _instance;

  WindowsPrinterService._internal();
  static final WindowsPrinterService _instance =
      WindowsPrinterService._internal();

  String? _lastError;
  String? get lastError => _lastError;

  // PRINTER_INFO_2.Status / PRINTER_STATUS_* flags (not exported by win32).
  static const int statusPaused = 0x00000001;
  static const int statusError = 0x00000002;
  static const int statusPaperJam = 0x00000008;
  static const int statusPaperOut = 0x00000010;
  static const int statusPaperProblem = 0x00000040;
  static const int statusOffline = 0x00000080;
  static const int statusOutputBinFull = 0x00000800;
  static const int statusNotAvailable = 0x00001000;
  static const int statusNoToner = 0x00040000;
  static const int statusUserIntervention = 0x00100000;
  static const int statusDoorOpen = 0x00400000;
  static const int statusServerUnknown = 0x00800000;

  /// Human readable problem described by a printer status bitmask, or null
  /// when the printer is healthy. "Busy"/"Printing" style flags are ignored
  /// because they are normal during a job.
  static String? describeStatus(int status) {
    if (status & statusPaperOut != 0) {
      return 'Printer is out of paper. Load a new roll, then reprint.';
    }
    if (status & statusPaperJam != 0) {
      return 'Paper jam detected. Clear the jam, then reprint.';
    }
    if (status & statusOffline != 0) {
      return 'Printer is offline. Check the cable/power, then reprint.';
    }
    if (status & statusError != 0) {
      return 'Printer reported an error. Check the printer, then reprint.';
    }
    if (status & statusPaperProblem != 0) {
      return 'Paper problem detected. Check the roll, then reprint.';
    }
    if (status & statusDoorOpen != 0) {
      return 'Printer cover is open. Close it, then reprint.';
    }
    if (status & statusNoToner != 0) {
      return 'Printer is out of consumables. Replace, then reprint.';
    }
    if (status & statusOutputBinFull != 0) {
      return 'Printer output bin is full. Empty it, then reprint.';
    }
    if (status & statusPaused != 0) {
      return 'Printer is paused. Resume it in Windows, then reprint.';
    }
    if (status & statusNotAvailable != 0) {
      return 'Printer is not available. Check the connection.';
    }
    if (status & statusServerUnknown != 0) {
      return 'Printer server is unavailable.';
    }
    if (status & statusUserIntervention != 0) {
      return 'Printer needs attention before it can print.';
    }
    return null;
  }

  /// Read the current printer status bitmask, or null if it cannot be read.
  int? getPrinterStatus(String printerName) {
    final namePtr = printerName.toNativeUtf16();
    final hPrinter = calloc<IntPtr>();
    try {
      final openResult = OpenPrinter(namePtr, hPrinter, nullptr);
      if (openResult == 0 || hPrinter.value == 0) {
        return null;
      }
      return _statusForHandle(hPrinter.value);
    } finally {
      if (hPrinter.value != 0) {
        ClosePrinter(hPrinter.value);
      }
      calloc.free(namePtr);
      calloc.free(hPrinter);
    }
  }

  int? _statusForHandle(int printerHandle) {
    final needed = calloc<Uint32>();
    try {
      // First call determines the required buffer size.
      GetPrinter(printerHandle, 2, nullptr, 0, needed);
      final size = needed.value;
      if (size == 0) {
        return null;
      }
      final buffer = calloc<Uint8>(size);
      try {
        if (GetPrinter(printerHandle, 2, buffer, size, needed) == 0) {
          return null;
        }
        return buffer.cast<PRINTER_INFO_2>().ref.Status;
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(needed);
    }
  }

  /// Returns a problem message when the named printer is currently in an
  /// error state (out of paper, offline, etc.), otherwise null.
  String? checkPrinter(String printerName) {
    final status = getPrinterStatus(printerName);
    if (status == null) {
      return null;
    }
    return describeStatus(status);
  }

  /// Polls the printer for a short while after a job was submitted so that
  /// failures that only surface mid-print (paper running out, offline, ...)
  /// are reported instead of a false success. The problem must be observed
  /// twice in a row to avoid reacting to a transient blip. Returns null when
  /// the printer stays healthy for the whole window.
  Future<String?> verifyPrinterHealth(
    String printerName, {
    Duration timeout = const Duration(seconds: 4),
    Duration interval = const Duration(milliseconds: 250),
  }) async {
    final deadline = DateTime.now().add(timeout);
    String? pending;
    do {
      final problem = checkPrinter(printerName);
      if (problem != null) {
        if (pending == problem) {
          return problem;
        }
        pending = problem;
      } else {
        pending = null;
      }
      await Future<void>.delayed(interval);
    } while (DateTime.now().isBefore(deadline));
    return null;
  }

  /// Enumerate installed printers. Returns a list of printer names.
  List<String> listPrinters() {
    final printers = <String>[];
    final pcbNeeded = calloc<Uint32>();
    final pcReturned = calloc<Uint32>();

    try {
      // Call 1: determine required buffer size.
      EnumPrinters(
        PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS,
        nullptr,
        2,
        nullptr,
        0,
        pcbNeeded,
        pcReturned,
      );
      final needed = pcbNeeded.value;
      if (needed == 0) {
        return printers;
      }

      // Call 2: fill the buffer.
      final buffer = calloc<Uint8>(needed);
      try {
        final result = EnumPrinters(
          PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS,
          nullptr,
          2,
          buffer,
          needed,
          pcbNeeded,
          pcReturned,
        );
        if (result == 0) {
          _lastError = 'EnumPrinters failed: ${GetLastError()}';
          return printers;
        }

        final count = pcReturned.value;
        final info = buffer.cast<PRINTER_INFO_2>();
        for (var i = 0; i < count; i++) {
          final name = info.elementAt(i).ref.pPrinterName;
          if (name != nullptr) {
            printers.add(name.toDartString());
          }
        }
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(pcbNeeded);
      calloc.free(pcReturned);
    }
    return printers;
  }

  /// Print a plain-text document using the RAW data type. Text is sent as
  /// byte-encoded characters that thermal printers understand.
  bool printText(String printerName, String text) {
    return printRaw(printerName, _encodeText(text));
  }

  /// Send raw ESC/POS bytes to the given printer name.
  /// Returns true on success.
  bool printRaw(String printerName, Uint8List data) {
    _lastError = null;
    if (data.isEmpty) {
      _lastError = 'No data to print';
      return false;
    }

    // Refuse to queue a job when the printer already reports a problem, so a
    // bill is never silently swallowed while the roll is empty/offline.
    final problem = checkPrinter(printerName);
    if (problem != null) {
      _lastError = problem;
      return false;
    }

    final printerNamePtr = printerName.toNativeUtf16();
    final hPrinter = calloc<IntPtr>();
    final docInfo = calloc<DOC_INFO_1>();
    var opened = false;

    try {
      final openResult = OpenPrinter(printerNamePtr, hPrinter, nullptr);
      final printerHandle = hPrinter.value; // int handle
      if (openResult == 0 || printerHandle == 0) {
        _lastError = 'Could not open printer "$printerName" '
            '(${GetLastError()})';
        return false;
      }
      opened = true;

      // DOC_INFO_1 fields are direct Pointer<Utf16>.
      final docName = 'POS Receipt'.toNativeUtf16();
      final dataType = 'RAW'.toNativeUtf16();
      docInfo.ref.pDocName = docName;
      docInfo.ref.pOutputFile = nullptr;
      docInfo.ref.pDatatype = dataType;

      final startDoc = StartDocPrinter(printerHandle, 1, docInfo);
      calloc.free(docName);
      calloc.free(dataType);

      if (startDoc == 0) {
        _lastError = 'StartDocPrinter failed: ${GetLastError()}';
        return false;
      }

      StartPagePrinter(printerHandle);

      final dataPtr = calloc<Uint8>(data.length);
      final writtenPtr = calloc<Uint32>();
      try {
        dataPtr.asTypedList(data.length).setAll(0, data);
        final ok = WritePrinter(printerHandle, dataPtr, data.length, writtenPtr);
        if (ok == 0 || writtenPtr.value != data.length) {
          _lastError = 'WritePrinter failed: ${GetLastError()}';
          return false;
        }
      } finally {
        calloc.free(dataPtr);
        calloc.free(writtenPtr);
      }

      EndPagePrinter(printerHandle);
      EndDocPrinter(printerHandle);
      return true;
    } finally {
      calloc.free(printerNamePtr);
      calloc.free(docInfo);
      if (opened) {
        ClosePrinter(hPrinter.value);
      }
      calloc.free(hPrinter);
    }
  }

  /// Convert Unicode text to a byte stream using a single-byte mapping that
  /// thermal printers accept. Characters outside Latin-1 become '?'.
  Uint8List _encodeText(String text) {
    final bytes = <int>[];
    for (final rune in text.runes) {
      bytes.add(rune < 0x100 ? rune : 0x3F);
    }
    return Uint8List.fromList(bytes);
  }
}
