# NØTH architecture

One SwiftPM executable target (`Sources/NotchFlow`), AppKit for windows and
system integration, SwiftUI for every view.

## Lifecycle and windows

- `main.swift` — `AppDelegate`: agent app (`LSUIElement`), creates the
  `NotchWindow`, installs `StatusMenuController` (menu-bar item + app menu).
- `NotchWindow` — borderless non-activating `NSPanel` at menu-bar level,
  pinned to the notch. Gathers ~20 publishers into `IslandSignals`, asks
  `IslandStateMachine` for the state, and animates the frame (stretch
  sideways, then drop; instant under Reduce Motion). Hover is a 25 Hz mouse
  poll against fixed geometry, not a SwiftUI tracking area.
- `NotchGeometry` — pure display/notch geometry (tested).
- Separate key windows where text input is needed: `QuickBarController`,
  `NotesController`, `CameraController`, Settings (`StatusMenuController`).

## State

- `IslandState` / `IslandStateMachine.resolve` — the Island's one state and
  its priority rules (clean mode › Command Center › drop › level HUD ›
  transient event › peek › music › persistent activity › pill). Pure, tested.
- `AppCoordinator` — shared UI state (expanded, peeking, settings, tab, drop)
  and shelf file actions.
- `AppSettings` — every user preference as `@Published` + UserDefaults;
  starts/stops managers in `didSet`; `resetToDefaults()`.
- Feature managers are `ObservableObject` singletons (`*Manager`), each owning
  one capability and publishing state; views observe them.

## Views

- `RootView` — the pill: collapsed wings, peek, drop surface, HUDs; hosts the
  Command Center when expanded.
- `CommandCenter.swift` — `CommandTab` and the tabbed Command Center
  (header + one scrolling section per tab).
- `SettingsView` — data-driven toggles (`Item` list) in grouped sections.
- `DesignSystem.swift` — tokens (`Theme.Palette/Space/Radius/Typo/Motion`) and
  components (`NIconButton`, `NChip`, `NSectionHeader`, `NStatusBanner`,
  `nfCard`, `nfAnimation`). Accessibility basics live here.

## Pure models (tested by `Scripts/run_tests.sh`)

`FileStore`, `NotchGeometry`, `NowPlaying`, `Lyrics`, `Downloads`, `Meeting`,
`Spectrum`, `SystemStats`, `TimeKeeping` (Stopwatch, Countdown, BreakTimer),
`Tools`, `Calculator`, `NoiseGenerator`, `Pins`/`Snap`, `IslandState`,
`Weather`, `Bluetooth`, `ClipboardHistory`, `DuePreset`.

## System integration

| Area | API |
|---|---|
| Now Playing | vendored mediaremote-adapter via `/usr/bin/perl` (Apple-entitled), AppleScript fallback |
| Visualizer | Core Audio process tap + private aggregate device, vDSP FFT |
| Camera/mic in use, mute, output | CoreAudio / CoreMediaIO properties (`AudioDevices`) |
| Lock-screen card | private SkyLight space, `dlsym`'d, opt-in (`LockScreenSpace`) |
| Brightness | DisplayServices, `dlsym`'d |
| Window snapping | Accessibility (`AXUIElement`) |
| Calendar/Reminders | EventKit |

Private APIs are always `dlsym`'d and isolated so a missing symbol disables one
feature, never the app.
