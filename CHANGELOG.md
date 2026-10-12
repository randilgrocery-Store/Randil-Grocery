# Changelog

All notable changes to Randil Grocery POS will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.17] - 2026-10-12

### Changed
- **Shopping Bags is now a bulk-bundle section, fully separate from grocery
  stock.** The owner adds each bulk bag he buys (name + buying price per bundle
  + selling price per bundle), restocks whole bundles, and then records from the
  section either **bundles used in the shop** or **bundles sold to a customer**.
  Stock is counted in whole bundles only (one bundle taken = one bundle off the
  bought stock) — no counting little bags one by one.
- The section shows today's totals: bundles in stock and stock value at cost,
  bundles sold (with profit), and bundles used in the shop (with cost), plus a
  **Recent activity** history.
- The dashboard Profit & Loss panel now reports **Bundles sold** and **Bundles
  used in the shop**, and the year/period net profit counts bulk-bag sales
  revenue and cost correctly.

### Fixed
- **The POS Rs 3 / 5 / 10 / 20 bag charge is no longer mixed into the bulk
  Shopping Bags section.** It is once again a plain bill charge for the little
  bags a customer buys (optionally, with a quantity/bundle), and it never moves
  the bulk bundle stock or the shop-use ledger.
- Removed the auto-created "Rs 3/5/10/20 bag" rows from earlier builds; the
  section now starts empty so the owner adds his own bulk bags.

## [1.1.11] - 2026-10-10

### Fixed
- **Cash drawer opened twice on every printed bill.** The receipt itself
  carried a hard-coded drawer pulse AND the POS sent a second, properly-gated
  pulse after printing — two separate spooler jobs, so the till popped twice.
  The embedded pulse is removed; the drawer now opens exactly once per sale,
  and the Settings rules (off for card-only when chosen, no re-pop on reprint)
  now actually apply.
- **GRN barcode scan (admin AND cashier).** "Scan barcode" in GRN now finds the
  item the same way the POS does — exact barcode, then product name, then a
  leading-zero-tolerant match, with a database fallback — and it is no longer
  greyed out on an empty GRN, so the first item can be scanned too.
- **Wastage barcode scan.** "Record Wastage" now has a scan field: scan the
  product barcode and it selects the product for you. The scanned selection
  also appears on the product dropdown and loads its batches.

### Changed
- **Cash drawer setting wording** clarified: "Open drawer for card-only bills"
  (ON = card-only also pops the till; OFF = keeps the till shut on card-only
  sales; cash and split always open it).
- Wastage list stays visible if a synced row contains a missing date/number
  (defensive parsing, from the previous change set).

## [1.1.10] - 2026-10-10

### Fixed
- **Scale label found the wrong item (or nothing) when the product barcode and
  the label's item/PLU code differ only in leading zeros.** The shop's real
  label `0000010002100` decodes to item `00010`, but the Banana product was
  saved with barcode `0000010`; the exact lookup failed and the sale was not
  added. Scale scans now match on the barcode with leading zeros stripped on
  both sides (`00010`, `0000010` and `10` all resolve to the same product).
  Exact matching is still tried first, so ordinary EAN-13 barcodes — including
  ones that legitimately start with `0` — are unaffected.

## [1.1.9] - 2026-10-10

### Fixed
- **Label-scale barcodes rejected on the cashier PC until the app was
  restarted.** The cashier decodes scale labels using the layout copied from
  the admin PC by the catalog sync. That layout was only applied to the
  in-memory settings while the app was running, so a layout synced after
  startup could be ignored and the scale barcode read as "not found". The POS
  scan path and the Settings → Label scale "Test a label" box now read the
  layout fresh from the database on every scan, so a synced layout is honoured
  immediately with no restart.
- **Clearer scale test feedback.** The test box now reports exactly what is
  wrong — prefix mismatch, digit-count mismatch, or a decoded item/weight with
  no matching product — instead of one generic message.

### Changed
- Wastage rows synced from another machine can no longer blank the wastage
  screen when a date or number field is missing (`Wastage.fromMap` now parses
  defensively).

## [1.1.8] - 2026-10-10

### Fixed
- **Settings (and other menu screens) missing from the sidebar.** The sidebar
  addressed each screen by a hardcoded index, and inserting **Expiry** and
  **Expenses** mid-list shifted the indices without updating the groups — so
  **Settings** (and, on the cashier menu, **Reload** and **Profile**) were no
  longer listed in any sidebar group and simply didn't appear. All screens are
  now listed in a single source of truth (`AppSidebar`), each index appears
  exactly once, and a new `navigation_sections_test` fails the build if a
  screen is ever dropped or duplicated again.

## [1.1.7] - 2026-10-10

