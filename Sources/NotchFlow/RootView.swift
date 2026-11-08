import AppKit
import SwiftUI

// The one accent used across the app: a subtle indigo/purple (spec §11). Defined
// once here, visible package-wide. Replaces the scattered `.blue`/`.accentColor`
// so selection, focus and the drop glow all read as the same product.
extension Color {
    static let nfAccent = Color(red: 0.48, green: 0.42, blue: 0.95)
}

// Explicit sizes, not derived from SwiftUI's fitting size — NotchWindow needs
// a size to reposition the panel *before* layout happens, same constraint
// that applied to the old AppKit ShelfView.
enum Layout {
    /// Matches the real hardware notch so the collapsed pill reads as an
    /// extension of it instead of visibly overhanging on either side. Falls
    /// back to a generic pill on displays without a physical notch.
    static var collapsedSize: NSSize {
        NotchWindow.notchSize() ?? NSSize(width: 200, height: 32)
    }
    /// The compact command center (spec §2): one fixed size, a 2-column card
    /// grid that scrolls internally. Fixed height means new modules never
    /// balloon the window — they just add a grid cell behind the scroll.
    /// Command Center size. Glance mode: one wide, short strip for every tab.
    /// Cards mode: the compact 640 panel.
    static var expandedSize: NSSize {
        guard AppSettings.shared.homeGlance else { return NSSize(width: 640, height: 432) }
        let screenWidth = NotchWindow.notchScreen()?.frame.width ?? 1440
        let width = min(1040, max(640, screenWidth - 120))
        // One size for every tab — switching tabs never resizes the panel.
        return NSSize(width: width, height: 96 + stripHeight + 20)
    }

    /// Height of the strip card's content in the uniform Command Center.
    static let stripHeight: CGFloat = 150

    /// Hover-peek strip (spec §2 State 2): notch-height, wide enough for a
    /// music glyph on the left and battery + gear on the right, around the
    /// physical notch. Same height as the pill, so collapsed ⇄ peek is a single
    /// sideways stretch (no vertical phase).
    static var peekSize: NSSize {
        // Notch-height band for the wings + a 46 pt controls row below the
        // notch line, where nothing is hidden by the camera housing.
        NSSize(width: collapsedSize.width + 320, height: collapsedSize.height + 46)
    }

    /// Settings panel — one fixed height; its content scrolls, so new settings
    /// never need another height bump.
    static let settingsSize = NSSize(width: 460, height: 360)

    /// Volume HUD: notch height, with a visible "wing" each side of the
    /// physical notch for the speaker icon (left) and level bar (right).
    static var hudSize: NSSize {
        let collapsed = collapsedSize
        return NSSize(width: collapsed.width + 300, height: collapsed.height)
    }

}

