import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'data/database/database_service.dart';
import 'data/services/backup_service.dart';
import 'data/services/supabase_sync_service.dart';
import 'presentation/providers/auth_provider.dart';
import 'presentation/providers/batch_provider.dart';
import 'presentation/providers/category_provider.dart';
import 'presentation/providers/customer_provider.dart';
import 'presentation/providers/payment_provider.dart';
import 'presentation/providers/product_provider.dart';
import 'presentation/providers/purchase_order_provider.dart';
import 'presentation/providers/expense_provider.dart';
import 'presentation/providers/grn_provider.dart';
import 'presentation/providers/network_provider.dart';
import 'presentation/providers/refund_return_provider.dart';
import 'presentation/providers/reports_provider.dart';
import 'presentation/providers/sales_provider.dart';
import 'presentation/providers/settings_provider.dart';
import 'presentation/providers/supplier_provider.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/providers/wastage_provider.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/dashboard/home_screen.dart';
import 'presentation/screens/pos/customer_display_screen.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (args.isNotEmpty && args.first == 'multi_window') {
    final windowId = args[1];
    // ignore: unused_local_variable
    final argument = args[2].isEmpty
        ? const {}
        : jsonDecode(args[2]) as Map<String, dynamic>;
    
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CustomerDisplayScreen(windowId: windowId),
    ));
    return;
  }

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      center: true,
      title: 'Randil Grocery POS',
      size: Size(1366, 860),
      minimumSize: Size(1024, 700),
      backgroundColor: Color(0xFFF5F6FA),
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      // Enter fullscreen only after the window is visible and the first frame
      // has rendered. Doing it earlier can leave an invisible / non-interactive
      // window on some Windows setups.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await windowManager.setFullScreen(true);
    });
  }

  // Initialize sqflite for Windows
  sqfliteFfiInit();

  // Initialize ThemeProvider
  await ThemeProvider().init();

  // Initialize backup system
  try {
    final settings = await DatabaseService().getShopSettings();
    final backupService = BackupService();
    final dbPath = await DatabaseService().getDatabasePath();
    await backupService.initializeBackupSystem(dbPath, settings: settings);
  } catch (_) {}

  // Cloud sync to the Randil Grocery POS phone app (no-op until configured)
  try {
    await SupabaseSyncService.instance.init();
  } catch (_) {}

  runApp(const RandilGroceryPOS());
}

class RandilGroceryPOS extends StatelessWidget {
  const RandilGroceryPOS({super.key});

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => CategoryProvider()),
          ChangeNotifierProvider(create: (_) => ProductProvider()),
          ChangeNotifierProvider(create: (_) => SalesProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => ReportsProvider()),
          ChangeNotifierProvider(create: (_) => CustomerProvider()),
          ChangeNotifierProvider(create: (_) => SupplierProvider()),
          ChangeNotifierProvider(create: (_) => BatchProvider()),
          ChangeNotifierProvider(create: (_) => RefundReturnProvider()),
          ChangeNotifierProvider(create: (_) => PaymentProvider()),
          ChangeNotifierProvider(create: (_) => PurchaseOrderProvider()),
          ChangeNotifierProvider(create: (_) => ExpenseProvider()),
          ChangeNotifierProvider(create: (_) => GrnProvider()),
          ChangeNotifierProvider(create: (_) => WastageProvider()),
          ChangeNotifierProvider(create: (_) => NetworkProvider()..init()),
        ],
        child: Consumer<ThemeProvider>(
          builder: (context, themeProvider, child) => MaterialApp(
            title: 'Randil Grocery POS',
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode:
                themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            debugShowCheckedModeBanner: false,
            home: const _AuthGate(),
            routes: {
              '/login': (_) => const LoginScreen(),
              '/home': (_) => const HomeScreen(),
            },
          ),
        ),
      );
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) => Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          if (authProvider.isLoggedIn) {
            return const HomeScreen();
          }
          // Always show the login screen. On fresh installs a default
          // admin account (admin / admin123) is seeded in the database.
          return const LoginScreen();
        },
      );
}
