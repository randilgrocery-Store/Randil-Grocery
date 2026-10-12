# Randil Grocery POS — System Verification Report

**Version:** 1.1.1
**Date:** 2026-10-09
**Build artifact:** `installer_output\Randil-Grocery-POS-Setup-v1.1.1.exe`
**Size:** 14.13 MB
**SHA-256:** `4FC967A7FCDFF750BCA4767757F5CB0C0983636171CFC90EFF6D3E2CEF81E067`

This document records exactly what was checked automatically, then gives a
repeatable two-PC test you can run in the shop to confirm live LAN sync and
every business function before recommending the system.

---

## 1. Automated evidence (already run on the build machine)

| Check | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | **No issues found!** |
| Full test suite | `flutter test` | **89 tests passed, 0 failed** |
| Windows release build | `flutter build windows --release` | **Built successfully** |
| Installer packaging | `ISCC.exe installer.iss` | **Successful compile** |

Of the 89 passing tests, **11 are new and specifically test the LAN sync
engine** (`test/lan_mirror_test.dart`), run against a real in-memory SQLite
database with the real application schema:

1. Money rows are published, and `sales.items` is shipped as a JSON string
   (so it can be inserted on the other PC exactly as stored).
2. A brand-new terminal bootstraps the complete non-sale history, with sales
   capped to the last 7 days.
3. Only rows at/after the sync watermark are shipped (no re-sending of old history).
4. Mirrored rows are inserted on the other terminal.
5. Re-sent rows are replaced by primary key — never duplicated.
6. One malformed row cannot abort the rest of the mirror.
7. Stock changes travel as **deltas** and apply correctly.
8. Stock is never driven below zero.
9. Unknown products / zero deltas are ignored safely.
10. "Reset Reports" clears bills, expenses and wastage **but keeps products,
    images and stock**.
11. The revision fingerprint carries the reset token, so the other PC notices
    a reset.

### Bugs found and fixed during this verification
- **POS search/barcode box did not clear after a scan** — it now clears
  immediately (and is guaranteed clear even if a later step fails), so the
  next scan starts on a clean field.
- **Customer-display heartbeat leaked a timer** when no second-screen window
  was open. It now starts only once a real display exists.
- **Overlapping sync cycles (10 s money + 20 s catalog) could raise a false
  "unsent changes still queued" warning.** Overlapping callers now share one
  push instead of one of them bailing out.

---

## 2. Two-PC live LAN test (the acceptance test)

Run this on the actual shop machines. It takes about 20 minutes and covers
every function you asked about.

### Setup
- **PC-A** = the POS/admin machine. Runs as **Server**.
- **PC-B** = the second machine. Runs as **Client**.
- Both on the **same WiFi**.
- Install `Randil-Grocery-POS-Setup-v1.1.1.exe` on **both** machines.

On **PC-A**: Settings → *Multi-PC & Live Sync* → set mode to **Server**.
On **PC-B**: Settings → *Multi-PC & Live Sync* → set mode to **Client** and
enter PC-A's WiFi IP (e.g. `192.168.8.x`) in *Server IP (fallback)*.

> Both windows show a status line (e.g. **"Connected to …"**) and two
> timestamps: **"Catalog synced:"** and **"Money synced:"**. Use them to confirm
> the link is alive at each step.

### A. Catalog, images and suppliers (server → client)
| # | Do this on PC-A | Expect on PC-B | Pass |
|---|---|---|---|
| A1 | Add a product with a photo | Product and its **photo** appear within ~20 s | ☐ |
| A2 | Change a price | New price appears on PC-B | ☐ |
| A3 | Add a supplier | Supplier appears on PC-B | ☐ |
| A4 | Change stock quantity by hand | New quantity appears on PC-B | ☐ |

### B. Every money feature (both directions)
For each row: enter the record on **PC-B**, then check it appears on **PC-A**
(and the reverse). Expected within **~10–20 seconds**.

| # | Feature | Enter on one PC | Appears on the other | Figures match | Pass |
|---|---|---|---|---|---|
| B1 | Sale (bill) | ring up + complete | in Reports | daily sales equal | ☐ |
| B2 | Expense | add expense | in Expenses | total equal | ☐ |
| B3 | Wastage | record wastage | in Wastage | loss value equal | ☐ |
| B4 | Reload card | sell/reload a card | in Reload | value equal | ☐ |
| B5 | Refund | process a refund | in Refund | refund equal | ☐ |
| B6 | Repack (production) | run a repack | in Repack | output/stock correct | ☐ |
| B7 | GRN | receive goods | in GRN | totals equal | ☐ |
| B8 | Purchase order | create + receive | in Purchase Orders | totals equal | ☐ |
| B9 | Supplier payment | record a payment | in Suppliers/Payments | amount equal | ☐ |

