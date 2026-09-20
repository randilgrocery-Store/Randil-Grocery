# Randil Grocery POS - Database Backups

This repository holds ONLY the shop's database backups (no app code).

## How backups work

- **Every change is saved locally.** Every time something happens in the POS
  (a sale, GRN, expense, refund, wastage, product/customer edit) the app
  immediately saves a plain `.db` snapshot on the shop machine, and it also
  keeps one every 15 minutes so nothing is ever lost.
- **Every hour the app pushes to the cloud, together:**
  1. GitHub here in `database-backups/`, and
  2. the shop's Google Drive folder.

## Where the live database lives (the POS machine)

    %LOCALAPPDATA%\RandilGroceryPOS\randil_grocery_pos.db

## Restoring a backup (make the file "work in here")

Simplest way, from inside the app:

1. Open Settings > Backup.
2. Tap `Restore from .db backup`, pick the `.db` file you downloaded,
   then close and reopen the POS.

Or manually:

1. Close the POS completely.
2. Replace the file in %LOCALAPPDATA%\RandilGroceryPOS\ with a backup:
     Copy-Item "randil_grocery_pos_*.db" "$env:LOCALAPPDATA\RandilGroceryPOS\randil_grocery_pos.db" -Force
3. Open the POS - all products, sales, customers, batches and settings return.

## File naming

Each backup is named randil_grocery_pos_<date>.db. The newest one is always the
safest to restore.