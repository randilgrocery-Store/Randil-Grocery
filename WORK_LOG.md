# Randil Grocery POS - Applied Change Log

This document records the actual code changes applied to make the POS sellable:
security, real printer support, backup encryption, purchase orders, loyalty &
credit accounts, expense tracking, profit reporting, and the admin seeding flow.

---

## 1. Printer Support (Windows)

- **win32 fixed to `5.15.0`** in `pubspec.yaml` (resolves `PRINTER_HANDLE` to `int`,
  required non-nullable pointers for `EnumPrinters` / `OpenPrinter`, buffers freed via `LocalFree`).
- **`lib/data/services/windows_printer_service.dart`** — real ESC/POS thermal printing via
  the GDI/win32 printer API:
  - Enumeration of available printers.
  - Receipt layout (store header, items, totals, payment breakdown, footer).
  - Raw byte writing to the printer queue.
- **`lib/data/services/print_service.dart`** — abstraction that routes to the Windows
  printer service; `lib/presentation/screens/pos/pos_screen.dart` triggers receipt printing
  after each completed sale.

## 2. Security

- **`lib/core/utils/password_hasher.dart`** — salted SHA-256 (HMAC) password hashing,
  1000 iterations, format `<salt>$<hash>`; `verify` does constant-time comparison.
- **`lib/core/utils/secure_storage.dart`** — Windows DPAPI (`CRYPTPROTECT_*`) for
  machine-bound secret storage; legacy plaintext secrets are auto-upgraded on decrypt.
- **`lib/data/services/settings_service.dart`** — no plaintext passwords; tokens stored securely.
- **`lib/data/services/backup_service.dart`** — database backups are encrypted with
  a DPAPI-protected key before being written; restore decrypts transparently.

## 3. Backup System

- Automatic + manual encrypted backups.
- `clearAllData()` wipes the database, including the new `expenses` table.
- Backup files are batch-restorable.

## 4. Purchase Orders & Restock

- **`lib/data/models/purchase_order.dart`** + DB tables + provider.
- **`lib/presentation/screens/inventory/purchase_order_screen.dart`** — create purchase
  orders, receive items (restock), track order status.

## 5. Loyalty Points & Customer Credit Accounts

- **`lib/data/models/customer.dart`** — added `creditBalance`, `loyaltyPoints`;
  `fromMap` falls back to `0.0` / `0` for existing rows.
- **`lib/data/database/database_service.dart`**:
  - `customers` table now includes the two new columns (new installs).
  - ALTER migration adds the columns to existing databases.
  - `adjustCustomerCredit`, `adjustCustomerLoyaltyPoints`, `updateCustomerCreditAndLoyalty`
    (+ provider wrappers in `customer_provider.dart`).
- **`lib/presentation/screens/pos/pos_screen.dart`**:
  - Customer picker (dropdown) with live credit-balance / loyalty-points chips.
  - Redeem points toggle: 1 point = Rs 1, clamped to the sale total, applied as a
    custom discount.
  - **Credit account payment** requires a selected customer with sufficient balance;
    balance is deducted on sale.
  - Points earned on every paid sale: `floor(totalPaid / 100)`.
  - Both normal sales and the instant-checkout path update the customer account.
- **`lib/presentation/providers/payment_provider.dart`** — default enabled methods now
  include all 6: cash, card, mobile wallet, cheque, bank transfer, credit account.
- **`lib/presentation/screens/admin/customer_management_screen.dart`** — customer cards
  show credit & points; "Add/Deduct Credit" and "Adjust Points" dialogs.

## 6. Expense Tracking & Profit Reports

- **`lib/data/models/expense.dart`** — Expense model (description, category, amount,
  date, notes, recorded by).
- **`lib/data/database/database_service.dart`** — `expenses` table, CRUD methods plus
  `getProfitReport()`:
  - Revenue, COGS (approximated using current product buying price × qty sold),
    gross profit, total expenses, expense list, net profit.
- **`lib/presentation/providers/expense_provider.dart`** — provider registered in `main.dart`.
- **`lib/presentation/screens/reports/expense_management_screen.dart`** — add/list/delete
  expenses with category picker and date selector.
- **`lib/presentation/screens/reports/reports_screen.dart`** — now has 3 tabs:
  Daily, Monthly, **Profit & Expenses** (revenue / COGS / expenses / net profit stat cards
  + expense breakdown).
- **`lib/presentation/screens/dashboard/home_screen.dart`** — added "Expenses" admin nav
  item (index 8; Reports 9, Settings 10).

## 7. Login Flow & Default Admin Seeding

- **`lib/data/database/database_service.dart`** — `_seedDefaultAdmin()`: when the `users`
  table is empty on app open, inserts a default admin via the password hasher
  (username `admin`, password `admin123`, role `admin`, full name `Administrator`).
- **`lib/main.dart`** — removed the first-run admin-creation gate; `_AuthGate` now
  always shows `LoginScreen`. On fresh installs the seeded admin lets you sign in.
- **Deleted** `lib/presentation/screens/auth/first_run_setup_screen.dart`.
- **`lib/presentation/providers/auth_provider.dart`** — removed `createInitialAdmin`.
- **`lib/presentation/screens/settings/settings_screen.dart`**:
  - Add-user dialog: always creates a **Cashier** (no role selection) with an info note.
  - Edit-user dialog: role shown as read-only ("roles cannot be changed").
- **`lib/presentation/screens/auth/login_screen.dart`** — hint box showing the default
  admin login.

### Installation notes for seeding

- The seed only runs on a **completely empty** `users` table. If a database from an older
  build already contains users, it is left untouched (existing credentials keep working).
- Stale test databases on a dev machine can be reset by deleting
  `<folder>\...\sqflite_common_ffi\databases\randil_grocery_pos.db`
  so a fresh seeded database is created on next launch.

---

## Verification

- `flutter analyze` — clean (no issues).
- `flutter test` — 8/8 tests pass, including DPAPI secure-storage round trips and the
  POS smoke test.
- `flutter build windows` (Release) — succeeds; output in `build\windows\x64\runner\Release\randil_grocery_pos.exe`.