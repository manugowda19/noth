import SwiftUI

/// Command Center sections. Tabs navigate (they never act) and are always
/// present; a section with nothing enabled shows an empty state instead.
enum CommandTab: String, CaseIterable {
    case home, shelf, media, time, tools

    var title: String {
        switch self {
        case .home: "Home"
        case .shelf: "Shelf"
        case .media: "Media"
        case .time: "Time"
        case .tools: "Tools"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .shelf: "tray.full"
        case .media: "play.circle"
        case .time: "clock"
        case .tools: "wrench.and.screwdriver"
        }
    }
}

// The expanded Island: NØTH's Command Center. A fixed header (identity, tabs,
// live status, settings) over one scrolling section, so adding widgets never
// crushes or overlaps the layout — the cause of the v2.5 overlap bug.
extension RootView {
    @ViewBuilder
    var commandCenter: some View {
        if coordinator.showSettings {
            SettingsView(settings: settings) { coordinator.showSettings = false }
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                commandHeader
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        tabContent
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(coordinator.tab)   // fresh scroll position per section
            }
        }
    }

    // Two rows. The first is notch-height and only uses the wings — its middle
    // sits behind the camera housing, so nothing goes there. Tabs get the full
    // width on the row below the notch line.
    private var commandHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Text("NØTH")
                    .font(.system(size: 13, weight: .bold))
                    .kerning(2)
                    .foregroundColor(Theme.Palette.text)
                    .fixedSize()
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Layout.collapsedSize.width)   // keep clear of the notch
                headerStatus
                NIconButton(symbol: "gearshape", label: "Settings") { coordinator.showSettings = true }
            }
            .frame(height: max(20, Layout.collapsedSize.height - 8))
            .environment(\.colorScheme, .dark)   // sits on the black notch band
            HStack(spacing: 4) {
                ForEach(CommandTab.allCases, id: \.self) { tab in
                    NChip(title: tab.title, icon: tab.icon, selected: coordinator.tab == tab) {
                        coordinator.tab = tab
                    }
                }
            }
            .fixedSize()
        }
    }

    // Live status in the header: mic mute (when enabled), a level HUD while a
    // key is pressed, otherwise weather + battery.
    @ViewBuilder
    private var headerStatus: some View {
        if settings.showPrivacy {
            NIconButton(symbol: privacy.muted ? "mic.slash.fill" : "mic.fill",
                        label: privacy.muted ? "Unmute microphone (⌥⌘M)" : "Mute microphone (⌥⌘M)",
                        tint: privacy.muted ? Theme.Palette.danger
                            : (privacy.micInUse ? Theme.Palette.microphone : Theme.Palette.text)) {
                privacy.toggleMute()
            }
        }
        if let hud = activeLevelHUD {
            levelPill(icon: hud.icon, level: hud.level)
        } else {
            if settings.showWeather, let w = weather.weather { weatherBadge(w).fixedSize() }
            if battery.hasBattery { batteryBadge.fixedSize() }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        if settings.homeGlance {
            // Uniform strip layout: same size and shape on every tab, and no
            // widget repeated across tabs.
            switch coordinator.tab {
            case .home: glanceStrip
            case .shelf: shelfStrip
            case .media: mediaStrip
            case .time: timeStrip
            case .tools: toolsStrip
            }
        } else {
            switch coordinator.tab {
            case .home: homeTab
            case .shelf: shelfTab
            case .media: mediaTab
            case .time: timeTab
            case .tools: toolsTab
            }
        }
    }

    // MARK: Home — what matters right now

    @ViewBuilder
    private var homeTab: some View {
        if let meeting = meetings.alert {
            meetingCard(meeting).nfCard()
        }
        if let track = nowPlayingManager.nowPlaying {
            NowPlayingPanel(track: track, manager: nowPlayingManager).nfCard()
        }
        if settings.showCalendarSection || settings.showRemindersSection {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                if settings.showCalendarSection {
                    cardMenu(CalendarView(calendar: calendarManager)
                        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 190, alignment: .top)
                        .nfCard(), \.showCalendarSection, "Calendar")
                }
                if settings.showRemindersSection {
                    cardMenu(ScrollView { ReminderView(manager: reminderManager) }
                        .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 190, alignment: .top)
                        .nfCard(), \.showRemindersSection, "Reminders")
                }
            }
        }
        if settings.showQuickNotes {
            cardMenu(VStack(alignment: .leading, spacing: Theme.Space.s) {
                NSectionHeader("Notes")
                QuickNotesView()
            }.nfCard(), \.showQuickNotes, "Notes")
        }
        if settings.showDayProgress {
            cardMenu(DayProgressView(calendar: calendarManager, reminders: reminderManager).nfCard(),
                     \.showDayProgress, "Day progress")
        }
        if !recent.items.isEmpty {
            recentCard.nfCard()
        }
        if meetings.alert == nil && nowPlayingManager.nowPlaying == nil
            && !settings.showCalendarSection && !settings.showRemindersSection && !settings.showDayProgress {
            emptyState("Your day at a glance",
                       "Turn on Calendar, Reminders or Day progress to fill Home.")
        }
    }

    // Recent results that outlive their 3-second notice: one action each.
    private var recentCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            NSectionHeader(title: "Recent") {
                NChip(title: "Clear", help: "Clear recent activity") { recent.clear() }
            }
            ForEach(recent.items.prefix(4)) { item in
                HStack(spacing: Theme.Space.s) {
                    if item.kind == .color, let c = Tools.components(item.detail) {
                        RoundedRectangle(cornerRadius: 4).fill(Color(red: c.0, green: c.1, blue: c.2))
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: item.symbol).font(.system(size: 12))
                            .foregroundColor(Theme.Palette.textSecondary).frame(width: 16)
                    }
                    Text(item.title).font(Theme.Typo.body).foregroundColor(Theme.Palette.text)
                        .lineLimit(1).truncationMode(.middle)
                    Text(item.date, style: .relative).font(Theme.Typo.caption)
                        .foregroundColor(Theme.Palette.textTertiary).fixedSize()
                    Spacer(minLength: Theme.Space.s)
                    NChip(title: item.actionTitle, help: "\(item.actionTitle) \(item.title)") { recent.perform(item) }
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    // MARK: Shelf — files, clipboard, pins

    @ViewBuilder
    private var shelfTab: some View {
        if settings.homeGlance && !recent.items.isEmpty {
            recentCard.nfCard()
        }
        filesSection
            .frame(height: 176)
            .nfCard(padding: Theme.Space.s)
        if settings.showClipboard {
            cardMenu(
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                NSectionHeader("Clipboard")
                if clipboard.clips.isEmpty {
                    Text("Copied text appears here.")
                        .font(Theme.Typo.label).foregroundColor(Theme.Palette.textSecondary)
                } else {
                    clipboardBar
                }
            }
            .nfCard(), \.showClipboard, "Clipboard")
        }
        if settings.showPins {
            cardMenu(
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                NSectionHeader("Pinned")
                pinsBar
            }
            .nfCard(), \.showPins, "Pinned")
        }
    }

    // MARK: Media — playback, output, ambience

    @ViewBuilder
    private var mediaTab: some View {
        if let track = nowPlayingManager.nowPlaying {
            NowPlayingPanel(track: track, manager: nowPlayingManager).nfCard()
        } else {
            NStatusBanner(icon: "play.circle", title: "Nothing playing",
                          message: "Play something in any app — Music, Spotify, a browser — and it shows up here.",
                          tint: Theme.Palette.textSecondary)
                .nfCard()
        }
        if settings.showOutputSwitcher {
            cardMenu(
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                NSectionHeader("Output")
                outputSwitcherBar
            }
            .nfCard(), \.showOutputSwitcher, "Output")
        }
        if settings.showFocusSounds {
            cardMenu(
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                NSectionHeader("Focus sounds")
                focusSoundsBar
            }
            .nfCard(), \.showFocusSounds, "Focus sounds")
        }
    }

    // MARK: Time — timers and focus

    @ViewBuilder
    private var timeTab: some View {
        pomodoroCard.nfCard()
        if settings.showStopwatch {
            cardMenu(stopwatchBar.nfCard(), \.showStopwatch, "Stopwatch")
        }
        if settings.showScreenTime && !screenTime.ranked.isEmpty {
            cardMenu(
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                NSectionHeader("Screen time")
                screenTimeBar
            }
            .nfCard(), \.showScreenTime, "Screen time")
        }
    }

    // Pomodoro from the Time tab (it used to live only in Settings).
    private var pomodoroCard: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: pomodoro.running && pomodoro.phase == .rest ? "cup.and.saucer.fill" : "timer")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.Palette.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(pomodoro.running ? "\(pomodoroPhaseName) · \(pomodoro.cycle.label)" : "Pomodoro")
                    .font(Theme.Typo.bodyEmphasis).foregroundColor(Theme.Palette.text)
                Text(pomodoro.running ? pomodoro.label : "4 sessions · 5-min breaks · 15-min long break")
                    .font(pomodoro.running ? Theme.Typo.value : Theme.Typo.label)
                    .foregroundColor(pomodoro.running ? Theme.Palette.text : Theme.Palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if pomodoro.running {
                NIconButton(symbol: pomodoro.paused ? "play.fill" : "pause.fill",
                            label: pomodoro.paused ? "Resume" : "Pause") { pomodoro.togglePause() }
                NIconButton(symbol: "forward.end.fill", label: "Skip to next phase") { pomodoro.skip() }
                NChip(title: "Stop", icon: "stop.fill") { pomodoro.stop() }
            } else {
                ForEach([15, 25, 50], id: \.self) { minutes in
                    NChip(title: "\(minutes) min", help: "Start a \(minutes)-minute focus session") {
                        pomodoro.start(workMinutes: minutes)
                    }
                }
            }
        }
    }

    // MARK: Tools — utilities and system

    @ViewBuilder
    private var toolsTab: some View {
        if settings.showTools { cardMenu(toolsBar.nfCard(), \.showTools, "Tools") }
        if settings.showSystemStats {
            cardMenu(
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                NSectionHeader("System")
                systemStatsBar
            }
            .nfCard(), \.showSystemStats, "System stats")
        }
        if settings.showBluetooth && !bluetooth.devices.isEmpty {
            cardMenu(bluetoothBar.nfCard(), \.showBluetooth, "Bluetooth")
        }
        if settings.showLauncher {
            cardMenu(
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                NSectionHeader("Apps")
                launcherBar
            }
            .nfCard(), \.showLauncher, "App launcher")
        }
        if !settings.showTools && !settings.showSystemStats && !settings.showLauncher && !settings.showBluetooth {
            emptyState("No tools yet",
                       "Turn on Tools, System stats or the App launcher to fill this section.")
        }
    }

    /// Right-click a card to hide it or jump to Settings — options live where
    /// they take effect (settings.md › Task-specific options).
    private func cardMenu<V: View>(_ view: V, _ key: ReferenceWritableKeyPath<AppSettings, Bool>,
                                   _ name: String) -> some View {
        view.contextMenu {
            Button("Hide \(name)") { settings[keyPath: key] = false }
            Button("Customize…") { coordinator.showSettings = true }
        }
    }

    private func emptyState(_ title: String, _ message: String) -> some View {
        NStatusBanner(icon: "square.dashed", title: title, message: message,
                      tint: Theme.Palette.textSecondary,
                      actionTitle: "Customize") { coordinator.showSettings = true }
            .nfCard()
    }
}