### Added
- **Expiry now syncs between the two PCs.** Batch lots (with their expiry
  dates) travel over the LAN mirror in both directions, so an expiry date typed
  on the office PC reaches the counter PC and vice-versa. When a lot already
  exists on the other machine its own remaining quantity is kept — only the
  expiry date, batch number, prices, supplier and notes are refreshed, so the
  two tills never fight over stock counts.
- **Expiry screen on the cashier login.** The cashier can now open **Expiry**
  from their own menu and see exactly what is about to go out of date before
  selling it.
- **Detailed expenses for cash-drawer reconciliation.** Every expense now
  records **who was paid** (`Paid to`), **what for**, **how much**, the date and
  the exact time, and **which logged-in user** entered it. The Expenses screen
  shows a "Cash paid out today" total and lists each payment with its
  paid-to, reason, time and recorder.
- **Expenses on the cashier login.** Cashiers can record an expense (supplier
  collecting from the drawer, a worker, fuel, etc.) and it appears on the
  admin PC within seconds, and vice-versa.

### Changed
- **Expired stock can no longer be sold.** The FIFO picker skips any batch
  whose expiry date has passed, and tapping a product whose **newest** lot has
  already expired is blocked with a hint to record it in Wastage first. A
  product with mixed lots (one expired, one fresh) stays sellable — the fresh
  lot is sold.
- POS tiles turn red only when **every** remaining lot of a product is expired;
  otherwise the tile shows the closest *future* expiry.
- The Expiry screen refreshes every 15 seconds while open so a sync from the
  other PC shows up almost immediately.

## [1.1.6] - 2026-10-10

### Added
- **Expiry screen** (menu → Expiry). One place that shows the whole shop's
  expiry picture: every batch that carries an expiry date, sorted soonest
  first and grouped into **Expired / within 7 days / within 30 days / later**.
  The same product received on different dates appears once per batch with its
  own expiry date and remaining quantity — exactly how mixed lots should be
  read. Summary tiles show the counts, a refresh button and an automatic
  minute-by-minute refresh keep it current.
- **Live alerts bell.** The bell in the top bar now refreshes itself every
  30 seconds, so batches added in GRN (or received via LAN sync) appear
  without restarting the app.

### Changed
- **POS tiles now warn from the real batch expiry.** A product's "Exp: X days"
  badge (and the red expired card) previously used a product-level expiry date
  that the Inventory form never sets. It now reads the item's closest stocked
  batch, so a banana lot expiring in 3 days turns the tile orange exactly when
  it matters.
- **Profit & Loss provider no longer crashes if a refresh lands after the
  dashboard was closed** (async notify guard).

## [1.1.5] - 2026-10-09

### Added
- **Label-printing scale barcodes (embedded weight).** The POS can now read the
  barcode a label scale such as the Budry Electronics ABD-90 prints, which
  carries the item/PLU code **and** the weight in one barcode. Scanning the
  label drops the item into the bill at the exact printed weight — no manual
  weighing at the counter.
- **Settings → Label scale** pane: enable decoding, set the prefix digit(s),
  total digits, item/PLU digit count, whether the last digit is a check digit,
  and whether the barcode carries weight (kg) or price (Rs.). Includes a
  **Test a label** box that decodes a scan exactly the way the POS does, so the
  layout can be verified against one real label before the counter uses it.
- A short, from-scratch scale normally prints the 12-digit layout
  `2 + 5 item + 5 grams + 1 check digit`. If the item/PLU split is set
  slightly wrong, the POS automatically tries neighbouring split points and
  uses whichever one matches a real product, so a sale is never blocked.

## [1.1.4] - 2026-10-09

### Fixed
- **Customers and suppliers now sync live in both directions.** They were only
  ever pushed *server → cashier* through the catalog; a contact added on the
  cashier PC never reached the admin PC. They now ride the same 10-second money
  mirror as bills/expenses, so a new (or edited) customer or supplier appears on
  the other machine within a few seconds.
- **Wastage (and other ledger) rows no longer go missing in sync.** A row dated
  with the date picker (which returns *midnight* for "today") sorted before the
  sync watermark and was silently never sent, so the Wastage screen on the other
  PC stayed empty. Each ledger row now travels on the later of its business date
  and the moment it was entered, so a back-dated or midnight-dated row always
  reaches the other PC. Applied to wastage, expenses, goods received, supplier
  payments and refunds.
- The outbound sync watermark now follows this PC's own clock rather than the
  server's. A terminal whose clock ran a little behind the server could skip its
  own freshly entered rows; the two are now measured on the same clock.
- Expenses gain a record timestamp (`createdAt`) so a back-dated expense still
  syncs; customers gain `updatedAt` so edits sync too. Existing databases are
  migrated automatically and the columns are back-filled (no data is cleared).

## [1.1.3] - 2026-10-09

