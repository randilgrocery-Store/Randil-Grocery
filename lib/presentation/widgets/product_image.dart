import 'dart:io';

import 'package:flutter/material.dart';

/// Shows a product image, or a neutral placeholder when there is nothing usable
/// to show.
///
/// This exists because the same "is there an image?" check was written out by
/// hand in five places (inventory grid, POS grid, POS preview dialog, cart line
/// and the add/edit product form) and every copy had the same two defects:
///
///  * **No error handling.** A file that exists but cannot be decoded — a
///    corrupt download, a HEIC photo off a phone, a renamed `.txt` — made
///    `Image.file` throw. The tile then rendered as an empty grey box with
///    nothing in it and an exception in the log, and there was no way back
///    except editing the product. [errorBuilder] turns that into the normal
///    placeholder.
///
///  * **`BoxFit.cover` everywhere.** In the small inventory/grid tiles a cover
///    fit on a portrait product photo crops it down to an unreadable slice —
///    typically the middle of a packet. Fit is now chosen per call site so a
///    thumbnail crops sensibly while a full-size preview shows the whole item.
///
/// Both are silent failures: no crash, no message, just a wrong-looking screen.
class ProductImage extends StatelessWidget {
  /// `Colors.grey[400]` is declared `Color?`, so it cannot be used directly as a
  /// non-nullable default. Bound once here to keep the placeholder colour
  /// definite.
  static const Color _defaultPlaceholderColor = Color(0xFF9E9E9E);

