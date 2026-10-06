# Randil POS — Owner's Phone App (randil_mobile)

Android app for the shop owner (also builds for Windows for quick local demos).
Opens straight to a live dashboard (no login) showing the shop's **real** data
from Supabase:

- **Today's income** (net), sales count, gross, discount
- Payment split (Cash / Card / Mixed)
- Today's costs (Refunds / Expenses / Wastage)
- **Top 5 selling products**
- **Last 7 days income** bar chart
- Recent bills

Language toggle: **English ↔ සිංහල** (persisted on the phone). Pull down to
refresh; a refresh button is in the header.

## Data source

Reads the same Supabase project the desktop POS syncs to
(`lib/config/cloud_config.dart` — publishable anon key, read-only tables):

- `daily_routines` — per-day summary the POS pushes at every sync
  (net, gross, discount, cash/card/mixed split, refunds, expenses, wastage,
  top products). Newest 31 days.
- `sales_sync` — recent completed bills (latest 30).

Everything shown is computed from these rows. If the shop hasn't synced yet,
the app says "No data yet" and explains how to trigger a sync on the POS
(Settings → Cloud sync → Save & Sync Now).

## Build

```sh
cd randil_mobile
flutter pub get
flutter build apk --release   # output: build/app/outputs/flutter-apk/app-release.apk
```

Signed with the debug key (see the `release` signingConfig in
`android/app/build.gradle.kts`). For Play Store / distribution, add a real
signing config.

Quick local demo without Android (also on this laptop):

```sh
flutter build windows --release   # build\windows\x64\runner\Release\randil_mobile.exe
```

## Tests

```sh
cd randil_mobile
flutter test
```

Unit tests cover the bilingual labels and parsing of real
`daily_routines` / `sales_sync` rows.

## ⚠️ Machine note (this laptop)

**The APK is built by GitHub Actions (cloud)** — see `.github/workflows/build-apk.yml`.
Any push to `main` touching `randil_mobile/` (or a manual
`gh workflow run build-apk.yml`) builds `app-release.apk` on GitHub's Linux
runners and uploads it as the `randil-mobile-apk` artifact:
`gh run download <run> -n randil-mobile-apk`. A built copy is kept at
`dist/app-release.apk`.

Why cloud: every Google/LLVM-built native Android tool on this laptop
(`cmake`, `ninja`, NDK `clang`, `llvm-strip`, `aapt2`, …) crashes at launch
with a stack overflow (exit `0xC00000FD`) on this custom Windows build
(26200), so the Gradle build cannot complete here. Verified with minimal
repros (`ninja --version` alone crashes); all four installed NDKs crash.
The local workaround (in `android/app/build.gradle.kts`, gated by the
`randil.machineWorkaround` property set in `C:\Users\jerus\.gradle\gradle.properties`)
makes local configure survive by seeding CMake's compiler-probe results and
skipping the symbol-strip step. On healthy machines and CI the property is
unset, so the repo builds as a standard Flutter app.

The app itself also builds for Windows on this laptop for quick live demos
(`flutter build windows --release` → `build\windows\x64\runner\Release\randil_mobile.exe`).