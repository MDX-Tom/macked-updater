# Macked Updater

[English](README.md) | [简体中文](README.zh-CN.md)

<p align="center">
  <img src="assets/app-icon.png" alt="Macked Updater icon" width="112" height="112">
</p>

**Macked Updater** is a native macOS update assistant built around one core workflow: scan your installed apps, automatically check whether they are available on **Macked.app**, compare versions, and download matched updates directly to your Mac.

It keeps the process local and fast: installed apps stay on your machine, Macked.app lookups run from your signed-in local session, and downloads go straight into `~/Downloads` without opening a browser tab for every app.

<p align="center">
  <strong>Scan Apps → Match on Macked.app → Compare Versions → Download Updates</strong>
</p>

| Light | Dark |
| --- | --- |
| ![Macked Updater light-mode screenshot with demo data](assets/main-window-light.png) | ![Macked Updater dark-mode screenshot with demo data](assets/main-window-dark.png) |

> Screenshots are based on the real app UI and use fictitious app names and bundle identifiers.

## Built for Macked.app Updates

- **Automatic Macked.app update checks**: scan your installed macOS apps and automatically search Macked.app for matching entries after login.
- **Version comparison at a glance**: see your installed version, the latest official version, and the latest Macked.app version in one dashboard.
- **Direct in-app downloads**: when a Macked.app match is available, the app resolves the download flow and saves the file directly to `~/Downloads`.
- **Macked Included badge**: instantly identify apps that are already matched with Macked.app entries.
- **Download queue**: track downloaded size, total size, live speed, completion, and failure states.
- **Official source side-by-side**: keep official pages, official download links, and release notes visible next to Macked.app metadata.
- **Local-first design**: app scanning and cache data remain on your Mac.
- **Native macOS UI**: SwiftUI dashboard with sidebar navigation, clean cards, light/dark mode, and macOS-style controls.

## Macked.app Update Flow

Sign in once, then let Macked Updater handle the Macked.app update flow:

1. scan installed `.app` bundles;
2. search Macked.app for matching app pages;
3. compare installed, official, and Macked.app versions;
4. mark matched apps with `Macked Included`;
5. download matched updates directly from the app when you click `Download Macked`.

### Local App Scanner for Macked.app Matching

- Scans `/Applications`, `~/Applications`, and `/System/Applications`.
- Reads app name, bundle identifier, version, build number, install path, modification date, icon, Sparkle feed, and App Store receipt hints.
- Deduplicates app bundles and prefers user-installed copies over system-managed copies.

## Macked.app First, Optional Fallbacks

Macked Updater is designed around Macked.app matching and downloading. It also keeps a few optional metadata sources to improve version comparison and context:

- Macked.app search, detail parsing, version metadata, and direct download resolution after sign-in.
- Official app pages and release notes for comparison context.
- Sparkle appcast (`SUFeedURL` from the app bundle), when available.
- Homebrew Cask metadata, when Homebrew is installed.
- Mac App Store receipt / lookup metadata.
- Self-hosted JSON catalogs for local testing or private metadata.
- Manual website search fallback for apps that cannot be matched automatically.

## Requirements

- macOS 12 or later.
- Xcode 15+ or Swift 5.9+.
- Optional: Homebrew, if you want Homebrew Cask checks.

## Run from Source

Clone and run:

```bash
git clone https://github.com/<your-name>/macked-updater.git
cd macked-updater
swift run macked-updater
```

Open in Xcode:

```bash
open Package.swift
```

Then run the `macked-updater` executable target.

## Build and Package

Debug app bundle:

```bash
./script/build_and_run.sh --verify
```

Release app and DMGs:

```bash
./script/package_release.sh
```

The release script creates Apple Silicon, Intel, and universal builds. Each DMG includes an `/Applications` shortcut for drag-and-drop installation.

```text
dist/Macked Updater.app
dist/Macked Updater-universal.app
dist/Macked Updater-arm64.app
dist/Macked Updater-intel.app
dist/MackedUpdater_0.1.0_apple_silicon_aarch64.dmg
dist/MackedUpdater_0.1.0_intel_x64.dmg
dist/MackedUpdater_0.1.0_universal.dmg
```

These local builds use ad-hoc signing. For public distribution, sign and notarize with your own Apple Developer identity.

## Self-hosted Catalog Deployment

You can add your own update source by hosting a JSON catalog.

Minimal schema:

```json
{
  "schemaVersion": 1,
  "sourceName": "Example Update Catalog",
  "generatedAt": "2026-07-05T00:00:00Z",
  "apps": [
    {
      "name": "Nebula Notes",
      "bundleIdentifier": "com.example.nebula-notes",
      "latestVersion": "2.7.0",
      "officialPageURL": "https://updates.example.com/apps/nebula-notes",
      "downloadURL": "https://updates.example.com/downloads/nebula-notes-2.7.0.dmg",
      "releaseNotesURL": "https://updates.example.com/apps/nebula-notes/releases/2.7.0"
    }
  ]
}
```

Deployment steps:

1. Edit `deploy/authorized-catalog.json`.
2. Upload it to your own HTTPS static endpoint.
3. Open Macked Updater > Sources.
4. Paste the catalog URL and add matching entries.

Local testing can use a `file://` catalog URL.

## Project Layout

```text
App/            App entry point
Models/         App, update, source, and settings models
Services/       Scanning, update checks, matching, downloads, command helpers
Persistence/    Local JSON cache and user source storage
Views/          SwiftUI screens and shared components
Resources/      macOS app icon resource
assets/         App icon and README screenshots
script/         Build, run, package, and cleanup scripts
deploy/         Example self-hosted catalog
Tests/          XCTest coverage
```

## Development Checks

```bash
swift test
swift build -c release
./script/build_and_run.sh --verify
./script/package_release.sh
```

Clean generated local artifacts while keeping packaged DMGs:

```bash
./script/cleanup_after_run.sh
```

## Privacy

- The app scans local `.app` metadata on your Mac.
- It does not upload your installed app list.
- Macked.app login state is stored in the local WebKit website data store.
- Downloads run only after you click a download button.
- Downloaded files are saved to `~/Downloads`.
- The app does not install, replace, or modify your existing applications.
