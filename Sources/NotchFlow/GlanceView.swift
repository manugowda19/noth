import EventKit
import SwiftUI

// Glance Home: one wide, short strip with everything at once — music, today,
// links, notes, focus — instead of stacked cards (inspired by NotchNest).
// Columns only appear for features that are on; each is a real, working
// widget, not a summary.
extension RootView {
    var glanceStrip: some View { stripCard(glanceColumns) }

    /// The one layout every Command Center tab uses: a single card of
    /// columns at a fixed height. Column widths come from the space actually
    /// available, so the strip can never overflow the panel; below ~880 pt it
    /// scrolls sideways at a comfortable width instead of squeezing.
    func stripCard(_ cols: [(Double, AnyView)]) -> some View {
        GeometryReader { geo in
            if geo.size.width >= 880 {
                stripRow(cols, width: geo.size.width)
            } else {
                ScrollView(.horizontal, showsIndicators: false) { stripRow(cols, width: 1000) }
            }
        }
        .frame(height: Layout.stripHeight)
        .nfCard(padding: Theme.Space.s)
    }

    /// (share of the strip width, column) for the columns that are on.
    private var glanceColumns: [(Double, AnyView)] {
        var cols: [(Double, AnyView)] = []
        // A meeting about to start leads the strip (a column, so the panel
        // height never changes).
        if let meeting = meetings.alert { cols.append((0.22, AnyView(meetingColumn(meeting)))) }
        // Nothing playing: no column at all, the others take the space.
        if nowPlayingManager.nowPlaying != nil { cols.append((0.23, AnyView(glanceMusic))) }
        if settings.showCalendarSection { cols.append((0.19, AnyView(glanceToday))) }
        if settings.showPins { cols.append((0.14, AnyView(glanceLinks))) }
        if settings.showQuickNotes { cols.append((0.27, AnyView(QuickNotesView(maxRows: 3)))) }
        cols.append((0.17, AnyView(glanceFocus)))
        return cols
    }

