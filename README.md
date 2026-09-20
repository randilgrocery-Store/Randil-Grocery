# Randil Grocery POS - Database Backups

This repository holds ONLY the shop's database backups (no app code).

Every time something changes in the POS (a sale, GRN, expense, refund,
wastage, product or customer edit) the app saves an automatic snapshot, and a
scheduled task pushes the latest snapshot here.

## Where the live database lives (the POS machine)

    %LOCALAPPDATA%\RandilGroceryPOS\randil_grocery_pos.db

## Restoring a backup (make the file "work in here")

1. Close the POS completely.
2. Replace the file in %LOCALAPPDATA%\RandilGroceryPOS\ with a backup:
     Copy-Item "randil_grocery_pos_YYYY-MM-DD.db" "$env:LOCALAPPDATA\RandilGroceryPOS\randil_grocery_pos.db" -Force
3. Open the POS - all products, sales, customers, batches and settings return.

## File naming

Each backup is named randil_grocery_pos_<date>.db. The newest one is always the
safest to restore.