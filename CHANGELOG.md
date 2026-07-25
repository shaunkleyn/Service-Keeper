# Changelog

## [Unreleased] — 2026-07-25/26

### Added

#### UI / Cards
- **Reusable `AppGroupCard` widget** — sliver-based expandable card with sticky header, used across all three monitoring screens (Services, Accessibility, Notifications). Replaces three separate header delegate implementations.
- **3-state group toggle** — each app card header now has a compact toggle controlling the monitoring state for all services in the group:
  - **Off** (`block`) — not monitored
  - **Monitor** (`eye`) — watched silently, no notifications
  - **Notify** (`bell`) — watched and notified on restart
- **State-aware toggle icons** — icons reflect the current selection contextually. Off state: grey closed eye + grey mute. Monitor state: green check + green open eye + grey mute. Notify state: green check + green open eye + green bell.
- **Toggle explainer banner** — global dismissable banner at the top of the app explaining the 3-state toggle with inline icons and descriptions. Restored via Settings → Reset dismissed banners.
- ** Added **Report Issue** to easily report issues on Github
- **Multi-select Apps and Services** to enable / disable

#### Undo
- **Undo snackbar** — toggling a group state shows a 10-second snackbar with an animated countdown progress bar and an Undo button.
- **AppBar undo action** — the 3-dot menu shows "Undo: [last action]" while the snackbar is active.
- **Reliable auto-dismiss** — undo timer is managed in the shell; snackbar and AppBar action are cleared together after exactly 10 seconds regardless of Flutter's SnackBar duration behavior.

### Changed

- **Notification Monitor screen** — replaced the custom `_NotifGroupHeaderDelegate` with `AppGroupCard`. The old separate monitor switch + notification bell icon + popup are unified into the same 3-state toggle used by all other screens.

### Fixed

- **Notification screen card spacing** — extra 8 px spacers between cards removed; spacing now matches the Services and Accessibility screens.
- **Added option to restart entire app** if service fails to start