### Fixed
- **Net Profit now includes everything.** Both the Profit & Expenses report and
  the admin dashboard's Profit & Loss panel now fold in **refunds paid out** and
  the **reload (top-up) margin** earned, on top of bills, cost of goods,
  expenses and wastage. Previously the report ignored refunds and reload, and
  the dashboard ignored reload, so the bottom line was overstated.
  - Reload counts as **margin only** (value sold minus the cost paid to the
    ISP), so the wholesale cost is never also counted as an expense.
  - A processed refund is counted on the day the money actually left
    (`processedDate`), not the day the request was raised.
- Removed the misleading double-discount line on the dashboard P&L (discounts
  are already netted into sales revenue) so the breakdown reconciles with the
  net figure.

## [1.1.2] - 2026-10-09

### Fixed
- **Reset Reports now also clears Wastage Tracking and the Reload value
  ledger.** Previously it cleared only bills, expenses and wastage, so the
  Wastage screen and the Reload screen kept their old rows. It now clears
  `sales`, `expenses`, `wastages` and `reload_cards` — and still leaves every
  **product, image, customer, batch and current stock quantity untouched**.
- A terminal that has not yet caught up with a reset can no longer re-send the
  old bills/expenses/wastage/reload rows and undo the reset. The push now
  carries the reset stamp it last saw; a stale push is refused and the terminal
  pulls the reset before re-sending.
- The reset confirmation and the result message now say that reload cards are
  cleared too.

## [1.1.1] - 2026-10-09

### Changed
- The LAN mirror is now a single, general engine. Sales, expenses, wastage,
  reload cards, refunds, repack runs (productions + components), recipes,
  goods received notes, purchase orders and supplier payments all travel
  between the admin PC and every terminal through one revision-gated channel,
  in both directions. A new terminal bootstraps the complete history on its
  first sync.
- Stock stays owned by the admin PC. A terminal now sends *deltas* (product has
  moved by -2) instead of absolute quantities, so a bill the server rang up at
  the same moment is never overwritten by a stale figure from the other PC.
- Suppliers now travel with the catalog, so they appear on every machine.
- Every mirrored screen (Wastage, Reload Card, Repack, Refund, Expenses, GRN,
  Purchase Orders, Suppliers) refreshes itself as soon as new money rows arrive.

### Fixed
- POS: after a barcode scan or tapping a searched product, the search/barcode
  box now clears itself immediately instead of holding the last scan until it
  was cleared by hand.
- Customer display: the 2-second cart heartbeat no longer keeps a timer running
  when no display window is open (fixes a leaked timer and a false "working"
  state seen in tests).

## [1.1.0] - 2026-10-08

### Added
- Reload screen for cashier accounts (same as admin).
- Pull-to-refresh on the cashier dashboard re-syncs the customer display.
- Sales, expenses and wastage now mirror from the admin PC to cashier
  terminals, so every machine reports the same daily sales and profit instead
  of a terminal only counting the bills it rang up itself. The mirror is
  revision-gated and only re-reads rows written since the last check, so an
  idle link costs one tiny request every refresh and history is fetched once.
- Expenses and wastage recorded on a cashier terminal are now pushed up to the
  admin PC as well, so the profit/loss figures are identical in both
  directions. Money sync runs on a 10-second heartbeat, gated by a cheap
  revision check.
- "Reset Reports" button in Settings → Multi-PC & Live Sync. It clears bills,
  expenses and wastage on every PC — for starting real trading figures from
  zero — while keeping all products, images, customers and current stock
  quantities. The reset is stamped and propagates to the other machine
  automatically on its next sync.
- Settings now shows a "Money synced" timestamp next to "Catalog synced", and
  reports if any money row was rejected (a sign the two PCs run different
  app versions).

### Changed
- Cashier dashboard simplified to greeting + action buttons (business
  analytics / daily sales remain admin-only).
- Buttons sized for single-touch POS screens.
- Customer display now retries placement, verifies it landed on the second
  screen and re-asserts every few seconds so it always stays on the
  customer-facing monitor.
- Cart updates are re-pushed every 2 seconds so both screens stay in sync.

### Fixed
- Customer display window staying on / expanding onto the main display
  instead of the second screen.
- Installer now bundles the Microsoft C++ runtime (fixes
  "VCRUNTIME140_1.dll was not found" on fresh PCs).
- Sidebar expand/collapse button not working on screens narrower than
  1500px (manual toggle now always wins over auto-collapse).
- Settings, Reports (admin) and Profile (cashier) missing from the sidebar
  after Reload was added — all menu items are restored.
- Reload screen now hides cost/profit/buy/delete from cashiers; admin keeps
  the full profit & loss view.
