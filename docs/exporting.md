# Exporting builds

Presets for Linux, Windows, Web, macOS, and Android live in
`export_presets.cfg`. Outputs land under `build/` (gitignored). Test,
addon, and tool files are excluded from packs via the presets'
`exclude_filter`.

## One-time setup

1. **Main scene** (required for a runnable build): in the editor, create
   a scene containing a single `Node2D`, attach
   `presentation/main.gd`, save as `res://main.tscn`, and set it as the
   main scene under Project Settings → Application → Run. Everything
   else is assembled by script at runtime.
2. **Export templates**: Editor → Manage Export Templates → Download,
   or `godot --headless --path . --install-android-build-template` for
   the Android gradle template if you go that route. Templates must
   match the editor version.
3. **Android only**: install Android Studio's SDK + a debug keystore and
   fill in Editor Settings → Export → Android. The preset ships
   `runnable=false` until that's done.

## Commands

```
godot --headless --path . --export-release "Linux"           build/linux/preemptive_peril.x86_64
godot --headless --path . --export-release "Windows Desktop" build/windows/preemptive_peril.exe
godot --headless --path . --export-release "Web"             build/web/index.html
godot --headless --path . --export-release "macOS"           build/macos/preemptive_peril.zip
```

The web build needs to be served (not opened from file://):
`python3 -m http.server -d build/web`.

## CI

The `export` job in `.github/workflows/ci.yml` builds Linux, Windows,
and Web on every push after tests pass (the CI image bundles matching
templates) and uploads them as the `builds` artifact. macOS and Android
exports stay local — signing and SDKs don't live in CI.
