import SwiftUI

// The non-Home tabs in the uniform strip layout. Home is the summary (music,
// today, links, notes, focus); each other tab holds *different* things, so no
// widget appears twice:
//   Shelf — files · clipboard · snippets · recent
//   Media — lyrics · output devices · focus sounds
//   Time  — stopwatch · reminders · day timeline + screen time
//   Tools — tools + color · system stats · apps · Bluetooth
// A column whose feature is off offers a one-click "Turn on"; one that is on
// but has nothing to show and nothing to do is left out, not shown blank.
extension RootView {
    // MARK: Shelf

    var shelfStrip: some View {
        var cols: [(Double, AnyView)] = [(0.40, AnyView(filesSection))]
        cols.append((0.20, AnyView(clipboardColumn)))
        cols.append((0.20, AnyView(snippetsColumn)))
        if !recent.items.isEmpty { cols.append((0.20, AnyView(recentColumn))) }
        return stripCard(cols)
    }

    @ViewBuilder
    private var clipboardColumn: some View {
        columnHeader("Clipboard")
        if !settings.showClipboard {
            turnOn("Keeps your last 8 text copies (RAM only).") { settings.showClipboard = true }
        } else if clipboard.clips.isEmpty {
            hint("Copied text appears here.")
        } else {
            ForEach(clipboard.clips.prefix(4), id: \.self) { clip in
                rowButton(clip, help: "Copy again") { clipboard.copy(clip) }
            }
        }
    }

    @ViewBuilder
    private var snippetsColumn: some View {
        HStack {
            columnHeader("Snippets")
            Spacer()
            if settings.showPins {
                NIconButton(symbol: "plus", label: "Pin the text on your clipboard", size: 11) {
                    if !pins.pinClipboard() {
                        DeviceNoticeManager.shared.show(.init(symbol: "pin.slash", text: "Nothing to pin", style: .warning))
                    }
                }
            }
        }
        if !settings.showPins {
            turnOn("Pin text and links you reuse.") { settings.showPins = true }
        } else if pins.snippets.isEmpty {
            hint("Copy text, then + to pin it.")
        } else {
            ForEach(pins.snippets.prefix(4), id: \.self) { snippet in
                rowButton(Pins.snippetTitle(snippet), help: "Copy") { pins.copy(snippet) }
                    .contextMenu { Button("Remove", role: .destructive) { pins.remove(snippet: snippet) } }
            }
        }
    }