// The shelf's entire visual surface: the black pill and, when expanded, the
// files section on the left and (calendar + reminders) stacked on the right —
// or the settings screen, reached via the home icon.
struct RootView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var calendarManager = CalendarManager.shared
    @ObservedObject var reminderManager = ReminderManager.shared
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var keyboardBacklight = KeyboardBacklightManager.shared
    @ObservedObject var nowPlayingManager = NowPlayingManager.shared
    @ObservedObject var downloads = DownloadsManager.shared
    @ObservedObject var privacy = PrivacyManager.shared
    @ObservedObject var meetings = MeetingAlertManager.shared
    @ObservedObject var spectrum = AudioSpectrumManager.shared
    @ObservedObject var capsLock = CapsLockManager.shared
    @ObservedObject var audioOutput = AudioOutputManager.shared
    @ObservedObject var stats = SystemStatsManager.shared
    @ObservedObject var deviceNotice = DeviceNoticeManager.shared
    @ObservedObject var breaks = BreakReminderManager.shared
    @ObservedObject var stopwatch = StopwatchManager.shared
    @ObservedObject var tools = ToolsManager.shared
    @ObservedObject var focusSounds = FocusSoundsManager.shared
    @ObservedObject var pins = PinsManager.shared
    @ObservedObject var recent = RecentActivityManager.shared
    @ObservedObject var cleanMode = CleanModeManager.shared
    @ObservedObject var battery = BatteryManager.shared
    @ObservedObject var weather = WeatherManager.shared
    @ObservedObject var clipboard = ClipboardManager.shared
    @ObservedObject var bluetooth = BluetoothManager.shared
    @ObservedObject var pomodoro = PomodoroManager.shared
    @ObservedObject var screenTime = ScreenTimeManager.shared

    /// Glass applies to the hover strip and the Command Center; wings, HUDs
    /// and the idle pill stay black so they read as the notch.
    var glassActive: Bool { settings.glassPanel && (coordinator.isExpanded || coordinator.isPeeking) }

    var body: some View {
        content
            .environment(\.colorScheme, glassActive && settings.lightPanel ? .light : .dark)
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
            // Fill the window and pin content to the top-left. The window's
            // animated frame *is* the reveal: as it grows taller, more content
            // shows from the top down (a curtain), never re-centering.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(panelBackground)
            .clipShape(pillShape)
            // A file drag onto the notch wakes it: expand so there's room to
            // drop, and glow an accent border while the drag is over it.
            .overlay {
                if coordinator.dropActive {
                    pillShape
                        .strokeBorder(Color.nfAccent, lineWidth: 2)
                        .shadow(color: .nfAccent.opacity(0.8), radius: 6)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: coordinator.dropActive)
            // Hover is NOT detected here: the window resizes during the
            // expand/collapse animation, which would churn a SwiftUI hover
            // tracking area and flip the state on/off mid-animation. NotchWindow
            // watches the mouse against fixed geometry instead.
            //
            // A drag flips `dropActive`, which NotchWindow turns into the compact
            // drop surface (spec §2 State 3) — it does NOT open the full hub.
            .onDrop(of: [.fileURL], isTargeted: $coordinator.dropActive, perform: handleDrop)
            .accessibilityElement(children: coordinator.isExpanded ? .contain : .combine)
    }

    /// The icon + level to flash for a recent volume/brightness/battery
    /// change, or nil. One place drives both the collapsed HUD and the
    /// expanded-shelf overlay.
    var activeLevelHUD: (icon: String, level: Float)? {
        if volumeManager.hudVisible {
            return (volumeManager.muted || volumeManager.volume == 0
                        ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    volumeManager.muted ? 0 : volumeManager.volume)
        }
        if brightnessManager.hudVisible {
            return ("sun.max.fill", brightnessManager.brightness)
        }
        if keyboardBacklight.hudVisible {
            return ("keyboard", keyboardBacklight.brightness)
        }
        if battery.hudVisible {
            let icon = battery.charging ? "battery.100.bolt"
                : (battery.level <= 0.2 ? "battery.25" : "battery.100")
            return (icon, Float(battery.level))
        }
        return nil
    }

    @ViewBuilder
    var content: some View {
        if cleanMode.active {
            cleanModeView
        } else if coordinator.isExpanded {
            commandCenter
        } else if coordinator.dropActive || coordinator.justAdded != nil {
            dropView
        } else if let hud = activeLevelHUD {
            wingHUD(icon: hud.icon, level: hud.level)
        } else if capsLock.hudVisible {
            capsLockWing
        } else if let notice = deviceNotice.notice {
            noticeWing(notice)
        } else if breaks.reminderVisible {
            breakWing
        } else if let meeting = meetings.alert {
            meetingWing(meeting)
        } else if let due = reminderManager.justDue, settings.showCompanion {
            companionView(due)
        } else if let done = downloads.justFinished {
            downloadDoneWing(done)
        } else if coordinator.isPeeking {
            peekView
        } else if let track = nowPlayingManager.nowPlaying, track.playing {
            musicLiveActivity(track)
        } else if privacy.showing {
            privacyWing
        } else if stopwatch.running {
            stopwatchWing
        } else if let dl = downloads.active {
            downloadWing(dl.name, progress: dl.progress)
        } else if pomodoro.running {
            pomodoroWing
        } else if settings.showBatteryInNotch, battery.hasBattery {
            batteryWing
        }
    }

    // Drag/drop surface (spec §2 State 3): while a file drag is over the notch,
    // a clear "↓ Drop file here" prompt; the instant after a drop, a compact
    // "✓ Added" with the filename — then it collapses. Never opens the full hub.
    var dropView: some View {
        Group {
            if let name = coordinator.justAdded {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.green)
                    Text(name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("Added").foregroundColor(Theme.Palette.textSecondary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.nfAccent)
                    Text("Drop file here")
                }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(Theme.Palette.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Running Pomodoro in the collapsed wings: phase glyph left, countdown right.
    // Meeting about to start: camera glyph + title on the left, a live
    // "in 3 min" / "now" on the right. A transient wing suppresses the hover
    // peek strip, so a click here opens the shelf, where the card holds
    // Join/dismiss.
    func meetingWing(_ meeting: Meeting) -> some View {
        let wing = (Layout.hudSize.width - Layout.collapsedSize.width) / 2 - 24
        return HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "video.fill")
                    .font(.system(size: 11)).foregroundColor(.blue)
                Text(meeting.title)
                    .font(.system(size: 10, weight: .medium)).foregroundColor(Theme.Palette.text)
                    .lineLimit(1).truncationMode(.tail)
            }
            .frame(width: wing)
            Spacer(minLength: 0)
            meetingCountdown(meeting)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.blue)
                .frame(width: wing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { coordinator.isExpanded = true }
    }

    // "in 3 min" before the start, "now" after it; ticks on its own.
    func meetingCountdown(_ meeting: Meeting) -> some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            let mins = Int(ceil(meeting.start.timeIntervalSince(ctx.date) / 60))
            Text(mins > 0 ? "in \(mins) min" : "now").monospacedDigit()
        }
    }

    // Shelf card for the alerting meeting: title + countdown, Join when the
    // event has a call link, and a dismiss that silences this occurrence.
    func meetingCard(_ meeting: Meeting) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "video.fill")
                .font(.system(size: 13)).foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(meeting.title)
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.Palette.text)
                    .lineLimit(1).truncationMode(.tail)
                meetingCountdown(meeting)
                    .font(.system(size: 10)).foregroundColor(Theme.Palette.textSecondary)
            }
            Spacer(minLength: 6)
            if meeting.joinURL != nil {
                NChip(title: "Join", icon: "video.fill", selected: true,
                      help: "Join \(meeting.title)") { meetings.join() }
            }
            NIconButton(symbol: "xmark", label: "Dismiss meeting alert", tint: Theme.Palette.textSecondary,
                        size: 11) { meetings.dismiss() }
        }
    }

    // Camera/mic in use: green camera / orange mic glyphs (red slashed mic when
    // muted) on the left, a short status on the right. Status only — hovering
    // turns the pill into the peek strip, so mute lives in the shelf + ⌥⌘M.
    var privacyWing: some View {
        let wing = (Layout.hudSize.width - Layout.collapsedSize.width) / 2 - 24
        let status = privacy.muted ? "Muted"
            : privacy.cameraInUse ? (privacy.micInUse ? "Cam + mic" : "Camera") : "Mic on"
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                if privacy.cameraInUse {
                    Image(systemName: "video.fill").foregroundColor(.green)
                }
                if privacy.micInUse || privacy.muted {
                    Image(systemName: privacy.muted ? "mic.slash.fill" : "mic.fill")
                        .foregroundColor(privacy.muted ? .red : .orange)
                }
            }
            .font(.system(size: 12))
            .frame(width: wing)
            Spacer(minLength: 0)
            Text(status)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(privacy.muted ? .red : .white)
                .frame(width: wing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Finished download: a brief check + name; click reveals it in Finder.
    func downloadDoneWing(_ name: String) -> some View {
        let wing = (Layout.hudSize.width - Layout.collapsedSize.width) / 2 - 24
        return HStack(spacing: 0) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12)).foregroundColor(.green)
                .frame(width: wing)
            Spacer(minLength: 0)
            Text(name)
                .font(.system(size: 10, weight: .medium)).foregroundColor(Theme.Palette.text)
                .lineLimit(1).truncationMode(.middle)
                .frame(width: wing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { downloads.revealFinished() }
    }

    // Persistent battery readout in the collapsed notch wings (opt-in): icon in
    // the left wing, % in the right. Same wing geometry as the HUD/companion.
    var batteryWing: some View {
        let wing = (Layout.hudSize.width - Layout.collapsedSize.width) / 2 - 24
        return HStack(spacing: 0) {
            BatteryGlyph(level: battery.level, charging: battery.charging)
                .frame(width: wing)
            Spacer(minLength: 0)
            Text("\(Int((battery.level * 100).rounded()))%")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundColor(Theme.Palette.text)
                .frame(width: wing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // A character peeks from the notch when a reminder comes due: a friendly
    // symbol in the left wing, the reminder title in the right. Mirrors the
    // music live-activity wing layout.
    func companionView(_ item: ReminderItem) -> some View {
        let wing = (Layout.hudSize.width - Layout.collapsedSize.width) / 2 - 24
        return HStack(spacing: 0) {
            Image(systemName: "bird.fill")
                .font(.system(size: 12))
                .foregroundColor(.yellow)
                .frame(width: wing)
            Spacer(minLength: 0)
            Text(item.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.Palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: wing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Album artwork for a track — adapter image bytes or a Spotify URL — else the
    // supplied fallback (equalizer bars or a note glyph).
    func albumArt(_ track: NowPlaying, size: CGFloat, fallback: AnyView) -> some View {
        Group {
            if let data = track.artworkData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else if let art = track.artworkURL, let url = URL(string: art) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    fallback
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                fallback
            }
        }
    }

    // Clean mode: lock icon + countdown in the left wing, a Cancel button in
    // the right wing. Escape key also cancels (the tap lets it through). A
    // single click, not a long-press — a continuous SwiftUI gesture doesn't
    // reliably receive events in this non-key notch panel, which left the user
    // unable to cancel at all.
    var cleanModeView: some View {
        let wing = (Layout.hudSize.width - Layout.collapsedSize.width) / 2 - 24
        return HStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 12))
                Text("\(cleanMode.remaining)s")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundColor(Theme.Palette.text)
            .frame(width: wing)
            Spacer(minLength: 0)
            Button(action: { cleanMode.stop() }) {
                Text("Cancel")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.Palette.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.red))
            }
            .buttonStyle(.plain)
            .frame(width: wing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Bezel-style HUD: icon in the left wing, level bar in the right wing,
    // and an empty stretch in the middle where the physical notch sits.
    func wingHUD(icon: String, level: Float) -> some View {
        let wing = (Layout.hudSize.width - Layout.collapsedSize.width) / 2 - 24
        return HStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(Theme.Palette.text)
                .frame(width: wing)
            Spacer(minLength: 0)
            Capsule()
                .fill(Color(white: 0.3))
                .frame(width: wing, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.white)
                        .frame(width: wing * CGFloat(level))
                        .animation(.easeOut(duration: 0.12), value: level)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Compact level indicator (icon + bar) for a live volume/brightness/keyboard
    // change, shown in the home bar's trailing slot.
    func levelPill(icon: String, level: Float) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(Theme.Palette.text)
            Capsule()
                .fill(Color(white: 0.3))
                .frame(width: 54, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 54 * CGFloat(level), height: 4)
                        .animation(.easeOut(duration: 0.12), value: level)
                }
        }
    }

    // Local weather in the open shelf: condition glyph + temperature.
    func weatherBadge(_ w: Weather) -> some View {
        HStack(spacing: 3) {
            Image(systemName: w.symbol)
                .font(.system(size: 11))
            Text(w.label)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
        }
        .foregroundColor(Theme.Palette.text)
    }

    // Always-on battery readout in the open shelf: icon reflects charging /
    // low state, with the exact %. Green while charging, red under 20%.
    // ponytail: shelf-only, not the collapsed pill — a persistent readout in
    // the bare notch means forcing the wings open all day (an opt-in, always-on
    // visual). Add that behind a setting if anyone asks.
    var batteryBadge: some View {
        let low = battery.level <= 0.2 && !battery.charging
        return HStack(spacing: 4) {
            BatteryGlyph(level: battery.level, charging: battery.charging)
            Text("\(Int((battery.level * 100).rounded()))%")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundColor(battery.charging ? .green : (low ? .red : .white))
        }
    }

    /// Solid black, or frosted glass when the Command Center is open in glass
    /// mode. A black band at notch height fades into the glass so the camera
    /// housing still reads as part of the panel.
    @ViewBuilder var panelBackground: some View {
        if glassActive {
            ZStack(alignment: .top) {
                FrostedGlass(light: settings.lightPanel)
                // A thin dark tint keeps gray labels legible over white windows.
                if !settings.lightPanel { Color.black.opacity(0.15) }
                LinearGradient(colors: [.black, .black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: Layout.collapsedSize.height + 12)
            }
            .clipShape(pillShape)
        } else {
            pillShape.fill(Color.black)
        }
    }

    var pillShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(bottomLeadingRadius: settings.cornerRadius,
                               bottomTrailingRadius: settings.cornerRadius)
    }

    var filesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Scrollable so more actions can't clip the narrow files column.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // AirDrop lives on the drop-tile below (tap = all, drop =
                    // one); per-file removal is the ✕ on each tile.
                    iconButton("camera.viewfinder", "Screenshot") { coordinator.screenshot() }
                    iconButton("camera", "Photo") { CameraController.shared.present() }
                    iconButton("person.crop.square", "Mirror") { CameraController.shared.present(mirror: true) }
                    iconButton("note.text", "Notes") { NotesController.shared.present() }
                    iconButton("eye", "Quick Look") { coordinator.quickLook() }
                    iconButton("doc.on.clipboard", "Copy Path") { coordinator.copyPath() }
                    iconButton("folder", "Reveal in Finder") { coordinator.revealInFinder() }
                    iconButton("trash", "Clear shelf (files stay on disk)") { coordinator.clear() }
                }
            }
            // Horizontal shelf of file tiles (icon + name), inside a dashed
            // drop zone, led by an always-present AirDrop-out tile. Echoes
            // NotchDrop: parked files read as cards you can drag back out.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    airdropTile
                    copyPathTile
                    if coordinator.files.isEmpty {
                        Text("Drop files here")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.Palette.textSecondary)
                            .frame(maxHeight: .infinity)
                            .padding(.leading, 4)
                    } else {
                        ForEach(coordinator.files, id: \.self) { url in
                            FileTileView(url: url) { coordinator.remove(url) }
                        }
                    }
                }
                .padding(4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundColor(Color.white.opacity(0.15))
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Recent clipboard entries as a horizontal chip row; click one to put it
    // back on the pasteboard.
    var clipboardBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 10))
                .foregroundColor(Theme.Palette.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(clipboard.clips, id: \.self) { clip in
                        Text(clip)
                            .font(.system(size: 10))
                            .foregroundColor(Theme.Palette.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 90)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.Palette.elevated))
                            .onTapGesture { clipboard.copy(clip) }
                            .help(clip)
                    }
                }
            }
        }
    }

    func stopwatchTime(size: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            Text(Stopwatch.label(stopwatch.watch.elapsed(at: ctx.date)))
                .font(.system(size: size, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(Theme.Palette.text)
        }
    }

    // Tools: pick color / scan QR / emoji buttons, then recent color swatches
    // (click = copy hex) and, after a scan, the payload with Open for links.
    var toolsBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                toolButton("eyedropper.halffull", "Pick color") { tools.pickColor() }
                toolButton("qrcode.viewfinder", "Scan QR") { tools.scanQR() }
                toolButton("face.smiling", "Emoji") { tools.showEmojiPalette() }
                toolButton("command", "Quick bar") { QuickBarController.shared.present() }
                Spacer(minLength: 0)
                ForEach(tools.colors, id: \.self) { hex in
                    let c = Tools.components(hex) ?? (0, 0, 0)
                    Button { tools.copy(hex) } label: {
                        Circle().fill(Color(red: c.0, green: c.1, blue: c.2))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help("Copy \(hex)")
                }
            }
            if let hex = tools.colors.first, let c = Tools.components(hex) {
                let rgb = "rgb(\(Int((c.0 * 255).rounded())), \(Int((c.1 * 255).rounded())), \(Int((c.2 * 255).rounded())))"
                HStack(spacing: Theme.Space.s) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(red: c.0, green: c.1, blue: c.2))
                        .frame(width: 22, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.Palette.border))
                        .accessibilityHidden(true)
                    Text(hex).font(Theme.Typo.bodyEmphasis).monospaced().foregroundColor(Theme.Palette.text)
                    Text(rgb).font(Theme.Typo.label).monospaced().foregroundColor(Theme.Palette.textSecondary)
                    Spacer(minLength: 0)
                    NChip(title: "Copy hex", help: "Copy \(hex)") { tools.copy(hex) }
                    NChip(title: "Copy RGB", help: "Copy \(rgb)") { tools.copy(rgb) }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Last picked color \(hex)")
            }
            if let qr = tools.lastQR {
                HStack(spacing: 6) {
                    Image(systemName: "qrcode").font(.system(size: 10)).foregroundColor(Theme.Palette.textSecondary)
                    Text(qr.text)
                        .font(.system(size: 10)).foregroundColor(Theme.Palette.text)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    if let url = qr.url {
                        // Name the destination before anything opens (never automatic).
                        NChip(title: "Open \(url.host ?? "link")", icon: "safari",
                              help: "Open \(url.absoluteString)") { tools.openLastQR() }
                    }
                }
            }
        }
    }

    // Pinned links (open) and snippets (copy) as chips; "+" pins the clipboard,
    // right-click removes.
    var pinsBar: some View {
        HStack(spacing: 6) {
            Button {
                if !pins.pinClipboard() {
                    DeviceNoticeManager.shared.show(.init(symbol: "pin.slash", text: "Nothing to pin", style: .warning))
                }
            } label: {
                Image(systemName: "plus.circle.fill").font(.system(size: 13)).foregroundColor(Theme.Palette.text)
            }
            .buttonStyle(.plain)
            .help("Pin the clipboard (link or text)")
            if pins.links.isEmpty && pins.snippets.isEmpty {
                Text("Copy a link or text, then + to pin it")
                    .font(.system(size: 10)).foregroundColor(Theme.Palette.textSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(pins.links, id: \.self) { link in
                        Button { pins.open(link) } label: {
                            HStack(spacing: 5) {
                                LinkTile(link: link, size: 16)
                                Text(URL(string: link).map(Pins.linkTitle) ?? link)
                                    .font(Theme.Typo.label).foregroundColor(Theme.Palette.text).lineLimit(1)
                            }
                            .padding(.horizontal, 6).frame(minHeight: 24)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.control).fill(Theme.Palette.elevated))
                        }
                        .buttonStyle(NPressStyle())
                        .help(link)
                        .contextMenu { Button("Remove", role: .destructive) { pins.remove(link: link) } }
                    }
                    ForEach(pins.snippets, id: \.self) { snippet in
                        pinChip(icon: "text.quote", title: Pins.snippetTitle(snippet),
                                help: "Copy", action: { pins.copy(snippet) }, remove: { pins.remove(snippet: snippet) })
                    }
                }
            }
        }
    }

    func pinChip(icon: String, title: String, help: String,
                         action: @escaping () -> Void, remove: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10))
                Text(title).font(.system(size: 10)).lineLimit(1)
            }
            .foregroundColor(Theme.Palette.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.Palette.elevated))
        }
        .buttonStyle(.plain)
        .help(help)
        .contextMenu { Button("Remove", role: .destructive, action: remove) }
    }

    // Focus sounds: one chip per noise color (tap again to stop) + volume.
    var focusSoundsBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 10))
                .foregroundColor(.green)
            ForEach(NoiseGenerator.Kind.allCases, id: \.self) { kind in
                let on = focusSounds.playing == kind
                Button { focusSounds.toggle(kind) } label: {
                    Text(kind.rawValue.capitalized)
                        .font(.system(size: 10, weight: on ? .semibold : .regular))
                        .foregroundColor(on ? .white : .gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(on ? Color.green.opacity(0.5) : Theme.Palette.elevated))
                }
                .buttonStyle(.plain)
            }
            Slider(value: $focusSounds.volume, in: 0...1)
                .controlSize(.mini)
                .frame(maxWidth: 120)
        }
    }

    func toolButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        NChip(title: label, icon: symbol, action: action)
    }

    // Shelf stopwatch: time, start/pause, reset.
    var stopwatchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "stopwatch.fill")
                .font(.system(size: 11))
                .foregroundColor(.orange)
            stopwatchTime(size: 14)
            Spacer(minLength: 0)
            Button { stopwatch.toggle() } label: {
                Image(systemName: stopwatch.running ? "pause.fill" : "play.fill")
                    .font(.system(size: 12)).foregroundColor(Theme.Palette.text)
            }
            .buttonStyle(.plain)
            Button { stopwatch.reset() } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12)).foregroundColor(Theme.Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Reset")
        }
    }

    // Caps Lock flash: the glyph lit (on) or dimmed (off), with a label.
    var capsLockWing: some View {
        let wing = (Layout.hudSize.width - Layout.collapsedSize.width) / 2 - 24
        return HStack(spacing: 0) {
            Image(systemName: capsLock.isOn ? "capslock.fill" : "capslock")
                .font(.system(size: 13))
                .foregroundColor(capsLock.isOn ? .green : .gray)
                .frame(width: wing)
            Spacer(minLength: 0)
            Text(capsLock.isOn ? "Caps On" : "Caps Off")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.Palette.text)
                .frame(width: wing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Output devices as chips; the current one is highlighted, a click
    // switches the system output. Refreshes whenever the card appears.
    var outputSwitcherBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "hifispeaker.2.fill")
                .font(.system(size: 10))
                .foregroundColor(Theme.Palette.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(audioOutput.devices) { device in
                        let selected = device.id == audioOutput.current
                        Button { audioOutput.select(device) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: device.symbol).font(.system(size: 10))
                                Text(device.name)
                                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                                    .lineLimit(1).truncationMode(.tail)
                                    .frame(maxWidth: 110)
                            }
                            .foregroundColor(selected ? .white : .gray)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(selected ? Color.nfAccent.opacity(0.6) : Theme.Palette.elevated))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear { audioOutput.refresh() }
    }

    // CPU · memory · network throughput, one line, updated every 2 s.
    var systemStatsBar: some View {
        let s = stats.snapshot
        return HStack(spacing: 12) {
            Label("\(Int((s.cpu * 100).rounded()))%", systemImage: "cpu")
            Label("\(SystemStats.formatGB(s.memoryUsed)) / \(SystemStats.formatGB(stats.memoryTotal))",
                  systemImage: "memorychip")
            Spacer(minLength: 0)
            Label(SystemStats.formatRate(s.download), systemImage: "arrow.down")
            Label(SystemStats.formatRate(s.upload), systemImage: "arrow.up")
        }
        .font(.system(size: 10, weight: .medium))
        .monospacedDigit()
        .foregroundColor(Theme.Palette.text)
        .labelStyle(.titleAndIcon)
    }

    var bluetoothBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "wave.3.right")
                .font(.system(size: 10))
                .foregroundColor(Theme.Palette.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(bluetooth.devices, id: \.name) { device in
                        HStack(spacing: 3) {
                            Text(device.name)
                                .font(.system(size: 10))
                                .foregroundColor(Theme.Palette.text)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 80)
                            Text("\(device.battery)%")
                                .font(.system(size: 10, weight: .medium))
                                .monospacedDigit()
                                .foregroundColor(device.battery <= 20 ? .red : .gray)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.Palette.elevated))
                    }
                }
            }
        }
    }

    // Top apps by foreground time today, as a chip row.
    var screenTimeBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "hourglass")
                .font(.system(size: 10))
                .foregroundColor(Theme.Palette.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(screenTime.ranked.prefix(5), id: \.app) { entry in
                        HStack(spacing: 3) {
                            Text(entry.app)
                                .font(.system(size: 10))
                                .foregroundColor(Theme.Palette.text)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 80)
                            Text(ScreenTimeManager.format(entry.seconds))
                                .font(.system(size: 10, weight: .medium))
                                .monospacedDigit()
                                .foregroundColor(Theme.Palette.textSecondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.Palette.elevated))
                    }
                }
            }
        }
    }

    // Favorite-app launcher: click an icon to open, drop .app bundles to add,
    // hover an icon to remove it.
    var launcherBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 10))
                .foregroundColor(Theme.Palette.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if settings.launcherApps.isEmpty {
                        Text("Drop apps here")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.Palette.textSecondary)
                    }
                    ForEach(settings.launcherApps, id: \.self) { path in
                        LauncherIcon(path: path) { settings.removeLauncherApp(path) }
                    }
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            loadURLs(from: providers) { urls in
                urls.forEach { settings.addLauncherApp($0.path) }
            }
        }
    }

    func transportButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        NIconButton(symbol: systemName, label: transportLabel(systemName), size: 12, action: action)
    }

    // The single AirDrop control: tap to send all shelf files, or drop a file
    // on it to AirDrop that one without parking it. Its own onDrop shadows the
    // section's park-on-drop for this tile only.
    var airdropTile: some View {
        VStack(spacing: 3) {
            Image(systemName: "paperplane.circle.fill")
                .font(.system(size: 26))
                .foregroundColor(.blue)
            Text("AirDrop")
                .font(.system(size: 10))
                .foregroundColor(Theme.Palette.text)
        }
        .frame(width: 60, height: 58)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.15)))
        .onTapGesture { coordinator.airdrop() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            loadURLs(from: providers) { coordinator.airdropURLs($0) }
        }
        .help("Tap to AirDrop shelf files, or drop a file to send it")
    }

    // Drop a file here to copy its path to the clipboard, without parking it.
    var copyPathTile: some View {
        VStack(spacing: 3) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 24))
                .foregroundColor(.indigo)
            Text("Copy Path")
                .font(.system(size: 10))
                .foregroundColor(Theme.Palette.text)
        }
        .frame(width: 60, height: 58)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.indigo.opacity(0.15)))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            loadURLs(from: providers) { coordinator.copyPaths($0) }
        }
        .help("Drop a file to copy its path")
    }

    func iconButton(_ systemName: String, _ help: String, action: @escaping () -> Void) -> some View {
        NIconButton(symbol: systemName, label: help, size: 15,
                    role: systemName == "trash" ? .destructive : nil, filled: true, action: action)
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        loadURLs(from: providers) { coordinator.handleDrop(urls: $0, confirm: true) }
    }

    /// Load file URLs from dropped providers, then run `sink` on main. Returns
    /// false (nothing to do) for an empty drop.
    @discardableResult
    func loadURLs(from providers: [NSItemProvider],
                          then sink: @escaping ([URL]) -> Void) -> Bool {
        guard !providers.isEmpty else { return false }
        let group = DispatchGroup()
        var urls: [URL] = []
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                // loadObject callbacks fire concurrently on arbitrary threads;
                // funnel appends through main so the Array isn't raced.
                DispatchQueue.main.async {
                    if let url { urls.append(url) }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { sink(urls) }
        return true
    }
}