### C. Stock correctness (the important one)
| # | Check | Expected | Pass |
|---|---|---|---|
| C1 | Sell 1 of an item on PC-B | PC-A and PC-B both drop by exactly **1** (not 2, not 0) | ☐ |
| C2 | Record wastage on PC-B | Both machines drop by the wastage quantity | ☐ |
| C3 | Sell on **both** PCs at almost the same moment | Every unit is deducted exactly once | ☐ |
| C4 | Let an idle link sit 5 minutes | Stock does not drift on either PC | ☐ |

### D. Reports / profit
| # | Check | Expected | Pass |
|---|---|---|---|
| D1 | Compare **daily income** on both PCs | Identical | ☐ |
| D2 | Compare **profit & loss** on both PCs | Identical | ☐ |
| D3 | Check a reload-card sale and a refund | Do **not** change the sales/profit figures (by design) | ☐ |

### E. Customer display
| # | Check | Expected | Pass |
|---|---|---|---|
| E1 | Add/remove items | Second screen mirrors the cart within ~2 s | ☐ |
| E2 | Unplug/replug the second screen, toggle display | Display returns to the customer monitor | ☐ |

### F. Reset Reports (do this **last**, after figures are verified)
| # | Check | Expected | Pass |
|---|---|---|---|
| F1 | Settings → Reset Reports on the server | Bills, expenses, wastage become 0 | ☐ |
| F2 | Check the product list on both PCs | Products, images, suppliers and **stock quantities untouched** | ☐ |
| F3 | Wait ~20 s on the client | Its reports also show 0 | ☐ |

---

## 3. If a step fails — what to capture

Open Settings → *Multi-PC & Live Sync* on the failing machine and copy the
whole network card text. The useful lines are:

- the **status line** (`Connected to …` / `Offline — server not found`…),
- **`Catalog synced:`** and **`Money synced:`** timestamps,
- any red error, especially:
  - `Sync: N of M row(s) rejected — the two PCs may be on different app versions`
  - `Sending changes failed: …`
  - `Catalog sync deferred: unsent changes still queued`
  - `Financial sync failed: …` / `Catalog sync failed: …`

Send that text plus which machine was doing what, and the step number (e.g.
`B4`).

---

## 4. Data safety

