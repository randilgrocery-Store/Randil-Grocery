# Randil Grocery POS — Project Continuation Guide

This file is the single place to continue work on the **Randil Grocery POS** Windows
point-of-sale application. Read the *Quick Start* and *Current Status* first, then pick
up the *Roadmap*.

> Keep this file updated every session: bump "Current status", note anything that was
> changed, and copy any decisions made during a session here.

---

## 1. Quick start

- Project dir: `D:\Randil Grocery POS`
- Framework: **Flutter 3.44.1 stable** (Windows desktop target)
- Build output: `build\windows\x64\runner\Release\randil_grocery_pos.exe`
- The built app must be launched **from the Release folder** (it is shipped as a
  self-contained folder), e.g.:
  ```powershell
  Start-Process -FilePath "D:\Randil Grocery POS\build\windows\x64\runner\Release\randil_grocery_pos.exe"
  ```

### Commands
| Task | Command |
| ---- | ------- |
| Analyze | `flutter analyze lib` |
| Build release | `flutter build windows --release` |
| Run (dev) | `flutter run -d windows` |
| Check table | `dart run <tool>.dart` (temporary tools in project root, delete after use) |

### Login accounts (always available, auto-repaired on open)
- **Administrator:** `admin` / `admin123`
- **Cashier:** `cashier` / `1234`
Passwords are re-seeded/fixed automatically by the app on every database open
(`_ensureStandardAccounts`). The forced-reset happens only once (flag
`standard_accounts_repaired_v1` in SharedPreferences) so a password the owner
deliberately changes later is not overwritten.
- The login **screen no longer prints the default credentials** (they are listed
  in `docs/LOGIN_CREDENTIALS.md`, which also covers the phone app's Supabase keys).
- Standard credentials stay hardcoded in the DB seeder (`database_service.dart`),
  as the owner wants defaults present in the database, not a registration flow.

### Bundled installer (client POS deployment)
- `setup/build_installer.ps1` packages the latest release into
  `setup/RandilGroceryPOS-Setup` (+ `.zip`): the full `app/` folder (Release incl.
  hidden `.dart_tool`), `install.bat`/`install.ps1`, `README.txt`,
  `docs/CLIENT_GUIDE.txt`, `docs/LOGIN_CREDENTIALS.md`,
  `docs/supabase_schema.sql` and `RandilGroceryPOS.apk`.
- On the target PC: copy the kit (e.g. USB) → double-click `install.bat` → allow
  elevation → shortcuts created, app under `C:\Program Files\RandilGroceryPOS`,
  uninstaller generated next to the exe. Role (server/client) is chosen in
  Settings → Multi-PC & Live Sync after first run.

---

## 2. Database (IMPORTANT — read this)

**Location (current):**
`%LOCALAPPDATA%\RandilGroceryPOS\randil_grocery_pos.db`
(e.g. `C:\Users\jerus\AppData\Local\RandilGroceryPOS\randil_grocery_pos.db`)

### Why this is stable now
Older builds placed the DB at `<working-directory>\.dart_tool\sqflite_common_ffi\databases\...`.
That produced **two different databases** depending on whether the app was run via
`flutter run` (project root) or the built EXE (Release folder), which caused lost data and
"wrong password" bugs. The fix in `DatabaseService.getDatabasePath()`:
- always uses the stable `%LOCALAPPDATA%\RandilGroceryPOS\` path, and
- on first run, **inherits the largest legacy DB** automatically so nothing is lost
  (`_findLargestLegacyDatabase` checks cwd + the two known dev paths).

### Troubleshooting data issues
- If data seems "missing", check `%LOCALAPPDATA%\RandilGroceryPOS\` — that is the only
  real database now. Legacy copies under any `.dart_tool` folder are dead files.
- CSV export/backup lives in Settings → Backup.

---

## 3. Architecture

```
lib/
  main.dart                     App bootstrap, providers (ChangeNotifierProvider)
  core/
    utils/password_hasher.dart  salt$hmac-sha256, 1000 iterations
    utils/secure_storage.dart   AES-encrypted storage for tokens
  data/
    database/database_service.dart   SQLite (sqflite_common_ffi) singleton + migrations
    models/                          sale, product, batch, grn, po, refund, supplier,
                                     customer, category, expense, user, cart_item, shop_settings
    services/
      customer_display_service.dart  second-screen customer display (desktop_multi_window)
      display_service.dart           Win32 monitor resolution helper
      network_sync.dart              offline push queue + retry (SharedPreferences-backed)
      pos_server.dart                shelf HTTP server + UDP beacon (server mode)
      pos_client.dart                HTTP client (client mode)
      pos_discovery.dart             UDP multicast discovery
      pos_protocol.dart              protocol constants
      backup_service.dart            local backup/restore (Google Drive stub)
  presentation/
    providers/                     auth, product, category, customer, sales, reports,
                                   refund_return, settings, network
    screens/
      auth/login_screen.dart
      dashboard/home_screen.dart    shell + cashier dashboard + Profile
      dashboard/dashboard_screen.dart  admin analytics dashboard
      pos/pos_screen.dart           billing
      pos/customer_display_screen.dart second-monitor display UI
      inventory/  sales buttons (GRN, batches, purchase orders, inventory)
      suppliers, customers, reports, refunds, expenses, settings
    widgets/custom_widgets.dart     shared UI (cards, hero panels, theme)
```

### LAN multi-PC (already built & verified)
- Two roles share one backend over the shop Wi-Fi (everything is FREE, no cloud needed):
  - **Server mode** (Admin PC): the machine's DB owns the data. Runs a shelf HTTP server
    on port 8180 (configurable via Settings → Multi-PC & Live Sync) and announces itself on
    UDP multicast group `239.0.0.7:8181` (magic string `RANDILPOS`).
  - **Client mode** (Cashier POS): auto-discovers the server (`pos_discovery.dart`), falls
    back to a saved IP (`serverIpFallback`), syncs the catalog/products/customers down,
    pushes sales up.
- Endpoints: `GET /api/health`, `GET /api/catalog`, `GET /api/customers`,
  `GET /api/report/daily?from&to`, `GET /api/guide`, `POST /api/sales`.
- Sales push is idempotent (keyed by cashier sale id); offline sales are queued in
  SharedPreferences (`pending_push_sales`) and retried until accepted.
- V1 scope: **sales push + catalog pull only** (not full two-way CRUD parity). Catalog edits
  made on a client machine are NOT merged back — a future V2 item.
- Tested headless once: health 200, catalog pull, sale → `INV-000009`, idempotent re-push,
  daily report with payment-method split.

### Customer display
- Auto-opens on the second monitor for **both admin and cashier** at login.
- Cashier dashboard has a **Open/Close Customer Display** quick-action button
  (`CustomerDisplayService.toggle()`); hiding uses native window hide, keeping the
  sub-window alive for instant reopen.
- The display window fills the secondary monitor (borderless, out of taskbar/alt-tab) via
  Win32 calls in `customer_display_screen.dart`.

---

## 4. Feature highlight (what exists)

- **Billing / POS** — touch-friendly, search/barcode add-to-cart, batch/FIFO stock
  allocation (splits across batches with expiry/movement order), Cash + Card split
  payment (single Pay button flow), change calculation.
- **Receipts** — thermal 78 mm printing (XP-80), logo, shop stamp/address/contact
  ("Jerusha Tech Solutions / 070 3027 611 / jerushasharon1999@gmail.com"), dev credits.
- **GRN** — goods received note, stock-in with batch allocation.
- **Inventory** — products, barcodes, stock levels, batches (expiry/movement), low-stock
  alerts, batch delete, PO receive.
- **Purchase Orders, Suppliers, Customers, Refunds/Returns** (pending approval workflow,
  batch restore on refund), **Expenses**.
- **Reports** — daily & monthly, payment-method breakdown, sales-by-cashier, top items,
  printable.
- **Dashboard** — upgraded to a professional look.
  - Hero header: time-based greeting + shop name + date + live refresh + big **Today**
    revenue/transactions block with decorative circles.
  - Segmented range control (Today / 7D / 30D).
  - Six gradient KPI cards **with vs-previous-period delta** on Revenue (nested FutureBuilders:
    `_prevRangeSalesFuture` vs `_rangeSalesFuture`, see `_deltaPercent`).
  - Revenue trend line chart, Top-selling bar chart, Inventory Health pie, Low Stock
    alerts, Cashier Leaderboard, Quick Actions grid.
- **Settings** — shop name/address/phone/email/tax/printer, backup, network (Multi-PC).

---

## 5. Theme / style notes
- Shared widgets live in `lib/presentation/widgets/custom_widgets.dart`
  (`GroceryCard`, `DashboardHeroPanel`, `PosAppTheme` etc.).
- App runs fullscreen (`windowManager.setFullScreen(true)`).
- Existing conventions: `ChangeNotifierProvider` + `context.read/watch`, sqflite_common_ffi,
  `Uuid().v4()` string PKs, dates stored ISO-8601.
- **Do not add code comments unless asked.** Follow the existing import sorting style.

---

## 6. Current status (last session)

- **POS payment panel scroll fixed** (`pos_screen.dart`): the payment inputs scroll
  internally now, but **TOTAL DUE, Paid/Change and the Pay / Hold Bill / Clear buttons are
  pinned** in a new `_buildPaymentFooter()` so they can never scroll out of reach.
- **Android companion app BUILT** (`D:\Randil Grocery POS\randil_mobile`):
  "Randil Grocery POS" — **no login**, modern Material 3 UI, theme switcher (Light /
  Dark / Auto + 5 accent colors), fl_chart dashboards, bottom-nav tabs
  (**Home / Sales / Stock / Reports / Settings**). See section 8.
- **Cloud sync implemented on the desktop POS**
  (`lib/data/services/supabase_sync_service.dart`, wired in `SalesProvider.processSale`,
  `main.dart` init + Settings → **Cloud** tab):
  - Config lives in SharedPreferences (`supabase_url` / `supabase_anon` /
    `supabase_enabled`) — no DB migration.
  - Every sale pushes instantly; products/customers/refunds/GRNs/expenses sync on app
    start + every 15 minutes via a timer + on demand ("Save & Sync Now" button).
  - Upserts via PostgREST `Prefer: resolution=merge-duplicates` (idempotent).
  - SQL setup script: `docs/supabase_schema.sql` (paste into Supabase SQL Editor once).
- **Android APK built OK**: `randil_mobile\build\app\outputs\flutter-apk\app-release.apk`.
  Note: `randil_mobile/android/gradle.properties` sets `kotlin.incremental=false` —
  required because sources are on `D:\` while the pub cache is on `C:\` (Kotlin
  incremental caches crash across drives).
- Desktop app rebuilt + relaunched (currently running). `flutter analyze lib` clean on
  both projects.
- Earlier (this + last sessions): two-DB/wrong-password fix (stable `%LOCALAPPDATA%`
  DB + legacy inheritance + `_ensureStandardAccounts`); cashier & admin dashboards
  redesigned; customer display open/close toggle; LAN V1 multi-PC sync built/verified.

---

## 7. Roadmap / next steps

1. **Go live with Supabase** — create the project at supabase.com, paste
   `docs/supabase_schema.sql`, then enter URL + anon key in desktop
   **Settings → Cloud** and in the phone app's **Setup** screen. This is the only step
   left that needs the user's project keys.
2. **GitHub scheduled backup + restore UI**
   - `lib/data/services/backup_service.dart` still has a Google Drive stub. Replace with
     GitHub: create a private repo, push an encrypted DB dump on a schedule, add a Settings
     restore action. Verify `git` is installed on this machine first.
3. **LAN V2** — full two-way CRUD parity (products/GRN/PO created on client merge back),
   catalog change timestamps, service restart survival of the beacon.
4. **Client install** — copy the Release folder to both PCs; run from the fixed folder;
   configure server mode on admin laptop + client mode on the cashier POS; verify discovery
   on the real LAN.
5. **Phone app extras (later)** — FCM "low stock" / daily sales push notifications, stock
   level editing from the phone, offline cache badge.

---

## 8. Android companion app + Supabase cloud (DONE)

**Goal achieved:** phone app where the owner can watch live sales, inventory, and key
reports from home. Architecture = **Windows POS pushes to Supabase → Android app reads
from Supabase**. Free tier (500 MB DB, 1 GB storage, 2 GB transfer/month) is plenty for
one shop.

**The phone app has NO login.** It reads with a Supabase **anon key**; Supabase RLS is
set to allow anon access (fine for a single-owner project whose keys are kept private).

### 8.1 Code layout
- `randil_mobile\` — separate Flutter project (`flutter create --org com.randil
  --project-name randil_mobile --platforms android`).
- Dependencies (resolved): `supabase_flutter ^2.17.2`, `fl_chart ^0.70.2`, `intl ^0.20.3`,
  `shared_preferences ^2.5.5`, `provider ^6.1.5+1`, `uuid ^4.6.0`.
- App entry `randil_mobile\lib\main.dart`:
  - `RandilGroceryApp` → `AppShell` (bottom `NavigationBar` with 5 tabs:
    Home / Sales / Stock / Reports / Settings, `IndexedStack`).
  - If Supabase is not configured yet → **SetupScreen** (asks for Supabase **URL**,
    **anon key**, shop name; saved in SharedPreferences `sb_url`, `sb_anon`, `shop_name`).
- `randil_mobile\lib\services\supabase_service.dart` — singleton `ChangeNotifier`,
  lazy `Supabase.initialize(url:…, publishableKey:…)`, fetches all 6 tables in
  parallel on `refresh()`, holds them in memory (`DashboardData`). Reconfiguring to a
  different URL after init throws a StateError telling the user to restart the app.
- `randil_mobile\lib\core\theme.dart` — `ThemeController` (Light/Dark/Auto + 5 accent
  presets, persisted via SharedPreferences `theme_mode` / `accent_index`).
- `randil_mobile\lib\core\aggregations.dart` — `todayStats`, `rangeRevenue`,
  `lastNDays` (7-day line), `todayByHour` (hourly bar), `byPayment` (pie),
  `byCategory`, `topProducts`, `lowStockCount`, `outOfStockCount`.
- `randil_mobile\lib\widgets\widgets.dart` — `StatCard`, `ChartCard`, `SectionHeader`,
  `EmptyState`, `Pill`, `LoadingOverlay`; `fmt`/`fmt0` (currency `Rs `).
- Screens: `home_screen.dart` (hero, KPI cards, charts, top products, recent sales),
  `sales_screen.dart` (search/filter, expandable sale tiles), `stock_screen.dart`
  (low-stock highlighting, category chips), `reports_screen.dart` (4 tabs: Refunds /
  GRN / Expenses / Customers + charts), `settings_screen.dart` (theme + accent +
  connection status / refresh / change project).
- Money formatting uses `intl` with `en_US` locale and `Rs ` symbol.
- Build/test: `flutter build apk --release` ✓ (52 MB),
  `flutter analyze` ✓ (no issues), `flutter test` ✓ (pure `fmt` test). **Always set
  `kotlin.incremental=false`** in `randil_mobile\android\gradle.properties` (see §6).

### 8.2 Supabase schema (one-time setup)
Paste `docs/supabase_schema.sql` into the Supabase **SQL Editor** (Project → SQL
Editor → New query → Run). It creates the 6 tables below with RLS anon-access policies,
grants and indexes. Tables are shared, so **desktop upserts** into the same tables the
phone reads.

| Table | Purpose |
| ----- | ------- |
| `sales_sync` | live sales (bill_number, amount, discount, tax, payment_method, items_count, cashier, items_json, timestamp) |
| `products_snapshot` | inventory snapshot (name, barcode, category, qty/selling/buying price, reorder_level, id + updated_at) |
| `customers_sync` | customer list |
| `supplier_grns_sync` | goods-received notes |
| `expenses_sync` | expense records |
| `refunds_sync` | refund/return records |

### 8.3 Desktop POS publisher
- `lib/data/services/supabase_sync_service.dart`:
  - Config in SharedPreferences (`supabase_url`, `supabase_anon`, `supabase_enabled`);
    no database change.
  - Dio PostgREST calls with header `Prefer: resolution=merge-duplicates` (idempotent
    upserts).
  - `onSaleCompleted(Sale)` enqueues the sale immediately (from `processSale`);
    `syncAll()` pushes products → customers → refunds → GRNs → expenses → sales on app
    start, then every 15 min (`Timer.periodic`), and via **Save & Sync Now**.
  - Exposes `lastSync`, `lastError`, `isSending`.
- Settings → **Cloud** tab: enable switch, URL + anon key fields, Save & Sync Now,
  status + last-sync time, and a hint pointing at `docs/supabase_schema.sql`.

### 8.4 Field-name contract (keep in sync!)
- `items_json` entries use keys `name`, `qty`, `price`, `line_total` (desktop
  `_saleRow`/batch serialization). Mobile parser accepts `qty` else `quantity`, and
  `line_total` else `total`/`subtotal` — survive both.
- Dates are ISO-8601 UTC (`toIso8601String()`); the phone converts to local.
- Changing shape here means changing both `SupabaseSyncService` (desktop) and the model
  files in `randil_mobile\lib\models\models.dart`.

### 8.5 To rebrand
- Android label is set in `randil_mobile\android\app\src\main\AndroidManifest.xml`
  (`android:label`). App display name used by the UI comes from the registry `shop_name`
  / the Setup screen.
- Keystore signing is not set up yet (debug-signed). Add `signingConfig`s in
  `randil_mobile\android\app\build.gradle.kts` + a `key.properties` before Play Store
  release (not needed for sideloading the APK).

---

## 9. Team / support footer (for receipts & docs)
**Jerusha Tech Solutions — 070 3027 611 — jerushasharon1999@gmail.com**