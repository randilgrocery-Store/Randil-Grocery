import 'package:flutter_test/flutter_test.dart';
import 'package:randil_grocery_pos/presentation/shell/app_sidebar.dart';

/// Regression guard for the navigation. The sidebar addresses screens by their
/// *index* in [AppSidebar.adminLabels] / [AppSidebar.cashierLabels], so if a
/// screen is inserted in the middle and a group forgets to list the shifted
/// index, that screen silently vanishes (this is exactly how **Settings**
/// disappeared once Expiry/Expenses were added).
void main() {
  test('admin sidebar lists every screen exactly once, including Settings', () {
    expect(
      AppSidebar.coversEveryScreen(
        AppSidebar.adminSections,
        AppSidebar.adminLabels.length,
      ),
      isTrue,
      reason: 'Every admin screen must appear in a sidebar group exactly once.',
    );

    final settings = AppSidebar.adminLabels.indexOf('Settings');
    expect(settings, isNot(-1), reason: 'Settings must exist in the menu');
    final flat = [for (final s in AppSidebar.adminSections) ...s.indices];
    expect(flat, contains(settings),
        reason: 'Settings must be reachable from the sidebar');
  });

  test('cashier sidebar lists every screen exactly once', () {
    expect(
      AppSidebar.coversEveryScreen(
        AppSidebar.cashierSections,
        AppSidebar.cashierLabels.length,
      ),
      isTrue,
    );
  });

  test('every label has a matching icon', () {
    expect(AppSidebar.adminIcons.length, AppSidebar.adminLabels.length);
    expect(AppSidebar.cashierIcons.length, AppSidebar.cashierLabels.length);
  });

  test('cashier menu carries GRN, Expiry and Expenses', () {
    for (final label in ['GRN', 'Expiry', 'Expenses']) {
      expect(AppSidebar.cashierLabels, contains(label));
    }
  });
}