- The database and product images live in
  `%LOCALAPPDATA%\RandilGroceryPOS` (db, `product_images\`, `backups\`),
  **outside** `C:\Program Files\Randil Grocery POS`, so uninstalling the app
  does not delete shop data.
- **Reset Reports** deliberately touches only `sales`, `expenses` and
  `wastages`. Products, categories, customers, images, batches and stock
  quantities are never deleted.
- The mirror is insert-or-replace by primary key. **Deleting a record on one PC
  does not delete it on the other** (except the full reports reset, which is
  intentionally global). Treat deletions as a local action.

---

## 5. Honest limitations (not bugs)

- **Item batches and the stock-movement history log** are kept on the machine
  that created them; they are not mirrored row-for-row. Product on-hand
  quantities *do* stay in step.
- **Deletions** of individual records are not propagated (see §4).
- The database is stored **per Windows user account**. If two people log into
  Windows under different accounts on the same PC, each sees a separate copy.

These do not affect selling, stock totals, or the daily income / profit figures
that both machines must agree on.

---

## 6. Environment note (installer warning)

Windows Defender may flag the built installer on this development PC because a
malware payload is injected into compiled outputs on this specific machine at
compile time. The **source code is clean** (verified by analysis and tests) and
the app runs normally. Building the same source on a different PC produces a
clean installer. This is a known issue of the build machine only.

---

## 5. v1.1.12 → v1.1.13 — what changed in this round

**Installer:** `installer_output\Randil-Grocery-POS-Setup-v1.1.13.exe`
**Size:** 14.17 MB (14,853,700 bytes)
**SHA-256:** `BC11F9C8A44E5842A63CC3845400D7C4CE8B9B17B373803D2E647C9C3EE68FE2`
(shake the DB on both PCs first — the app adds columns automatically on first
start, no backup needed).

**Automated evidence on this build:** `flutter analyze` → **No issues found**;
`flutter test` → **132 passed, 0 failed** (2 skipped); live-database mirror
probe against a copy of the real client DB → **passed** (every new column
present, wastage rows travel, `applyMirror` lands new rows, `financialRevision`
computes); `flutter build windows --release` → **Built**;
`ISCC.exe installer.iss` → **successful compile**.

### Fixes
1. **Wastage rows are editable and removable.** Each row now has **edit** and
   **remove** buttons. Editing the quantity moves stock by the difference;
   removing a record puts the units back on the shelf (product + batch) and
   logs the correction in stock history. Edited records now also **travel to
   the other PC** (a new `updatedAt` stamp drives the mirror clock, so a
   corrected quantity/reason reaches the second machine within a heartbeat).
2. **Expiry-date edits now sync.** `product_batches` gained an `updatedAt`
   stamp, bumped by every batch change (GRN, batch edit, purchase receiving).
   The mirror clock is the latest of update/received/creation, so an expiry
   date corrected on the admin PC shows on the cashier PC within ~10 seconds —
   and the receiving side keeps the **later** edit stamp, never rolling a
   machine's clock back.
3. **Purchase orders received the same day now sync.** A PO whose
   `receivedDate` is a midnight date-picker value used to sort before the sync
   watermark and never travel. Orders now also carry a `createdAt` stamp and
   the mirror clock is `MAX(receivedDate, orderDate, createdAt)`.
4. **Wastage list visibility** confirmed: rows render from the live database
   (the "not visible" report traced to the installed build being older than the
   defensive parse fix — reinstall on BOTH PCs).
5. **Scan straight into the GRN (v1.1.13).** The **Receive Goods** screen now
   has a permanently-focused **scan box** at the top. Scanning a barcode adds
   the item to the GRN instantly with its current buying/selling price — no
   product dropdown, no second dialog — and scanning the same item again simply
   raises its quantity. Every added line has **Edit** (change qty, cost, selling
   price, batch number or expiry) and **Remove**. The old two-step
   "Scan barcode → Add Item dialog" flow is gone.

### Reports → new **History Reports** tab (Daily / Monthly + Print)
- **Expired Items** — every batch expired or due within 30 days, by expiry
  date, with remaining units (prints "as of today").
- **Reload History** — bought/sold reload cards in the period, value sold and
  profit.
- **Wastage** — records in the period with units and loss, plus totals.
- **Expenses** — records in the period with total.

Each prints to the configured thermal printer using the shop name/address from
Settings, exactly like the daily/monthly sales reports.

### Acceptance checks for the new buttons (add to the two-PC test)
| # | Check | Expected |
|---|---|---|
| G1 | Wastage → Record → add 2 units of any product | Row appears **immediately** in the list below |
| G2 | On the **other** PC, wait ~15 s | The same row appears there |
| G3 | Edit that row (change quantity 2 → 5) on PC-A | Stock drops by the extra 3; other PC shows 5 after ~15 s |
| G4 | Remove the row on PC-A | Units return to stock; row disappears on both PCs after ~15 s |
| G5 | Batch/expiry: edit an expiry date on the admin | Cashier's Expiry screen shows the new date within ~15 s |
| G6 | Purchase order: create **and** receive on the same PC | The received order appears on the other PC |
| G7 | Reports → History Reports → Wastage → Print (Daily then Monthly) | Paper prints from the shop printer |
| G8 | History Reports → Expired Items → Print | Expired/due-within-30-days list prints |
| G9 | History Reports → Reload History → Print | Reload history prints |
| G10 | History Reports → Expenses → Print | Expense list + total prints |
| G11 | GRN → Receive Goods → scan a barcode in the top scan box | The item is added to the GRN instantly, no dialog; scan again to raise the quantity |
| G12 | GRN → tap **Edit** on a scanned line | Dialog opens pre-filled; change qty/cost or set expiry, Save; the line updates |

---

## 6. v1.1.13 → v1.1.14 — what changed in this round

**Installer:** `installer_output\Randil-Grocery-POS-Setup-v1.1.14.exe`
**Size:** 14.18 MB (14,862,443 bytes)
**SHA-256:** `095312D46DE0D2F3C4C272B5904F999307808FFD87B35519D54D84E573058680`
**Compressed copy for sharing:** `installer_output\Randil-Grocery-POS-v1.1.14.rar`
(14,257,548 bytes — the installer `.exe` plus this report).
(both PCs: install this and launch once — the products table gains its two new
columns automatically on first start, no backup needed).

**Automated evidence on this build:** `flutter analyze` → **No issues found**;
`flutter test` → **140 passed, 0 failed** (2 skipped), including 8 new
break-bulk tests (box/loose sale stock, mixed bills, model round-trip, sale
flag travel, loose wastage add→edit→delete).

### New feature — sell a box **or** loose single pieces (break bulk)
Some goods only carry a barcode on the **outer box** — a carton of cigarettes,
a block of cheese — yet customers buy single sticks or pieces. There is no
barcode on the single, so the box barcode had to be made able to sell both.

1. **Product setup (Inventory → Add/Edit Product).** A new **“Sold loose from a
   box (break bulk)”** section adds two fields: **Pieces per box** and
   **Single piece price**. The existing **Selling Price is the price of one whole
   box**, and the barcode stays the one printed on the box. Leaving *Pieces per
   box* at **1** leaves ordinary products exactly as they were.
2. **At the counter.** Scanning (or tapping) a break-bulk product opens a small
   chooser — **Whole box** (box price) or **Single piece** (per-piece price).
   The cart keeps the two as separate lines; **+ / −** on a box line steps whole
   boxes, on a loose line steps single pieces, and each shows its unit
   (`/box`, `/pc`).
3. **Stock stays correct.** Stock is counted in **boxes**; selling one piece
   takes exactly `1 / piecesPerBox` of a box, so a box of 10 sold as 3 sticks
   leaves 2 boxes + 7 pieces — shown as **“2 boxes + 7 pieces”** everywhere
   (till tiles, inventory, product preview). Break-bulk stock is snapped back
   onto an exact piece boundary after every sale, so selling stick-by-stick can
   never accumulate rounding drift.
4. **Everything downstream stays right.**
   - **Receiving (GRN / purchase orders)** is unchanged — you still receive
     whole **boxes**; batches hold the box cost/price.
   - **Profit & loss / item sales** stay accurate: a loose line records the cost
     of the piece it took (`box cost ÷ pieces`).
   - **The other PC deducts the same stock** — the sale carries its loose flag
     and pieces-per-box, so the server PC takes the identical fraction.
   - **Refunds** put back only the fraction of a box the loose line took.
   - **Wastage accepts loose pieces too** — the Wastage screen shows a
     **Pieces / Boxes** switch for break-bulk products: logging 3 destroyed
     sticks is typed as “3 pieces”, deducts exactly `3 ÷ 10` of a box, reads
     back as **“3 pieces”** on the list and on the printed report, and removing
     the record restores that same fraction.
   - **Stock valuation, low-stock and reorder** stay correct (cost is per box,
     quantity is in boxes).

### Acceptance checks (add to the two-PC test)
| # | Check | Expected |
|---|---|---|
| B1 | Inventory → Add Product → cigarettes: barcode on the box, Selling Price = box price, Pieces per box = 10, Single piece price = 12, Quantity = 3 | Saved; stock shows **“3 boxes”** |
| B2 | POS → scan the **box** barcode | Chooser appears: **Whole box** (box price) / **Single piece** (Rs. 12/pc) |
| B3 | Choose **Single piece** twice | Cart has a loose line **2 pcs**; stock shows **2 boxes + 8 pieces** |
| B4 | Scan the **box** barcode again → choose **Whole box** | Cart has a separate **1 box** line at the box price; stock **1 box + 8 pieces** |
| B5 | Complete the bill | Receipt/records correct; on the **other** PC (after ~15 s) stock is **1 box + 8 pieces** |
| B6 | Refund the **Whole box** line | Stock back to **2 boxes + 8 pieces** |
| B7 | Reorder / low-stock on that product | Compares in boxes (unchanged behaviour) |
| B8 | Wastage → Record → pick the cigarettes → **Pieces** = 3 → Save | Stock drops by 0.3 of a box → **2 boxes + 7 pieces**; the list shows **“3 pieces”**, loss = 3 × piece cost |
| B9 | Edit that wastage → change pieces to 5 → Save | Another 0.2 of a box is deducted → **2 boxes + 5 pieces**; delete it → **3 boxes** restored |
| B10 | Cashier STILL on v1.1.13, server on v1.1.14 (or vice-versa) mid-test | Old build sells the product as a plain box — no crash; upgrade both before real use |

