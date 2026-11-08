import SwiftUI

// NØTH Island views: the hover peek and the live-activity wings.
//
// Geometry rule: the middle of the pill sits under the physical camera
// housing, so content goes in the two wings (left/right of the notch) or, in
// the taller peek, in a full-width row *below* the notch line. Wings that are
// showing while the pointer hovers (transient notices, meetings) stay
// clickable because the state machine keeps them over the peek.
extension RootView {
    /// Width of each wing beside the notch in the HUD-size pill.
    var hudWing: CGFloat { (Layout.hudSize.width - Layout.collapsedSize.width) / 2 - 20 }
    private var peekWing: CGFloat { (Layout.peekSize.width - Layout.collapsedSize.width) / 2 - 16 }

    // MARK: - Hover peek (context-aware)

    /// Top band: identity/weather left, battery + Command Center right. Below
    /// the notch line: controls for whatever is live — media, a timer — or
    /// quick actions. Clicking empty space opens the Command Center.
    var peekView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    if settings.showWeather, let w = weather.weather {
                        Image(systemName: w.symbol).font(.system(size: 11))
                        Text(w.label).font(Theme.Typo.label).monospacedDigit()
                    } else {
                        Text("NØTH").font(.system(size: 11, weight: .bold)).kerning(1.5)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundColor(Theme.Palette.text)
                .frame(width: peekWing)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    if battery.hasBattery { batteryBadge.fixedSize() }
                }
                .frame(width: peekWing)
            }
            .frame(height: Layout.collapsedSize.height)
            .environment(\.colorScheme, .dark)   // sits on the black notch band

            peekControls
                .padding(.horizontal, Theme.Space.s)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture { coordinator.isExpanded = true }
    }

    @ViewBuilder
    private var peekControls: some View {
        if let track = nowPlayingManager.nowPlaying {
            peekMedia(track)
        } else if pomodoro.running {
            peekTimer(icon: pomodoro.phase == .work ? "timer.circle.fill" : "cup.and.saucer.fill",
                      title: (pomodoro.paused ? "Paused" : pomodoroPhaseName) + " · " + pomodoro.cycle.label,
                      time: pomodoro.label, paused: pomodoro.paused,
                      onPause: pomodoro.togglePause, onReset: pomodoro.restartPhase,
                      resetLabel: "Restart this phase", onSkip: pomodoro.skip)
        } else if stopwatch.running {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "stopwatch.fill").font(.system(size: 18)).foregroundColor(Theme.Palette.warning)
                stopwatchTime(size: 20)
                Spacer(minLength: 0)
                NIconButton(symbol: "pause.fill", label: "Pause stopwatch", size: 14) { stopwatch.toggle() }
                NIconButton(symbol: "arrow.counterclockwise", label: "Reset stopwatch", size: 14) { stopwatch.reset() }
                openButton(.time)
            }
        } else {
            peekQuickActions
        }
    }

    private func peekMedia(_ track: NowPlaying) -> some View {
        HStack(spacing: Theme.Space.s) {
            albumArt(track, size: 30, fallback: AnyView(EqualizerBars(levels: spectrum.levels)))
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).font(Theme.Typo.bodyEmphasis).foregroundColor(Theme.Palette.text)
                if !track.artist.isEmpty {
                    Text(track.artist).font(Theme.Typo.label).foregroundColor(Theme.Palette.textSecondary)
                }
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            Spacer(minLength: Theme.Space.s)
            // Bars stand in for missing art (left); only repeat them here when
            // there *is* artwork.
            if let levels = spectrum.levels, track.artworkData != nil || track.artworkURL != nil {
                EqualizerBars(levels: levels)
            }
            transportButton("backward.fill") { nowPlayingManager.previousTrack() }
            transportButton(track.playing ? "pause.fill" : "play.fill") { nowPlayingManager.playPause() }
            transportButton("forward.fill") { nowPlayingManager.nextTrack() }
            openButton(.media)
        }
    }

    /// "Focus" / "Break" / "Long break" for the current Pomodoro phase.
    var pomodoroPhaseName: String {
        switch pomodoro.cycle.phase {
        case .work: "Focus"
        case .rest: "Break"
        case .longRest: "Long break"
        }
    }

    private func peekTimer(icon: String, title: String, time: String, paused: Bool,
                           onPause: @escaping () -> Void, onReset: @escaping () -> Void,
                           resetLabel: String, onSkip: (() -> Void)? = nil) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon).font(.system(size: 18, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Theme.Palette.warning)
            VStack(alignment: .leading, spacing: 0) {
                Text(title.uppercased()).font(Theme.Typo.eyebrow).kerning(0.6)
                    .foregroundColor(Theme.Palette.textSecondary)
                Text(time).font(.system(size: 20, weight: .semibold)).monospacedDigit()
                    .foregroundColor(paused ? Theme.Palette.textSecondary : Theme.Palette.text)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            NIconButton(symbol: paused ? "play.fill" : "pause.fill",
                        label: paused ? "Resume timer" : "Pause timer", size: 14, action: onPause)
            NIconButton(symbol: "arrow.counterclockwise", label: resetLabel, size: 14, action: onReset)
            if let onSkip {
                NIconButton(symbol: "forward.end.fill", label: "Skip to next phase", size: 14, action: onSkip)
            }
            openButton(.time)
        }
    }

    // Idle hover: the everyday actions, one click each.
    private var peekQuickActions: some View {
        HStack(spacing: 6) {
            NIconButton(symbol: "camera.viewfinder", label: "Screenshot to shelf", size: 14, filled: true) {
                coordinator.screenshot()
            }
            NIconButton(symbol: "qrcode.viewfinder", label: "Scan QR code", size: 14, filled: true) {
                tools.scanQR()
            }
            NIconButton(symbol: "eyedropper.halffull", label: "Pick color", size: 14, filled: true) {
                tools.pickColor()
            }
            NIconButton(symbol: "tray.full", label: "Open shelf", size: 14, filled: true) {
                coordinator.tab = .shelf
                coordinator.isExpanded = true
            }
            NIconButton(symbol: "timer", label: "Start 25-minute focus", size: 14, filled: true) {
                pomodoro.start(workMinutes: 25)
            }
            Spacer(minLength: 0)
            NIconButton(symbol: "gearshape", label: "Settings", size: 13) {
                coordinator.showSettings = true
                coordinator.isExpanded = true
            }
            openButton(nil)
        }
    }

    /// Chevron that opens the Command Center (optionally on a tab).
    private func openButton(_ tab: CommandTab?) -> some View {
        NIconButton(symbol: "chevron.down", label: "Open NØTH", size: 12) {
            if let tab { coordinator.tab = tab }
            coordinator.isExpanded = true
        }
    }

    // MARK: - Wings (notch height)

    /// Two-sided wing layout shared by every live activity.
    func wing<L: View, R: View>(@ViewBuilder _ left: () -> L, @ViewBuilder right: () -> R) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) { left(); Spacer(minLength: 0) }.frame(width: hudWing)
            Spacer(minLength: 0)
            HStack(spacing: 6) { Spacer(minLength: 0); right() }.frame(width: hudWing)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Media: art + live bars left, title right (controls live in the peek).
    func musicLiveActivity(_ track: NowPlaying) -> some View {
        wing {
            albumArt(track, size: 18, fallback: AnyView(EqualizerBars(levels: spectrum.levels)))
            if let levels = spectrum.levels, track.artworkData != nil || track.artworkURL != nil {
                EqualizerBars(levels: levels)
            }
        } right: {
            Text(track.title)
                .font(Theme.Typo.label).foregroundColor(Theme.Palette.text)
                .lineLimit(1).truncationMode(.tail)
        }
        .accessibilityLabel("Now playing \(track.title)\(track.artist.isEmpty ? "" : " by \(track.artist)")")
    }

    var pomodoroWing: some View {
        wing {
            Image(systemName: pomodoro.paused ? "pause.circle.fill"
                  : (pomodoro.phase == .work ? "timer.circle.fill" : "cup.and.saucer.fill"))
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(pomodoro.phase == .work ? Theme.Palette.warning : Theme.Palette.success)
        } right: {
            Text(pomodoro.label)
                .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                .foregroundColor(pomodoro.paused ? Theme.Palette.textSecondary : Theme.Palette.text)
        }
        .accessibilityLabel("\(pomodoro.phase == .work ? "Focus" : "Break") \(pomodoro.paused ? "paused, " : "")\(pomodoro.label) left")
    }

    var stopwatchWing: some View {
        wing {
            Image(systemName: "stopwatch.fill").font(.system(size: 13)).foregroundColor(Theme.Palette.warning)
        } right: {
            stopwatchTime(size: 14)
        }
    }

    /// Download: name left; a real progress bar + % right (spinner when the
    /// browser exposes no total). No cancel — another app owns the download.
    func downloadWing(_ name: String, progress: Double?) -> some View {
        wing {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 13)).foregroundColor(Theme.Palette.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text("Downloading").font(Theme.Typo.caption).foregroundColor(Theme.Palette.textSecondary)
                Text(name).font(Theme.Typo.caption).foregroundColor(Theme.Palette.text)
                    .lineLimit(1).truncationMode(.middle)
            }
        } right: {
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.Palette.accent)
                    .frame(width: 44)
                Text("\(Int(progress * 100))%")
                    .font(Theme.Typo.label).monospacedDigit().foregroundColor(Theme.Palette.text)
            } else {
                ProgressView().controlSize(.mini).colorScheme(.dark)
            }
            if downloads.activeCount > 1 {
                Text("+\(downloads.activeCount - 1)").font(Theme.Typo.caption)
                    .foregroundColor(Theme.Palette.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Downloading \(name)\(progress.map { ", \(Int($0 * 100)) percent" } ?? "")")
    }

    /// Brief notice: styled glyph left; message + dismiss right. Clickable
    /// while hovered (transient states keep priority over the peek).
    func noticeWing(_ notice: DeviceNoticeManager.Notice) -> some View {
        let tint: Color = switch notice.style {
        case .success: Theme.Palette.success
        case .warning: Theme.Palette.warning
        case .info: Theme.Palette.text
        }
        return wing {
            Image(systemName: notice.symbol).font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.monochrome).foregroundStyle(tint)
            Text(notice.text)
                .font(Theme.Typo.label).foregroundColor(Theme.Palette.text)
                .lineLimit(1).truncationMode(.tail)
        } right: {
            NIconButton(symbol: "xmark", label: "Dismiss", tint: Theme.Palette.textSecondary, size: 10) {
                deviceNotice.dismiss()
            }
            .frame(width: 22)
        }
    }

    /// Break reminder uses the same wing grammar.
    var breakWing: some View {
        wing {
            Image(systemName: "figure.walk").font(.system(size: 13)).foregroundColor(Theme.Palette.success)
        } right: {
            Text("Time for a break").font(Theme.Typo.label).foregroundColor(Theme.Palette.text).lineLimit(1)
        }
    }
}