    @ViewBuilder
    private var recentColumn: some View {
        columnHeader("Recent")
        ForEach(recent.items.prefix(4)) { item in
            HStack(spacing: 6) {
                Image(systemName: item.symbol).font(.system(size: 11))
                    .foregroundColor(Theme.Palette.textSecondary).frame(width: 14)
                Text(item.title).font(Theme.Typo.label).foregroundColor(Theme.Palette.text)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 2)
                Button(item.actionTitle) { recent.perform(item) }
                    .buttonStyle(.plain)
                    .font(Theme.Typo.caption).foregroundColor(Theme.Palette.accent)
            }
            .frame(height: 22)
        }
    }

    // MARK: Media

    var mediaStrip: some View {
        var cols: [(Double, AnyView)] = []
        // Lyrics need a song; without one the column would only be blank.
        if !settings.showLyrics || nowPlayingManager.nowPlaying != nil { cols.append((0.42, AnyView(lyricsColumn))) }
        cols.append((0.29, AnyView(outputColumn)))
        cols.append((0.29, AnyView(focusSoundsColumn)))
        return stripCard(cols)
    }

    @ViewBuilder
    private var lyricsColumn: some View {
        columnHeader("Lyrics")
        if !settings.showLyrics {
            turnOn("Synced lyrics for what's playing (lrclib.net).") { settings.showLyrics = true }
        } else if let track = nowPlayingManager.nowPlaying {
            LyricsColumn(track: track)
        }
    }

    @ViewBuilder
    private var outputColumn: some View {
        columnHeader("Output")
        if !settings.showOutputSwitcher {
            turnOn("Switch speakers, AirPods or a display.") { settings.showOutputSwitcher = true }
        } else {
            VStack(alignment: .leading, spacing: 0) {
            if audioOutput.devices.isEmpty { hint("Looking for outputs…") }
            ForEach(audioOutput.devices.prefix(4)) { device in
                let on = device.id == audioOutput.current
                Button { audioOutput.select(device) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: device.symbol).font(.system(size: 11))
                        Text(device.name).font(on ? Theme.Typo.bodyEmphasis : Theme.Typo.body).lineLimit(1)
                        Spacer(minLength: 0)
                        if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                    }
                    .foregroundColor(on ? Theme.Palette.text : Theme.Palette.textSecondary)
                    .frame(height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NPressStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            }
            .onAppear { audioOutput.refresh() }
        }
    }

    @ViewBuilder
    private var focusSoundsColumn: some View {
        columnHeader("Focus sounds")
        if !settings.showFocusSounds {
            turnOn("White, pink or brown noise, generated live.") { settings.showFocusSounds = true }
        } else {
            HStack(spacing: 4) {
                ForEach(NoiseGenerator.Kind.allCases, id: \.self) { kind in
                    NChip(title: kind.rawValue.capitalized, selected: focusSounds.playing == kind) {
                        focusSounds.toggle(kind)
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundColor(Theme.Palette.textSecondary)
                Slider(value: $focusSounds.volume, in: 0...1).controlSize(.mini)
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).foregroundColor(Theme.Palette.textSecondary)
            }
            .padding(.top, 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Focus sound volume")
        }
    }

    // MARK: Time

    var timeStrip: some View {
        stripCard([
            (0.24, AnyView(stopwatchColumn)),
            (0.38, AnyView(remindersColumn)),
            (0.38, AnyView(timelineColumn)),
        ])
    }

    @ViewBuilder
    private var stopwatchColumn: some View {
        columnHeader("Stopwatch")
        stopwatchTime(size: 30)
        HStack(spacing: 2) {
            NIconButton(symbol: stopwatch.running ? "pause.fill" : "play.fill",
                        label: stopwatch.running ? "Pause stopwatch" : "Start stopwatch") { stopwatch.toggle() }
            NIconButton(symbol: "arrow.counterclockwise", label: "Reset stopwatch") { stopwatch.reset() }
        }
    }

    @ViewBuilder
    private var remindersColumn: some View {
        if settings.showRemindersSection {
            ScrollView(showsIndicators: false) { ReminderView(manager: reminderManager) }
        } else {
            columnHeader("Reminders")
            turnOn("What's due, from your Reminders lists.") { settings.showRemindersSection = true }
        }
    }

    @ViewBuilder
    private var timelineColumn: some View {
        DayProgressView(calendar: calendarManager, reminders: reminderManager)
        columnHeader("Screen time").padding(.top, 10)
        if !settings.showScreenTime {
            turnOn("Which apps you used today (tracked on this Mac).") { settings.showScreenTime = true }
        } else if screenTime.ranked.isEmpty {
            hint("Building today's picture…")
        } else {
            ForEach(screenTime.ranked.prefix(3), id: \.app) { entry in
                HStack {
                    Text(entry.app).font(Theme.Typo.label).foregroundColor(Theme.Palette.text).lineLimit(1)
                    Spacer()
                    Text(ScreenTimeManager.format(entry.seconds))
                        .font(Theme.Typo.label).monospacedDigit().foregroundColor(Theme.Palette.textSecondary)
                }
            }
        }
    }

    // MARK: Tools

    var toolsStrip: some View {
        var cols: [(Double, AnyView)] = [
            (0.34, AnyView(toolsColumn)),
            (0.22, AnyView(statsColumn)),
            (0.22, AnyView(appsColumn)),
        ]
        if !settings.showBluetooth || !bluetooth.devices.isEmpty { cols.append((0.22, AnyView(bluetoothColumn))) }
        return stripCard(cols)
    }

    @ViewBuilder
    private var toolsColumn: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6, alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 6) {
            toolButton("eyedropper.halffull", "Pick color") { tools.pickColor() }
            toolButton("qrcode.viewfinder", "Scan QR") { tools.scanQR() }
            toolButton("face.smiling", "Emoji") { tools.showEmojiPalette() }
            toolButton("command", "Quick bar") { QuickBarController.shared.present() }
        }
        if let hex = tools.colors.first, let c = Tools.components(hex) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Color(red: c.0, green: c.1, blue: c.2))
                    .frame(width: 16, height: 16)
                Text(hex).font(Theme.Typo.bodyEmphasis).monospaced().foregroundColor(Theme.Palette.text)
                Spacer(minLength: 0)
                NChip(title: "Copy") { tools.copy(hex) }
            }
            .padding(.top, 8)
        }
        if let qr = tools.lastQR {
            HStack(spacing: 6) {
                Image(systemName: "qrcode").font(.system(size: 10)).foregroundColor(Theme.Palette.textSecondary)
                Text(qr.text).font(Theme.Typo.caption).foregroundColor(Theme.Palette.text)
                    .lineLimit(1).truncationMode(.middle)
                if let url = qr.url {
                    Spacer(minLength: 0)
                    NChip(title: "Open \(url.host ?? "link")") { tools.openLastQR() }
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var statsColumn: some View {
        columnHeader("System")
        if !settings.showSystemStats {
            turnOn("CPU, memory and network, every 2 s.") { settings.showSystemStats = true }
        } else {
            let s = stats.snapshot
            statRow("cpu", "CPU", "\(Int((s.cpu * 100).rounded()))%")
            statRow("memorychip", "Memory", SystemStats.formatGB(s.memoryUsed))
            statRow("arrow.down", "Down", SystemStats.formatRate(s.download))
            statRow("arrow.up", "Up", SystemStats.formatRate(s.upload))
        }
    }

    @ViewBuilder
    private var appsColumn: some View {
        columnHeader("Apps")
        if !settings.showLauncher {
            turnOn("Your favorite apps, one click away.") { settings.showLauncher = true }
        } else {
            launcherBar
        }
    }

    @ViewBuilder
    private var bluetoothColumn: some View {
        columnHeader("Bluetooth")
        if !settings.showBluetooth {
            turnOn("Battery of connected devices.") { settings.showBluetooth = true }
        } else {
            ForEach(bluetooth.devices.prefix(4), id: \.name) { device in
                statRow("wave.3.right", device.name, "\(device.battery)%")
            }
        }
    }

    // MARK: Shared column pieces

    func columnHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Theme.Typo.eyebrow).kerning(0.6)
            .foregroundColor(Theme.Palette.textSecondary)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(Theme.Typo.label).foregroundColor(Theme.Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Off-state for a column: what it does + a one-click "Turn on".
    private func turnOn(_ what: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            hint(what)
            NChip(title: "Turn on", icon: "power", action: action)
        }
    }

    private func rowButton(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.Typo.label).foregroundColor(Theme.Palette.text)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(NPressStyle())
        .help(help)
    }

    private func statRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10)).foregroundColor(Theme.Palette.textSecondary).frame(width: 14)
            Text(label).font(Theme.Typo.label).foregroundColor(Theme.Palette.textSecondary).lineLimit(1)
            Spacer(minLength: 4)
            Text(value).font(Theme.Typo.label).monospacedDigit().foregroundColor(Theme.Palette.text).lineLimit(1)
        }
        .frame(height: 20)
        .accessibilityElement(children: .combine)
    }
}

