# Randil Grocery POS - Client PC Setup & Requirements

Everything needed to install the POS on the shop's computer and have
backups + realtime mobile sync working.

## What to copy to the client PC

| Item | Location (this machine) | What it is |
|---|---|---|
| POS Windows app | `build\windows\x64\runner\Release\` | `randil_grocery_pos.exe` + `data\` folder. Copy the whole `Release` folder |
| Phone app | `randil_mobile\build\app\outputs\flutter-apk\app-release.apk` | Install on the owner's Android phone |

## Machine requirements

- Windows 10/11 (64-bit).
- Internet connection (needed for Google Drive, GitHub, Supabase realtime).
- Optional but recommended: `git` installed so hourly GitHub pushes run
  through git. If git is NOT installed, the POS falls back to the GitHub
  REST API using a token set in Settings > Backup.
- Optional: Google Drive for Desktop - if installed the client can also just
  copy backups into a "My Drive" folder and they sync automatically.

## First run - check these in the POS (Settings)

1. **Found this deployment checklist copy is not needed - the app runs as-is.**
2. **Shop Settings tab**: name, address, phone, email, tax %.
3. **Cloud tab (phone app sync)**: keep "Cloud sync" ON. It is already ON by
   default with the shop project pre-filled (no typing).
   - Press **Save & Sync Now** once - this uploads all products, sales,
     customers, GRNs, expenses, refunds and today's routine to Supabase.
4. **Backup tab**:
   - Local backup folder: leave default or pick one.
   - Google Drive: tick "Enable Google Drive Backup".
     - Paste a **Google Drive access token** (from Google's OAuth Playground,
       scope `drive.file`) - your Google account must have access to the shop
       backup folder. Save.
   - GitHub Backup Folder: leave the auto-detect value OR enter the path of
     the local clone (e.g. `D:\Randil Grocery POS`).
   - GitHub Token: only needed if the PC has **no git** installed. Paste a
     GitHub Personal Access Token (repo scope) - saved encrypted.

## How the backup schedule works (built into the app)

- **Every change** (sale, GRN, expense, refund, wastage, product edit):
  instant `.db` snapshot saved locally.
- **Every 15 minutes**: extra local snapshot.
- **30 seconds after the app opens, then every 1 hour, together:**
  1. encrypted local backup
  2. uploaded to the shop's Google Drive folder
  3. plain `.db` pushed to the GitHub repo
     `randilgrocery-Store/Randil-Grocery` (`database-backups/`)

> Keep the POS open during shop hours so the hourly pushes run.

## What the phone app shows (realtime)

- Daily routine (sales, net, refunds, expenses, wastage, GRNs, top products).
- Updates every 2 minutes automatically while open (plus pull-to-refresh).
- Requires the desktop POS cloud sync to be ON.

## Restoring a backup (make the file "work in here")

In the app:
1. Open **Settings > Backup**.
2. Tap **"Restore from .db backup"**, pick the `.db` file.
3. Close and reopen the POS.

Manually:
1. Close the POS.
2. Replace the database:
   `Copy-Item "randil_grocery_pos_<date>.db" "$env:LOCALAPPDATA\RandilGroceryPOS\randil_grocery_pos.db" -Force`
3. Open the POS.

## Where the live database lives

`%LOCALAPPDATA%\RandilGroceryPOS\randil_grocery_pos.db`

Local snapshots: `%LOCALAPPDATA%\RandilGroceryPOS\backups\`

## Re-verify the client PC before shipping

Run this on the PC (it checks the live DB, a real GitHub push and a live
Supabase write/read):

    flutter test test/deploy_verify_test.dart

## Hosted services

- Supabase project (DB + REST) url/key are pre-filled in both apps
  (`lib/data/config/cloud_config.dart` and `randil_mobile/.../supabase_service.dart`).
- GitHub repo holds ONLY database backups (no code).
- Google Drive folder: id `1N0YvowmSVGnI-X6MWfQf3o6ux880JHom`.