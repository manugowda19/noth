import SwiftUI

// The customization panel behind the home icon. Toggles are data (one
// `Item` per feature) shown as grouped two-column sections, with filter pills
// to jump to a group — no search field, since the notch panel is a poor text-
// input host (Notes and the Quick bar get their own key windows for that).
// Rows that need a macOS permission say which.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var pomodoro = PomodoroManager.shared
    @State private var pomWork = 25
    @State private var filter: Category = .all
    @State private var confirmReset = false
    /// Back to the Command Center; nil in the standalone Settings window
    /// (which closes with its own window button).
    let onBack: (() -> Void)?

    enum Category: String, CaseIterable {
        case all = "All", media = "Media", time = "Time", shelf = "Shelf"
        case alerts = "Alerts", system = "System", more = "More"
    }

    private struct Item {
        let group: Category
        let icon: String
        let tint: Color
        let label: String
        let key: ReferenceWritableKeyPath<AppSettings, Bool>
        var hint: String? = nil
    }

    private var items: [Item] {
        var list: [Item] = [
            // Media
            Item(group: .media, icon: "quote.bubble.fill", tint: .indigo, label: "Synced lyrics",
                 key: \.showLyrics, hint: "Sends title/artist to lrclib.net"),
            Item(group: .media, icon: "waveform", tint: .pink, label: "Audio visualizer",
                 key: \.showVisualizer, hint: "System Audio Recording"),
            Item(group: .media, icon: "hifispeaker.2.fill", tint: .teal, label: "Audio output switcher",
                 key: \.showOutputSwitcher),
            Item(group: .media, icon: "leaf.fill", tint: .green, label: "Focus sounds", key: \.showFocusSounds),
            // Time
            Item(group: .system, icon: "circle.lefthalf.filled", tint: .cyan, label: "Glass panel",
                 key: \.glassPanel, hint: "See-through panel and hover strip; the notch stays black"),
            Item(group: .system, icon: "sun.max.fill", tint: .yellow, label: "Light glass",
                 key: \.lightPanel, hint: "Light frosted glass, dark text · needs Glass panel"),
            Item(group: .time, icon: "rectangle.split.3x1.fill", tint: .indigo, label: "Glance Home",
                 key: \.homeGlance, hint: "One wide strip — music, today, links, notes, focus"),
            Item(group: .time, icon: "calendar", tint: .red, label: "Show Calendar",
                 key: \.showCalendarSection, hint: "Calendars"),
            Item(group: .time, icon: "checklist", tint: .orange, label: "Show Reminders",
                 key: \.showRemindersSection, hint: "Reminders"),
            Item(group: .time, icon: "sparkles", tint: .yellow, label: "Reminder companion", key: \.showCompanion),
            Item(group: .time, icon: "note.text", tint: .yellow, label: "Quick notes",
                 key: \.showQuickNotes, hint: "Type in the notch · color tags"),
            Item(group: .time, icon: "video.badge.checkmark", tint: .blue, label: "Meeting alerts",
                 key: \.meetingAlerts, hint: "Calendars"),
            Item(group: .time, icon: "figure.walk", tint: .green, label: "Break reminders", key: \.breakReminders),
            Item(group: .time, icon: "stopwatch.fill", tint: .orange, label: "Stopwatch", key: \.showStopwatch),
            Item(group: .time, icon: "chart.bar.xaxis", tint: .mint, label: "Day progress", key: \.showDayProgress),
            Item(group: .time, icon: "hourglass", tint: .pink, label: "Screen time", key: \.showScreenTime),
            // Shelf
            Item(group: .shelf, icon: "cloud.sun.fill", tint: .cyan, label: "Weather",
                 key: \.showWeather, hint: "Location"),
            Item(group: .shelf, icon: "wrench.and.screwdriver.fill", tint: .indigo,
                 label: "Tools", key: \.showTools, hint: "Color picker · QR · emoji · quick bar"),
            Item(group: .shelf, icon: "pin.fill", tint: .red, label: "Pinned snippets & links", key: \.showPins),
            Item(group: .shelf, icon: "globe", tint: .blue, label: "Site icons for links",
                 key: \.siteIcons, hint: "Fetched once from each pinned site"),
            Item(group: .shelf, icon: "doc.on.clipboard", tint: .indigo, label: "Clipboard history",
                 key: \.showClipboard),
            Item(group: .shelf, icon: "cpu", tint: .mint, label: "System stats", key: \.showSystemStats),
            Item(group: .shelf, icon: "wave.3.right", tint: .blue, label: "Bluetooth battery", key: \.showBluetooth),
            Item(group: .shelf, icon: "square.grid.2x2", tint: .purple, label: "App launcher", key: \.showLauncher),
            // Alerts (notch wings)
            Item(group: .alerts, icon: "arrow.down.circle.fill", tint: .green, label: "Download progress",
                 key: \.showDownloads, hint: "Downloads folder"),
            Item(group: .alerts, icon: "mic.fill", tint: .orange, label: "Camera & mic indicator",
                 key: \.showPrivacy, hint: "Mute: ⌥⌘M"),
            Item(group: .alerts, icon: "capslock.fill", tint: .yellow, label: "Caps Lock HUD", key: \.capsLockHUD),
            Item(group: .alerts, icon: "externaldrive.fill", tint: .gray, label: "Drive & display notices",
                 key: \.deviceNotices),
            Item(group: .alerts, icon: "battery.100", tint: .green, label: "Battery in notch",
                 key: \.showBatteryInNotch),
            // System
            Item(group: .system, icon: "power", tint: .green, label: "Launch at login", key: \.launchAtLogin),
            Item(group: .system, icon: "menubar.rectangle", tint: .gray, label: "Menu bar icon",
                 key: \.showMenuBarIcon, hint: "Open · Settings… ⌘, · Quit"),
            Item(group: .system, icon: "speaker.wave.2.fill", tint: .blue, label: "Replace system HUD",
                 key: \.hudReplacement, hint: "Accessibility"),
            Item(group: .system, icon: "command", tint: .gray, label: "Global shortcuts",
                 key: \.globalShortcuts, hint: "Input Monitoring · ⌥⌘ K quick bar, N notes, P pomodoro, S shot, M mute"),
            Item(group: .system, icon: "rectangle.split.2x1.fill", tint: .blue, label: "Window snapping",
                 key: \.windowSnapping, hint: "⌃⌥ ← → ↑ ↩ · needs Global shortcuts"),
            Item(group: .system, icon: "moon.zzz.fill", tint: .yellow, label: "Keep awake", key: \.keepAwake),
        ]
        if LockScreenManager.shared.isAvailable {
            list.append(Item(group: .media, icon: "lock.rectangle.stack.fill", tint: .gray,
                             label: "Lock screen widget", key: \.lockScreenWidgets, hint: "Experimental"))
        }
        return list
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.Palette.text)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color(white: 0.2)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to Command Center")
                }
                Text("Customize")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.Palette.text)
                Spacer()
                Text("NØTH \(appVersion)")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.Palette.textSecondary)
            }
            // Group filter — pinned under the header.
            HStack(spacing: 5) {
                ForEach(Category.allCases, id: \.self) { g in
                    pill(g.rawValue, selected: filter == g) { filter = g }
                }
            }

            // Scrollable so adding settings never needs another panel-height
            // bump — the header and filter stay pinned, the rest scrolls.
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    settingsBody
                }
            }
        }
    }

    @ViewBuilder
    private var settingsBody: some View {
        ForEach(Category.allCases.filter { $0 != .all && $0 != .more }, id: \.self) { group in
            if filter == .all || filter == group {
                let rows = items.filter { $0.group == group }
                if !rows.isEmpty { section(group.rawValue.uppercased(), rows) }
            }
        }
        if filter == .all || filter == .more {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("MORE")
                cornerRadiusRow
                // Only worth showing with more than one display.
                if NSScreen.screens.count > 1 { displayRow }
                cleanModeRow
                pomodoroRow
                resetRow
            }
        }
    }

    private func section(_ title: String, _ rows: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())],
                      alignment: .leading, spacing: 8) {
                ForEach(rows, id: \.label) { item in
                    row(item)
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Theme.Palette.textSecondary)
            .kerning(0.5)
    }

    // Reset feature toggles. Two-step: the first click arms it, the second
    // resets — no modal alert in the notch panel, and no accidental wipe.
    private var resetRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.Palette.text)
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.gray))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Reset to defaults").font(.system(size: 11)).foregroundColor(Theme.Palette.text)
                Text(confirmReset ? "Turns every feature back off. Files, pins and apps are kept."
                                  : "Feature switches only")
                    .font(.system(size: 10)).foregroundColor(Theme.Palette.textSecondary)
            }
            Spacer(minLength: 8)
            if confirmReset {
                NChip(title: "Cancel") { confirmReset = false }
                NChip(title: "Reset", selected: true, help: "Confirm reset to defaults") {
                    settings.resetToDefaults()
                    confirmReset = false
                }
            } else {
                NChip(title: "Reset…") { confirmReset = true }
            }
        }
    }

    // Pomodoro: pick a work length and Start; while running, show the countdown
    // and a Stop button. Break is a fixed 5 min.
    private var pomodoroRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.Palette.text)
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.orange))
            Text("Pomodoro")
                .font(.system(size: 11))
                .foregroundColor(Theme.Palette.text)
                .fixedSize()
            Spacer(minLength: 8)
            if pomodoro.running {
                Text(pomodoro.label)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Theme.Palette.text)
                Button("Stop") { pomodoro.stop() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                    .font(.system(size: 11))
            } else {
                ForEach([15, 25, 50], id: \.self) { minutes in
                    pill("\(minutes)m", selected: pomWork == minutes) { pomWork = minutes }
                }
                Button("Start") { pomodoro.start(workMinutes: pomWork) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .font(.system(size: 11))
            }
        }
    }

    // Which display the shelf pins to. "Auto" prefers the notched screen.
    private var displayRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "display")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.Palette.text)
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.blue))
            Text("Display")
                .font(.system(size: 11))
                .foregroundColor(Theme.Palette.text)
                .fixedSize()
            Spacer(minLength: 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    pill("Auto", selected: settings.preferredDisplayID == 0) {
                        settings.preferredDisplayID = 0
                    }
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        let id = NotchWindow.displayID(of: screen)
                        pill(screen.localizedName, selected: settings.preferredDisplayID == id) {
                            settings.preferredDisplayID = id
                        }
                    }
                }
            }
        }
    }

    private func pill(_ label: String, selected: Bool, _ tap: @escaping () -> Void) -> some View {
        NChip(title: label, selected: selected, action: tap)
    }

    // Shelf roundness — three presets, custom pills (native controls render
    // dark-on-black here). The pill stays black; only the corners change.
    private var cornerRadiusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.roundedbottom")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.Palette.text)
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.teal))
            Text("Corners")
                .font(.system(size: 11))
                .foregroundColor(Theme.Palette.text)
                .fixedSize()
            Spacer(minLength: 8)
            ForEach([(8.0, "Subtle"), (14.0, "Default"), (22.0, "Round")], id: \.0) { radius, label in
                pill(label, selected: settings.cornerRadius == radius) { settings.cornerRadius = radius }
            }
        }
    }

    // Lock the keyboard for a set interval so you can wipe it. Countdown shows
    // in the notch; mouse-hold cancels early.
    private var cleanModeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.Palette.text)
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.purple))
            Text("Clean mode")
                .font(.system(size: 11))
                .foregroundColor(Theme.Palette.text)
                .fixedSize()
            Spacer(minLength: 8)
            // Custom pills: native segmented/menu renders dark-on-black here,
            // so unselected options were invisible. These stay legible.
            ForEach([15, 30, 60], id: \.self) { seconds in
                pill("\(seconds)s", selected: settings.cleanModeDuration == seconds) {
                    settings.cleanModeDuration = seconds
                }
            }
            Button("Start") { CleanModeManager.shared.start(seconds: settings.cleanModeDuration) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .font(.system(size: 11))
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.Palette.text)
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 5).fill(item.tint))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Palette.text)
                    .lineLimit(1)
                if let hint = item.hint {
                    Text(hint)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.Palette.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            Toggle("", isOn: Binding(get: { settings[keyPath: item.key] },
                                     set: { settings[keyPath: item.key] = $0 }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
    }
}
