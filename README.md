# Service Keeper

An Android app that monitors and automatically restarts background services killed by the system. Built with Flutter and powered by [Shizuku](https://shizuku.rikka.app/) for privileged shell access.

> **Disclosure:** This project was built with significant AI assistance (Claude). All code has been reviewed and tested on a physical device (Android 16, API 36).

---

## What it does

- **Monitors background services** — detects when a selected service is killed and restarts it automatically
- **Monitors accessibility services** — re-enables them if Android revokes access in the background
- **Monitors notification listeners** — re-enables if disabled by the system
- **Scheduled checks** — configurable per-service interval (5 min to 4+ hours)
- **Audit log** — full timestamped history of every detected stop, restart attempt, and outcome
- **Boot persistence** — reschedules all monitors after device reboot
- **Per-app notifications** — toggle restart alerts per service

---

## Requirements

| Requirement | Details |
|---|---|
| Android | 8.0+ (API 26), tested on API 36 |
| [Shizuku](https://shizuku.rikka.app/) | Must be installed and running |
| ADB / Wireless Debugging | Required to start Shizuku |

Shizuku is a mandatory dependency. Without it, the app cannot execute privileged shell commands to restart services.

---

## Setup

### 1. Install Shizuku

1. Install [Shizuku](https://play.google.com/store/apps/details?id=moe.shizuku.privileged.api) from the Play Store
2. Enable **Developer Options** on your device
3. Enable **Wireless Debugging** under Developer Options
4. Open Shizuku → tap **Pair using Wireless Debugging** and follow the prompts
5. Shizuku should now show as **Running**

### 2. Install Service Keeper

Install from a release APK or build from source (see below). On first launch, grant Shizuku permission when prompted. The app displays a status banner at the top when Shizuku is inactive.

### 3. Add services to monitor

Tap **+** on the Services tab → browse running services by app → select what you want to keep alive.

---

## Building from source

```bash
# Prerequisites: Flutter 3.x, Android SDK (minSdk 26, targetSdk 35)

git clone https://github.com/shaunkleyn/service_keeper.git
cd service_keeper
flutter pub get
flutter run                          # debug on connected device
flutter build apk --release          # release APK
flutter build appbundle --release    # Play Store bundle
```

---

## Permissions

| Permission | Reason |
|---|---|
| `FOREGROUND_SERVICE` | Background monitoring service |
| `QUERY_ALL_PACKAGES` | Enumerate installed services for the picker |
| `POST_NOTIFICATIONS` | Restart event alerts |
| `RECEIVE_BOOT_COMPLETED` | Restore monitors after reboot |
| `WAKE_LOCK` + `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Prevent Doze from deferring checks |

---

## How it works

**Shizuku bridge**
All privileged operations go through a single `MethodChannel` (`com.shaunkleyn.service_keeper/shizuku`). Kotlin receives calls, spawns a Shizuku process, runs the shell command, and returns stdout to Dart.

Shell commands used:
- `dumpsys activity services [pkg]` — detect running services
- `am start-foreground-service -n pkg/.Class` — restart a service
- `am force-stop pkg` — hard stop before restart

**Scheduling**
- Interval ≥ 15 min → `WorkManager` periodic task (battery-efficient)
- Interval < 15 min → self-chaining one-off tasks (re-schedules itself after each run)
- `BootReceiver` restores all schedules from SharedPreferences on `BOOT_COMPLETED`

**Service detection**
Parses `dumpsys activity services` output with a regex that handles both standard and Android 16 output format (which appends ` c:<caller>` before `}`).

---

## Tech stack

- **Flutter** — UI and app logic
- **Kotlin** — Android native bridge (Shizuku, WorkManager, icon/name lookup)
- **Shizuku** — Privileged shell execution without root
- **WorkManager** — Background task scheduling
- **sqflite** — Audit event persistence
- **flutter_local_notifications** — Restart alerts
- **palette_generator** — Dynamic app colors extracted from icons

---

## AI disclosure

This project was prototyped and developed with heavy use of Claude (Anthropic). The development approach is commonly called "vibe coding" — iterating rapidly with an AI pair programmer. All generated code was tested on a physical device before shipping. If you find bugs, open an issue.

---

## License

MIT
