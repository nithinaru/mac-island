# Halo

A native macOS Dynamic Island for MacBook Pro. Agent app — no Dock icon. Apple Music only.

## Requirements

- macOS 14.4+
- Xcode 16+
- A notched MacBook Pro, or any Mac (fallback pill at the top of the screen)

## Build

```bash
xcodebuild -project Halo.xcodeproj -scheme Halo -configuration Debug build
```

Open `Halo.xcodeproj` and run the Halo scheme. The app launches as a background agent (`LSUIElement`). Right-click the island for Settings / Quit.

## Live activities

```bash
notch push --id build --title "Building" --progress 0.4
```

The `notch` CLI is copied into `Halo.app/Contents/MacOS/`. Bind is localhost-only.

## Spec

See `notch-app-spec.md`.
