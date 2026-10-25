# Doppio

A menu bar app for macOS 14+ that keeps the Mac awake, like Caffeine. Click the cup to toggle it; it can also switch on by itself while the apps you choose are running. Distributed outside the Mac App Store, unsandboxed.

## Features

- Left click toggles; right click (or ⌃/⌥ click) opens the menu with timed sessions (15 min to 5 h).
- Default duration for the click, chosen in Settings.
- Automatic mode: stays awake while any watched app is running.
- Keeps the display on, or only prevents system sleep.
- Turns itself off on battery below a chosen level (5–30 %, or never).
- Launch at login.

## Layout

| Path | What |
| --- | --- |
| `Sources/Doppio` | App: `AwakeController` (state and rules), `SleepBlocker` (IOKit power assertion), `BatteryMonitor`, `StatusItemController` (menu bar), `SteamingCupIcon`, `SettingsView` |
| `assets/` | App icon (`AppIcon.icns`) and its source image |
| `scripts/` | Build, signing, icon and release helpers |

## Commands

```sh
make                    # lists the targets
make cert               # once: local signing identity so the app keeps its identity across rebuilds
make run                # builds build/Doppio.app, signed with "Doppio Dev", and opens it
make install            # builds the app, replaces the copy in /Applications and relaunches it
make icon               # regenerates assets/AppIcon.icns from assets/icon-source.png
make bump V=1.2.0       # sets the version and commits it
make release            # builds, tags, pushes and publishes the zip on GitHub
make release:patch      # bumps 1.0.0 → 1.0.1 and releases it (release:minor → 1.1.0)
```

Xcode is not required. To open in Xcode later: `open Package.swift`.

## Notes

- Doppio holds an IOKit power assertion (`PreventUserIdleDisplaySleep`, or `PreventUserIdleSystemSleep` when the display may sleep). Check it with `pmset -g assertions`.
- It doesn't keep a MacBook awake with the lid closed, unless macOS's closed-display mode applies (power and an external display).
- Launch at login uses `SMAppService`, which is tied to the code signature: builds signed with the stable "Doppio Dev" identity keep it; ad-hoc builds (the fallback) may lose it on rebuild.
