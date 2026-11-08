#!/bin/bash
# Compiles and runs the assert-based tests for the AppKit-free pure models
# (FileStore, NotchGeometry) directly with swiftc — no Xcode/XCTest needed.
set -euo pipefail
cd "$(dirname "$0")/.."

BIN="$(mktemp -t notchflow_pure_tests)"
trap 'rm -f "$BIN"' EXIT

swiftc Sources/NotchFlow/FileStore.swift Sources/NotchFlow/NotchGeometry.swift \
    Sources/NotchFlow/NowPlaying.swift Sources/NotchFlow/Lyrics.swift Sources/NotchFlow/Downloads.swift Sources/NotchFlow/Meeting.swift Sources/NotchFlow/Spectrum.swift Sources/NotchFlow/SystemStats.swift Sources/NotchFlow/TimeKeeping.swift Sources/NotchFlow/Tools.swift Sources/NotchFlow/Calculator.swift Sources/NotchFlow/FocusSoundsManager.swift Sources/NotchFlow/Pins.swift Sources/NotchFlow/IslandState.swift Sources/NotchFlow/RecentActivity.swift Sources/NotchFlow/QuickNotes.swift Sources/NotchFlow/DesignSystem.swift Sources/NotchFlow/Weather.swift \
    Sources/NotchFlow/Bluetooth.swift Sources/NotchFlow/ClipboardHistory.swift \
    Sources/NotchFlow/DuePreset.swift Sources/NotchFlow/UpdateCheck.swift \
    Scripts/test_pure_models.swift -o "$BIN"
"$BIN"