// A drawn battery: body + nub, with an inner fill that tracks the real level
// (animating as it drains) and, while charging, sweeps up toward full on a
// loop to read as an active charge. Green charging / red <20% / white.
struct BatteryGlyph: View {
    let level: Double        // 0...1
    let charging: Bool
    @State private var sweep = false

    private let bodyW: CGFloat = 22
    private let bodyH: CGFloat = 11
    private let inset: CGFloat = 1.5

    var body: some View {
        let low = level <= 0.2 && !charging
        let tint: Color = charging ? .green : (low ? .red : .white)
        let innerMax = bodyW - inset * 2
        // While charging the fill sweeps level→full→level; otherwise it just
        // reflects the real level (and animates smoothly when it changes).
        let fillWidth = charging
            ? (sweep ? innerMax : innerMax * CGFloat(level))
            : innerMax * CGFloat(max(0.02, level))

        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(tint.opacity(0.7), lineWidth: 1)
                    .frame(width: bodyW, height: bodyH)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(tint)
                    .frame(width: max(1, fillWidth), height: bodyH - inset * 2)
                    .padding(.leading, inset)
                    .animation(charging
                        ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
                        : .easeOut(duration: 0.35), value: fillWidth)
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: bodyW, height: bodyH)
                }
            }
            // Terminal nub.
            RoundedRectangle(cornerRadius: 1)
                .fill(tint.opacity(0.7))
                .frame(width: 2, height: 5)
        }
        .onAppear { if charging { sweep = true } }
        .onChange(of: charging) { sweep = charging }
    }
}

