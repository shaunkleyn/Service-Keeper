# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run on connected Android device (USB debugging required)
flutter run -d <device-id>

# List connected devices
flutter devices

# Install pre-built APK directly (faster when flutter run keeps dropping)
/Users/shaunkleyn/Library/Android/sdk/platform-tools/adb -s <device-id> uninstall com.shaunkleyn.service_keeper
/Users/shaunkleyn/Library/Android/sdk/platform-tools/adb -s <device-id> install -r build/app/outputs/flutter-apk/app-debug.apk
/Users/shaunkleyn/Library/Android/sdk/platform-tools/adb -s <device-id> shell am start -n com.shaunkleyn.service_keeper/.MainActivity

# Release build
flutter build apk --release

# Clean build artifacts
flutter clean && flutter pub get

# Check dumpsys output format on device (important when debugging service parsing)
/Users/shaunkleyn/Library/Android/sdk/platform-tools/adb -s <device-id> shell dumpsys activity services | head -80
```

There are no automated tests. `adb` is at `~/Library/Android/sdk/platform-tools/adb`.

## Architecture

### Flutter ↔ Kotlin bridge

All native communication goes through a single `MethodChannel`:

**Channel:** `com.shaunkleyn.service_keeper/shizuku` (defined in `MainActivity.kt` and referenced as `_channel` in both `ShizukuService` and `AppInfoService`)

| Method | Called from | Returns |
|---|---|---|
| `execCommand {command}` | `ShizukuService.exec()` | `String?` stdout |
| `getInstalledServices {includeSystem}` | `AppInfoService.getInstalledServices()` | `List<{p,c,n}>` — packageName, className, appName |
| `getAppIcon {packageName}` | `AppInfoService.getAppIcon()` | `Uint8List?` PNG bytes |
| `getAppName {packageName}` | `AppInfoService.getAppName()` | `String?` |

Kotlin spawns background threads for all I/O and marshals results back via `runOnUiThread {}`. Adding a new native method requires: a `when` branch in `MainActivity.kt` + a corresponding method in the relevant Dart service class.

### Privilege model (Shizuku)

The app requires Shizuku (an on-device privilege daemon) to execute shell commands. Without it, nothing works.

`ShizukuService` handles the lifecycle: `pingBinder()` → `checkPermission()` → `requestPermission()`. The `ShizukuStatus` enum drives the UI warning banner. Actual shell execution goes through `ShizukuExecutor.exec()` (Kotlin) which spawns a privileged process via `ShizukuHelper.newProcess()`.

Shell commands used:
- `dumpsys activity services [pkg]` — detect running services
- `am start-foreground-service -n pkg/.Class` — start service (falls back to `am startservice`)
- `am force-stop pkg` — hard reset before restart

### Background scheduling

WorkManager has a 15-minute minimum for periodic tasks. The app works around this:

- **`intervalMinutes >= 15`** → `registerPeriodicTask` (standard WorkManager)
- **`intervalMinutes < 15`** → `registerOneOffTask` with `selfChain: true` input — `MonitorWorker` re-schedules itself after each run

`BootReceiver` fires on `BOOT_COMPLETED` and calls `MonitorWorker.scheduleAllFromPrefs()` to restore all schedules from SharedPreferences.

Work task tag format: `{packageName}_{serviceClass_with_dots_as_underscores}`

### Data flow

```
StorageService (Dart)
  └─ SharedPreferences key: flutter.monitored_services → JSON array of MonitoredService

MonitorWorker (Kotlin)
  └─ SharedPreferences key: flutter.monitored_services (same key, flutter. prefix is standard)
  └─ Reads on boot/work execution; writes nothing (Dart side owns writes)
```

`MonitoredService` model owns JSON serialization (`toJson`/`fromJson`). The `copyWith` pattern is used throughout for immutable updates.

### Icon/app name caching

`AppInfoService` fetches icons and names from native. The picker screen (`service_picker_screen.dart`) and home screen (`home_screen.dart`) both cache results in `SharedPreferences` as base64 PNG under key `app_icon_v1_{packageName}`. Cached icons are loaded first, then missing ones fetched — this is why icons appear instantly on second open.

### Service discovery parsing

`ServiceManager._parseDumpsys()` parses `dumpsys activity services` output with:

```dart
RegExp(r'ServiceRecord\{(?:0x)?[0-9a-f]+ +u\d+ +([^\s/}]+)/([^\s}]+)', caseSensitive: false)
```

**Important:** Android 16 appends ` c:<caller>` before the `}` — the regex intentionally does NOT anchor on `}` for this reason. Short-form class names (`.MyService`) are expanded by prepending the package name.

`isAppOwned` on `RunningService` identifies app-owned services (vs library services like `androidx.*`, `com.google.firebase.*`) by checking the first two package segments match and excluding known library prefixes.

## SDK targets

- `minSdk 26` (Android 8.0), `targetSdk 35`, `compileSdk 36`
- Device connected during this session: CPH2649, Android 16 (API 36), device ID `248a302`