  const ProductImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.placeholderIcon = Icons.image_not_supported_outlined,
    this.placeholderColor,
    this.placeholderSize,
    this.width,
    this.height,
    this.cacheWidth,
  });

  /// The stored image reference from the product row.
  ///
  /// Normally just a filename such as `1758231041203045.jpg`. Older rows may
  /// hold an absolute path, including one from a different machine — see
  /// [ProductImageStore.resolve], which normalises all of them. May be null or
  /// blank.
  final String? path;

  /// How the image fills its box. Use [BoxFit.contain] for previews where the
  /// whole product must be recognisable.
  final BoxFit fit;

  final IconData placeholderIcon;
  final Color? placeholderColor;
  final double? placeholderSize;
  final double? width;
  final double? height;

  /// Decoded width in pixels. Setting this lets Flutter downsample a large
  /// photo instead of decoding it at full resolution, which matters when a grid
  /// shows a hundred products.
  final int? cacheWidth;

  /// True when [path] resolves to a file that currently exists on this machine.
  ///
  /// Kept as a static helper so the add/edit form can show a warning before the
  /// product is saved, rather than letting the image silently disappear later.
  static bool hasImage(String? path) => ProductImageStore.resolve(path) != null;

  @override
  Widget build(BuildContext context) {
    final resolved = ProductImageStore.resolve(path);
    final file = resolved == null ? null : File(resolved);

    if (file == null) {
      return _Placeholder(
        icon: placeholderIcon,
        color: placeholderColor ?? _defaultPlaceholderColor,
        size: placeholderSize ?? 35,
      );
    }

    return Image.file(
      file,
      fit: fit,
      width: width,
      height: height,
      cacheWidth: cacheWidth,
      // A file that exists but will not decode must degrade to the placeholder
      // instead of blowing away the tile.
      errorBuilder: (context, error, stack) => _Placeholder(
        icon: placeholderIcon,
        color: placeholderColor ?? _defaultPlaceholderColor,
        size: placeholderSize ?? 35,
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.color,
    required this.size,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Centred so the icon sits in the middle of whatever box it was given.
    return Center(
      child: Icon(icon, size: size, color: color),
    );
  }
}

/// Owns where product images live on disk, and — critically — what gets written
/// into the database.
///
/// ## Why only a bare filename is stored
///
/// Storing the absolute path of a picked file is what most code does, and it is
/// wrong for this app in two separate ways:
///
///  * The file the user picked usually sits in Downloads or on the Desktop,
///    which the OS moves, renames or clears. The product silently loses its
///    picture.
///  * The database stores `C:\Users\jerus\AppData\Local\RandilGroceryPOS\...`.
///    Deliver that database to the client's machine and **every single image
///    breaks at once**, because the client's Windows profile directory is a
///    different name. That is the exact situation this app is in: one
///    development machine, then delivery to a shop.
///
/// So the file is copied into an app-owned folder and only its *name* is stored
/// (e.g. `1758231041203045.jpg`). [resolve] turns that back into an absolute
/// path at read time using whatever `%LOCALAPPDATA%` the current machine has.
///
/// The consequence to be aware of: the database and the `product_images` folder
/// must be delivered together. The database alone is not self-contained.
class ProductImageStore {
  const ProductImageStore._();

  /// Folder name under the app data directory. Deliberately a bare name so it
  /// can be looked up from [dataDirectory].
  static const String folderName = 'product_images';

  /// The app's own data directory (`%LOCALAPPDATA%\RandilGroceryPOS`).
  ///
  /// Matches `DatabaseService._stableDataDirectory` so the database and its
  /// images always sit side by side.
  static Directory dataDirectory() {
    final localAppData = Platform.environment['LOCALAPPDATA']?.trim();
    final base = (localAppData == null || localAppData.isEmpty)
        ? Directory.systemTemp.path
        : localAppData;
    return Directory(
        '$base${Platform.pathSeparator}RandilGroceryPOS');
  }

  static Directory directory() =>
      Directory('${dataDirectory().path}${Platform.pathSeparator}$folderName');

  /// Turns a stored value into an absolute path on the current machine.
  ///
  /// Handles all three shapes that can be sitting in the `imagePath` column:
  ///
  ///  * a bare filename — the current format, resolved against [directory];
  ///  * an absolute path from an older build that still exists on this machine;
  ///  * an absolute path from another machine — the basename is retried against
  ///    [directory], which recovers images when the folder was delivered
  ///    alongside the database but the database still holds a foreign path.
  ///
  /// Returns null when nothing resolves, so callers show the placeholder.
  static String? resolve(String? stored) {
    if (stored == null || stored.isEmpty) return null;

    // Already a full path: use it as-is when it exists here.
    if (stored.length > 2 && (stored[1] == ':' || stored.startsWith(r'\\'))) {
      if (File(stored).existsSync()) return stored;

      // Delivered from another machine. The folder came along, so the file name
      // is still valid even though the folder it was copied from is not.
      final name = stored.split(RegExp(r'[/\\]')).last;
      final relocated = '${directory().path}${Platform.pathSeparator}$name';
      if (File(relocated).existsSync()) return relocated;
      return null;
    }

    // Relative filename (the normal case).
    final resolved =
        '${directory().path}${Platform.pathSeparator}$stored';
    return File(resolved).existsSync() ? resolved : null;
  }

  /// Copies [sourcePath] into the app image folder and returns the *filename* to
  /// store in the database — not an absolute path.
  ///
  /// Returns null if the copy failed. Never throws, so a failed copy degrades to
  /// "this product has no picture" instead of blocking the save.
  static Future<String?> store(String sourcePath) async {
    final source = File(sourcePath);
    if (!source.existsSync()) return null;

    try {
      final dir = directory();
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }

      // Unique per product so two items called "Milk 1kg" with different photos
      // do not overwrite each other.
      final name =
          '${DateTime.now().microsecondsSinceEpoch}${_extensionOf(sourcePath)}';
      final target = File(
          '${dir.path}${Platform.pathSeparator}$name');

      await source.copy(target.path);
      // Hand back the name only. This is the value that goes into imagePath.
      return name;
    } catch (_) {
      return null;
    }
  }

  /// Deletes a stored image. Best-effort; failure is not worth surfacing.
  static Future<void> delete(String? stored) async {
    final absolute = resolve(stored);
    if (absolute == null) return;
    try {
      final file = File(absolute);
      // Only ever touch images inside our own folder, so this can never delete
      // something the user picked from elsewhere on disk.
      if (!file.path.startsWith(directory().path)) return;
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || path.length - dot > 6) return '.jpg';
    return path.substring(dot);
  }
}