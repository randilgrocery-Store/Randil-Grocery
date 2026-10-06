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

**This laptop cannot produce an Android APK.** Every LLVM-built native tool in
the Android SDK/NDK — `cmake`, `ninja`, `clang`, `llvm-strip`, `llvm-readelf`,
etc. — crashes at startup with a stack overflow (exit `0xC00000FD`) on this
Windows build (26200). Verified with minimal repros (`ninja --version` alone
crashes; the official MSVC-built ninja/CMake work; all four installed NDKs'
clang crash). Android's Gradle build requires the NDK compiler check to pass,
so no configuration change can work around it on this machine.

- ✅ Everything that *doesn't* need the Android toolchain works here: the app
  code, `flutter analyze`, unit tests, and `flutter build windows` (demo
  build: `build\windows\x64\runner\Release\randil_mobile.exe`).
- ✅ To get the APK, run `flutter build apk --release` on any normal
  Windows 10/11, macOS or Linux machine with Flutter + Android SDK installed.
  No special setup is needed there — standard Flutter project.
- The MSVC-built CMake 3.30.5 + ninja 1.12.1 are still installed in the SDK's
  `cmake\3.22.1` / `cmake\4.1.2` / `cmake\3.30.5` folders (they report
  `cmake version 3.30.5`) in case you ever script around the NDK issue;
  they're harmless, but not required on a healthy machine.