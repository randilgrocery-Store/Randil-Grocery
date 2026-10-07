# Randil Grocery POS — Remaining Work

Status as of the last session. Read this before touching the codebase.

## Verified working (do not redo)

| Area | How it was verified |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | 84/84 passing |
| `flutter build windows --debug` | Builds successfully |
| Repack/Recipes module | Compiles + builds; **not** tested with real stock data |
| Cash drawer | 22 dedicated tests passing; user reports it works on the real machine |
| Scanner → cart fix | Compiles + builds; **needs physical scanner confirmation** |

---

## 1. CRITICAL — Held bills are lost on restart

**File:** `lib/presentation/providers/sales_provider.dart` (~line 224)

`heldBills` is a plain in-memory `List<HeldBill>` with **no limit and no persistence**.

- No cap — unlimited bills can be held
- **Not saved anywhere.** App close, crash, or restart silently loses every held bill
- For a live shop this is lost money

**To do:**
1. Persist held bills to a new `held_bills` table (items as JSON, same pattern as
   `sales.items` / `goods_received_notes.items`)
2. Load them back on app start in `SalesProvider`
3. Add a sane cap (e.g. 20) and show a clear message when reached
4. Delete a held bill's row on `removeHeldBill` and on `resumeBill`
5. Add tests: persist → reload → still there; cap enforced

---

## 2. `duplicateLastBill()` is a stub that silently no-ops

**File:** `lib/presentation/providers/sales_provider.dart` (~line 255)

```dart
void duplicateLastBill() {
  if (_lastSale == null || _lastSale!.items.isEmpty) {
    return;
  }
  notifyListeners();   // <-- does nothing useful
}
```

It checks `_lastSale`, then only calls `notifyListeners()`. No items are copied
into the cart, so pressing the button appears to do nothing.

**To do:** copy `_lastSale.items` into the cart, clear the discount/bag charge, notify.

---

## 3. Full automated P&L — the biggest missing feature

The dashboard's "Profit" is a **rough estimate**, not a real P&L. It currently does
`revenue − (product.buyingPrice × qty)`, which ignores everything below.

**Must be included:**
- Revenue (sales)
- COGS — use **FIFO batch cost**, not `product.buyingPrice`, otherwise profit is wrong
  when prices changed between deliveries
- Expenses (`expenses` table)
- Wastage (`wastages` table)
- Reload card cost vs. face value (`reload_cards`)
- Repack/production cost (`productions`, `production_components`)
- Refunds (`refund_returns`) as negative revenue
- **Net profit = Revenue − COGS − Expenses − Wastage − Reload card cost − Refunds**

**To do:**
1. Add a P&L query to `DatabaseService` (sales + expenses + wastage + reload + productions in one date range)
2. Wire it into `ReportsProvider`
3. Build a visual P&L screen: waterfall or breakdown chart, plus profit/loss trend
4. Surface it on the dashboard as a proper card, not just "Profit Est."

---

## 4. Repack module — needs real-data testing

Newly added and compiling, but **never run against actual stock.** Verify manually:

- [ ] Buy a bulk raw item via GRN (e.g. 25 kg mix)
- [ ] Create a recipe: components → yield quantity
- [ ] Run a production, confirm raw stock drops by the right amount
- [ ] Confirm finished-goods stock rises
- [ ] Confirm the finished product's cost = total component cost ÷ yield
- [ ] Sell the repacked item and confirm profit matches the computed unit cost
- [ ] Confirm cashier role is **blocked** from the Repack screen

**Files:** `lib/data/models/recipe.dart`, `production.dart`,
`lib/data/database/repack_crud.dart`, `repack_production.dart`,
`lib/presentation/screens/admin/repack_screen.dart`

**Known weakness:** component quantities are rounded with `.ceil()` because product
stock is integer-only. Repacking by grams/kg will drift. Consider a decimal
quantity column on `products` if the shop measures in weight.

---

## 5. Mobile app — source code is MISSING

**Folder:** `randil_mobile/`

Contains only `android/`, `build/`, `.dart_tool/`, `.idea/`. There is **no
`pubspec.yaml` and no `lib/`**. The `Randil-Grocery-Phone-App-debug.apk` in the repo
root is a dead artifact and cannot be rebuilt or maintained.

**Decision needed:** rebuild from scratch, or recover the original source.
Until then the mobile app requirement is **unmet**. If it tracks daily routines, it
will need an API — the POS already has `shelf` / `shelf_router` dependencies for a
LAN server, so the phone could read from the shop PC over Wi-Fi.

---

## 6. Deployment to the client PC — not verified

- **DB path (confirmed correct):** `%LOCALAPPDATA%\RandilGroceryPOS\randil_grocery_pos.db`
  Single source of truth — older locations are ignored on purpose. Good.
- **Images:** `ProductImageStore` stores a **bare filename** and resolves it at read
  time (9 passing tests cover this). Verified portable.
- **Still to confirm:**
  - [ ] Images ship with the installer and resolve on a fresh client machine
  - [ ] Backups actually write to `backups/` and reach GitHub + Google Drive
  - [ ] Restore-from-backup works on a clean machine
  - [ ] Installer produces a working desktop shortcut
- `Item Images/` and `assets/images/` — confirm which is the real source of truth
  before shipping

---

## 7. Hardware

- **Cash drawer** — user confirms working. Do not touch.
- **Scanner** — fixed (focus-independent capture). **Needs physical confirmation.**
- **TSYSO POS terminal** — not tested at all. Unknown what it is used for
  (payment terminal? display?). Clarify before assuming anything.

---

## Quick wins (small, safe)

1. Implement `duplicateLastBill` (item 2)
2. Add a cap + warning when held bills reach the limit (item 1, part 2)
3. Confirm scanner fix on real hardware (item 7)

## Order of work I'd suggest

1. Verify the scanner fix physically — everything else is blocked on trust
2. Held-bill persistence (real money, silent loss)
3. Full P&L + visual dashboard (your main ask)
4. Repack real-data testing
5. Mobile app decision
6. Deployment dry run on a clean machine