    private func stripRow(_ cols: [(Double, AnyView)], width: CGFloat) -> some View {
        let total = cols.reduce(0) { $0 + $1.0 }
        let usable = width - CGFloat(cols.count - 1)          // 1 pt dividers
        return HStack(alignment: .top, spacing: 0) {
            ForEach(cols.indices, id: \.self) { i in
                if i > 0 { divider }
                VStack(alignment: .leading, spacing: 0) { cols[i].1 }
                    .padding(.horizontal, Theme.Space.s)
                    .frame(width: usable * cols[i].0 / total, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: width, alignment: .leading)
    }

    var divider: some View {
        Rectangle().fill(Theme.Palette.border).frame(width: 1).padding(.vertical, 4)
    }


    // MARK: Music

    // One container view: as loose siblings inside AnyView they'd become extra
    // columns in the strip's HStack.
    private var glanceMusic: some View {
        VStack(alignment: .leading, spacing: 0) { glanceMusicContent }
    }

    @ViewBuilder
    private var glanceMusicContent: some View {
        if let track = nowPlayingManager.nowPlaying {
            HStack(alignment: .top, spacing: Theme.Space.s) {
                albumArt(track, size: 64, fallback: AnyView(EqualizerBars(levels: spectrum.levels)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(Theme.Typo.bodyEmphasis).foregroundColor(Theme.Palette.text)
                        .lineLimit(2)
                    Text(track.artist).font(Theme.Typo.label).foregroundColor(Theme.Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            HStack(spacing: 2) {
                transportButton("backward.fill") { nowPlayingManager.previousTrack() }
                transportButton(track.playing ? "pause.fill" : "play.fill") { nowPlayingManager.playPause() }
                transportButton("forward.fill") { nowPlayingManager.nextTrack() }
                Spacer(minLength: 0)
                if let levels = spectrum.levels { EqualizerBars(levels: levels) }
            }
        }
    }

    // MARK: Today

    @ViewBuilder
    private var glanceToday: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(now.formatted(.dateTime.weekday(.abbreviated)))
                    .font(Theme.Typo.title).foregroundColor(Theme.Palette.danger)
                Text(now.formatted(.dateTime.day().month(.abbreviated)))
                    .font(Theme.Typo.title).foregroundColor(Theme.Palette.text)
            }
            switch calendarManager.authorizationStatus {
            case .fullAccess:
                let upcoming = calendarManager.events
                    .filter { $0.isAllDay || $0.endDate > now }
                    .prefix(3)
                if upcoming.isEmpty {
                    Text("Nothing else today").font(Theme.Typo.label).foregroundColor(Theme.Palette.textSecondary)
                }
                ForEach(Array(upcoming), id: \.eventIdentifier) { event in
                    HStack(spacing: 6) {
                        Capsule().fill(Color(cgColor: event.calendar.cgColor)).frame(width: 3, height: 26)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(event.title).font(Theme.Typo.label).foregroundColor(Theme.Palette.text).lineLimit(1)
                            Text(event.isAllDay ? "All day"
                                 : event.startDate.formatted(date: .omitted, time: .shortened))
                                .font(Theme.Typo.caption).foregroundColor(Theme.Palette.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            case .notDetermined:
                NChip(title: "Allow Calendar") { calendarManager.requestAccess() }
            default:
                NChip(title: "Open Settings") { SystemSettingsLink.open("Privacy_Calendars") }
            }
        }
    }

    // MARK: Links

    private var glanceLinks: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LINKS").font(Theme.Typo.eyebrow).kerning(0.6).foregroundColor(Theme.Palette.textSecondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 8), count: 3),
                      alignment: .leading, spacing: 8) {
                ForEach(pins.links.prefix(8), id: \.self) { link in
                    Button { pins.open(link) } label: { LinkTile(link: link) }
                        .buttonStyle(NPressStyle())
                        .contextMenu { Button("Remove", role: .destructive) { pins.remove(link: link) } }
                }
                Button {
                    if !pins.pinClipboard() {
                        DeviceNoticeManager.shared.show(.init(symbol: "pin.slash", text: "Copy a link first",
                                                              style: .warning))
                    }
                } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.Palette.text)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.Palette.elevated))
                }
                .buttonStyle(NPressStyle())
                .help("Pin the link on your clipboard")
                .accessibilityLabel("Pin the link on your clipboard")
            }
        }
    }

    // MARK: Focus

    @ViewBuilder
    private var glanceFocus: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pomodoro.running ? "\(pomodoroPhaseName.uppercased()) · \(pomodoro.cycle.label)" : "FOCUS")
                .font(Theme.Typo.eyebrow).kerning(0.6)
                .foregroundColor(pomodoro.running ? Theme.Palette.warning : Theme.Palette.textSecondary)
            Text(pomodoro.running ? pomodoro.label : "25:00")
                .font(.system(size: 34, weight: .semibold)).monospacedDigit()
                .foregroundColor(pomodoro.running && !pomodoro.paused ? Theme.Palette.text : Theme.Palette.textSecondary)
                .accessibilityLabel(pomodoro.running ? "\(pomodoro.label) left" : "25 minutes")
            HStack(spacing: 2) {
                if pomodoro.running {
                    NIconButton(symbol: "arrow.counterclockwise", label: "Restart this phase") { pomodoro.restartPhase() }
                    NIconButton(symbol: pomodoro.paused ? "play.fill" : "pause.fill",
                                label: pomodoro.paused ? "Resume" : "Pause") { pomodoro.togglePause() }
                    NIconButton(symbol: "forward.end.fill", label: "Skip to next phase") { pomodoro.skip() }
                    NIconButton(symbol: "stop.fill", label: "Stop", tint: Theme.Palette.textSecondary) { pomodoro.stop() }
                } else {
                    NChip(title: "Start focus", icon: "play.fill") { pomodoro.start(workMinutes: 25) }
                }
            }
        }
    }

    private func meetingColumn(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MEETING").font(Theme.Typo.eyebrow).kerning(0.6).foregroundColor(Theme.Palette.accent)
            Text(meeting.title).font(Theme.Typo.bodyEmphasis).foregroundColor(Theme.Palette.text).lineLimit(2)
            Text(meeting.start.formatted(date: .omitted, time: .shortened))
                .font(Theme.Typo.label).foregroundColor(Theme.Palette.textSecondary)
            HStack(spacing: 4) {
                if meeting.joinURL != nil {
                    NChip(title: "Join", icon: "video.fill", selected: true) { meetings.join() }
                }
                NChip(title: "Dismiss") { meetings.dismiss() }
            }
        }
    }
}
