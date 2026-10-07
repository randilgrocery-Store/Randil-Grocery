import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/password_hasher.dart';
import '../models/cart_item.dart';
import '../models/category.dart';
import '../models/customer.dart';
import '../models/expense.dart';
import '../models/goods_received_note.dart';
import '../models/product.dart';
import '../models/product_batch.dart';
import '../models/production.dart';
import '../models/purchase_order.dart';
import '../models/recipe.dart';
import '../models/refund_return.dart';
import '../models/reload_card.dart';
import '../models/sale.dart';
import '../models/shop_settings.dart';
import '../models/supplier.dart';
import '../models/supplier_payment.dart';
import '../models/user.dart';
import '../models/wastage.dart';
import '../services/backup_service.dart';

part 'repack_crud.dart';
part 'repack_production.dart';

class DatabaseService {
  factory DatabaseService() => _instance;

  DatabaseService._internal();
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  Future<Database> get database async {
    _database ??= await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    // Use sqflite_ffi for Windows
    final databaseFactory = databaseFactoryFfi;
    final path = await getDatabasePath();

    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: _createTables,
        onUpgrade: (db, oldVersion, newVersion) async {},
        onOpen: _onDatabaseOpen,
        readOnly: false,
      ),
    );
  }

  Future<String> getDatabasePath() async {
    // Use a stable location that does not depend on the working directory.
    // The old behaviour put the database under "<cwd>/.dart_tool/..." which
    // produced a DIFFERENT database depending on whether the app was launched
    // via "flutter run" or the built .exe (causing missing data and broken
    // logins when the copies diverged).
    final stablePath =
        join(_stableDataDirectory().path, 'randil_grocery_pos.db');

    final stableFile = File(stablePath);
    if (!stableFile.existsSync()) {
      // First run on the new path: inherit the data already saved by an older
      // build so nothing is lost.
      final legacy = _findLargestLegacyDatabase();
      if (legacy != null) {
        try {
          await File(legacy).copy(stablePath);
          developer.log(
            'Inherited database from legacy location: $legacy',
            name: 'DatabaseService',
          );
        } catch (e) {
          developer.log(
            'Failed to inherit legacy database: $e',
            name: 'DatabaseService',
          );
        }
      }
    }
    return stablePath;
  }

  /// Location where plain .db snapshots of the live database are kept.
  /// These are what get pushed to GitHub and uploaded to Google Drive.
  Directory snapshotsDirectory() {
    final dir = Directory(join(_stableDataDirectory().path, 'backups'));
    try {
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
    } catch (_) {}
    return dir;
  }

  /// Plain copy of the live database, saved so every change is kept on the
  /// local machine immediately. Returns the snapshot path or null on failure.
  Future<String?> createDbSnapshot() async {
    try {
      final livePath = await getDatabasePath();
      final liveFile = File(livePath);
      if (!liveFile.existsSync()) return null;

      final dir = snapshotsDirectory();
      final stamp = _timestampForFile(DateTime.now());
      final snapshotPath =
          join(dir.path, 'randil_grocery_pos_$stamp.db');

      final tmp = '$snapshotPath.tmp';
      await liveFile.copy(tmp);
      await File(tmp).rename(snapshotPath);
      _pruneFiles(dir, keep: 60, prefix: 'randil_grocery_pos_');
      return snapshotPath;
    } catch (e) {
      developer.log('createDbSnapshot failed: $e', name: 'DatabaseService');
      return null;
    }
  }

  /// All local snapshots, newest first.
  Future<List<File>> listDbSnapshots() async {
    final dir = snapshotsDirectory();
    final files = (dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.db'))
            .toList())
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  static String _timestampForFile(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  static void _pruneFiles(Directory dir, {required int keep, String? prefix}) {
    try {
      final files = (dir
              .listSync()
              .whereType<File>()
              .where((f) => prefix == null || f.path.contains(prefix))
              .toList())
        ..sort((a, b) =>
            a.statSync().modified.compareTo(b.statSync().modified));
      while (files.length > keep) {
        files.removeAt(0).deleteSync();
      }
    } catch (_) {}
  }

  Directory _stableDataDirectory() {
    final localAppData = Platform.environment['LOCALAPPDATA']?.trim();
    final base = (localAppData == null || localAppData.isEmpty)
        ? Directory.systemTemp.path
        : localAppData;
    final dir = Directory(join(base, 'RandilGroceryPOS'));
    try {
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
    } catch (_) {}
    return dir;
  }

  /// Legacy locations used by older builds (database lived next to the
  /// executable / cwd). Largest file wins so the copy with the most data is
  /// inherited. Only relevant on machines that had an older build.
  String? _findLargestLegacyDatabase() {
    const fileName = 'randil_grocery_pos.db';
    final candidates = <String>[
      join(
        Directory.current.path,
        '.dart_tool',
        'sqflite_common_ffi',
        'databases',
        fileName,
      ),
      join(r'D:\Randil Grocery POS', '.dart_tool', 'sqflite_common_ffi',
          'databases', fileName),
      join(r'D:\Randil Grocery POS', 'build', 'windows', 'x64', 'runner',
          'Release', '.dart_tool', 'sqflite_common_ffi', 'databases', fileName),
    ];
    String? best;
    var bestSize = -1;
    for (final candidate in candidates) {
      final file = File(candidate);
      if (!file.existsSync()) {
        continue;
      }
      final size = file.lengthSync();
      if (size > bestSize) {
        best = candidate;
        bestSize = size;
      }
    }
    return best;
  }

  Future<void> _onDatabaseOpen(Database db) async {
    // Ensure all tables exist
    await _createTables(db, 1);
    // Seed / repair the built-in accounts on every open so the standard
    // logins (admin/admin123, cashier/1234) always work.
    await _ensureStandardAccounts(db);
  }

  /// Repairs the two built-in accounts so the standard logins always work:
  ///   admin  / admin123 (Administrator)
  ///   cashier / 1234     (Cashier)
  ///
  /// Missing accounts are created. Passwords are reset to the defaults once
  /// (guarded by a flag in SharedPreferences) so databases written by older
  /// versions whose hashes no longer verify get fixed, without overwriting a
  /// password the owner deliberately changed afterwards.
  Future<void> _ensureStandardAccounts(Database db) async {
    final prefs = await SharedPreferences.getInstance();
    const marker = 'standard_accounts_repaired_v1';
    final forceRepair = !(prefs.getBool(marker) ?? false);

    await _ensureAccount(
      db,
      username: 'admin',
      password: 'admin123',
      role: 'admin',
      fullName: 'Administrator',
      forceRepair: forceRepair,
    );
    await _ensureAccount(
      db,
      username: 'cashier',
      password: '1234',
      role: 'cashier',
      fullName: 'Cashier',
      forceRepair: forceRepair,
    );

    if (forceRepair) {
      await prefs.setBool(marker, true);
    }
  }

  Future<void> _ensureAccount(
    Database db, {
    required String username,
    required String password,
    required String role,
    required String fullName,
    required bool forceRepair,
  }) async {
    try {
      final rows = await db.query(
        'users',
        where: 'username = ?',
        whereArgs: [username],
      );
      if (rows.isEmpty) {
        await db.insert('users', {
          'id': const Uuid().v4(),
          'username': username,
          'password': PasswordHasher.hash(password),
          'role': role,
          'fullName': fullName,
          'createdAt': DateTime.now().toIso8601String(),
          'isActive': 1,
        });
        return;
      }
      if (!forceRepair) {
        return;
      }
      final stored = rows.first['password'] as String? ?? '';
      if (!PasswordHasher.verify(password, stored)) {
        await db.update(
          'users',
          {'password': PasswordHasher.hash(password)},
          where: 'username = ?',
          whereArgs: [username],
        );
        developer.log(
          'Reset default password for $username',
          name: 'DatabaseService',
        );
      }
    } catch (e) {
      developer.log(
        'Account ensure error ($username): $e',
        name: 'DatabaseService',
      );
    }
  }

  Future<void> _createTables(Database db, int version) async {
    // Users Table
    final userTableExists = await _tableExists(db, 'users');
    if (!userTableExists) {
      await db.execute('''
        CREATE TABLE users (
          id TEXT PRIMARY KEY,
          username TEXT UNIQUE NOT NULL,
          password TEXT NOT NULL,
          role TEXT NOT NULL,
          fullName TEXT NOT NULL,
          createdAt TEXT NOT NULL,
          isActive INTEGER NOT NULL DEFAULT 1
        )
      ''');
    }

    // Categories Table (NEW)
    final categoriesTableExists = await _tableExists(db, 'categories');
    if (!categoriesTableExists) {
      await db.execute('''
        CREATE TABLE categories (
          id TEXT PRIMARY KEY,
          name TEXT UNIQUE NOT NULL,
          description TEXT,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL
        )
      ''');
    }

    // Products Table
    final productTableExists = await _tableExists(db, 'products');
    if (!productTableExists) {
      await db.execute('''
        CREATE TABLE products (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          barcode TEXT UNIQUE NOT NULL,
          categoryId TEXT NOT NULL,
          buyingPrice REAL NOT NULL,
          sellingPrice REAL NOT NULL,
          quantity REAL NOT NULL,
          expiryDate TEXT,
          supplierId TEXT,
          reorderLevel INTEGER,
          imagePath TEXT,
          soldByWeight INTEGER NOT NULL DEFAULT 0,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL,
          FOREIGN KEY (categoryId) REFERENCES categories(id)
        )
      ''');
    } else {
      // Migration: Check if imagePath column exists
      try {
        final columns = await db.rawQuery('PRAGMA table_info(products)');
        final hasImagePath = columns.any((col) => col['name'] == 'imagePath');
        if (!hasImagePath) {
          await db.execute('ALTER TABLE products ADD COLUMN imagePath TEXT');
        }
      } catch (e) {
        developer.log('Migration error: $e', name: 'DatabaseService');
      }

      // Migration: Update category column to categoryId if it doesn't exist
      try {
        await db.execute('ALTER TABLE products ADD COLUMN categoryId TEXT');
      } catch (e) {
        // Column already exists
      }
      try {
        await db.execute('ALTER TABLE products ADD COLUMN supplierId TEXT');
      } catch (e) {
        // Column already exists
      }
      try {
        await db
            .execute('ALTER TABLE products ADD COLUMN reorderLevel INTEGER');
      } catch (e) {
        // Column already exists
      }
      try {
        await db.execute(
          'ALTER TABLE products ADD COLUMN soldByWeight INTEGER NOT NULL DEFAULT 0',
        );
      } catch (e) {
        // Column already exists
      }
    }

    // Sales Table
    final salesTableExists = await _tableExists(db, 'sales');
    if (!salesTableExists) {
      await db.execute('''
        CREATE TABLE sales (
          id TEXT PRIMARY KEY,
          invoiceNumber TEXT,
          cashierId TEXT NOT NULL,
          cashierName TEXT NOT NULL,
          items TEXT NOT NULL,
          subtotal REAL NOT NULL,
          totalDiscount REAL NOT NULL,
          totalAmount REAL NOT NULL,
          amountReceived REAL NOT NULL,
          balance REAL NOT NULL,
          paymentMethod TEXT NOT NULL,
          saleDate TEXT NOT NULL,
          notes TEXT,
          customerName TEXT,
          customerPhone TEXT,
          cashAmount REAL NOT NULL DEFAULT 0,
          cardAmount REAL NOT NULL DEFAULT 0,
          FOREIGN KEY (cashierId) REFERENCES users(id)
        )
      ''');
    } else {
      // Migration: add the numeric invoice number column for older databases.
      try {
        final columns = await db.rawQuery('PRAGMA table_info(sales)');
        final names = columns.map((col) => col['name'] as String).toSet();
        if (!names.contains('invoiceNumber')) {
          await db.execute('ALTER TABLE sales ADD COLUMN invoiceNumber TEXT');
        }
        if (!names.contains('customerName')) {
          await db.execute('ALTER TABLE sales ADD COLUMN customerName TEXT');
        }
        if (!names.contains('customerPhone')) {
          await db.execute('ALTER TABLE sales ADD COLUMN customerPhone TEXT');
        }
        if (!names.contains('cashAmount')) {
          await db.execute(
              'ALTER TABLE sales ADD COLUMN cashAmount REAL NOT NULL DEFAULT 0');
        }
        if (!names.contains('cardAmount')) {
          await db.execute(
              'ALTER TABLE sales ADD COLUMN cardAmount REAL NOT NULL DEFAULT 0');
        }
      } catch (e) {
        developer.log('Sales migration error: $e', name: 'DatabaseService');
      }
    }

    // Counters Table (used for invoice numbering)
    final countersTableExists = await _tableExists(db, 'counters');
    if (!countersTableExists) {
      await db.execute('''
        CREATE TABLE counters (
          name TEXT PRIMARY KEY,
          value INTEGER NOT NULL
        )
      ''');
      await db.insert('counters', {'name': 'sale_invoice', 'value': 0});
    }

    // Stock History Table
    final historyTableExists = await _tableExists(db, 'stock_history');
    if (!historyTableExists) {
      await db.execute('''
        CREATE TABLE stock_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          productId TEXT NOT NULL,
          productName TEXT NOT NULL,
          quantityChanged REAL NOT NULL,
          reason TEXT NOT NULL,
          createdAt TEXT NOT NULL,
          FOREIGN KEY (productId) REFERENCES products(id)
        )
      ''');
    }

    // Customers Table
    final customerTableExists = await _tableExists(db, 'customers');
    if (!customerTableExists) {
      await db.execute('''
        CREATE TABLE customers (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          phone TEXT UNIQUE NOT NULL,
          email TEXT NOT NULL,
          address TEXT,
          totalSpent REAL NOT NULL DEFAULT 0,
          totalTransactions INTEGER NOT NULL DEFAULT 0,
          createdAt TEXT NOT NULL,
          lastPurchaseDate TEXT NOT NULL,
          isActive INTEGER NOT NULL DEFAULT 1
        )
      ''');
    }
    // NOTE: legacy creditBalance/loyaltyPoints columns on old databases are
    // intentionally left in place and ignored (feature removed).

    // Suppliers Table (NEW)
    final suppliersTableExists = await _tableExists(db, 'suppliers');
    if (!suppliersTableExists) {
      await db.execute('''
        CREATE TABLE suppliers (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          contactPerson TEXT NOT NULL,
          phone TEXT NOT NULL,
          email TEXT NOT NULL,
          address TEXT NOT NULL,
          paymentTerms TEXT NOT NULL,
          creditLimit REAL,
          currentBalance REAL NOT NULL DEFAULT 0,
          isActive INTEGER NOT NULL DEFAULT 1,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL
        )
      ''');
    }

    // Product Batches Table (NEW)
    final batchesTableExists = await _tableExists(db, 'product_batches');
    if (!batchesTableExists) {
      await db.execute('''
        CREATE TABLE product_batches (
          id TEXT PRIMARY KEY,
          productId TEXT NOT NULL,
          batchNumber TEXT NOT NULL,
          price REAL NOT NULL,
          sellingPrice REAL NOT NULL DEFAULT 0,
          expiryDate TEXT,
          quantity REAL NOT NULL,
          initialQuantity REAL NOT NULL DEFAULT 0,
          receivedDate TEXT NOT NULL,
          supplierId TEXT NOT NULL,
          notes TEXT,
          createdAt TEXT NOT NULL,
          FOREIGN KEY (productId) REFERENCES products(id),
          FOREIGN KEY (supplierId) REFERENCES suppliers(id),
          UNIQUE(productId, batchNumber)
        )
      ''');
    } else {
      // Migration: batches now carry their own retail (selling) price so each
      // delivery can be sold at the price agreed for that stock.
      try {
        final columns = await db.rawQuery('PRAGMA table_info(product_batches)');
        final names = columns.map((col) => col['name'] as String).toSet();
        if (!names.contains('sellingPrice')) {
          await db.execute(
            'ALTER TABLE product_batches ADD COLUMN sellingPrice REAL NOT NULL DEFAULT 0',
          );
        }
        if (!names.contains('initialQuantity')) {
          await db.execute(
            'ALTER TABLE product_batches ADD COLUMN initialQuantity REAL NOT NULL DEFAULT 0',
          );
          // Existing rows only tracked remaining stock; treat it as the
          // received quantity so bought/used reporting still makes sense.
          await db.execute(
            'UPDATE product_batches SET initialQuantity = quantity WHERE initialQuantity = 0',
          );
        }
      } catch (e) {
        developer.log('Batch migration error: $e', name: 'DatabaseService');
      }
    }

    // Goods Received Notes Table (NEW)
    final grnTableExists = await _tableExists(db, 'goods_received_notes');
    if (!grnTableExists) {
      await db.execute('''
        CREATE TABLE goods_received_notes (
          id TEXT PRIMARY KEY,
          grnNumber TEXT UNIQUE NOT NULL,
          supplierId TEXT NOT NULL,
          supplierName TEXT NOT NULL,
          items TEXT NOT NULL,
          total REAL NOT NULL,
          receivedBy TEXT NOT NULL DEFAULT '',
          notes TEXT NOT NULL DEFAULT '',
          receivedDate TEXT NOT NULL,
          createdAt TEXT NOT NULL
        )
      ''');
    }

    // Refund/Return Table (NEW)
    final refundsTableExists = await _tableExists(db, 'refund_returns');
    if (!refundsTableExists) {
      await db.execute('''
        CREATE TABLE refund_returns (
          id TEXT PRIMARY KEY,
          originalSaleId TEXT NOT NULL,
          invoiceNumber TEXT NOT NULL DEFAULT '',
          items TEXT NOT NULL,
          totalRefundAmount REAL NOT NULL,
          refundMethod TEXT NOT NULL,
          status TEXT NOT NULL,
          notes TEXT,
          processedBy TEXT,
          requesterId TEXT NOT NULL DEFAULT '',
          requesterName TEXT NOT NULL DEFAULT '',
          requestDate TEXT NOT NULL,
          processedDate TEXT,
          createdAt TEXT NOT NULL,
          FOREIGN KEY (originalSaleId) REFERENCES sales(id)
        )
      ''');
    } else {
      try {
        final columns = await db.rawQuery('PRAGMA table_info(refund_returns)');
        final names = columns.map((col) => col['name'] as String).toSet();

        if (!names.contains('requesterId')) {
          await db.execute(
            "ALTER TABLE refund_returns ADD COLUMN requesterId TEXT NOT NULL DEFAULT ''",
          );
        }
        if (!names.contains('requesterName')) {
          await db.execute(
            "ALTER TABLE refund_returns ADD COLUMN requesterName TEXT NOT NULL DEFAULT ''",
          );
        }
        if (!names.contains('invoiceNumber')) {
          await db.execute(
            "ALTER TABLE refund_returns ADD COLUMN invoiceNumber TEXT NOT NULL DEFAULT ''",
          );
        }
      } catch (e) {
        developer.log('Refund migration error: $e', name: 'DatabaseService');
      }
    }

    // Purchase Orders Table (NEW)
    final purchaseOrderTableExists =
        await _tableExists(db, 'purchase_orders');
    if (!purchaseOrderTableExists) {
      await db.execute('''
        CREATE TABLE purchase_orders (
          id TEXT PRIMARY KEY,
          orderNumber TEXT UNIQUE NOT NULL,
          supplierId TEXT NOT NULL,
          supplierName TEXT NOT NULL,
          items TEXT NOT NULL,
          subtotal REAL NOT NULL,
          total REAL NOT NULL,
          status TEXT NOT NULL,
          notes TEXT NOT NULL DEFAULT '',
          orderDate TEXT NOT NULL,
          receivedDate TEXT,
          FOREIGN KEY (supplierId) REFERENCES suppliers(id)
        )
      ''');
    }

    // Expenses Table (NEW)
    final expenseTableExists = await _tableExists(db, 'expenses');
    if (!expenseTableExists) {
      await db.execute('''
        CREATE TABLE expenses (
          id TEXT PRIMARY KEY,
          description TEXT NOT NULL,
          category TEXT NOT NULL,
          amount REAL NOT NULL,
          expenseDate TEXT NOT NULL,
          notes TEXT NOT NULL DEFAULT '',
          recordedBy TEXT NOT NULL DEFAULT ''
        )
      ''');
    }

    // Wastage Table (NEW)
    final wastageTableExists = await _tableExists(db, 'wastages');
    if (!wastageTableExists) {
      await db.execute('''
        CREATE TABLE wastages (
          id TEXT PRIMARY KEY,
          productId TEXT NOT NULL,
          productName TEXT NOT NULL,
          quantity REAL NOT NULL,
          reason TEXT NOT NULL,
          lossValue REAL NOT NULL,
          batchId TEXT NOT NULL DEFAULT '',
          batchNumber TEXT NOT NULL DEFAULT '',
          notes TEXT NOT NULL DEFAULT '',
          recordedBy TEXT NOT NULL DEFAULT '',
          wastageDate TEXT NOT NULL,
          createdAt TEXT NOT NULL,
          FOREIGN KEY (productId) REFERENCES products(id)
        )
      ''');
    }

    // Supplier payments (cash / cheque made TO suppliers for goods received)
    final supplierPaymentsTableExists =
        await _tableExists(db, 'supplier_payments');
    if (!supplierPaymentsTableExists) {
      await db.execute('''
        CREATE TABLE supplier_payments (
          id TEXT PRIMARY KEY,
          supplierId TEXT NOT NULL,
          supplierName TEXT NOT NULL DEFAULT '',
          amount REAL NOT NULL,
          method TEXT NOT NULL,
          chequeNumber TEXT NOT NULL DEFAULT '',
          bankName TEXT NOT NULL DEFAULT '',
          chequeDate TEXT,
          note TEXT NOT NULL DEFAULT '',
          paymentDate TEXT NOT NULL,
          createdAt TEXT NOT NULL,
          FOREIGN KEY (supplierId) REFERENCES suppliers(id)
        )
      ''');
    }

    // Shop Settings Table
    final settingsTableExists = await _tableExists(db, 'shop_settings');
    if (!settingsTableExists) {
      await db.execute('''
        CREATE TABLE shop_settings (
          shopName TEXT PRIMARY KEY,
          address TEXT NOT NULL,
          phone TEXT NOT NULL,
          email TEXT NOT NULL,
          currency TEXT NOT NULL,
          currencySymbol TEXT NOT NULL,
          printerName TEXT NOT NULL,
          enablePrinting INTEGER NOT NULL,
          paperWidth INTEGER NOT NULL,
          backupLocalPath TEXT NOT NULL DEFAULT '',
          enableGoogleDriveBackup INTEGER NOT NULL DEFAULT 0,
          googleDriveAccessToken TEXT NOT NULL DEFAULT '',
          googleDriveFolderId TEXT NOT NULL DEFAULT '',
          googleDriveAdminEmail TEXT NOT NULL DEFAULT '',
          isServerMode INTEGER NOT NULL DEFAULT 0,
          networkPort INTEGER NOT NULL DEFAULT 8180,
          serverIpFallback TEXT NOT NULL DEFAULT '',
          useAutoDiscovery INTEGER NOT NULL DEFAULT 1,
          cashDrawerEnabled INTEGER NOT NULL DEFAULT 1,
          cashDrawerPin INTEGER NOT NULL DEFAULT 2,
          cashDrawerPulseOnMs INTEGER NOT NULL DEFAULT 120,
          cashDrawerPulseOffMs INTEGER NOT NULL DEFAULT 240,
          cashDrawerPrinterName TEXT NOT NULL DEFAULT '',
          cashDrawerOpenOnCardOnly INTEGER NOT NULL DEFAULT 1,
          updatedAt TEXT NOT NULL
        )
      ''');

      // Insert default shop settings only on first creation
      try {
        await db.insert('shop_settings', ShopSettings().toMap());
      } catch (e) {
        // Already exists
      }
    } else {
      try {
        final columns = await db.rawQuery('PRAGMA table_info(shop_settings)');
        final names = columns
            .map((col) => col['name'] as String)
            .toSet();

        if (!names.contains('backupLocalPath')) {
          await db.execute(
            "ALTER TABLE shop_settings ADD COLUMN backupLocalPath TEXT NOT NULL DEFAULT ''",
          );
        }
        if (!names.contains('enableGoogleDriveBackup')) {
          await db.execute(
            'ALTER TABLE shop_settings ADD COLUMN enableGoogleDriveBackup INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (!names.contains('googleDriveAccessToken')) {
          await db.execute(
            "ALTER TABLE shop_settings ADD COLUMN googleDriveAccessToken TEXT NOT NULL DEFAULT ''",
          );
        }
        if (!names.contains('googleDriveFolderId')) {
          await db.execute(
            "ALTER TABLE shop_settings ADD COLUMN googleDriveFolderId TEXT NOT NULL DEFAULT ''",
          );
        }
        if (!names.contains('googleDriveAdminEmail')) {
          await db.execute(
            "ALTER TABLE shop_settings ADD COLUMN googleDriveAdminEmail TEXT NOT NULL DEFAULT ''",
          );
        }
        if (!names.contains('isServerMode')) {
          await db.execute(
            'ALTER TABLE shop_settings ADD COLUMN isServerMode INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (!names.contains('networkPort')) {
          await db.execute(
            'ALTER TABLE shop_settings ADD COLUMN networkPort INTEGER NOT NULL DEFAULT 8180',
          );
        }
        if (!names.contains('serverIpFallback')) {
          await db.execute(
            "ALTER TABLE shop_settings ADD COLUMN serverIpFallback TEXT NOT NULL DEFAULT ''",
          );
        }
        if (!names.contains('useAutoDiscovery')) {
          await db.execute(
            'ALTER TABLE shop_settings ADD COLUMN useAutoDiscovery INTEGER NOT NULL DEFAULT 1',
          );
        }
        if (!names.contains('cashDrawerEnabled')) {
          await db.execute(
            'ALTER TABLE shop_settings ADD COLUMN cashDrawerEnabled INTEGER NOT NULL DEFAULT 1',
          );
        }
        if (!names.contains('cashDrawerPin')) {
          await db.execute(
            'ALTER TABLE shop_settings ADD COLUMN cashDrawerPin INTEGER NOT NULL DEFAULT 2',
          );
        }
        if (!names.contains('cashDrawerPulseOnMs')) {
          await db.execute(
            'ALTER TABLE shop_settings ADD COLUMN cashDrawerPulseOnMs INTEGER NOT NULL DEFAULT 120',
          );
        }
        if (!names.contains('cashDrawerPulseOffMs')) {
          await db.execute(
            'ALTER TABLE shop_settings ADD COLUMN cashDrawerPulseOffMs INTEGER NOT NULL DEFAULT 240',
          );
        }
        if (!names.contains('cashDrawerPrinterName')) {
          await db.execute(
            "ALTER TABLE shop_settings ADD COLUMN cashDrawerPrinterName TEXT NOT NULL DEFAULT ''",
          );
        }
        if (!names.contains('cashDrawerOpenOnCardOnly')) {
          await db.execute(
            'ALTER TABLE shop_settings ADD COLUMN cashDrawerOpenOnCardOnly INTEGER NOT NULL DEFAULT 1',
          );
        }
      } catch (e) {
        developer.log('Settings migration error: $e', name: 'DatabaseService');
      }
    }

    // ============== FEATURE TABLES ==============
    // Reload Cards (value ledger: each row is a Bought or Sold reload unit).
    final reloadTableExists = await _tableExists(db, 'reload_cards');
    if (!reloadTableExists) {
      await db.execute('''
        CREATE TABLE reload_cards (
          id TEXT PRIMARY KEY,
          cardNumber TEXT NOT NULL DEFAULT '',
          batchId TEXT NOT NULL DEFAULT '',
          supplier TEXT NOT NULL DEFAULT '',
          value REAL NOT NULL,
          cost REAL NOT NULL DEFAULT 0,
          status TEXT NOT NULL,
          customerPhone TEXT NOT NULL DEFAULT '',
          customerName TEXT NOT NULL DEFAULT '',
          createdAt TEXT NOT NULL,
          usedAt TEXT NOT NULL DEFAULT '',
          notes TEXT NOT NULL DEFAULT ''
        )
      ''');
    } else {
      try {
        final reloadCols = await db.rawQuery('PRAGMA table_info(reload_cards)');
        final hasBatchId =
            reloadCols.any((col) => col['name'] == 'batchId');
        if (!hasBatchId) {
          await db.execute(
            "ALTER TABLE reload_cards ADD COLUMN batchId TEXT NOT NULL DEFAULT ''",
          );
        }
      } catch (e) {
        developer.log('Reload migration error: $e', name: 'DatabaseService');
      }
    }

    // Recipes (repack/packing recipes).
    final recipesTableExists = await _tableExists(db, 'recipes');
    if (!recipesTableExists) {
      await db.execute('''
        CREATE TABLE recipes (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          finishedProductId TEXT NOT NULL,
          finishedProductName TEXT NOT NULL,
          yieldQuantity REAL NOT NULL,
          notes TEXT NOT NULL DEFAULT '',
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL
        )
      ''');
    }

    final recipeItemsTableExists = await _tableExists(db, 'recipe_items');
    if (!recipeItemsTableExists) {
      await db.execute('''
        CREATE TABLE recipe_items (
          id TEXT PRIMARY KEY,
          recipeId TEXT NOT NULL,
          componentProductId TEXT NOT NULL,
          componentName TEXT NOT NULL,
          quantityNeeded REAL NOT NULL,
          unit TEXT NOT NULL DEFAULT 'pcs'
        )
      ''');
    }

    // Productions (completed repack runs).
    final productionsTableExists = await _tableExists(db, 'productions');
    if (!productionsTableExists) {
      await db.execute('''
        CREATE TABLE productions (
          id TEXT PRIMARY KEY,
          recipeId TEXT NOT NULL,
          recipeName TEXT NOT NULL,
          finishedProductId TEXT NOT NULL,
          finishedProductName TEXT NOT NULL,
          quantityProduced REAL NOT NULL,
          totalComponentCost REAL NOT NULL,
          unitCost REAL NOT NULL,
          batchNumber TEXT NOT NULL DEFAULT '',
          notes TEXT NOT NULL DEFAULT '',
          producedAt TEXT NOT NULL,
          createdAt TEXT NOT NULL,
          producedBy TEXT NOT NULL DEFAULT ''
        )
      ''');
    }

    final productionComponentsTableExists =
        await _tableExists(db, 'production_components');
    if (!productionComponentsTableExists) {
      await db.execute('''
        CREATE TABLE production_components (
          id TEXT PRIMARY KEY,
          productionId TEXT NOT NULL,
          componentProductId TEXT NOT NULL,
          componentName TEXT NOT NULL,
          quantityUsed REAL NOT NULL,
          costPerUnit REAL NOT NULL,
          batchId TEXT NOT NULL DEFAULT '',
          batchNumber TEXT NOT NULL DEFAULT ''
        )
      ''');
    }

    // Cash drawer pulse events (exactly-once tracking per sale).
    final drawerTableExists = await _tableExists(db, 'drawer_events');
    if (!drawerTableExists) {
      await db.execute('''
        CREATE TABLE drawer_events (
          saleId TEXT PRIMARY KEY,
          invoiceNumber TEXT NOT NULL DEFAULT '',
          isCardOnly INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL,
          printerName TEXT NOT NULL DEFAULT '',
          errorMessage TEXT NOT NULL DEFAULT '',
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL
        )
      ''');
    }
  }

  Future<bool> _tableExists(Database db, String tableName) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );
    return result.isNotEmpty;
  }

  // ============== CATEGORIES ==============
  Future<void> insertCategory(Category category) async {
    final db = await database;
    await db.insert(
      'categories',
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    BackupService.notifyTransaction('category');
  }

  Future<List<Category>> getAllCategories() async {
    final db = await database;
    final maps = await db.query('categories');
    return maps.map(Category.fromMap).toList();
  }

  Future<Category?> getCategoryById(String id) async {
    final db = await database;
    final maps = await db.query('categories', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return Category.fromMap(maps.first);
    }
    return null;
  }

  Future<Category?> getCategoryByName(String name) async {
    final db = await database;
    final maps =
        await db.query('categories', where: 'name = ?', whereArgs: [name]);
    if (maps.isNotEmpty) {
      return Category.fromMap(maps.first);
    }
    return null;
  }

  Future<void> updateCategory(Category category) async {
    final db = await database;
    await db.update(
      'categories',
      category.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
    BackupService.notifyTransaction('category');
  }

  Future<void> deleteCategory(String id) async {
    final db = await database;
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
    BackupService.notifyTransaction('category');
  }

  // ============== PRODUCTS ==============
  Future<void> insertProduct(Product product) async {
    try {
      final db = await database;

      // Check if product with same barcode already exists
      final existing = await db.query(
        'products',
        where: 'barcode = ?',
        whereArgs: [product.barcode],
      );

      if (existing.isNotEmpty) {
        throw Exception(
            'Product with barcode "${product.barcode}" already exists');
      }

      await db.insert(
        'products',
        product.toMap(),
        conflictAlgorithm: ConflictAlgorithm.fail,
      );
    } catch (e) {
      if (e.toString().contains('already exists')) {
        rethrow;
      }
      developer.log('Error inserting product: $e', name: 'DatabaseService');
      rethrow;
    }
    BackupService.notifyTransaction('product');
  }

  Future<List<Product>> getAllProducts() async {
    final db = await database;
    final maps = await db.query('products');
    return maps.map(Product.fromMap).toList();
  }

  // ============== LAN SYNC (catalog pull from the server PC) ==============
  /// Upserts the catalog pushed by the admin PC (server) into this cashier's
  /// local database so the terminal keeps working even offline. Every row is
  /// overwritten by its server copy (admin owns the catalog).
  Future<void> upsertCatalog({
    required List<Map<String, dynamic>> products,
    List<Map<String, dynamic>> categories = const [],
    List<Map<String, dynamic>> customers = const [],
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      for (final cat in categories) {
        final map = Map<String, dynamic>.from(cat);
        map['createdAt'] ??= now;
        map['updatedAt'] ??= now;
        try {
          await txn.insert(
            'categories',
            Category.fromMap(map).toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } catch (_) {
          // Name or id conflict with a locally created category: keep local.
        }
      }

      for (final prod in products) {
        final map = Map<String, dynamic>.from(prod);
        map['createdAt'] ??= now;
        map['updatedAt'] ??= now;
        try {
          await txn.insert(
            'products',
            Product.fromMap(map).toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } catch (_) {
          // Barcode or id conflict with a locally created product: keep local.
        }
      }

      for (final cust in customers) {
        final map = Map<String, dynamic>.from(cust);
        try {
          await txn.insert(
            'customers',
            Customer.fromMap(map).toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } catch (_) {
          // Keep the local customer on any conflict.
        }
      }
    });
    BackupService.notifyTransaction('catalog sync');
  }

  /// Records a sale pushed to this PC by another terminal (the cashier).
  /// Assigns the *server's* invoice number so invoice sequences never collide
  /// across machines, deducts server-side stock FIFO, and is idempotent: a sale
  /// already received (same local sale id) is never stored twice.
  Future<Sale> recordRemoteSale(Sale incoming) async {
    final db = await database;
    // Idempotent: a sale already pushed with the same cashier-side id is a
    // retry, not a new sale.
    final existing = await db.query(
      'sales',
      where: 'id = ?',
      whereArgs: [incoming.id],
    );
    if (existing.isNotEmpty) {
      return incoming;
    }

    final cartItems = <CartItem>[];
    for (final item in incoming.items) {
      final product = await getProductById(item.productId);
      if (product == null || product.quantity <= 0) {
        continue;
      }
      cartItems.add(CartItem(
        id: product.id,
        product: product,
        quantity: item.quantity,
        unitPrice: product.sellingPrice,
      ));
    }
    if (cartItems.isEmpty) {
      throw Exception('Remote sale has no items with available stock');
    }

    final sequence = await getNextInvoiceSequence();
    final serverInvoice = formatInvoiceNumber(sequence);

    final sale = Sale(
      id: incoming.id,
      cashierId: incoming.cashierId,
      cashierName: incoming.cashierName,
      items: incoming.items,
      subtotal: incoming.subtotal,
      totalDiscount: incoming.totalDiscount,
      totalAmount: incoming.totalAmount,
      amountReceived: incoming.amountReceived,
      balance: incoming.balance,
      invoiceNumber: serverInvoice,
      paymentMethod: incoming.paymentMethod,
      saleDate: incoming.saleDate,
      notes: incoming.notes,
    );
    await completeSale(sale, cartItems);
    BackupService.notifyTransaction('sale');
    return sale;
  }

  Future<Product?> getProductById(String id) async {
    final db = await database;
    final maps = await db.query('products', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return Product.fromMap(maps.first);
    }
    return null;
  }

  Future<Product?> getProductByBarcode(String barcode) async {
    final db = await database;
    final maps = await db.query(
      'products',
      where: 'barcode = ?',
      whereArgs: [barcode],
    );
    if (maps.isNotEmpty) {
      return Product.fromMap(maps.first);
    }
    return null;
  }

  Future<void> updateProduct(Product product) async {
    final db = await database;
    await db.update(
      'products',
      product.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
    BackupService.notifyTransaction('product');
  }

  Future<void> deleteProduct(String id) async {
    final db = await database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
    BackupService.notifyTransaction('product');
  }

  Future<List<Product>> searchProducts(String query) async {
    final db = await database;
    final maps = await db.query(
      'products',
      where: 'name LIKE ? OR barcode LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
    );
    return maps.map(Product.fromMap).toList();
  }

  Future<List<Product>> getProductsByCategory(String categoryId) async {
    final db = await database;
    final maps = await db.query(
      'products',
      where: 'categoryId = ?',
      whereArgs: [categoryId],
    );
    return maps.map(Product.fromMap).toList();
  }

  // ============== USERS ==============
  Future<void> insertUser(User user) async {
    final db = await database;
    await db.insert(
      'users',
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    BackupService.notifyTransaction('user');
  }

  Future<User?> getUserByUsername(String username) async {
    final db = await database;
    final maps = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
    );
    if (maps.isNotEmpty) {
      return User.fromMap(maps.first);
    }
    return null;
  }

  Future<User?> getUserById(String id) async {
    final db = await database;
    final maps = await db.query('users', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return User.fromMap(maps.first);
    }
    return null;
  }

  Future<List<User>> getAllUsers() async {
    final db = await database;
    final maps = await db.query('users');
    return maps.map(User.fromMap).toList();
  }

  Future<void> updateUser(User user) async {
    final db = await database;
    await db.update(
      'users',
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
    BackupService.notifyTransaction('user');
  }

  Future<void> deleteUser(String id) async {
    final db = await database;
    await db.delete('users', where: 'id = ?', whereArgs: [id]);
    BackupService.notifyTransaction('user');
  }

  // ============== SALES ==============
  Future<void> insertSale(Sale sale) async {
    final db = await database;
    final saleData = sale.toMap();
    saleData['items'] = jsonEncode(sale.items.map((e) => e.toMap()).toList());
    await db.insert(
      'sales',
      saleData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    BackupService.notifyTransaction('sale');
  }

  Future<List<Sale>> getAllSales() async {
    final db = await database;
    final maps = await db.query('sales', orderBy: 'saleDate DESC');
    return maps.map((map) {
      final saleData = Map<String, dynamic>.from(map);
      saleData['items'] = jsonDecode(saleData['items'] as String);
      return Sale.fromMap(saleData);
    }).toList();
  }

  Future<Sale?> getSaleById(String id) async {
    final db = await database;
    final maps = await db.query('sales', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      final saleData = Map<String, dynamic>.from(maps.first);
      saleData['items'] = jsonDecode(saleData['items'] as String);
      return Sale.fromMap(saleData);
    }
    return null;
  }

  Future<List<Sale>> getSalesByDate(DateTime date) async {
    final db = await database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final maps = await db.query(
      'sales',
      where: 'saleDate >= ? AND saleDate < ?',
      whereArgs: [startOfDay.toIso8601String(), endOfDay.toIso8601String()],
      orderBy: 'saleDate DESC',
    );

    return maps.map((map) {
      final saleData = Map<String, dynamic>.from(map);
      saleData['items'] = jsonDecode(saleData['items'] as String);
      return Sale.fromMap(saleData);
    }).toList();
  }

  Future<List<Sale>> getSalesByDateRange(DateTime start, DateTime end) async {
    final db = await database;
    final maps = await db.query(
      'sales',
      where: 'saleDate >= ? AND saleDate <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'saleDate DESC',
    );

    return maps.map((map) {
      final saleData = Map<String, dynamic>.from(map);
      saleData['items'] = jsonDecode(saleData['items'] as String);
      return Sale.fromMap(saleData);
    }).toList();
  }

  // ============== RELOAD CARDS (VALUE LEDGER) ==============
  /// All reload records, newest first. Each row is one Bought or Sold reload
  /// unit; sold rows carry a [ReloadCard.batchId] back to the bought batch.
  Future<List<ReloadCard>> getAllReloadCards() async {
    final db = await database;
    final maps = await db.query('reload_cards', orderBy: 'createdAt DESC');
    return maps.map(ReloadCard.fromMap).toList();
  }

  Future<void> insertReloadCard(ReloadCard card) async {
    final db = await database;
    await db.insert(
      'reload_cards',
      card.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    BackupService.notifyTransaction('reload card');
  }

  Future<void> updateReloadCard(ReloadCard card) async {
    final db = await database;
    await db.update(
      'reload_cards',
      card.toMap(),
      where: 'id = ?',
      whereArgs: [card.id],
    );
    BackupService.notifyTransaction('reload card');
  }

  Future<void> deleteReloadCard(String id) async {
    final db = await database;
    await db.delete('reload_cards', where: 'id = ?', whereArgs: [id]);
    BackupService.notifyTransaction('reload card');
  }

  // ============== CASH DRAWER EVENTS ==============
  /// True when a drawer pulse has already been successfully sent for a sale,
  /// so a double tap / app restart can never pop the drawer twice.
  Future<bool> wasDrawerCommandSent(String saleId) async {
    final db = await database;
    final maps = await db.query(
      'drawer_events',
      columns: ['status'],
      where: 'saleId = ? AND status = ?',
      whereArgs: [saleId, 'sent'],
      limit: 1,
    );
    return maps.isNotEmpty;
  }

  /// Records the outcome of a drawer pulse attempt (exactly one row per sale).
  Future<void> upsertDrawerEvent({
    required String saleId,
    required String invoiceNumber,
    required bool isCardOnly,
    required String status,
    required String printerName,
    required String errorMessage,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final existing = await db.query(
      'drawer_events',
      columns: ['saleId'],
      where: 'saleId = ?',
      whereArgs: [saleId],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('drawer_events', {
        'saleId': saleId,
        'invoiceNumber': invoiceNumber,
        'isCardOnly': isCardOnly ? 1 : 0,
        'status': status,
        'printerName': printerName,
        'errorMessage': errorMessage,
        'createdAt': now,
        'updatedAt': now,
      });
    } else {
      await db.update(
        'drawer_events',
        {
          'invoiceNumber': invoiceNumber,
          'isCardOnly': isCardOnly ? 1 : 0,
          'status': status,
          'printerName': printerName,
          'errorMessage': errorMessage,
          'updatedAt': now,
        },
        where: 'saleId = ?',
        whereArgs: [saleId],
      );
    }
  }

  // ============== INVOICE NUMBERING ==============
  /// Atomically increments and returns the next sale invoice sequence.
  Future<int> getNextInvoiceSequence() async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'counters',
        where: 'name = ?',
        whereArgs: ['sale_invoice'],
      );
      var current = rows.isNotEmpty ? (rows.first['value'] as int) : 0;
      current += 1;
      if (rows.isEmpty) {
        await txn.insert('counters', {'name': 'sale_invoice', 'value': current});
      } else {
        await txn.update(
          'counters',
          {'value': current},
          where: 'name = ?',
          whereArgs: ['sale_invoice'],
        );
      }
      return current;
    });
  }

  // ============== FIFO / BATCH PRICING ==============
  /// Batches for a product that still have stock, oldest received first.
  Future<List<ProductBatch>> _fifoBatches(
    DatabaseExecutor db,
    String productId,
  ) async {
    final maps = await db.query(
      'product_batches',
      where: 'productId = ? AND quantity > 0',
      whereArgs: [productId],
    );
    final batches = maps.map(ProductBatch.fromMap).toList();
    batches.sort((a, b) {
      final byDate = a.receivedDate.compareTo(b.receivedDate);
      if (byDate != 0) return byDate;
      final expA = a.expiryDate;
      final expB = b.expiryDate;
      if (expA != null && expB != null) return expA.compareTo(expB);
      if (expA != null) return -1;
      if (expB != null) return 1;
      return 0;
    });
    return batches;
  }

  /// The price to charge for the next unit of [product], taken from the oldest
  /// batch that has a batch-specific selling price. Falls back to the
  /// product's current selling price when no priced batch is available.
  Future<double> getEffectiveSellingPrice(Product product) async {
    final db = await database;
    final batches = await _fifoBatches(db, product.id);
    for (final batch in batches) {
      if (batch.sellingPrice > 0) return batch.sellingPrice;
    }
    return product.sellingPrice;
  }

  /// Works out which batches (oldest first) would fulfil [quantity] of
  /// [product], the effective sale price and the weighted cost. Read-only;
  /// the actual deduction happens in [completeSale].
  Future<FifoPlan> getFifoPlan(Product product, double quantity) async {
    final db = await database;
    final batches = await _fifoBatches(db, product.id);

    final allocations = <BatchAllocation>[];
    var remaining = quantity;
    double costSum = 0;
    double priceSum = 0;
    var qtySum = 0.0;

    for (final batch in batches) {
      if (remaining <= 0) break;
      final take = batch.quantity < remaining ? batch.quantity : remaining;
      final price =
          batch.sellingPrice > 0 ? batch.sellingPrice : product.sellingPrice;
      allocations.add(BatchAllocation(
        batchId: batch.id,
        batchNumber: batch.batchNumber,
        quantity: take,
        unitPrice: price,
        costPrice: batch.price,
      ));
      costSum += batch.price * take;
      priceSum += price * take;
      qtySum += take;
      remaining -= take;
    }

    if (remaining > 0) {
      allocations.add(BatchAllocation(
        batchId: '',
        batchNumber: 'No batch',
        quantity: remaining,
        unitPrice: product.sellingPrice,
        costPrice: product.buyingPrice,
      ));
      costSum += product.buyingPrice * remaining;
      priceSum += product.sellingPrice * remaining;
      qtySum += remaining;
    }

    return FifoPlan(
      allocations: allocations,
      effectivePrice:
          qtySum > 0 ? priceSum / qtySum : product.sellingPrice,
      weightedCost: qtySum > 0 ? costSum / qtySum : product.buyingPrice,
    );
  }

  /// Persists a completed sale and deducts stock from product batches (FIFO)
  /// and the product total in a single transaction. This keeps batch prices
  /// accurate: stock bought at the old price is sold first at the old price.
  Future<void> completeSale(Sale sale, List<CartItem> items) async {
    final db = await database;
    await db.transaction((txn) async {
      final saleData = sale.toMap();
      saleData['items'] =
          jsonEncode(sale.items.map((e) => e.toMap()).toList());
      await txn.insert(
        'sales',
        saleData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final now = DateTime.now().toIso8601String();
      for (final item in items) {
        var remaining = item.quantity;
        final batches = await _fifoBatches(txn, item.product.id);
        for (final batch in batches) {
          if (remaining <= 0) break;
          final take = batch.quantity < remaining ? batch.quantity : remaining;
          await txn.update(
            'product_batches',
            {'quantity': batch.quantity - take},
            where: 'id = ?',
            whereArgs: [batch.id],
          );
          remaining -= take;
        }

        final productMaps = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [item.product.id],
        );
        if (productMaps.isNotEmpty) {
          final product = Product.fromMap(productMaps.first);
          final newQty =
              (product.quantity - item.quantity).clamp(0.0, double.infinity);
          await txn.update(
            'products',
            {'quantity': newQty, 'updatedAt': now},
            where: 'id = ?',
            whereArgs: [product.id],
          );
        }

        await txn.insert('stock_history', {
          'productId': item.product.id,
          'productName': item.product.name,
          'quantityChanged': -item.quantity,
          'reason': 'Sale ${sale.invoiceLabel}',
          'createdAt': now,
        });
      }
    });
    BackupService.notifyTransaction('bill');
  }

  /// Look up a product by barcode (exact) or, failing that, by exact name.
  /// This lets a scanner configured to send the item code work even when the
  /// code differs from the barcode.
  Future<Product?> getProductByCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return null;
    final byBarcode = await getProductByBarcode(trimmed);
    if (byBarcode != null) return byBarcode;
    final db = await database;
    final maps = await db.query(
      'products',
      where: 'LOWER(name) = ?',
      whereArgs: [trimmed.toLowerCase()],
    );
    if (maps.isNotEmpty) return Product.fromMap(maps.first);
    return null;
  }

  // ============== GOODS RECEIVED NOTES ==============
  /// Returns the next daily GRN number, e.g. GRN-20260919-0003.
  Future<String> getNextGrnNumber() async {
    final db = await database;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM goods_received_notes WHERE receivedDate >= ?',
      [startOfDay],
    );
    final count = rows.isNotEmpty ? (rows.first['c'] as int) : 0;
    String two(int n) => n.toString().padLeft(2, '0');
    final seq = (count + 1).toString().padLeft(4, '0');
    return 'GRN-${now.year}${two(now.month)}${two(now.day)}-$seq';
  }

  /// Records received goods: increases stock, creates/merges a batch with its
  /// own cost and selling price, updates the product prices to the latest and
  /// writes stock history — all atomically.
  Future<void> receiveGoodsNote(GoodsReceivedNote grn) async {
    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      for (final item in grn.items) {
        final productMaps = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [item.productId],
        );
        if (productMaps.isEmpty) continue;
        final product = Product.fromMap(productMaps.first);

        await txn.update(
          'products',
          {
            'quantity': product.quantity + item.quantity,
            'buyingPrice': item.costPrice,
            'sellingPrice':
                item.sellingPrice > 0 ? item.sellingPrice : product.sellingPrice,
            'updatedAt': now,
          },
          where: 'id = ?',
          whereArgs: [item.productId],
        );

        final batchNumber =
            item.batchNumber.isNotEmpty ? item.batchNumber : grn.grnNumber;
        final existing = await txn.query(
          'product_batches',
          where: 'productId = ? AND batchNumber = ?',
          whereArgs: [item.productId, batchNumber],
        );
        if (existing.isNotEmpty) {
          final batch = ProductBatch.fromMap(existing.first);
          await txn.update(
            'product_batches',
            {
              'quantity': batch.quantity + item.quantity,
              'initialQuantity': batch.initialQuantity + item.quantity,
              'price': item.costPrice,
              'sellingPrice': item.sellingPrice > 0
                  ? item.sellingPrice
                  : batch.sellingPrice,
            },
            where: 'id = ?',
            whereArgs: [batch.id],
          );
        } else {
          await txn.insert('product_batches', {
            'id': const Uuid().v4(),
            'productId': item.productId,
            'batchNumber': batchNumber,
            'price': item.costPrice,
            'sellingPrice': item.sellingPrice,
            'expiryDate': item.expiryDate?.toIso8601String(),
            'quantity': item.quantity,
            'initialQuantity': item.quantity,
            'receivedDate': grn.receivedDate.toIso8601String(),
            'supplierId': grn.supplierId,
            'notes': 'GRN ${grn.grnNumber}',
            'createdAt': now,
          });
        }

        await txn.insert('stock_history', {
          'productId': item.productId,
          'productName': item.productName,
          'quantityChanged': item.quantity,
          'reason': 'GRN ${grn.grnNumber} received',
          'createdAt': now,
        });
      }

      final data = grn.toMap();
      data['items'] = jsonEncode(grn.items.map((e) => e.toMap()).toList());
      await txn.insert(
        'goods_received_notes',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    BackupService.notifyTransaction('goods received');
  }

  Future<List<GoodsReceivedNote>> getAllGoodsReceivedNotes() async {
    final db = await database;
    final maps =
        await db.query('goods_received_notes', orderBy: 'receivedDate DESC');
    return maps.map(GoodsReceivedNote.fromMap).toList();
  }

  // ============== STOCK HISTORY ==============
  Future<void> addStockHistory(
    String productId,
    String productName,
    double quantityChanged,
    String reason,
  ) async {
    final db = await database;
    await db.insert('stock_history', {
      'productId': productId,
      'productName': productName,
      'quantityChanged': quantityChanged,
      'reason': reason,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getStockHistory(String productId) async {
    final db = await database;
    return db.query(
      'stock_history',
      where: 'productId = ?',
      whereArgs: [productId],
      orderBy: 'createdAt DESC',
    );
  }

  // ============== SHOP SETTINGS ==============
  Future<ShopSettings> getShopSettings() async {
    final db = await database;
    final maps = await db.query('shop_settings');
    if (maps.isNotEmpty) {
      return ShopSettings.fromMap(maps.first);
    }
    return ShopSettings();
  }

  Future<void> updateShopSettings(ShopSettings settings) async {
    final db = await database;
    final updated = await db.update(
      'shop_settings',
      settings.toMap(),
      where: '1 = 1',
    );

    if (updated == 0) {
      await db.insert('shop_settings', settings.toMap());
    }
    BackupService.notifyTransaction('shop settings');
  }

  // ============== REPORTS ==============
  Future<Map<String, dynamic>> getDailySalesReport(DateTime date) async {
    final sales = await getSalesByDate(date);

    double totalRevenue = 0;
    var totalTransactions = 0;
    var totalItemsSold = 0.0;
    final itemsBreakdown = <String, double>{};

    for (final sale in sales) {
      totalRevenue += sale.totalAmount;
      totalTransactions++;
      for (final item in sale.items) {
        totalItemsSold += item.quantity;
        itemsBreakdown[item.productName] =
            (itemsBreakdown[item.productName] ?? 0) + item.quantity;
      }
    }

    return {
      'date': date,
      'totalRevenue': totalRevenue,
      'totalTransactions': totalTransactions,
      'totalItemsSold': totalItemsSold,
      'itemsBreakdown': itemsBreakdown,
      'sales': sales,
    };
  }

  Future<Map<String, dynamic>> getMonthlySalesReport(
    int year,
    int month,
  ) async {
    final startDate = DateTime(year, month, 1);
    final endDate =
        month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);

    final sales = await getSalesByDateRange(
      startDate,
      endDate.subtract(const Duration(seconds: 1)),
    );

    double totalRevenue = 0;
    var totalTransactions = 0;
    final itemsBreakdown = <String, double>{};
    final dailyRevenue = <int, double>{};

    for (final sale in sales) {
      totalRevenue += sale.totalAmount;
      totalTransactions++;

      final day = sale.saleDate.day;
      dailyRevenue[day] = (dailyRevenue[day] ?? 0) + sale.totalAmount;

      for (final item in sale.items) {
        itemsBreakdown[item.productName] =
            (itemsBreakdown[item.productName] ?? 0) + item.quantity;
      }
    }

    // Sort items by quantity (best sellers first)
    final sortedItems = itemsBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return {
      'year': year,
      'month': month,
      'totalRevenue': totalRevenue,
      'totalTransactions': totalTransactions,
      'dailyRevenue': dailyRevenue,
      'bestSellingItems': sortedItems.take(10).toList(),
      'sales': sales,
    };
  }

  // ============== CUSTOMERS ==============
  Future<void> insertCustomer(Customer customer) async {
    final db = await database;
    await db.insert(
      'customers',
      customer.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    BackupService.notifyTransaction('customer');
  }

  Future<List<Customer>> getAllCustomers() async {
    final db = await database;
    final maps = await db.query('customers', orderBy: 'createdAt DESC');
    return maps.map(Customer.fromMap).toList();
  }

  Future<Customer?> getCustomerById(String id) async {
    final db = await database;
    final maps = await db.query('customers', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return Customer.fromMap(maps.first);
    }
    return null;
  }

  Future<Customer?> getCustomerByPhone(String phone) async {
    final db = await database;
    final maps =
        await db.query('customers', where: 'phone = ?', whereArgs: [phone]);
    if (maps.isNotEmpty) {
      return Customer.fromMap(maps.first);
    }
    return null;
  }

  Future<void> updateCustomer(Customer customer) async {
    final db = await database;
    await db.update(
      'customers',
      customer.toMap(),
      where: 'id = ?',
      whereArgs: [customer.id],
    );
    BackupService.notifyTransaction('customer');
  }

  Future<void> deleteCustomer(String id) async {
    final db = await database;
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
    BackupService.notifyTransaction('customer');
  }

  Future<List<Customer>> searchCustomers(String query) async {
    final db = await database;
    final maps = await db.query(
      'customers',
      where: 'name LIKE ? OR phone LIKE ? OR email LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
    );
    return maps.map(Customer.fromMap).toList();
  }

  Future<void> updateCustomerAfterSale(String customerId, double amount) async {
    final customer = await getCustomerById(customerId);
    if (customer != null) {
      final updatedCustomer = customer.copyWith(
        totalSpent: customer.totalSpent + amount,
        totalTransactions: customer.totalTransactions + 1,
        lastPurchaseDate: DateTime.now(),
      );
      await updateCustomer(updatedCustomer);
    }
  }

  /// Bumps the customer's spend totals after a completed sale.
  /// The POS is cash-and-carry only (no customer credit or loyalty).
  Future<void> updateCustomerPurchaseStats({
    required String customerId,
    required double amountSpent,
  }) async {
    final customer = await getCustomerById(customerId);
    if (customer == null) return;
    final updatedCustomer = customer.copyWith(
      totalSpent: customer.totalSpent + amountSpent,
      totalTransactions: customer.totalTransactions + 1,
      lastPurchaseDate: DateTime.now(),
    );
    await updateCustomer(updatedCustomer);
  }

  // ============== EXPENSES ==============
  Future<void> insertExpense(Expense expense) async {
    final db = await database;
    await db.insert(
      'expenses',
      expense.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    BackupService.notifyTransaction('expense');
  }

  Future<List<Expense>> getAllExpenses() async {
    final db = await database;
    final maps = await db.query('expenses', orderBy: 'expenseDate DESC');
    return maps.map(Expense.fromMap).toList();
  }

  Future<List<Expense>> getExpensesByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final db = await database;
    final maps = await db.query(
      'expenses',
      where: 'expenseDate >= ? AND expenseDate <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'expenseDate DESC',
    );
    return maps.map(Expense.fromMap).toList();
  }

  Future<void> deleteExpense(String id) async {
    final db = await database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
    BackupService.notifyTransaction('expense');
  }

  /// Compute profit for a date range.
  /// Profit = Revenue − COGS − Expenses.
  /// COGS uses the cost price recorded on each sale line at the time of the
  /// sale (the FIFO-weighted batch cost), falling back to the product's
  /// current buying price only for older rows that have no recorded cost.
  Future<Map<String, dynamic>> getProfitReport(
    DateTime start,
    DateTime end,
  ) async {
    final sales = await getSalesByDateRange(start, end);
    final expenses = await getExpensesByDateRange(start, end);
    final wastageReport = await getWastageReport(start, end);

    final products = await getAllProducts();
    final productById = <String, Product>{
      for (final p in products) p.id: p,
    };

    double totalRevenue = 0;
    double totalCogs = 0;
    for (final sale in sales) {
      totalRevenue += sale.totalAmount;
      for (final item in sale.items) {
        final unitCost = item.costPrice > 0
            ? item.costPrice
            : (productById[item.productId]?.buyingPrice ?? 0.0);
        totalCogs += unitCost * item.quantity;
      }
    }

    final totalExpenses =
        expenses.fold<double>(0, (sum, e) => sum + e.amount);
    final totalWastage = wastageReport['totalLoss'] as double;
    final grossProfit = totalRevenue - totalCogs;
    final netProfit = grossProfit - totalExpenses - totalWastage;

    return {
      'totalRevenue': totalRevenue,
      'totalCogs': totalCogs,
      'grossProfit': grossProfit,
      'totalExpenses': totalExpenses,
      'expenses': expenses,
      'totalWastage': totalWastage,
      'wastages': wastageReport['wastages'],
      'netProfit': netProfit,
    };
  }

  /// Whole-shop profit and loss for a date range.
  ///
  /// Every part of the business is included so the owner sees one honest
  /// number: billing (sales, discounts, cost of the goods sold), goods
  /// received from suppliers, wastage, refunds, running expenses, money paid
  /// to suppliers and what is still owed to them.
  Future<Map<String, dynamic>> getBusinessProfitLoss(
    DateTime start,
    DateTime end,
  ) async {
    final db = await database;
    final fromIso = start.toIso8601String();
    final toIso = end.toIso8601String();

    // ---- Billing -------------------------------------------------------
    final products = await getAllProducts();
    final costById = <String, double>{
      for (final p in products) p.id: p.buyingPrice.toDouble(),
    };

    final saleRows = await db.query(
      'sales',
      where: 'saleDate >= ? AND saleDate <= ?',
      whereArgs: [fromIso, toIso],
    );

    var revenue = 0.0;
    var discounts = 0.0;
    var cogs = 0.0;
    var itemsSold = 0.0;
    var cashSales = 0.0;
    var cardSales = 0.0;
    var splitSales = 0.0;

    for (final row in saleRows) {
      final total = (row['totalAmount'] as num?)?.toDouble() ?? 0;
      revenue += total;
      discounts += (row['totalDiscount'] as num?)?.toDouble() ?? 0;
      cashSales += (row['cashAmount'] as num?)?.toDouble() ?? 0;
      cardSales += (row['cardAmount'] as num?)?.toDouble() ?? 0;

      final items = row['items'];
      if (items is String) {
        try {
          final decoded = jsonDecode(items) as List;
          for (final raw in decoded) {
            final item = (raw as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            );
            final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
            final cost = (item['costPrice'] as num?)?.toDouble() ?? 0;
            itemsSold += qty;
            cogs += (cost > 0 ? cost : (costById[item['productId']] ?? 0)) * qty;
          }
        } catch (_) {
          // A single unreadable bill must never break the whole report.
        }
      }
    }

    final bills = saleRows.length;
    final grossProfit = revenue - cogs;

    // ---- Wastage -------------------------------------------------------
    final wasteRows = await db.query(
      'wastages',
      where: 'wastageDate >= ? AND wastageDate <= ?',
      whereArgs: [fromIso, toIso],
    );
    var wastageLoss = 0.0;
    var wastageUnits = 0.0;
    for (final row in wasteRows) {
      wastageLoss += (row['lossValue'] as num?)?.toDouble() ?? 0;
      wastageUnits += (row['quantity'] as num?)?.toDouble() ?? 0;
    }

    // ---- Refunds (money only leaves on a processed refund) --------------
    final refundRows = await db.query(
      'refund_returns',
      where: 'createdAt >= ? AND createdAt <= ?',
      whereArgs: [fromIso, toIso],
    );
    var refundLoss = 0.0;
    var refundPending = 0.0;
    var refundProcessedCount = 0;
    var refundPendingCount = 0;
    for (final row in refundRows) {
      final amount = (row['totalRefundAmount'] as num?)?.toDouble() ?? 0;
      final status = (row['status'] as String? ?? '').toLowerCase();
      if (status == 'processed') {
        refundLoss += amount;
        refundProcessedCount++;
      } else if (status == 'pending' || status == 'approved') {
        refundPending += amount;
        refundPendingCount++;
      }
    }

    // ---- Expenses ------------------------------------------------------
    final expenseRows = await db.query(
      'expenses',
      where: 'expenseDate >= ? AND expenseDate <= ?',
      whereArgs: [fromIso, toIso],
    );
    var expenseTotal = 0.0;
    final expenseByCategory = <String, double>{};
    for (final row in expenseRows) {
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      final category =
          (row['category'] as String? ?? '').trim().isEmpty
              ? 'Other'
              : (row['category'] as String).trim();
      expenseTotal += amount;
      expenseByCategory[category] =
          (expenseByCategory[category] ?? 0) + amount;
    }

    // ---- Goods received (stock bought) ---------------------------------
    final grnRows = await db.query(
      'goods_received_notes',
      where: 'receivedDate >= ? AND receivedDate <= ?',
      whereArgs: [fromIso, toIso],
    );
    var purchaseTotal = 0.0;
    for (final row in grnRows) {
      purchaseTotal += (row['total'] as num?)?.toDouble() ?? 0;
    }

    // ---- Supplier payments (cash / cheque out) -------------------------
    final paymentRows = await db.query(
      'supplier_payments',
      where: 'paymentDate >= ? AND paymentDate <= ?',
      whereArgs: [fromIso, toIso],
    );
    var supplierPaid = 0.0;
    var supplierPaidCash = 0.0;
    var supplierPaidCheque = 0.0;
    for (final row in paymentRows) {
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      final method = (row['method'] as String? ?? '').toLowerCase();
      supplierPaid += amount;
      if (method.contains('cheq')) {
        supplierPaidCheque += amount;
      } else {
        supplierPaidCash += amount;
      }
    }

    // ---- Money still owed to suppliers ---------------------------------
    var supplierOutstanding = 0.0;
    try {
      final suppliers = await getAllSuppliers(includeInactive: true);
      for (final supplier in suppliers) {
        supplierOutstanding += await getSupplierOutstanding(supplier.id);
      }
    } catch (_) {}

    // ---- Stock on hand -------------------------------------------------
    var stockValue = 0.0;
    var stockItems = 0;
    for (final p in products) {
      if (p.quantity > 0) {
        stockItems++;
        stockValue += p.buyingPrice * p.quantity;
      }
    }

    final totalLoss = cogs +
        wastageLoss +
        refundLoss +
        expenseTotal;
    final netProfit = revenue - totalLoss;

    return {
      'revenue': revenue,
      'discounts': discounts,
      'cogs': cogs,
      'grossProfit': grossProfit,
      'grossMarginPct': revenue > 0 ? (grossProfit / revenue) * 100 : 0.0,
      'bills': bills,
      'itemsSold': itemsSold,
      'cashSales': cashSales,
      'cardSales': cardSales,
      'splitSales': splitSales,
      'wastageLoss': wastageLoss,
      'wastageUnits': wastageUnits,
      'wastageCount': wasteRows.length,
      'refundLoss': refundLoss,
      'refundCount': refundProcessedCount,
      'refundPending': refundPending,
      'refundPendingCount': refundPendingCount,
      'expenseTotal': expenseTotal,
      'expenseCount': expenseRows.length,
      'expenseByCategory': expenseByCategory,
      'purchaseTotal': purchaseTotal,
      'purchaseCount': grnRows.length,
      'supplierPaid': supplierPaid,
      'supplierPaidCount': paymentRows.length,
      'supplierPaidCash': supplierPaidCash,
      'supplierPaidCheque': supplierPaidCheque,
      'supplierOutstanding': supplierOutstanding,
      'stockValue': stockValue,
      'stockItems': stockItems,
      'productCount': products.length,
      'netProfit': netProfit,
      'isLoss': netProfit < 0,
    };
  }

  // ============== WASTAGE ==============
  /// Records wastage/damage/spoilage: deducts the units from the product (and
  /// optionally the owning batch), writes a wastage record and logs stock
  /// history. The monetary loss is valued at cost — the units' batch cost when
  /// a batch is picked, otherwise the product's buying price. Returns null when
  /// the product can no longer be found (e.g. it was deleted meanwhile).
  Future<Wastage?> recordWastage({
    required String productId,
    required String productName,
    required double quantity,
    required String reason,
    String batchId = '',
    String batchNumber = '',
    String notes = '',
    String recordedBy = '',
    DateTime? wastageDate,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    Wastage? created;

    final ok = await db.transaction((txn) async {
      final productMaps = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
      );
      if (productMaps.isEmpty) {
        return false;
      }
      final product = Product.fromMap(productMaps.first);

      var unitCost = product.buyingPrice;
      if (batchId.isNotEmpty) {
        final batchMaps = await txn.query(
          'product_batches',
          where: 'id = ?',
          whereArgs: [batchId],
        );
        if (batchMaps.isNotEmpty) {
          final batch = ProductBatch.fromMap(batchMaps.first);
          unitCost = batch.price > 0 ? batch.price : unitCost;
          final newBatchQty =
              (batch.quantity - quantity).clamp(0.0, double.infinity);
          await txn.update(
            'product_batches',
            {'quantity': newBatchQty},
            where: 'id = ?',
            whereArgs: [batch.id],
          );
        }
      }

      final newQty =
          (product.quantity - quantity).clamp(0.0, double.infinity);
      await txn.update(
        'products',
        {'quantity': newQty, 'updatedAt': now},
        where: 'id = ?',
        whereArgs: [product.id],
      );

      created = Wastage(
        productId: productId,
        productName: productName,
        quantity: quantity,
        reason: reason,
        lossValue: unitCost * quantity,
        batchId: batchId,
        batchNumber: batchNumber,
        notes: notes,
        recordedBy: recordedBy,
        wastageDate: wastageDate ?? DateTime.now(),
      );
      await txn.insert('wastages', created!.toMap());

      await txn.insert('stock_history', {
        'productId': productId,
        'productName': productName,
        'quantityChanged': -quantity,
        'reason': 'Wastage: $reason',
        'createdAt': now,
      });
      return true;
    });

    if (ok) {
      BackupService.notifyTransaction('wastage');
    }
    return ok ? created : null;
  }

  Future<List<Wastage>> getAllWastages() async {
    final db = await database;
    final maps = await db.query('wastages', orderBy: 'wastageDate DESC');
    return maps.map(Wastage.fromMap).toList();
  }

  /// Aggregated wastage report for a date range: total units wasted, total
  /// monetary loss (at cost), and breakdowns per reason and per product.
  Future<Map<String, dynamic>> getWastageReport(
    DateTime start,
    DateTime end,
  ) async {
    final db = await database;
    final maps = await db.query(
      'wastages',
      where: 'wastageDate >= ? AND wastageDate <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'wastageDate DESC',
    );
    final wastages = maps.map(Wastage.fromMap).toList();

    var totalUnits = 0.0;
    double totalLoss = 0;
    final byReason = <String, double>{};
    final byProduct = <String, double>{};
    for (final w in wastages) {
      totalUnits += w.quantity;
      totalLoss += w.lossValue;
      byReason[w.reason] = (byReason[w.reason] ?? 0) + w.lossValue;
      byProduct[w.productName] = (byProduct[w.productName] ?? 0) + w.lossValue;
    }

    return {
      'start': start,
      'end': end,
      'wastages': wastages,
      'totalUnits': totalUnits,
      'totalLoss': totalLoss,
      'byReason': byReason,
      'byProduct': byProduct,
    };
  }
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('sales');
    await db.delete('products');
    await db.delete('users');
    await db.delete('stock_history');
    await db.delete('customers');
    await db.delete('suppliers');
    await db.delete('product_batches');
    await db.delete('refund_returns');
    await db.delete('purchase_orders');
    await db.delete('expenses');
    await db.delete('wastages');
  }

  Future<void> closeDatabase() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  // ============== SUPPLIERS ==============
  Future<void> insertSupplier(Supplier supplier) async {
    final db = await database;
    await db.insert(
      'suppliers',
      supplier.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    BackupService.notifyTransaction('supplier');
  }

  Future<List<Supplier>> getAllSuppliers({bool includeInactive = false}) async {
    final db = await database;
    final maps = includeInactive
        ? await db.query('suppliers', orderBy: 'isActive DESC, name ASC')
        : await db.query(
            'suppliers',
            where: 'isActive = ?',
            whereArgs: [1],
            orderBy: 'name ASC',
          );
    return maps.map(Supplier.fromMap).toList();
  }

  Future<Supplier?> getSupplierById(String id) async {
    final db = await database;
    final maps = await db.query('suppliers', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return Supplier.fromMap(maps.first);
    }
    return null;
  }

  Future<void> updateSupplier(Supplier supplier) async {
    final db = await database;
    await db.update(
      'suppliers',
      supplier.toMap(),
      where: 'id = ?',
      whereArgs: [supplier.id],
    );
    BackupService.notifyTransaction('supplier');
  }

  Future<void> deleteSupplier(String id) async {
    final db = await database;
    await db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
    BackupService.notifyTransaction('supplier');
  }

  // ── Supplier payments ──────────────────────────────────────────

  Future<void> recordSupplierPayment(SupplierPayment payment) async {
    final db = await database;
    await db.insert('supplier_payments', payment.toMap());
    BackupService.notifyTransaction('supplier payment');
  }

  Future<void> deleteSupplierPayment(String paymentId) async {
    final db = await database;
    await db
        .delete('supplier_payments', where: 'id = ?', whereArgs: [paymentId]);
    BackupService.notifyTransaction('supplier payment');
  }

  Future<List<SupplierPayment>> getSupplierPayments(String supplierId) async {
    final db = await database;
    final maps = await db.query(
      'supplier_payments',
      where: 'supplierId = ?',
      whereArgs: [supplierId],
      orderBy: 'paymentDate DESC',
    );
    return maps.map(SupplierPayment.fromMap).toList();
  }

  Future<List<SupplierPayment>> getAllSupplierPayments() async {
    final db = await database;
    final maps =
        await db.query('supplier_payments', orderBy: 'paymentDate DESC');
    return maps.map(SupplierPayment.fromMap).toList();
  }

  /// What the shop still owes the supplier: total value of goods received
  /// (all GRNs) minus everything already paid by cash or cheque.
  Future<double> getSupplierOutstanding(String supplierId) async {
    final db = await database;
    final grnRows = await db.rawQuery(
      'SELECT COALESCE(SUM(total), 0) AS t FROM goods_received_notes WHERE supplierId = ?',
      [supplierId],
    );
    final payRows = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS t FROM supplier_payments WHERE supplierId = ?',
      [supplierId],
    );
    final received = (grnRows.first['t'] as num).toDouble();
    final paid = (payRows.first['t'] as num).toDouble();
    return received - paid;
  }

  Future<double> getSupplierTotalReceived(String supplierId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(total), 0) AS t FROM goods_received_notes WHERE supplierId = ?',
      [supplierId],
    );
    return (rows.first['t'] as num).toDouble();
  }

  Future<double> getSupplierTotalPaid(String supplierId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS t FROM supplier_payments WHERE supplierId = ?',
      [supplierId],
    );
    return (rows.first['t'] as num).toDouble();
  }

  // ============== PRODUCT BATCHES ==============
  Future<void> insertProductBatch(ProductBatch batch) async {
    final db = await database;
    await db.insert(
      'product_batches',
      batch.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    BackupService.notifyTransaction('batch');
  }

  Future<List<ProductBatch>> getBatchesByProductId(String productId) async {
    final db = await database;
    final maps = await db.query(
      'product_batches',
      where: 'productId = ?',
      whereArgs: [productId],
      orderBy: 'expiryDate ASC',
    );
    return maps.map(ProductBatch.fromMap).toList();
  }

  Future<List<ProductBatch>> getExpiringBatches(
      {int daysUntilExpiry = 7}) async {
    final db = await database;
    final cutoffDate = DateTime.now().add(Duration(days: daysUntilExpiry));
    final maps = await db.query(
      'product_batches',
      where: 'expiryDate IS NOT NULL AND expiryDate <= ?',
      whereArgs: [cutoffDate.toIso8601String()],
      orderBy: 'expiryDate ASC',
    );
    return maps.map(ProductBatch.fromMap).toList();
  }

  Future<void> updateProductBatch(ProductBatch batch) async {
    final db = await database;
    await db.update(
      'product_batches',
      batch.toMap(),
      where: 'id = ?',
      whereArgs: [batch.id],
    );
    BackupService.notifyTransaction('batch');
  }

  /// Adds [delta] units to a batch's remaining quantity (used to put stock
  /// back when a sale line is refunded).
  Future<void> addBatchQuantity(String batchId, double delta) async {
    if (batchId.isEmpty || delta == 0) return;
    final db = await database;
    final maps = await db.query(
      'product_batches',
      where: 'id = ?',
      whereArgs: [batchId],
    );
    if (maps.isEmpty) return;
    final batch = ProductBatch.fromMap(maps.first);
    await db.update(
      'product_batches',
      {'quantity': batch.quantity + delta},
      where: 'id = ?',
      whereArgs: [batchId],
    );
    BackupService.notifyTransaction('batch');
  }

  /// Removes a stock batch and subtracts its remaining units from the product
  /// total so stock counts stay consistent. Used to discard a wrong/expired lot.
  Future<void> deleteProductBatch(String batchId) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'product_batches',
        where: 'id = ?',
        whereArgs: [batchId],
      );
      if (rows.isEmpty) return;
      final batch = ProductBatch.fromMap(rows.first);
      await txn.delete(
        'product_batches',
        where: 'id = ?',
        whereArgs: [batchId],
      );

      final productMaps = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [batch.productId],
      );
      if (productMaps.isNotEmpty) {
        final product = Product.fromMap(productMaps.first);
        final newQty =
            (product.quantity - batch.quantity).clamp(0.0, double.infinity);
        await txn.update(
          'products',
          {'quantity': newQty, 'updatedAt': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [product.id],
        );
        await txn.insert('stock_history', {
          'productId': product.id,
          'productName': product.name,
          'quantityChanged': -batch.quantity,
          'reason': 'Batch ${batch.batchNumber} deleted',
          'createdAt': DateTime.now().toIso8601String(),
        });
      }
    });
    BackupService.notifyTransaction('batch');
  }

  // ============== REFUND/RETURNS ==============
  Future<void> insertRefundReturn(RefundReturn refund) async {
    final db = await database;
    final refundData = refund.toMap();
    refundData['items'] =
        jsonEncode(refund.items.map((item) => item.toMap()).toList());
    await db.insert(
      'refund_returns',
      refundData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    BackupService.notifyTransaction('refund');
  }

  Future<List<RefundReturn>> getAllRefunds() async {
    final db = await database;
    final maps = await db.query(
      'refund_returns',
      orderBy: 'requestDate DESC',
    );
    return maps.map((map) {
      final refundData = Map<String, dynamic>.from(map);
      final rawItems = refundData['items'];
      if (rawItems is String) {
        refundData['items'] = jsonDecode(rawItems);
      }
      return RefundReturn.fromMap(refundData);
    }).toList();
  }

  Future<List<RefundReturn>> getPendingRefunds() async {
    final db = await database;
    final maps = await db.query(
      'refund_returns',
      where: 'status = ?',
      whereArgs: ['Pending'],
      orderBy: 'requestDate DESC',
    );
    return maps.map((map) {
      final refundData = Map<String, dynamic>.from(map);
      final rawItems = refundData['items'];
      if (rawItems is String) {
        refundData['items'] = jsonDecode(rawItems);
      }
      return RefundReturn.fromMap(refundData);
    }).toList();
  }

  Future<RefundReturn?> getRefundById(String id) async {
    final db = await database;
    final maps =
        await db.query('refund_returns', where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      final refundData = Map<String, dynamic>.from(maps.first);
      final rawItems = refundData['items'];
      if (rawItems is String) {
        refundData['items'] = jsonDecode(rawItems);
      }
      return RefundReturn.fromMap(refundData);
    }
    return null;
  }

  Future<void> updateRefundReturn(RefundReturn refund) async {
    final db = await database;
    final refundData = refund.toMap();
    refundData['items'] =
        jsonEncode(refund.items.map((item) => item.toMap()).toList());
    await db.update(
      'refund_returns',
      refundData,
      where: 'id = ?',
      whereArgs: [refund.id],
    );
    BackupService.notifyTransaction('refund');
  }

  Future<List<RefundReturn>> getRefundsBySale(String saleId) async {
    final db = await database;
    final maps = await db.query(
      'refund_returns',
      where: 'originalSaleId = ?',
      whereArgs: [saleId],
      orderBy: 'requestDate DESC',
    );
    return maps.map((map) {
      final refundData = Map<String, dynamic>.from(map);
      final rawItems = refundData['items'];
      if (rawItems is String) {
        refundData['items'] = jsonDecode(rawItems);
      }
      return RefundReturn.fromMap(refundData);
    }).toList();
  }

  // ============== PURCHASE ORDERS ==============
  Future<void> insertPurchaseOrder(PurchaseOrder order) async {
    final db = await database;
    final data = order.toMap();
    data['items'] =
        jsonEncode(order.items.map((e) => e.toMap()).toList());
    await db.insert(
      'purchase_orders',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    BackupService.notifyTransaction('purchase order');
  }

  Future<List<PurchaseOrder>> getAllPurchaseOrders() async {
    final db = await database;
    final maps = await db.query('purchase_orders', orderBy: 'orderDate DESC');
    return maps.map(_decodePurchaseOrder).toList();
  }

  Future<PurchaseOrder?> getPurchaseOrderById(String id) async {
    final db = await database;
    final maps =
        await db.query('purchase_orders', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) {
      return null;
    }
    return _decodePurchaseOrder(maps.first);
  }

  Future<List<PurchaseOrder>> getPendingPurchaseOrders() async {
    final db = await database;
    final maps = await db.query(
      'purchase_orders',
      where: 'status = ?',
      whereArgs: ['Ordered'],
      orderBy: 'orderDate DESC',
    );
    return maps.map(_decodePurchaseOrder).toList();
  }

  /// Mark a purchase order as received: increase product stock, upsert a
  /// product batch for the delivery, and log stock history. All in one
  /// transaction so a partial failure cannot corrupt stock levels.
  Future<void> receivePurchaseOrder(PurchaseOrder order) async {
    if (order.isReceived || order.isCancelled) {
      return;
    }
    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      for (final item in order.items) {
        final productMaps = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [item.productId],
        );
        if (productMaps.isEmpty) {
          continue;
        }
        final product = Product.fromMap(productMaps.first);
        await txn.update(
          'products',
          {
            'quantity': product.quantity + item.quantity,
            // Keep the product's cost in step with the latest delivery so
            // profit fallbacks stay accurate (selling price is unchanged; the
            // new batch records its own selling price for FIFO).
            if (item.costPrice > 0) 'buyingPrice': item.costPrice,
            'updatedAt': now,
          },
          where: 'id = ?',
          whereArgs: [item.productId],
        );

        await txn.insert('stock_history', {
          'productId': item.productId,
          'productName': item.productName,
          'quantityChanged': item.quantity,
          'reason': 'Purchase order ${order.orderNumber} received',
          'createdAt': now,
        });

        final existing = await txn.query(
          'product_batches',
          where: 'productId = ? AND batchNumber = ?',
          whereArgs: [item.productId, order.orderNumber],
        );
        if (existing.isNotEmpty) {
          final batch = ProductBatch.fromMap(existing.first);
          await txn.update(
            'product_batches',
            {
              'quantity': batch.quantity + item.quantity,
              'initialQuantity': batch.initialQuantity + item.quantity,
            },
            where: 'id = ?',
            whereArgs: [batch.id],
          );
        } else {
          await txn.insert('product_batches', {
            'id': const Uuid().v4(),
            'productId': item.productId,
            'batchNumber': order.orderNumber,
            'price': item.costPrice,
            'sellingPrice': product.sellingPrice,
            'expiryDate': null,
            'quantity': item.quantity,
            'initialQuantity': item.quantity,
            'receivedDate': DateTime.now().toIso8601String(),
            'supplierId': order.supplierId,
            'notes': 'Received via ${order.orderNumber}',
            'createdAt': now,
          });
        }
      }

      await txn.update(
        'purchase_orders',
        {'status': 'Received', 'receivedDate': now},
        where: 'id = ?',
        whereArgs: [order.id],
      );
    });
    BackupService.notifyTransaction('goods received');
  }

  Future<void> cancelPurchaseOrder(String id) async {
    final db = await database;
    await db.update(
      'purchase_orders',
      {'status': 'Cancelled'},
      where: 'id = ?',
      whereArgs: [id],
    );
    BackupService.notifyTransaction('purchase order');
  }

  PurchaseOrder _decodePurchaseOrder(Map<String, dynamic> map) {
    final data = Map<String, dynamic>.from(map);
    final rawItems = data['items'];
    if (rawItems is String) {
      data['items'] = jsonDecode(rawItems);
    }
    return PurchaseOrder.fromMap(data);
  }
}