// Fake-but-lively spectrum: seven bars on a center-tall envelope, each bouncing
// at its own rate so it reads as a spectrum analyzer.
// ponytail: not audio-reactive — a real spectrum needs a system-audio tap
// (ScreenCaptureKit + permission); parked until someone actually misses it.
struct EqualizerBars: View {
    /// Real 0…1 band levels from AudioSpectrumManager; nil = decorative loop.
    var levels: [Float]? = nil
    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Per-bar peak heights — tallest in the middle, like a spectrum envelope.
    private let peaks: [CGFloat] = [5, 9, 13, 15, 12, 8, 5]

    var body: some View {
        if let levels {
            HStack(spacing: 1.5) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 2, height: 3 + CGFloat(levels[index]) * 12)
                }
            }
            .frame(height: 15)
            .animation(.linear(duration: 0.06), value: levels)
        } else {
            decorative
        }
    }

    var decorative: some View {
        HStack(spacing: 1.5) {
            ForEach(peaks.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2, height: animating ? peaks[index] : 3)
                    .animation(
                        .easeInOut(duration: 0.3 + Double(index % 4) * 0.1)
                            .repeatForever(autoreverses: true),
                        value: animating)
            }
        }
        .onAppear { animating = !reduceMotion }
        .accessibilityHidden(true)
    }
}

