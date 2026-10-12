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
import '../models/shopping_bag.dart';
import '../models/shop_settings.dart';
import '../models/supplier.dart';
import '../models/supplier_payment.dart';
import '../models/supplier_return.dart';
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

  /// Test-only: points the service at an already-open database (an in-memory
  /// one in tests) and ensures the real schema exists on it, so the LAN mirror
  /// rules can be exercised without touching the live shop database.
  Future<void> debugUseDatabase(Database db) async {
    _database = db;
    await _createTables(db, 1);
  }

  /// Test-only: forgets the injected database so the next call re-opens the
  /// real one.
  void debugResetDatabase() {
    _database = null;
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
          piecesPerBox INTEGER NOT NULL DEFAULT 1,
          singlePrice REAL NOT NULL DEFAULT 0,
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
      try {
        await db.execute(
          'ALTER TABLE products ADD COLUMN piecesPerBox INTEGER NOT NULL DEFAULT 1',
        );
      } catch (e) {
        // Column already exists
      }
      try {
        await db.execute(
          'ALTER TABLE products ADD COLUMN singlePrice REAL NOT NULL DEFAULT 0',
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
    // Migration: customers.updatedAt powers the LAN mirror so an edited contact
    // reaches the other PC. Backfill from the closest date we already have.
    try {
      final columns = await db.rawQuery('PRAGMA table_info(customers)');
      final hasUpdatedAt = columns.any((col) => col['name'] == 'updatedAt');
      if (!hasUpdatedAt) {
        await db.execute(
          "ALTER TABLE customers ADD COLUMN updatedAt TEXT NOT NULL DEFAULT ''",
        );
        await db.execute(
          "UPDATE customers SET updatedAt = "
          "CASE WHEN lastPurchaseDate IS NOT NULL AND lastPurchaseDate != '' "
          "THEN lastPurchaseDate ELSE createdAt END",
        );
      }
    } catch (e) {
      developer.log('Customer migration error: $e', name: 'DatabaseService');
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
          updatedAt TEXT,
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
        if (!names.contains('updatedAt')) {
          // In-place edits (an expiry date corrected later) bump this stamp so
          // the LAN mirror clock moves and the other PC sees the change.
          await db.execute(
            'ALTER TABLE product_batches ADD COLUMN updatedAt TEXT',
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
          createdAt TEXT NOT NULL DEFAULT '',
          FOREIGN KEY (supplierId) REFERENCES suppliers(id)
        )
      ''');
    } else {
      // Migration: `createdAt` is when the order was entered (the user may
      // back-date orderDate or the receiving screen may stamp a midnight
      // receivedDate). The mirror clock is the latest of these, so an order
      // created and received on the same machine still travels to the other PC.
      try {
        final columns = await db.rawQuery('PRAGMA table_info(purchase_orders)');
        final names = columns.map((col) => col['name'] as String).toSet();
        if (!names.contains('createdAt')) {
          await db.execute(
            'ALTER TABLE purchase_orders ADD COLUMN createdAt TEXT NOT NULL DEFAULT \'\'',
          );
          await db.execute(
            'UPDATE purchase_orders SET createdAt = orderDate WHERE createdAt = \'\'',
          );
        }
      } catch (e) {
        developer.log('Purchase order migration error: $e', name: 'DatabaseService');
      }
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
          recordedBy TEXT NOT NULL DEFAULT '',
          paidTo TEXT NOT NULL DEFAULT '',
          createdAt TEXT NOT NULL DEFAULT ''
        )
      ''');
    }
    // Migration: expenses.createdAt is the record time (the user may back-date
    // expenseDate), used by the LAN mirror to ship the row reliably.
    try {
      final columns = await db.rawQuery('PRAGMA table_info(expenses)');
      final names = columns.map((col) => col['name'] as String).toSet();
      final hasCreatedAt = names.contains('createdAt');
      if (!hasCreatedAt) {
        await db.execute(
          "ALTER TABLE expenses ADD COLUMN createdAt TEXT NOT NULL DEFAULT ''",
        );
        await db.execute(
          "UPDATE expenses SET createdAt = expenseDate WHERE createdAt = ''",
        );
      }
      // Migration: 'paidTo' records whom the money was handed to (a supplier
      // collecting from the drawer, a worker, the landlord...), so the owner
      // can reconcile the cash drawer at the end of the day.
      if (!names.contains('paidTo')) {
        await db.execute(
          "ALTER TABLE expenses ADD COLUMN paidTo TEXT NOT NULL DEFAULT ''",
        );
      }
    } catch (e) {
      developer.log('Expense migration error: $e', name: 'DatabaseService');
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
          updatedAt TEXT,
          FOREIGN KEY (productId) REFERENCES products(id)
        )
      ''');
    } else {
      // Migration: an in-place edit (quantity, reason, date) bumps this stamp
      // so the LAN mirror clock moves and the other PC sees the correction.
      try {
        final columns = await db.rawQuery('PRAGMA table_info(wastages)');
        final names = columns.map((col) => col['name'] as String).toSet();
        if (!names.contains('updatedAt')) {
          await db.execute('ALTER TABLE wastages ADD COLUMN updatedAt TEXT');
        }
      } catch (e) {
        developer.log('Wastage migration error: $e', name: 'DatabaseService');
      }
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

    // Supplier returns (goods sent BACK to a supplier; value is credited
    // against the outstanding balance and stock is taken out of the shelves).
    final supplierReturnsTableExists =
        await _tableExists(db, 'supplier_returns');
    if (!supplierReturnsTableExists) {
      await db.execute('''
        CREATE TABLE supplier_returns (
          id TEXT PRIMARY KEY,
          returnNumber TEXT NOT NULL DEFAULT '',
          supplierId TEXT NOT NULL,
          supplierName TEXT NOT NULL DEFAULT '',
          items TEXT NOT NULL DEFAULT '[]',
          total REAL NOT NULL DEFAULT 0,
          reason TEXT NOT NULL DEFAULT '',
          notes TEXT NOT NULL DEFAULT '',
          returnedBy TEXT NOT NULL DEFAULT '',
          returnDate TEXT NOT NULL,
          createdAt TEXT NOT NULL,
          FOREIGN KEY (supplierId) REFERENCES suppliers(id)
        )
      ''');
    }

    // ============ SHOPPING BAGS (separate stock, own section) ============
    final shoppingBagsTable = await _tableExists(db, 'shopping_bags');
    if (!shoppingBagsTable) {
      await db.execute('''
        CREATE TABLE shopping_bags (
          id TEXT PRIMARY KEY,
          label TEXT NOT NULL,
          price REAL NOT NULL,
          buyingPrice REAL NOT NULL,
          quantity REAL NOT NULL DEFAULT 0,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL
        )
      ''');
    }

    final shoppingBagUsageTable = await _tableExists(db, 'shopping_bag_usage');
    if (!shoppingBagUsageTable) {
      await db.execute('''
        CREATE TABLE shopping_bag_usage (
          id TEXT PRIMARY KEY,
          bagId TEXT NOT NULL,
          bagLabel TEXT NOT NULL DEFAULT '',
          bagPrice REAL NOT NULL DEFAULT 0,
          bagCost REAL NOT NULL DEFAULT 0,
          quantity REAL NOT NULL,
          value REAL NOT NULL DEFAULT 0,
          type TEXT NOT NULL,
          saleId TEXT NOT NULL DEFAULT '',
          createdAt TEXT NOT NULL
        )
      ''');
    } else {
      try {
        final columns = await db.rawQuery('PRAGMA table_info(shopping_bag_usage)');
        final names = columns.map((col) => col['name'] as String).toSet();
        if (!names.contains('value')) {
          await db.execute(
            'ALTER TABLE shopping_bag_usage ADD COLUMN value REAL NOT NULL DEFAULT 0',
          );
        }
      } catch (e) {
        developer.log('shopping_bag_usage migration error: $e',
            name: 'DatabaseService');
      }
    }

    // One-time cleanup: the first release auto-created four Rs 3 / 5 / 10 / 20
    // "bag tier" rows. Bags are now bought, used and sold as whole bulk
    // bundles, so drop those untouched seeded rows (never a row that has stock
    // or usage history) to leave the owner with a clean, empty bulk list.
    try {
      await db.rawDelete(
        "DELETE FROM shopping_bags WHERE quantity = 0 AND label IN "
        "('Rs 3 bag', 'Rs 5 bag', 'Rs 10 bag', 'Rs 20 bag') "
        "AND id NOT IN (SELECT DISTINCT bagId FROM shopping_bag_usage)",
      );
    } catch (e) {
      developer.log('legacy shopping-bag cleanup error: $e',
          name: 'DatabaseService');
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
          scaleBarcodeEnabled INTEGER NOT NULL DEFAULT 0,
          scaleBarcodePrefix TEXT NOT NULL DEFAULT '2',
          scaleBarcodeLength INTEGER NOT NULL DEFAULT 12,
          scaleBarcodeItemLength INTEGER NOT NULL DEFAULT 5,
          scaleBarcodePriceMode INTEGER NOT NULL DEFAULT 0,
          scaleBarcodeCheckDigit INTEGER NOT NULL DEFAULT 1,
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
        if (!names.contains('scaleBarcodeEnabled')) {
          await db.execute(
            'ALTER TABLE shop_settings ADD COLUMN scaleBarcodeEnabled INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (!names.contains('scaleBarcodePrefix')) {
          await db.execute(
            "ALTER TABLE shop_settings ADD COLUMN scaleBarcodePrefix TEXT NOT NULL DEFAULT '2'",
          );
        }
        if (!names.contains('scaleBarcodeLength')) {
          await db.execute(
            'ALTER TABLE shop_settings ADD COLUMN scaleBarcodeLength INTEGER NOT NULL DEFAULT 12',
          );
        }
        if (!names.contains('scaleBarcodeItemLength')) {
          await db.execute(
            'ALTER TABLE shop_settings ADD COLUMN scaleBarcodeItemLength INTEGER NOT NULL DEFAULT 5',
          );
        }
        if (!names.contains('scaleBarcodePriceMode')) {
          await db.execute(
            'ALTER TABLE shop_settings ADD COLUMN scaleBarcodePriceMode INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (!names.contains('scaleBarcodeCheckDigit')) {
          await db.execute(
            'ALTER TABLE shop_settings ADD COLUMN scaleBarcodeCheckDigit INTEGER NOT NULL DEFAULT 1',
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
    List<Map<String, dynamic>> suppliers = const [],
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

      for (final sup in suppliers) {
        final map = Map<String, dynamic>.from(sup);
        try {
          await txn.insert(
            'suppliers',
            Supplier.fromMap(map).toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } catch (_) {
          // Keep the local supplier on any conflict.
        }
      }
    });
    BackupService.notifyTransaction('catalog sync');
  }

  /// Applies the label-scale layout pushed by the admin PC in the catalog.
  /// Only the six scale fields are touched; every other local setting (printer,
  /// backup paths, network mode...) stays as this PC has it. Missing keys are
  /// ignored so an older server can never blank a locally set value.
  Future<void> applyScaleSettingsFromServer(Map<String, dynamic> scale) async {
    final current = await getShopSettings();
    final updated = current.copyWith(
      scaleBarcodeEnabled: scale['enabled'] as bool?,
      scaleBarcodePrefix: scale['prefix'] as String?,
      scaleBarcodeLength: (scale['length'] as num?)?.toInt(),
      scaleBarcodeItemLength: (scale['itemLength'] as num?)?.toInt(),
      scaleBarcodePriceMode: scale['priceMode'] as bool?,
      scaleBarcodeCheckDigit: scale['checkDigit'] as bool?,
    );
    await updateShopSettings(updated);
  }

  /// Cheap fingerprint of the catalog this PC owns.
  ///
  /// Client terminals save this value and only re-download the catalog when it
  /// changes, so a steady LAN link uses almost no WiFi data. Any rename, price
  /// change, stock move or new image on the server bumps the revision.
  Future<String> catalogRevision() async {
    final db = await database;
    Future<(int, String)> stamp(String table, String timeCol) async {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c, MAX($timeCol) AS m FROM $table',
      );
      final row = rows.isEmpty ? const <String, Object?>{} : rows.first;
      return ((row['c'] as int? ?? 0), (row['m'] as String? ?? ''));
    }

    final p = await stamp('products', 'updatedAt');
    final c = await stamp('categories', 'updatedAt');
    final u = await stamp('customers', 'lastPurchaseDate');
    final s = await stamp('suppliers', 'updatedAt');
    // Fold in the label-scale layout so changing it on the admin PC bumps the
    // revision and every terminal re-pulls the catalog (and the new layout).
    String scale = 'sc-';
    try {
      final rows = await db.query(
        'shop_settings',
        columns: [
          'scaleBarcodeEnabled',
          'scaleBarcodePrefix',
          'scaleBarcodeLength',
          'scaleBarcodeItemLength',
          'scaleBarcodePriceMode',
          'scaleBarcodeCheckDigit',
        ],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final r = rows.first;
        scale = 'sc${r['scaleBarcodeEnabled']}|${r['scaleBarcodePrefix']}|'
            '${r['scaleBarcodeLength']}|${r['scaleBarcodeItemLength']}|'
            '${r['scaleBarcodePriceMode']}|${r['scaleBarcodeCheckDigit']}';
      }
    } catch (_) {
      // Column missing on an un-migrated DB: ignore, catalogue still syncs.
    }
    return 'p$p|c$c|u$u|s$s|$scale';
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
      // An unknown product only means there is nothing to deduct — never a
      // reason to drop the sale. [completeSale] clamps stock at zero, and the
      // financial row is what the profit & loss report is built from, so
      // rejecting here would silently delete this shop's revenue.
      if (product == null) {
        continue;
      }
      cartItems.add(CartItem(
        id: item.loose ? '${product.id}#loose' : product.id,
        product: product,
        quantity: item.quantity,
        unitPrice: item.price,
        loose: item.loose,
        piecesPerBox: item.piecesPerBox,
      ));
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

  /// Look up a product by barcode, tolerating leading zeros on either side.
  ///
  /// A label scale may zero-pad (or not) its item/PLU code, and the shopkeeper
  /// may type a different number of leading zeros into the product barcode, so
  /// a label item `00010` and a product barcode `0000010` are the same code for
  /// a scale scan. Exact match is always tried first, so normal EAN-13 barcodes
  /// (including ones that legitimately begin with `0`) are unaffected.
  Future<Product?> getProductByBarcodeLoose(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return null;
    final exact = await getProductByBarcode(trimmed);
    if (exact != null) return exact;
    final stripped = trimmed.replaceFirst(RegExp(r'^0+'), '');
    if (stripped.isEmpty) return null;
    final db = await database;
    final maps = await db.rawQuery(
      "SELECT * FROM products WHERE LTRIM(barcode, '0') = ? LIMIT 1",
      [stripped],
    );
    return maps.isNotEmpty ? Product.fromMap(maps.first) : null;
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

  /// Reload (top-up) performance for a date range: the value sold to customers,
  /// the margin the shop earned on it and how many reload sales there were.
  ///
  /// Only the **margin** counts towards profit — the wholesale cost of the card
  /// is paid to the ISP and is already netted out here, so it is never also
  /// counted as an expense. Sold rows are dated by `usedAt`, falling back to
  /// `createdAt` for any legacy row that has no timestamp.
  Future<Map<String, dynamic>> getReloadSummary(
    DateTime start,
    DateTime end,
  ) async {
    final db = await database;
    const stamp =
        "CASE WHEN usedAt IS NULL OR usedAt = '' THEN createdAt ELSE usedAt END";
    final rows = await db.query(
      'reload_cards',
      where: "status = 'sold' AND $stamp >= ? AND $stamp <= ?",
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
    );
    var soldValue = 0.0;
    var profit = 0.0;
    for (final row in rows) {
      final value = (row['value'] as num?)?.toDouble() ?? 0;
      final cost = (row['cost'] as num?)?.toDouble() ?? 0;
      soldValue += value;
      profit += value - cost;
    }
    return {
      'soldValue': soldValue,
      'profit': profit,
      'count': rows.length,
    };
  }

  /// Money paid out on processed refunds and money still owed on pending or
  /// approved refunds within a window, plus their counts.
  ///
  /// A processed refund is dated by when it was paid out (`processedDate`,
  /// falling back to `createdAt` for legacy rows); a pending/approved one is
  /// dated by when it was raised.
  Future<Map<String, dynamic>> _refundSummary(
    String fromIso,
    String toIso,
  ) async {
    final db = await database;
    final rows = await db.query('refund_returns');
    var loss = 0.0;
    var pending = 0.0;
    var processed = 0;
    var pendingCount = 0;
    bool inRange(String? stamp) =>
        stamp != null &&
        stamp.isNotEmpty &&
        stamp.compareTo(fromIso) >= 0 &&
        stamp.compareTo(toIso) <= 0;
    for (final row in rows) {
      final amount = (row['totalRefundAmount'] as num?)?.toDouble() ?? 0;
      final status = (row['status'] as String? ?? '').toLowerCase();
      if (status == 'processed') {
        final processedOn = (row['processedDate'] as String?)?.isNotEmpty == true
            ? row['processedDate'] as String?
            : row['createdAt'] as String?;
        if (inRange(processedOn)) {
          loss += amount;
          processed++;
        }
      } else if (status == 'pending' || status == 'approved') {
        if (inRange(row['createdAt'] as String?)) {
          pending += amount;
          pendingCount++;
        }
      }
    }
    return {
      'loss': loss,
      'pending': pending,
      'count': processed,
      'pendingCount': pendingCount,
    };
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
  ///
  /// Expired batches are excluded (a batch whose expiry has passed must never
  /// be sold), so FIFO picking, the effective price and [completeSale] all
  /// only ever touch sellable stock. Batches without an expiry date remain
  /// sellable — not everything carries one.
  Future<List<ProductBatch>> _fifoBatches(
    DatabaseExecutor db,
    String productId,
  ) async {
    final maps = await db.query(
      'product_batches',
      where:
          'productId = ? AND quantity > 0 AND (expiryDate IS NULL OR expiryDate > ?)',
      whereArgs: [productId, DateTime.now().toIso8601String()],
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
        if (item.isBag) {
          // Retail bag charge on the bill (Rs 3 / 5 / 10 / 20). It is NOT
          // connected to the bulk Shopping Bags stock — that section tracks
          // whole bundles the owner buys, uses and resells. Here we only keep
          // the money on the bill, so skip all product/bag stock movement.
          continue;
        }
        // Stock is tracked in the product's own unit (boxes). A loose line
        // takes only a fraction of a box, so deduct its stock quantity rather
        // than its piece count.
        final stockTake = item.stockQuantity;
        var remaining = stockTake;
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
          var newQty =
              (product.quantity - stockTake).clamp(0.0, double.infinity);
          // Snap break-bulk stock back onto an exact piece boundary so selling
          // one stick at a time can never accumulate floating-point drift.
          if (product.isBreakBulk) {
            newQty = (newQty * product.piecesPerBox).round() /
                product.piecesPerBox;
          }
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
          'quantityChanged': -stockTake,
          'reason': 'Sale ${sale.invoiceLabel}',
          'createdAt': now,
        });
      }
    });
    BackupService.notifyTransaction('bill');
  }

  // ============== SHOPPING BAGS (bulk bundles, separate stock & usage) ======

  Future<List<ShoppingBag>> getShoppingBags() async {
    final db = await database;
    final maps = await db.query('shopping_bags', orderBy: 'price ASC');
    return maps.map(ShoppingBag.fromMap).toList();
  }

  Future<ShoppingBag?> getShoppingBagById(String id) async {
    final db = await database;
    final maps = await db.query(
      'shopping_bags',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return ShoppingBag.fromMap(maps.first);
  }

  /// Adds a bulk bag or saves an edit (name, bundle buying/selling price).
  /// Quantity is not changed here — use [recordShoppingBagMovement] so every
  /// stock change is logged for the daily sold / shop-use report.
  Future<void> upsertShoppingBag(ShoppingBag bag) async {
    final db = await database;
    bag.updatedAt = DateTime.now();
    await db.insert(
      'shopping_bags',
      bag.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    BackupService.notifyTransaction('shopping-bag');
  }

  Future<void> deleteShoppingBag(String id) async {
    final db = await database;
    await db.delete('shopping_bags', where: 'id = ?', whereArgs: [id]);
    BackupService.notifyTransaction('shopping-bag');
  }

  /// Moves bag stock and logs the movement.
  ///
  /// * `quantity > 0` → stock in (`type == 'restock'`)
  /// * `quantity < 0` → stock out (`type == 'shop_use'`, valued at cost for
  ///   profit & loss). Customer sells are handled atomically inside
  ///   [completeSale] with the sale.
  ///
  /// Returns false when the bag is missing or the movement would take the
  /// stock below zero.
  Future<bool> recordShoppingBagMovement({
    required String bagId,
    required double quantity,
    required String type,
    String saleId = '',
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    var ok = false;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'shopping_bags',
        where: 'id = ?',
        whereArgs: [bagId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final bag = ShoppingBag.fromMap(rows.first);
      var next = bag.quantity + quantity;
      if (next < 0) return;
      next = next.clamp(0.0, double.infinity);
      await txn.update(
        'shopping_bags',
        {'quantity': next, 'updatedAt': now},
        where: 'id = ?',
        whereArgs: [bagId],
      );
      await txn.insert(
        'shopping_bag_usage',
        ShoppingBagUsage(
          bagId: bag.id,
          bagLabel: bag.label,
          bagPrice: bag.price,
          bagCost: bag.buyingPrice,
          quantity: quantity.abs(),
          type: type,
          saleId: saleId,
        ).toMap(),
      );
      ok = true;
    });
    if (ok) BackupService.notifyTransaction('shopping-bag');
    return ok;
  }

  /// How bags were used between two dates: sold to customers and used by the
  /// shop itself — counts, money (value) and cost — plus restocks.
  Future<Map<String, dynamic>> getShoppingBagSummary(
    DateTime start,
    DateTime end,
  ) async {
    final db = await database;
    final maps = await db.query(
      'shopping_bag_usage',
      where: 'createdAt >= ? AND createdAt <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
    );

    var soldQty = 0.0, soldValue = 0.0, soldCost = 0.0;
    var usedQty = 0.0, usedValue = 0.0, usedCost = 0.0;
    var restockQty = 0.0;
    for (final m in maps) {
      final u = ShoppingBagUsage.fromMap(m);
      switch (u.type) {
        case 'customer_sell':
          soldQty += u.quantity;
          soldValue += u.value;
          soldCost += u.cost;
        case 'shop_use':
          usedQty += u.quantity;
          usedValue += u.value;
          usedCost += u.cost;
        case 'restock':
          restockQty += u.quantity;
      }
    }

    return {
      'soldQty': soldQty,
      'soldValue': soldValue,
      'soldCost': soldCost,
      'soldProfit': soldValue - soldCost,
      'usedQty': usedQty,
      'usedValue': usedValue,
      'usedCost': usedCost,
      'restockQty': restockQty,
      'sales': maps.length,
    };
  }

  /// Recent bag movements (newest first) for the history list.
  Future<List<ShoppingBagUsage>> getShoppingBagUsageHistory({int limit = 50}) async {
    final db = await database;
    final maps = await db.query(
      'shopping_bag_usage',
      orderBy: 'createdAt DESC',
      limit: limit,
    );
    return maps.map(ShoppingBagUsage.fromMap).toList();
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
              'updatedAt': now,
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
            'updatedAt': now,
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
    final map = customer.toMap();
    // Always stamp the mirror clock so the other PC picks the row up even when
    // the caller built the object from an older copy.
    map['updatedAt'] = DateTime.now().toIso8601String();
    await db.insert(
      'customers',
      map,
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
    final map = customer.toMap();
    map['updatedAt'] = DateTime.now().toIso8601String();
    await db.update(
      'customers',
      map,
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
    final map = expense.toMap();
    if ((map['createdAt'] as String?)?.isEmpty ?? true) {
      map['createdAt'] = DateTime.now().toIso8601String();
    }
    await db.insert(
      'expenses',
      map,
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
    final reload = await getReloadSummary(start, end);
    final refunds =
        await _refundSummary(start.toIso8601String(), end.toIso8601String());

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
    final totalRefunds = refunds['loss'] as double;
    final reloadProfit = reload['profit'] as double;
    final totalSupplierReturns = await getSupplierReturnsTotal(
      start.toIso8601String(),
      end.toIso8601String(),
    );
    final grossProfit = totalRevenue - totalCogs;
    // One honest bottom line: bills, minus the cost of what sold, minus
    // expenses, wastage and refunds paid out, plus the reload margin earned,
    // plus the value of any goods returned to suppliers.
    final netProfit = grossProfit -
        totalExpenses -
        totalWastage -
        totalRefunds +
        reloadProfit +
        totalSupplierReturns;

    return {
      'totalRevenue': totalRevenue,
      'totalCogs': totalCogs,
      'grossProfit': grossProfit,
      'totalExpenses': totalExpenses,
      'expenses': expenses,
      'totalWastage': totalWastage,
      'wastages': wastageReport['wastages'],
      'totalRefunds': totalRefunds,
      'reloadProfit': reloadProfit,
      'reloadSoldValue': reload['soldValue'],
      'totalSupplierReturns': totalSupplierReturns,
      'netProfit': netProfit,
    };
  }

  // ============== LAN DATA MIRROR ==============
  //
  // Every terminal keeps its own copy of the shop's data so it can keep selling
  // (and reporting) when the WiFi drops. This is the shared contract that keeps
  // those copies identical:
  //
  //   * the server publishes changed rows — bills, expenses, wastage, reload
  //     cards, refunds, repack runs, goods received, purchase orders and
  //     supplier payments — and every client pulls them,
  //   * a client pushes its own new rows back up, so the server's reports and
  //     stock count what that till did too.
  //
  // Stock is the one thing a row cannot carry: a bill must move FIFO batches,
  // not just a number. So the *server* stays the single owner of stock and a
  // client sends "this product moved by -2" deltas instead of absolute
  // quantities (see [applyStockDeltas]). That way a bill the server rang up in
  // the same second is never clobbered by a stale figure from the other PC.

  /// Fingerprint of every table the mirror carries.
  ///
  /// Terminals compare this before pulling, so an idle link costs one tiny
  /// request — the same trick the catalog sync uses to keep WiFi usage near
  /// zero. The row count, a money sum (* amount edits) and the newest date
  /// together catch new, edited and deleted rows, not just new ones.
  Future<String> financialRevision() async {
    final db = await database;
    final parts = <String>[];
    for (final spec in _mirrorTables) {
      if (spec.parentTable != null) continue; // covered by its parent's stamp
      final sum =
          spec.sumColumn == null ? '0' : 'COALESCE(SUM(${spec.sumColumn}), 0)';
      final rows = await db.rawQuery(
        'SELECT COUNT(*) c, $sum s, MAX(${spec.dateExpr}) m FROM ${spec.table}',
      );
      final row = rows.isEmpty ? const <String, Object?>{} : rows.first;
      parts.add(
        '${spec.table}=${row['c'] ?? 0}:${row['s'] ?? 0}:${row['m'] ?? ''}',
      );
    }
    // The reset token leads the string so a terminal can spot "the admin wiped
    // the reports" before it decides the data is unchanged.
    final reset = await getSyncMeta(_reportsResetKey) ?? '';
    return 'r$reset|${parts.join('|')}';
  }

  // ---------------- Sync bookkeeping ----------------

  static const String _reportsResetKey = 'reports_reset_at';

  /// Small key/value store for cross-machine bookkeeping. Created on demand so
  /// no schema migration is needed.
  Future<void> _ensureSyncMeta(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS sync_meta ('
      'key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }

  Future<String?> getSyncMeta(String key) async {
    final db = await database;
    await _ensureSyncMeta(db);
    final rows = await db.query(
      'sync_meta',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSyncMeta(String key, String value) async {
    final db = await database;
    await _ensureSyncMeta(db);
    await db.insert(
      'sync_meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// The moment the reports were last wiped, or null if never.
  Future<String?> reportsResetAt() => getSyncMeta(_reportsResetKey);

  /// Wipes the report/ledger history — bills, expenses, wastage and reload
  /// cards — and NOTHING else.
  ///
  /// Deliberately leaves products, categories, customers, images, batches and
  /// current stock quantities untouched: owners use this to clear test/opening
  /// figures and start trading from zero without re-entering the catalogue. It
  /// also stamps [reportsResetAt] so the other machine clears its own mirrored
  /// copy instead of pulling the deleted rows back in.
  Future<Map<String, int>> clearFinancialHistory() async {
    final db = await database;
    var sales = 0;
    var expenses = 0;
    var wastages = 0;
    var reloadCards = 0;
    var bagUsage = 0;
    await db.transaction((txn) async {
      sales = await txn.delete('sales');
      expenses = await txn.delete('expenses');
      wastages = await txn.delete('wastages');
      reloadCards = await txn.delete('reload_cards');
      // The daily sold / shop-use bag ledger is part of the reports; the bag
      // tiers and their stock stay untouched.
      bagUsage = await txn.delete('shopping_bag_usage');
    });
    await setSyncMeta(_reportsResetKey, DateTime.now().toIso8601String());
    BackupService.notifyTransaction('reset-reports');
    return {
      'sales': sales,
      'expenses': expenses,
      'wastages': wastages,
      'reload_cards': reloadCards,
      'shopping_bag_usage': bagUsage,
    };
  }

  /// Rows each mirrored table has written at or after [since].
  ///
  /// Sales fall back to the last 7 days when [since] is null (a bill table can
  /// grow for years); every other table is small, so a brand-new terminal gets
  /// all of it and its reports and history are complete from the first sync.
  ///
  /// Returned as raw database maps: `sales.items` and the GRN/order `items` are
  /// JSON *strings* in the schema and must stay that way, so the receiving
  /// terminal can insert them verbatim without re-encoding.
  Future<Map<String, dynamic>> mirrorRowsSince(DateTime? since) async {
    final db = await database;
    final out = <String, dynamic>{};

    for (final spec in _mirrorTables) {
      List<Map<String, dynamic>> maps;
      if (spec.parentTable != null) {
        final parent = _mirrorSpec(spec.parentTable!)!;
        if (since == null) {
          maps = await db.rawQuery('SELECT * FROM ${spec.table}');
        } else {
          maps = await db.rawQuery(
            'SELECT * FROM ${spec.table} WHERE ${spec.parentColumn} IN '
            '(SELECT id FROM ${spec.parentTable} WHERE (${parent.dateExpr}) >= ?)',
            [since.toIso8601String()],
          );
        }
      } else {
        final cutoff = since ??
            (spec.table == 'sales'
                ? DateTime.now().subtract(const Duration(days: 7))
                : null);
        maps = await db.query(
          spec.table,
          where: cutoff == null ? null : '(${spec.dateExpr}) >= ?',
          whereArgs: cutoff == null ? null : [cutoff.toIso8601String()],
          orderBy: spec.dateExpr,
        );
      }
      out[spec.table] =
          maps.map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return out;
  }

  /// Merges mirrored rows coming from the other machine.
  ///
  /// Insert-or-replace by primary key, and deliberately nothing else: stock is
  /// never touched here. Quantities ride [applyStockDeltas] instead, so a bill
  /// arriving twice — or a row that came *from* this machine in the first
  /// place — can never double-count a movement.
  Future<int> applyMirror(Map<String, dynamic> tables) async {
    final db = await database;
    var applied = 0;

    await db.transaction((txn) async {
      for (final spec in _mirrorTables) {
        final rows = tables[spec.table];
        if (rows is! List) continue;
        for (final raw in rows) {
          if (raw is! Map) continue;
          final row = Map<String, dynamic>.from(raw);
          if (row['id'] == null) continue;
          try {
            if (spec.table == 'product_batches') {
              // A batch lot can be pushed from either PC. When it already
              // exists here, refresh only its metadata (expiry date, prices,
              // batch number, notes) and KEEP the local quantities: each
              // terminal moves its own FIFO layers, so the other machine's
              // remaining-quantity figure must never overwrite ours.
              final existing = await txn.query(
                'product_batches',
                columns: ['id', 'updatedAt'],
                where: 'id = ?',
                whereArgs: [row['id']],
                limit: 1,
              );
              if (existing.isNotEmpty) {
                // Keep the later edit stamp: an older incoming `updatedAt`
                // must never roll the sync clock back and hide this machine's
                // newer expiry edit from the other PC.
                final localStamp =
                    existing.first['updatedAt'] as String? ?? '';
                final incomingStamp = (row['updatedAt'] as String?) ??
                    (row['createdAt'] as String?) ??
                    (row['receivedDate'] as String?) ??
                    '';
                final mergedStamp = incomingStamp.compareTo(localStamp) > 0
                    ? incomingStamp
                    : localStamp;
                await txn.update(
                  'product_batches',
                  {
                    'productId': row['productId'],
                    'batchNumber': row['batchNumber'],
                    'price': row['price'],
                    'sellingPrice': row['sellingPrice'],
                    'expiryDate': row['expiryDate'],
                    'supplierId': row['supplierId'],
                    'notes': row['notes'] ?? '',
                    'receivedDate': row['receivedDate'],
                    'updatedAt': mergedStamp.isEmpty ? null : mergedStamp,
                  },
                  where: 'id = ?',
                  whereArgs: [row['id']],
                );
                applied++;
                continue;
              }
            }
            await txn.insert(
              spec.table,
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            applied++;
          } catch (_) {
            // One malformed row must never abort the whole mirror.
          }
        }
      }
    });

    if (applied > 0) {
      BackupService.notifyTransaction('mirror');
    }
    return applied;
  }

  /// Applies the stock movements another terminal made, as *deltas*.
  ///
  /// The client sends "product X moved by -2" rather than an absolute number,
  /// so a bill the server rang up in the same second is never overwritten by a
  /// stale figure from the other PC. The server stays the single writer of the
  /// batch layers; only the product's on-hand total moves here.
  Future<int> applyStockDeltas(List<Map<String, dynamic>> deltas) async {
    if (deltas.isEmpty) return 0;
    final db = await database;
    final now = DateTime.now().toIso8601String();
    var applied = 0;

    await db.transaction((txn) async {
      for (final delta in deltas) {
        final id = delta['id'] as String?;
        final amount = (delta['delta'] as num?)?.toDouble() ?? 0;
        if (id == null || id.isEmpty || amount == 0) continue;
        final rows = await txn.query(
          'products',
          columns: ['quantity'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final current = (rows.first['quantity'] as num?)?.toDouble() ?? 0;
        var next = current + amount;
        if (next < 0) next = 0;
        await txn.update(
          'products',
          {'quantity': next, 'updatedAt': now},
          where: 'id = ?',
          whereArgs: [id],
        );
        applied++;
      }
    });

    if (applied > 0) {
      BackupService.notifyTransaction('stock mirror');
    }
    return applied;
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
    final refundSummary = await _refundSummary(fromIso, toIso);
    final refundLoss = refundSummary['loss'] as double;
    final refundPending = refundSummary['pending'] as double;
    final refundProcessedCount = refundSummary['count'] as int;
    final refundPendingCount = refundSummary['pendingCount'] as int;

    // ---- Reload (top-up) margin earned in the window --------------------
    final reloadSummary = await getReloadSummary(start, end);
    final reloadProfit = reloadSummary['profit'] as double;
    final reloadSoldValue = reloadSummary['soldValue'] as double;
    final reloadSoldCount = reloadSummary['count'] as int;

    // ---- Shopping bags (sold vs shop use, separate section) -------------
    final bagUsageSummary = await getShoppingBagSummary(start, end);

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

    // ---- Supplier returns (goods sent back; value is a credit) ----------
    final returnRows = await db.query(
      'supplier_returns',
      where: 'returnDate >= ? AND returnDate <= ?',
      whereArgs: [fromIso, toIso],
    );
    var supplierReturnsValue = 0.0;
    for (final row in returnRows) {
      supplierReturnsValue += (row['total'] as num?)?.toDouble() ?? 0;
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

    final bagSoldValue = (bagUsageSummary['soldValue'] as num?)?.toDouble() ?? 0;
    final bagSoldCost = (bagUsageSummary['soldCost'] as num?)?.toDouble() ?? 0;
    final bagUsedCost = (bagUsageSummary['usedCost'] as num?)?.toDouble() ?? 0;
    final totalLoss = cogs +
        wastageLoss +
        refundLoss +
        expenseTotal +
        bagSoldCost +
        bagUsedCost;
    // Bulk bag sales are not rung up on a bill (they live in the bag ledger),
    // so their takings are added to income here; their cost sits in totalLoss
    // above. Reload margin is additional income the shop earned, independent of
    // the till's bills, so it is added after the running costs are taken off. A
    // supplier return is money that came back from a supplier (the goods were
    // already counted in an earlier GRN), so it increases the bottom line too.
    final netProfit = revenue +
        reloadProfit +
        supplierReturnsValue +
        bagSoldValue -
        totalLoss;

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
      'reloadProfit': reloadProfit,
      'reloadSoldValue': reloadSoldValue,
      'reloadSoldCount': reloadSoldCount,
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
      'supplierReturnsValue': supplierReturnsValue,
      'supplierReturnsCount': returnRows.length,
      'stockValue': stockValue,
      'stockItems': stockItems,
      'productCount': products.length,
      'bagSoldQty': bagUsageSummary['soldQty'],
      'bagSoldValue': bagUsageSummary['soldValue'],
      'bagSoldCost': bagUsageSummary['soldCost'],
      'bagUsedQty': bagUsageSummary['usedQty'],
      'bagUsedValue': bagUsageSummary['usedValue'],
      'bagUsedCost': bagUsageSummary['usedCost'],
      'bagRestockQty': bagUsageSummary['restockQty'],
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
        updatedAt: DateTime.now(),
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

  /// Edits an existing wastage record. A changed quantity moves stock by the
  /// difference (a bigger loss deducts more units, a smaller one puts units
  /// back), and the loss is re-valued at the same unit cost used when it was
  /// first recorded. Returns null when the row or its product has gone.
  Future<Wastage?> updateWastage({
    required String id,
    double? quantity,
    String? reason,
    String? notes,
    DateTime? wastageDate,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    Wastage? updated;

    final ok = await db.transaction((txn) async {
      final rows = await txn.query(
        'wastages',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) return false;
      final current = Wastage.fromMap(rows.first);

      final newQty = quantity ?? current.quantity;
      final delta = newQty - current.quantity;

      final productMaps = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [current.productId],
      );
      if (productMaps.isEmpty) return false;
      final product = Product.fromMap(productMaps.first);
      var unitCost = product.buyingPrice;

      if (current.batchId.isNotEmpty) {
        final batchMaps = await txn.query(
          'product_batches',
          where: 'id = ?',
          whereArgs: [current.batchId],
        );
        if (batchMaps.isNotEmpty) {
          final batch = ProductBatch.fromMap(batchMaps.first);
          unitCost = batch.price > 0 ? batch.price : unitCost;
          if (delta != 0) {
            final newBatchQty =
                (batch.quantity - delta).clamp(0.0, double.infinity);
            await txn.update(
              'product_batches',
              {'quantity': newBatchQty, 'updatedAt': now},
              where: 'id = ?',
              whereArgs: [batch.id],
            );
          }
        }
      }

      if (delta != 0) {
        final newProductQty =
            (product.quantity - delta).clamp(0.0, double.infinity);
        await txn.update(
          'products',
          {'quantity': newProductQty, 'updatedAt': now},
          where: 'id = ?',
          whereArgs: [product.id],
        );
        await txn.insert('stock_history', {
          'productId': product.id,
          'productName': current.productName,
          'quantityChanged': -delta,
          'reason': 'Wastage corrected',
          'createdAt': now,
        });
      }

      updated = Wastage(
        id: current.id,
        productId: current.productId,
        productName: current.productName,
        quantity: newQty,
        reason: reason ?? current.reason,
        lossValue: unitCost * newQty,
        batchId: current.batchId,
        batchNumber: current.batchNumber,
        notes: notes ?? current.notes,
        recordedBy: current.recordedBy,
        wastageDate: wastageDate ?? current.wastageDate,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
      );
      await txn.update(
        'wastages',
        updated!.toMap(),
        where: 'id = ?',
        whereArgs: [id],
      );
      return true;
    });

    if (ok) {
      BackupService.notifyTransaction('wastage');
    }
    return ok ? updated : null;
  }

  /// Removes a wastage record and puts its units back on the shelf (product and
  /// owning batch), so stock counts stay consistent with the correction.
  Future<bool> deleteWastage(String id) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final ok = await db.transaction((txn) async {
      final rows = await txn.query(
        'wastages',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) return false;
      final current = Wastage.fromMap(rows.first);

      if (current.batchId.isNotEmpty) {
        final batchMaps = await txn.query(
          'product_batches',
          where: 'id = ?',
          whereArgs: [current.batchId],
        );
        if (batchMaps.isNotEmpty) {
          final batch = ProductBatch.fromMap(batchMaps.first);
          await txn.update(
            'product_batches',
            {
              'quantity': batch.quantity + current.quantity,
              'updatedAt': now,
            },
            where: 'id = ?',
            whereArgs: [batch.id],
          );
        }
      }

      final productMaps = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [current.productId],
      );
      if (productMaps.isNotEmpty) {
        final product = Product.fromMap(productMaps.first);
        await txn.update(
          'products',
          {'quantity': product.quantity + current.quantity, 'updatedAt': now},
          where: 'id = ?',
          whereArgs: [product.id],
        );
        await txn.insert('stock_history', {
          'productId': product.id,
          'productName': current.productName,
          'quantityChanged': current.quantity,
          'reason': 'Wastage record removed',
          'createdAt': now,
        });
      }

      await txn.delete(
        'wastages',
        where: 'id = ?',
        whereArgs: [id],
      );
      return true;
    });

    if (ok) {
      BackupService.notifyTransaction('wastage');
    }
    return ok;
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
    await db.delete('supplier_returns');
    await db.delete('shopping_bag_usage');
    await db.delete('shopping_bags');
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
    // Bump the mirror clock on every edit (same as products/customers), so a
    // corrected phone number or payment term actually travels to the other PC
    // instead of quietly staying behind because updatedAt never moved.
    await db.update(
      'suppliers',
      supplier.copyWith(updatedAt: DateTime.now()).toMap(),
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
    final returnRows = await db.rawQuery(
      'SELECT COALESCE(SUM(total), 0) AS t FROM supplier_returns WHERE supplierId = ?',
      [supplierId],
    );
    final received = (grnRows.first['t'] as num).toDouble();
    final paid = (payRows.first['t'] as num).toDouble();
    final returned = (returnRows.first['t'] as num).toDouble();
    // Goods the shop returned are credited: outstanding is what was received
    // minus what was paid minus what came back to the shelves.
    return received - paid - returned;
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

  Future<double> getSupplierTotalReturned(String supplierId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(total), 0) AS t FROM supplier_returns WHERE supplierId = ?',
      [supplierId],
    );
    return (rows.first['t'] as num).toDouble();
  }

  /// Returns the next daily supplier-return number, e.g. SRN-20261011-0001.
  Future<String> getNextSupplierReturnNumber() async {
    final db = await database;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM supplier_returns WHERE returnDate >= ?',
      [startOfDay],
    );
    final count = rows.isNotEmpty ? (rows.first['c'] as int) : 0;
    String two(int n) => n.toString().padLeft(2, '0');
    final seq = (count + 1).toString().padLeft(4, '0');
    return 'SRN-${now.year}${two(now.month)}${two(now.day)}-$seq';
  }

  /// Records goods returned to a supplier — the mirror image of a GRN.
  ///
  /// For every item the product quantity is reduced and the stock is taken
  /// back out of the FIFO batches (or the single batch the user picked), the
  /// returned value is stored against the supplier and a stock-history line is
  /// written — all atomically. The row then travels to the other PC through
  /// the LAN mirror and the product movement rides the normal stock deltas.
  /// Returns false when no item could be applied (product no longer exists).
  Future<bool> recordSupplierReturn(SupplierReturn record) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    var inserted = false;

    final ok = await db.transaction((txn) async {
      for (final item in record.items) {
        final productMaps = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [item.productId],
        );
        if (productMaps.isEmpty) continue;
        final product = Product.fromMap(productMaps.first);

        // Take the stock back out of the batches. A specific batch wins when
        // the user picked one; otherwise FIFO, just like a sale.
        var remaining = item.quantity;
        final batches = await _fifoBatches(txn, product.id);
        final pickedBatch = item.batchId.isNotEmpty ? item.batchId : null;
        for (final batch in batches) {
          if (remaining <= 0) break;
          if (pickedBatch != null && batch.id != pickedBatch) continue;
          final take = batch.quantity < remaining ? batch.quantity : remaining;
          await txn.update(
            'product_batches',
            {'quantity': batch.quantity - take},
            where: 'id = ?',
            whereArgs: [batch.id],
          );
          remaining -= take;
        }

        var newQty =
            (product.quantity - item.quantity).clamp(0.0, double.infinity);
        // Snap break-bulk stock back onto an exact piece boundary (returns are
        // stored in boxes, but never leave floating-point drift behind).
        if (product.isBreakBulk) {
          newQty = (newQty * product.piecesPerBox).round() /
              product.piecesPerBox;
        }
        await txn.update(
          'products',
          {'quantity': newQty, 'updatedAt': now},
          where: 'id = ?',
          whereArgs: [product.id],
        );

        await txn.insert('stock_history', {
          'productId': item.productId,
          'productName': item.productName,
          'quantityChanged': -item.quantity,
          'reason': 'Returned to supplier: ${record.reason}',
          'createdAt': now,
        });
        inserted = true;
      }

      if (inserted) {
        await txn.insert('supplier_returns', record.toMap());
      }
      return inserted;
    });

    if (ok) {
      BackupService.notifyTransaction('supplier return');
    }
    return ok;
  }

  Future<List<SupplierReturn>> getAllSupplierReturns() async {
    final db = await database;
    final maps = await db.query(
      'supplier_returns',
      orderBy: 'returnDate DESC, createdAt DESC',
    );
    return maps.map(SupplierReturn.fromMap).toList();
  }

  Future<List<SupplierReturn>> getSupplierReturnsBySupplier(
    String supplierId,
  ) async {
    final db = await database;
    final maps = await db.query(
      'supplier_returns',
      where: 'supplierId = ?',
      whereArgs: [supplierId],
      orderBy: 'returnDate DESC, createdAt DESC',
    );
    return maps.map(SupplierReturn.fromMap).toList();
  }

  /// Total value (in shop currency) of supplier returns dated inside a window.
  Future<double> getSupplierReturnsTotal(String fromIso, String toIso) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(total), 0) AS t FROM supplier_returns '
      'WHERE returnDate >= ? AND returnDate <= ?',
      [fromIso, toIso],
    );
    return (rows.first['t'] as num).toDouble();
  }

  // ============== PRODUCT BATCHES ==============
  Future<void> insertProductBatch(ProductBatch batch) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final map = batch.toMap()..['updatedAt'] = now;
    await db.insert(
      'product_batches',
      map,
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

  /// Every batch that carries an expiry date, joined with its product name and
  /// ordered soonest-expiry first. Powers the Expiry screen, which is the one
  /// place that shows the whole shop's expiry picture at once (a product
  /// received on several dates simply appears once per batch).
  Future<List<(ProductBatch batch, String productName)>>
      getExpiryOverview() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT pb.*, p.name AS productName
      FROM product_batches pb
      INNER JOIN products p ON p.id = pb.productId
      WHERE pb.expiryDate IS NOT NULL
      ORDER BY pb.expiryDate ASC
    ''');
    final result = <(ProductBatch, String)>[];
    for (final row in rows) {
      result.add((
        ProductBatch.fromMap(row),
        (row['productName'] as String?) ?? '',
      ));
    }
    return result;
  }

  /// `productId -> expiry signals across its stocked batches`, used by the POS
  /// grid so a tile can warn about the item's closest lot instead of the
  /// product-level expiry column, which the Inventory form never sets.
  ///
  /// * `$1` — the soonest expiry still in the future (drives the
  ///   "Exp: X days" badge);
  /// * `$2` — the newest expiry of any stocked lot (if this is already in
  ///   the past, every remaining lot is expired, so the whole item is
  ///   red-flagged as unsellable).
  Future<Map<String, (DateTime?, DateTime?)>> getBatchExpirySignals() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final rows = await db.rawQuery('''
      SELECT productId,
             MIN(CASE WHEN expiryDate > ? THEN expiryDate END) AS next,
             MAX(expiryDate) AS latest
      FROM product_batches
      WHERE expiryDate IS NOT NULL AND quantity > 0
      GROUP BY productId
    ''', [now]);
    return {
      for (final row in rows)
        row['productId'] as String: (
          row['next'] == null ? null : DateTime.tryParse(row['next'] as String),
          row['latest'] == null
              ? null
              : DateTime.tryParse(row['latest'] as String),
        ),
    };
  }

  Future<void> updateProductBatch(ProductBatch batch) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final map = batch.toMap()..['updatedAt'] = now;
    await db.update(
      'product_batches',
      map,
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
              'updatedAt': now,
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
            'updatedAt': now,
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

/// One table carried by the LAN data mirror.
///
/// [dateExpr] drives both the change fingerprint and the incremental pull — it
/// may be a plain column or a `COALESCE(...)` when a row's "last touched"
/// moment is not its creation date (a refund is finished on [processedDate]).
/// [sumColumn] lets an *edit* to an existing row (a corrected expense, a refund
/// that just got processed) move the fingerprint even when the row's own date
/// did not change. [parentTable]/[parentColumn] mark a child table with no date
/// of its own that therefore travels with its parent.
class _MirrorTable {
  const _MirrorTable(
    this.table,
    this.dateExpr, {
    this.sumColumn,
    this.parentTable,
    this.parentColumn,
  });

  final String table;
  final String dateExpr;
  final String? sumColumn;
  final String? parentTable;
  final String? parentColumn;
}

/// The tables the mirror ships, in insert order (parents before children).
const List<_MirrorTable> _mirrorTables = [
  _MirrorTable('sales', 'saleDate', sumColumn: 'totalAmount'),
  // Ledger rows carry a *business* date the user can back-date (a wastage
  // dated last week), so the sync clock is the later of that business date and
  // the row's own createdAt. Otherwise a row dated at midnight — what the date
  // picker returns for "today" — sorts before the push watermark and would
  // never travel to the other PC.
  _MirrorTable('expenses', 'MAX(expenseDate, createdAt)', sumColumn: 'amount'),
  _MirrorTable('wastages', 'MAX(COALESCE(updatedAt, \'\'), '
          'COALESCE(wastageDate, \'\'), COALESCE(createdAt, \'\'))',
      sumColumn: 'lossValue'),
  _MirrorTable(
    'reload_cards',
    "COALESCE(NULLIF(usedAt, ''), createdAt)",
    sumColumn: 'value',
  ),
  _MirrorTable(
    'refund_returns',
    'MAX(COALESCE(processedDate, createdAt), createdAt)',
    sumColumn: 'totalRefundAmount',
  ),
  _MirrorTable('productions', 'producedAt'),
  _MirrorTable(
    'production_components',
    '',
    parentTable: 'productions',
    parentColumn: 'productionId',
  ),
  _MirrorTable('recipes', 'updatedAt'),
  _MirrorTable(
    'recipe_items',
    '',
    parentTable: 'recipes',
    parentColumn: 'recipeId',
  ),
  _MirrorTable('goods_received_notes', 'MAX(receivedDate, createdAt)',
      sumColumn: 'total'),
  _MirrorTable(
    'purchase_orders',
    'MAX(COALESCE(receivedDate, orderDate), createdAt)',
    sumColumn: 'total',
  ),
  _MirrorTable('supplier_payments', 'MAX(paymentDate, createdAt)',
      sumColumn: 'amount'),
  // Goods returned to a supplier ride the mirror so the other PC learns about
  // the credit and its value in one heartbeat — exactly like a payment or GRN.
  // The stock that went back out of the shelves travels separately as a delta
  // (see applyStockDeltas), like every other stock movement.
  _MirrorTable(
    'supplier_returns',
    'MAX(COALESCE(returnDate, createdAt), createdAt)',
    sumColumn: 'total',
  ),
  // Customers and suppliers ride the same mirror so a new contact typed on the
  // cashier PC reaches the admin PC (and back) within one heartbeat, instead of
  // only travelling server -> client through the catalog.
  _MirrorTable('customers', 'MAX(updatedAt, createdAt)'),
  _MirrorTable('suppliers', 'MAX(updatedAt, createdAt)'),
  // Batch lots travel both ways so an expiry date entered on either PC (GRN
  // on the counter, receiving on the office machine) reaches the other PC and
  // the Expiry screen is complete everywhere. The clock is the latest of the
  // row's creation, received date and last edit (`updatedAt` is bumped by any
  // in-place change, so a corrected expiry date travels too). Stock quantities
  // are NOT taken from here — see the merge in [applyMirror], which never
  // clobbers a local quantity.
  _MirrorTable(
    'product_batches',
    'COALESCE(updatedAt, receivedDate, createdAt)',
  ),
  // Shopping bags: the tier rows (including their own stock — bag stock moves
  // rarely and from one counter, so each movement ships the updated row) and
  // the sold / shop-use / restock usage log that drives the dashboard numbers.
  _MirrorTable('shopping_bags', 'COALESCE(updatedAt, createdAt)'),
  _MirrorTable('shopping_bag_usage', 'createdAt', sumColumn: 'value'),
];

/// Look up a mirror descriptor by table name (used to reach a child table's
/// parent clock).
_MirrorTable? _mirrorSpec(String table) {
  for (final spec in _mirrorTables) {
    if (spec.table == table) return spec;
  }
  return null;
}
