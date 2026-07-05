# Changelog

This file records major release updates only. Do not add or advance release entries unless explicitly requested.

## v0.1.0 - 2026-07-05

### Core Features

- Initial runnable macOS native app built with Swift and SwiftUI.
- Scans locally installed apps and displays name, bundle identifier, current version, install path, and icon.
- Supports status-based navigation: All Apps, Updates Available, Up to Date, Unknown, Sources, and Settings.
- Includes local cache and settings persistence. App scan data and update metadata are stored locally by default.

### Update Sources

- Supports reading and parsing Sparkle appcasts.
- Supports Homebrew Cask lookup.
- Supports Mac App Store receipt detection and App Store page entry points.
- Displays official page, official download link, and official version metadata when available.
- Supports Macked.app session detection, search matching, page parsing, and download entry points.
- Uses Unknown status when an update cannot be determined safely, avoiding false positives.

### Downloads and Source Display

- Each app can show both official source information and Macked.app source information.
- Macked.app downloads are saved to `~/Downloads`.
- Adds a download queue with downloaded size, total size, live speed, completed state, and failure state.
- External links and downloads are only triggered by explicit user actions.

### UI and Experience

- Uses a macOS-style sidebar, app list, and detail-card dashboard layout.
- Supports light and dark mode.
- Adds a `Macked Included` badge.
- Improves list scrolling performance with app icon caching and reduced row re-rendering.
- Keeps App Search and renames the scan action to `Rescan Apps`.
- Quits the app completely after the last window is closed.

### Packaging

- Version numbering starts at `0.1.0 / build 1`.
- Supports three DMG builds:
  - `MackedUpdater_0.1.0_apple_silicon_aarch64.dmg`
  - `MackedUpdater_0.1.0_intel_x64.dmg`
  - `MackedUpdater_0.1.0_universal.dmg`
- Each DMG includes `Macked Updater.app` and an `/Applications` shortcut for drag-and-drop installation.
