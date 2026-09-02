# Mac Widget Drive

A lightweight macOS menu-bar app that checks live driving time between two addresses on a schedule and shows it directly on your desktop wallpaper.

## Features

- Live drive-time lookups (with traffic conditions) via Apple Maps directions
- Desktop-anchored widget that can be repositioned by dragging
- Configurable refresh interval and start/end addresses
- Optional launch at login via `SMAppService`

## Build & Run

For quick iteration without installing:

```bash
./run.sh
```

This builds a release binary with `swift build -c release` and launches it, replacing any already-running instance.

To install as a proper app (required for **Launch at Login** to work — macOS can only silently relaunch bundled apps at login, not bare executables):

```bash
./build_app.sh
```

This packages the release binary as `MacWidgetDrive.app` and installs it to `/Applications`.

## Requirements

- macOS 13+
- Swift 5.9+

## Settings

Preferences are stored at `~/Library/Application Support/MacWidgetDrive/settings.json`.