- Product images now sync to cashier terminals over LAN (server serves them,
  client caches them locally) so pictures show on every machine.
- Product pictures are copied into the app's own folder when picked, so the
  saved path is portable and survives delivery to another PC (old absolute
  paths keep working and are migrated on the next save).
- All product image views (POS grid, POS preview, cart lines, inventory grid,
  add/edit form) now resolve stored paths correctly instead of assuming a
  raw file path, which is what left grey placeholders on the client machine.
- The server's image endpoint can now serve files referenced by older
  database rows (absolute paths) instead of returning 404.
- Catalog sync is now revision-cached: a terminal only re-downloads products,
  categories and customers when the admin PC actually changes them, cutting
  WiFi usage to near zero on an idle link. Images that failed to download are
  retried even when nothing changed.
- Connected terminals re-check the admin PC catalog every 20s and pick up
  stock/price/image changes automatically — no manual "Find Server".
- A sale made on a cashier terminal now refreshes the admin PC's stock and
  today's figures immediately (previously the server deducted stock in the
  database but its own screen did not update).
- Queued offline sales are pushed to the server before the catalog is pulled,
  so a terminal's own stock deduction is never overwritten by stale data.
- Terminals now reach the admin PC over **plain HTTP** as well as UDP
  discovery. Previously the fallback address was only ever probed with a UDP
  packet, so a firewall or router that dropped discovery traffic left the
  terminal permanently disconnected — which showed up as missing images *and*
  missing live figures, even though HTTP itself worked.
- A sale whose push failed is re-sent on every refresh instead of sitting in
  the queue forever (its revenue previously never reached the admin PC's
  profit report).
- The server no longer discards an incoming sale when it has no stock left for
  it. Dropping the sale deleted its revenue from the profit & loss report;
  stock is now simply clamped at zero.
- Reports / Profit & Expenses now reload by themselves when another terminal
  records a sale, instead of only when the screen is reopened.
- Product images whose filenames contain spaces or special characters are
  requested with proper URL encoding and decoded on the server (they used to
  404 into a permanent placeholder).
- Image healing no longer depends on a recorded image list, so upgrading from
  an earlier build actually fetches the pictures instead of skipping them.

## [1.0.0] - 2024-01-01

### Added
- **Core POS Features**
  - Fast billing interface with barcode scanning
  - Shopping cart management with quantity adjustments
  - Real-time inventory updates
  - Multiple payment method support (extensible)
  - Discount application at item and order level
  - Professional receipt generation and thermal printer support
  
- **Inventory Management**
  - Complete product CRUD operations
  - Product categorization
  - Stock level tracking
  - Low stock alerts
  - Stock history and audit log
  - Profit margin calculations
  
- **Authentication & User Management**
  - Secure login system
  - Role-based access control (Admin/Cashier)
  - User management interface
  - Session management
  
- **Reporting & Analytics**
  - Daily sales reports with transaction details
  - Monthly sales analytics and trends
  - Best-selling items analysis
  - Revenue tracking and visualization
  - Transaction history
  
- **Settings & Configuration**
  - Shop details management
  - Tax configuration
  - Currency settings
  - Printer setup and configuration
  - User management interface
  
- **User Interface**
  - Material Design 3 with custom grocery theme
  - Green and white color palette
  - Responsive desktop layout
  - Smooth animations and transitions
  - Clean navigation with bottom bar
  
- **Architecture & Code Quality**
  - Clean Architecture with MVVM pattern
  - Provider-based state management
  - SQLite local database
  - Comprehensive error handling
  - Offline-first design
  - Well-organized code structure

### Technical Details
- Built with Flutter 3.0+
- Dart 3.0+ programming language
- SQLite database
- Provider state management
- Windows Desktop support

### Known Limitations
- Single machine operation (no cloud sync)
- No multi-currency support yet
- Barcode generator not included
- No customer tracking
- Limited payment method options (cash only in MVP)

### Planned Features for v1.1
- [ ] Cloud sync and backup
- [ ] Advanced reporting with charts
- [ ] Barcode generator utility
- [ ] Customer tracking and loyalty program
- [ ] Multiple payment methods (card, UPI, etc.)
- [ ] Export reports (PDF, Excel, CSV)
- [ ] Multi-register support
- [ ] Stock auto-reorder alerts
- [ ] Detailed audit logging
- [ ] Email receipt sending

---

## Notes

### Installation
See [QUICKSTART.md](QUICKSTART.md) for setup instructions.

### Support
For bug reports and feature requests, please refer to the GitHub issues page.

### Documentation
- [README.md](README.md) - Complete documentation
- [QUICKSTART.md](QUICKSTART.md) - Quick start guide
- Code comments throughout the project

---

**Project Status**: ✅ MVP Complete - Ready for Production Use

Last Updated: January 1, 2024
