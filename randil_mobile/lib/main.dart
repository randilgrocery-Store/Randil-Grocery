import 'package:flutter/material.dart';

import 'screens/dashboard_screen.dart';

const kBrandGreen = Color(0xFF00843D);

void main() {
  runApp(const RandilApp());
}

/// Owner-facing viewer for Randil Grocery Shop.
///
/// Opens straight to the live dashboard (no login — the data is read from the
/// shop's own Supabase project with the publishable anon key).
class RandilApp extends StatelessWidget {
  const RandilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Randil POS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kBrandGreen),
        scaffoldBackgroundColor: const Color(0xFFF3F5F7),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(backgroundColor: kBrandGreen),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}