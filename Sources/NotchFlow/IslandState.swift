import Foundation

/// What the NØTH Island is showing. One explicit state, resolved from the
/// signals below by a pure function — instead of scattered booleans that can
/// contradict each other mid-animation.
enum IslandState: Equatable {
    case collapsed     // bare pill, matches the hardware notch
    case peek          // hover strip
    case drop          // file being dragged over / just dropped
    case hud           // a wing: level HUD, notice, or a persistent activity
    case musicLive     // resting live activity for playing media
    case cleanMode     // keyboard-cleaning lock countdown
    case expanded      // Command Center
    case settings      // Command Center showing settings

    /// The two full-size Command Center states.
    var isBig: Bool { self == .expanded || self == .settings }
}

/// Every input that can affect the Island, already folded to booleans.
struct IslandSignals: Equatable {
    var expanded = false        // user opened the Command Center
    var showSettings = false
    var dropShowing = false     // drag over the notch or post-drop confirmation
    var levelHUD = false        // volume / brightness / keyboard backlight
    var peeking = false         // pointer over the notch
    var musicPlaying = false
    var cleaning = false        // clean-mode keyboard lock
    /// Brief events that take over even the music live activity (battery
    /// flash, due reminder, finished download, meeting, Caps Lock, notices).
    var transient = false
    /// Ongoing activities that only replace the *resting* pill (Pomodoro,
    /// stopwatch, download in progress, camera/mic in use, battery wings).
    var persistent = false
}

enum IslandStateMachine {
    /// Priority, highest first: clean mode › Command Center › drop › level HUD
    /// › transient event › hover peek › music › persistent activity › pill.
    static func resolve(_ s: IslandSignals) -> IslandState {
        if s.cleaning { return .cleanMode }
        if s.expanded { return s.showSettings ? .settings : .expanded }
        if s.dropShowing { return .drop }
        if s.levelHUD { return .hud }
        if s.transient { return .hud }        // a live flash trumps peek and music
        if s.peeking { return .peek }
        if s.musicPlaying { return .musicLive }
        if s.persistent { return .hud }       // only the resting pill is promoted
        return .collapsed
    }
}
