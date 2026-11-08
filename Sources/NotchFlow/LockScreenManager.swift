import AppKit
import SwiftUI

// Lock-screen widget: a glass card under the lock clock with what's playing
// (plus the current lyric when lyrics are on), the next event today and the
// weather. Opt-in (`AppSettings.lockScreenWidgets`) — it relies on the private
// SkyLight space in LockScreenSpace, and does nothing if that's unavailable.
// Display-only: the card ignores the mouse, so nothing on it can be operated
// while the Mac is locked.
// ponytail: main (notch) screen only; per-display cards if anyone runs a
// locked external display they look at.
final class LockScreenManager {
    static let shared = LockScreenManager()

    private var window: NSPanel?
    private var space: LockScreenSpace?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    var isAvailable: Bool { LockScreenSpace.isAvailable }

    func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        observers = [
            center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) {
                [weak self] _ in self?.present()
            },
            center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) {
                [weak self] _ in self?.dismiss()
            },
        ]
    }

    func stop() {
        observers.forEach(DistributedNotificationCenter.default().removeObserver)
        observers = []
        dismiss()
    }

    private func present() {
        guard window == nil, let screen = NotchWindow.notchScreen(),
              let space = LockScreenSpace() else { return }
        let host = NSHostingView(rootView: LockScreenCard())
        let size = NSSize(width: 400, height: 150)
        // Centered, its top ~34% down the screen — below the lock clock, well
        // above the avatar/password field.
        let f = screen.frame
        let origin = NSPoint(x: f.midX - size.width / 2, y: f.maxY - f.height * 0.34 - size.height)
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = host
        panel.orderFrontRegardless()   // needs a window number before moving spaces
        space.add([panel])
        window = panel
        self.space = space
    }

    private func dismiss() {
        window?.orderOut(nil)
        space?.tearDown()
        window?.close()
        window = nil
        space = nil
    }
}

private struct LockScreenCard: View {
    @ObservedObject private var nowPlaying = NowPlayingManager.shared
    @ObservedObject private var lyrics = LyricsManager.shared
    @ObservedObject private var calendar = CalendarManager.shared
    @ObservedObject private var weather = WeatherManager.shared
    @ObservedObject private var settings = AppSettings.shared

    private var nextEvent: (title: String, start: Date)? {
        let now = Date()
        return calendar.events
            .first { !$0.isAllDay && $0.startDate > now && Calendar.current.isDateInToday($0.startDate) }
            .map { ($0.title ?? "Event", $0.startDate) }
    }

    var body: some View {
        VStack(spacing: 10) {
            if let track = nowPlaying.nowPlaying {
                HStack(spacing: 12) {
                    art(track).frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(track.artist).font(.system(size: 12)).opacity(0.7).lineLimit(1)
                        if let lyrics = lyrics.lyrics {
                            // Coarse (no interpolation) — the poll's position is
                            // good enough for a glance at the lock screen.
                            Text(lyrics.line(at: track.position) ?? "")
                                .font(.system(size: 12, weight: .medium)).foregroundColor(.nfAccent)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: track.playing ? "waveform" : "pause.fill")
                        .font(.system(size: 14)).opacity(0.7)
                }
            }
            HStack(spacing: 14) {
                if let event = nextEvent {
                    Label {
                        Text("\(event.title) · \(event.start.formatted(date: .omitted, time: .shortened))")
                            .lineLimit(1)
                    } icon: { Image(systemName: "calendar") }
                }
                Spacer(minLength: 0)
                if settings.showWeather, let w = weather.weather {
                    Label(w.label, systemImage: w.symbol).monospacedDigit()
                }
            }
            .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(14)
        .frame(width: 400)
        .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
        .opacity(hasContent ? 1 : 0)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var hasContent: Bool {
        nowPlaying.nowPlaying != nil || nextEvent != nil || (settings.showWeather && weather.weather != nil)
    }

    @ViewBuilder private func art(_ track: NowPlaying) -> some View {
        if let data = track.artworkData, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFill()
        } else if let s = track.artworkURL, let url = URL(string: s) {
            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.1) }
        } else {
            ZStack { Color.white.opacity(0.1); Image(systemName: "music.note") }
        }
    }
}