// A launcher app icon: click to open, hover for a ✕ to remove.
struct LauncherIcon: View {
    let path: String
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        Button { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } label: {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help((path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: ""))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.Palette.text)
                        .background(Circle().fill(Color.black))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .onHover { hovering = $0 }
    }
}

// Now Playing as a dedicated compact panel (spec §7): album art on the left,
// title/artist stacked, a progress bar, and the transport row. The bar advances
// smoothly between the manager's 4 s polls by interpolating from the last known
// position + wall-clock, so it doesn't visibly jump every poll.
struct NowPlayingPanel: View {
    let track: NowPlaying
    let manager: NowPlayingManager
    @ObservedObject var lyrics = LyricsManager.shared
    // Anchor for interpolation: the position we last heard and when.
    @State private var basePos: Double = 0
    @State private var baseAt: Date = Date()

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                artwork
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.Palette.text)
                        .lineLimit(1).truncationMode(.tail)
                    Text(track.artist)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.Palette.textSecondary)
                        .lineLimit(1).truncationMode(.tail)
                    progressBar
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 12) {
                    transport("backward.fill") { manager.previousTrack() }
                    transport(track.playing ? "pause.fill" : "play.fill") { manager.playPause() }
                    transport("forward.fill") { manager.nextTrack() }
                }
            }
            if let lyrics = lyrics.lyrics { lyricsRow(lyrics) }
        }
        .onAppear { basePos = track.position; baseAt = Date() }
        // Re-anchor whenever the poll delivers a new position (or the track
        // changes), so the smooth bar tracks reality after each 4 s refresh.
        .onChange(of: track.position) { basePos = track.position; baseAt = Date() }
    }

    /// Interpolated playback position: last polled position + wall-clock.
    func position(at date: Date) -> Double {
        let elapsed = track.playing ? date.timeIntervalSince(baseAt) : 0
        let pos = basePos + max(0, elapsed)
        return track.duration > 0 ? min(track.duration, pos) : pos
    }

    /// Karaoke row under the track: the sung line large and white, the next
    /// one dimmed below, crossfading as lines change. Fixed two-line height so
    /// the card doesn't jump; a gap (instrumental) shows a soft note.
    func lyricsRow(_ lyrics: Lyrics) -> some View {
        TimelineView(.periodic(from: baseAt, by: 0.25)) { ctx in
            let w = lyrics.window(at: position(at: ctx.date))
            let current = w.current.flatMap { $0.isEmpty ? nil : $0 }
            VStack(spacing: 2) {
                Text(current ?? "♪")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(current == nil ? .gray : .white)
                    .id(current ?? "♪")
                    .transition(.opacity)
                Text(w.next ?? " ")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Palette.textSecondary)
                    .id("next-" + (w.next ?? ""))
                    .transition(.opacity)
            }
            .lineLimit(1).truncationMode(.tail)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.25), value: current)
        }
        .frame(height: 34)
    }

    @ViewBuilder private var progressBar: some View {
        if track.duration > 0 {
            TimelineView(.periodic(from: baseAt, by: 0.5)) { ctx in
                let pos = position(at: ctx.date)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2)).frame(height: 3)
                        Capsule().fill(Color.nfAccent)
                            .frame(width: geo.size.width * CGFloat(pos / track.duration), height: 3)
                    }
                }
                .frame(height: 3)
            }
            .frame(height: 3)
            .padding(.top, 2)
        }
    }

    var artwork: some View {
        Group {
            if let data = track.artworkData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let art = track.artworkURL, let url = URL(string: art) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { fallback }
            } else {
                fallback
            }
        }
    }

    var fallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Theme.Palette.elevated)
            Image(systemName: "music.note").font(.system(size: 16)).foregroundColor(Theme.Palette.text)
        }
    }

    func transport(_ name: String, action: @escaping () -> Void) -> some View {
        NIconButton(symbol: name, label: transportLabel(name), size: 13, action: action)
    }
}

// A parked file as a card: big icon over its name. Drag the tile to pull the
// file back out; a ✕ badge appears on hover to remove it from the shelf.
struct FileTileView: View {
    let url: URL
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 20, height: 20)
            Text(url.lastPathComponent)
                .font(.system(size: 11))
                .foregroundColor(Theme.Palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 96, alignment: .leading)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(hovering ? .white : Color(white: 0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.15)))
        .help(url.path)
        .onHover { hovering = $0 }
        .onDrag {
            NSItemProvider(object: url as NSURL)
        } preview: {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        }
    }
}

/// Behind-window blur of the desktop, dark or light to match the panel's text.
struct FrostedGlass: NSViewRepresentable {
    var light = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        updateNSView(view, context: context)
        return view
    }

    // .popover is one of the lighter blurs, so more of the desktop shows.
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = .popover
        view.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
    }
}