/// Live lyric lines for the Media tab: previous dimmed, current large, next
/// two dimmed — on an interpolated clock between Now Playing polls.
struct LyricsColumn: View {
    let track: NowPlaying
    @ObservedObject private var manager = LyricsManager.shared
    @State private var basePos: Double = 0
    @State private var baseAt = Date()

    var body: some View {
        if let lyrics = manager.lyrics { lines(lyrics) } else {
            Text("No synced lyrics for “\(track.title)”.")
                .font(Theme.Typo.label).foregroundColor(Theme.Palette.textSecondary)
        }
    }

    private func lines(_ lyrics: Lyrics) -> some View {
        TimelineView(.periodic(from: baseAt, by: 0.25)) { ctx in
            let pos = basePos + (track.playing ? max(0, ctx.date.timeIntervalSince(baseAt)) : 0)
            let idx = lyrics.lines.lastIndex { $0.time <= pos }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(-1...2, id: \.self) { offset in
                    let i = (idx ?? -1) + offset
                    let text = lyrics.lines.indices.contains(i) ? lyrics.lines[i].text : ""
                    Text(text.isEmpty && offset == 0 ? "♪" : text)
                        .font(offset == 0 ? .system(size: 15, weight: .semibold) : Theme.Typo.label)
                        .foregroundColor(offset == 0 ? Theme.Palette.text : Theme.Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: idx)
        }
        .onAppear { basePos = track.position; baseAt = Date() }
        .onChange(of: track.position) { basePos = track.position; baseAt = Date() }
        .accessibilityLabel("Lyrics")
    }
}
