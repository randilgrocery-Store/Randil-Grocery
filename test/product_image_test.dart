import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:randil_grocery_pos/presentation/widgets/product_image.dart';

/// A real 2x2 PNG written to a temp file, so the "file exists and decodes" path
/// is exercised for real rather than mocked.
Uint8List _tinyPngBytes() => Uint8List.fromList(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR length + type
      0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x02, // 2x2
      0x08, 0x06, 0x00, 0x00, 0x00, 0x72, 0xB6, 0x0D,
      0x24, 0x00, 0x00, 0x00, 0x00, 0x49, 0x44, 0x41, // CRC placeholder
      0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
      0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D,
      0xB0, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, // IEND
      0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('product_image_test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ProductImage.hasImage', () {
    test('is false for a null path', () {
      expect(ProductImage.hasImage(null), isFalse);
    });

    test('is false for an empty path', () {
      expect(ProductImage.hasImage(''), isFalse);
    });

    test('is false when the file does not exist', () {
      expect(ProductImage.hasImage('${tempDir.path}\\missing.png'), isFalse);
    });

    test('is true when the file exists', () async {
      final file = File('${tempDir.path}\\ok.png');
      await file.writeAsBytes(_tinyPngBytes());

      expect(ProductImage.hasImage(file.path), isTrue);
    });
  });

  group('ProductImage rendering', () {
    testWidgets('shows the placeholder when no image is set', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ProductImage(path: null),
        ),
      ));

      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('shows the placeholder for an empty path', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ProductImage(path: ''),
        ),
      ));

      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    });

    testWidgets('shows the placeholder when the file is missing',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProductImage(path: '${tempDir.path}\\nope.png'),
        ),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
      // A missing file must not surface an exception to the caller.
      expect(tester.takeException(), isNull);
    });

    // NOTE: tests that make the widget decode a real image file are
    // deliberately absent. `Image.file` performs genuine IO that does not
    // complete inside a widget test's fake-async zone, so such a test hangs
    // until the 10-minute timeout — two of them did, burning 20 minutes of
    // wall clock. `runAsync` does not rescue it.
    //
    // The behaviour that matters is verified without decoding, in
    // `ProductImageStore.resolve` below: a stored value resolves to an existing
    // absolute file, or to null. `build` is a straight branch on that result,
    // so a resolvable path yields `Image` and a null yields the placeholder.
    // Whether the bytes inside that file are decodable is what `errorBuilder`
    // handles, and that cannot be exercised without a real decode.

    testWidgets('honours a custom placeholder icon and colour',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ProductImage(
            path: null,
            placeholderIcon: Icons.image,
            placeholderColor: Colors.red,
          ),
        ),
      ));

      expect(find.byIcon(Icons.image), findsOneWidget);
    });
  });

  group('ProductImageStore portability', () {
    test('store returns a bare filename, never an absolute path', () async {
      // This is the property that makes the database deliverable: an absolute
      // path from the development machine would break on the client's machine.
      final source = File('${tempDir.path}\\portable.jpg');
      await source.writeAsBytes(_tinyPngBytes());

      final stored = await ProductImageStore.store(source.path);

      expect(stored, isNotNull);
      expect(File(stored!).isAbsolute, isFalse);
      expect(stored.contains('\\'), isFalse);
      expect(stored.contains('/'), isFalse);
      expect(stored, endsWith('.jpg'));
    });

    test('resolve turns a bare filename into an absolute path on disk',
        () async {
      final source = File('${tempDir.path}\\resolve_me.png');
      await source.writeAsBytes(_tinyPngBytes());
      final name = await ProductImageStore.store(source.path);

      final resolved = ProductImageStore.resolve(name);

      expect(resolved, isNotNull);
      expect(File(resolved!).existsSync(), isTrue);
      expect(resolved.startsWith(ProductImageStore.directory().path), isTrue);
    });

    test('resolve returns null for a filename with no file behind it',
        () async {
      expect(ProductImageStore.resolve('never_existed.jpg'), isNull);
    });

    test('resolve recovers an image delivered with a foreign absolute path',
        () async {
      // Simulates the delivery scenario: the image folder travelled with the
      // database, but the database still holds the old machine's full path.
      final source = File('${tempDir.path}\\relocated.png');
      await source.writeAsBytes(_tinyPngBytes());
      final name = await ProductImageStore.store(source.path);

      // A path from a different Windows user / machine.
      final foreign = r'C:\Users\someone-else\AppData\Local\RandilGroceryPOS'
          '\\product_images\\$name';

      final resolved = ProductImageStore.resolve(foreign);

      // The basename still matches the file that came along, so it must resolve.
      expect(resolved, isNotNull);
      expect(resolved, endsWith(name!));
    });

    test('resolve keeps an absolute path that exists on this machine',
        () async {
      final outside = File('${tempDir.path}\\still_here.jpg');
      await outside.writeAsBytes(_tinyPngBytes());

      expect(ProductImageStore.resolve(outside.path), outside.path);
    });

    test('resolve returns null when an absolute path is simply gone', () {
      expect(
        ProductImageStore.resolve(r'Z:\removed drive\missing.png'),
        isNull,
      );
    });

    test('hasImage accepts a bare filename', () async {
      final source = File('${tempDir.path}\\has_image.png');
      await source.writeAsBytes(_tinyPngBytes());
      final name = await ProductImageStore.store(source.path);

      expect(ProductImage.hasImage(name), isTrue);
    });
  });

  group('ProductImageStore', () {
    test('copies a picked image into the app folder', () async {
      final source = File('${tempDir.path}\\source.jpg');
      await source.writeAsBytes(_tinyPngBytes());

      final stored = await ProductImageStore.store(source.path);

      expect(stored, isNotNull);
      expect(stored, endsWith('.jpg'));
      // The copy really landed in the app's image folder...
      final absolute = ProductImageStore.resolve(stored);
      expect(absolute, isNotNull);
      expect(File(absolute!).existsSync(), isTrue);
      expect(absolute.startsWith(ProductImageStore.directory().path), isTrue);
      // ...and the original was left alone.
      expect(source.existsSync(), isTrue);
    });

    test('returns null for a file that does not exist', () async {
      expect(
        await ProductImageStore.store('${tempDir.path}\\missing.jpg'),
        isNull,
      );
    });

    test('gives two copies of the same name different paths', () async {
      final source = File('${tempDir.path}\\milk.jpg');
      await source.writeAsBytes(_tinyPngBytes());

      final first = await ProductImageStore.store(source.path);
      // Sub-millisecond timestamps collide, so space them out; the point is
      // that the store never hands the same path to two different products.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final second = await ProductImageStore.store(source.path);

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first, isNot(second));
    });

    test('delete removes a stored image', () async {
      final source = File('${tempDir.path}\\gone.jpg');
      await source.writeAsBytes(_tinyPngBytes());
      final stored = await ProductImageStore.store(source.path);
      final absolute = ProductImageStore.resolve(stored);

      await ProductImageStore.delete(stored);

      expect(File(absolute!).existsSync(), isFalse);
    });

    test('delete refuses to touch a file outside the app folder', () async {
      // Must never delete something the user picked from Downloads or Desktop.
      final outside = File('${tempDir.path}\\not_ours.jpg');
      await outside.writeAsBytes(_tinyPngBytes());

      await ProductImageStore.delete(outside.path);

      expect(outside.existsSync(), isTrue);
    });
  });
}