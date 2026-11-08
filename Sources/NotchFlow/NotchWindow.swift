import AppKit
import SwiftUI
import Combine

// A borderless, non-activating panel pinned directly under the notch.
// Modeled on boring.notch: an NSPanel at menu-bar level draws the shelf *over*
// the menu bar so it hugs the notch, instead of hiding in the dead zone beneath
// it. Non-activating: interacting with it never pulls focus from your current app.
final class NotchWindow: NSPanel {

    /// The Island's states and priority rules live in IslandStateMachine
    /// (pure, unit-tested); this window only gathers signals and animates.

    private let coordinator = AppCoordinator.shared
    private var expansionObserver: AnyCancellable?
    private var displayObserver: AnyCancellable?
    private var keyboardObservers: Set<AnyCancellable> = []
    private var hoverTimer: Timer?
    private var shelfState: IslandState = .collapsed

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        // No window shadow: the shelf should read as a seamless extension of
        // the hardware notch, not a floating card — a shadow halo around a
        // shape this small/dark made it look bigger than its actual bounds.
        hasShadow = false
        isFloatingPanel = true
        hidesOnDeactivate = false          // stay put when another app is focused
        level = .mainMenu + 3              // draw above the menu bar, at the notch
        collectionBehavior = [.canJoinAllSpaces, .stationary,
                              .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = false
        isMovable = false

        // The window auto-resizes its contentView to fill the content rect, so
        // the hosting view always matches the window's animated frame — no
        // manual sizing. RootView fills that and pins content to the top, which
        // is what makes the height-grow read as a top-down curtain.
        let hosting = NSHostingView(rootView: RootView(coordinator: coordinator))
        // NotchWindow owns the frame; the hosting view must NOT push its
        // content's intrinsic size back to the window (empty sizingOptions),
        // else tall content like the settings panel balloons the window
        // (measured 1127pt) and the hover zone no longer matches, so it
        // collapses unexpectedly.
        hosting.sizingOptions = []
        contentView = hosting

        // Shelf state is the combination of hover expansion and the transient
        // volume HUD: expanded wins, then HUD, then the collapsed pill.
        // `.dropFirst()` skips the value published at subscribe time so we
        // don't animate at launch — the initial collapsed frame is set below.
        // Any of the level HUDs (volume / brightness / keyboard backlight)
        // collapse into one "a HUD is showing" flag — combineLatest tops out at
        // a 4-tuple, and they drive the same wing state.
        let levelHUD = Publishers
            .CombineLatest3(VolumeManager.shared.$hudVisible,
                            BrightnessManager.shared.$hudVisible,
                            KeyboardBacklightManager.shared.$hudVisible)
            .map { $0 || $1 || $2 }
        // Fold the three non-expanded flags into one publisher so `base` stays
        // within CombineLatest's arity: a transient HUD wins, then hover-peek,
        // then the resting music live activity, else the bare pill.
        // A drag over the notch, or the brief post-drop confirmation, both show
        // the compact drop surface (spec §2 State 3).
        let dropShowing = coordinator.$dropActive
            .combineLatest(coordinator.$justAdded.map { $0 != nil })
            .map { $0 || $1 }
        let flags = Publishers
            .CombineLatest4(levelHUD,
                            NowPlayingManager.shared.$nowPlaying,
                            coordinator.$isPeeking,
                            dropShowing)
        let base = coordinator.$isExpanded
            .combineLatest(flags)
            .map { expanded, flags -> IslandSignals in
                let (hud, nowPlaying, peeking, drop) = flags
                return IslandSignals(expanded: expanded, dropShowing: drop, levelHUD: hud,
                                     peeking: peeking, musicPlaying: nowPlaying?.playing == true)
            }
        // Two promotion signals fold the many wing sources into a 4-tuple:
        //  - transient: a battery flash, a due-reminder companion, a finished
        //    download or a meeting about to start — takes over even the music
        //    live activity while it lasts.
        //  - persistent: always-on battery wings, a running Pomodoro, an
        //    in-progress download or camera/mic in use (or mic muted) — promote
        //    the *resting* pill only, so music keeps its live activity.
        let transient = Publishers
            .CombineLatest4(BatteryManager.shared.$hudVisible,
                            ReminderManager.shared.$justDue.map { $0 != nil },
                            DownloadsManager.shared.$justFinished.map { $0 != nil },
                            MeetingAlertManager.shared.$alert.map { $0 != nil })
            .map { $0 || $1 || $2 || $3 }
            .combineLatest(CapsLockManager.shared.$hudVisible,
                           DeviceNoticeManager.shared.$notice.map { $0 != nil },
                           BreakReminderManager.shared.$reminderVisible)
            .map { $0 || $1 || $2 || $3 }
        let privacy = PrivacyManager.shared
        let privacyShowing = Publishers
            .CombineLatest3(privacy.$micInUse, privacy.$cameraInUse, privacy.$muted)
            .map { $0 || $1 || $2 }
        let persistent = Publishers
            .CombineLatest4(AppSettings.shared.$showBatteryInNotch,
                            PomodoroManager.shared.$running,
                            DownloadsManager.shared.$activeCount.map { $0 > 0 },
                            privacyShowing)
            .map { $0 || $1 || $2 || $3 }
            .combineLatest(StopwatchManager.shared.$running)
            .map { $0 || $1 }
        // Clean mode overrides everything; while expanded, the settings panel
        // uses a taller frame.
        expansionObserver = base
            .combineLatest(CleanModeManager.shared.$active,
                           coordinator.$showSettings,
                           transient)
            .combineLatest(persistent)
            .map { tuple, persistent -> IslandState in
                var signals = tuple.0
                signals.cleaning = tuple.1
                signals.showSettings = tuple.2
                signals.transient = tuple.3
                signals.persistent = persistent
                return IslandStateMachine.resolve(signals)
            }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.transition(to: state)
            }

        // Notch geometry is measured from NSScreen, so re-measure and
        // reposition whenever displays change (external monitor plugged in,
        // resolution/scaling changed, etc.) instead of staying stuck at the
        // size/position computed at launch.
        observeKeyboard()
        observeSizeChanges()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // Re-pin to the chosen display when the user changes the preference.
        displayObserver = AppSettings.shared.$preferredDisplayID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.reposition(for: self.size(for: self.shelfState))
            }

        installMouseTracking()
        reposition(for: Layout.collapsedSize)
    }

    // MARK: - Hover tracking
    //
    // Expand/collapse is decided by polling the mouse's position against
    // *fixed* geometry (the notch rect when collapsed, the full expanded rect
    // when open), not by a SwiftUI tracking area on the resizing content — that
    // churns during the animation and flips the state on and off, stalling it
    // mid-open. A cheap ~25 Hz poll of `NSEvent.mouseLocation` is immune to that
    // and needs no permissions (mouse location is always readable).
    // ponytail: timer poll, 25 Hz; move to an NSEvent monitor if idle CPU ever
    // shows up in a profile.
    private func installMouseTracking() {
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            self?.updateHover()
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func updateHover() {
        // Keyboard locked = leave the countdown up; don't let a hover expand it.
        guard !CleanModeManager.shared.active else { return }
        // A file drag owns the notch — don't let the hover poll churn peek state
        // underneath the drop surface.
        guard !coordinator.dropActive else { return }
        guard let screen = NotchWindow.notchScreen() else { return }
        let mouse = NSEvent.mouseLocation

        // Expanded is intentional (a click) — hover only *collapses* it, once
        // the mouse leaves the whole hub. Zone must match the actual open size
        // (settings is taller), else the mouse reads as outside and it snaps shut.
        if coordinator.isExpanded {
            let openSize = coordinator.showSettings ? Layout.settingsSize : Layout.expandedSize
            let zone = frame(for: openSize, on: screen).insetBy(dx: -2, dy: -2)
            if zone.contains(mouse) {
                // The pointer took over: from now on, leaving closes it.
                if coordinator.keyboardOpen { coordinator.keyboardOpen = false }
            } else if !coordinator.keyboardOpen {
                coordinator.closeCommandCenter()
            }
            return
        }

        // Not expanded: hover the notch/peek zone reveals the compact peek strip
        // (spec §2 State 2). Hysteresis is automatic — while peeking, `frame` is
        // already the wider peek strip, so it stays open until the mouse leaves it.
        let inside = frame.insetBy(dx: -2, dy: -2).contains(mouse)
        if inside != coordinator.isPeeking { coordinator.isPeeking = inside }
    }

    @objc private func screenParametersChanged() {
        // Snap (no animation) to the correct geometry for the current state.
        reposition(for: size(for: shelfState))
    }

    // MARK: - State transitions
    //
    // The shelf should look like the hardware notch coming alive, not a card
    // sliding in from the screen. Expansion runs in two phases:
    //   1. Widen from the notch's own width to full width, still at notch
    //      height — the notch appears to stretch sideways from the camera.
    //   2. Grow the height *downward* — the panel drops open like a blind, top
    //      edge fixed at the screen top. RootView pins its content to the top,
    //      so this reveals content from the top down rather than sliding it up.
    // Collapse reverses the order. The HUD shares the notch's height, so
    // collapsed ⇄ hud is a single sideways stretch with no vertical phase.
    private func transition(to new: IslandState) {
        guard new != shelfState, let screen = NotchWindow.notchScreen() else { return }
        let old = shelfState
        shelfState = new
        let target = frame(for: size(for: new), on: screen)
        let wide = NSSize(width: Layout.expandedSize.width,
                          height: Layout.collapsedSize.height)

        // Reduce Motion: one short cross-size change, no stretch-then-drop.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            animateFrame(to: target, duration: 0.01, curve: .linear)
            return
        }

        switch (old.isBig, new.isBig) {
        case (false, true):
            // Quick sideways stretch, then the slower, prominent downward drop.
            animateFrame(to: frame(for: wide, on: screen), duration: 0.12, curve: .easeOut) {
                [weak self] in
                guard let self, self.shelfState.isBig else { return }
                self.animateFrame(to: self.frame(for: self.size(for: self.shelfState), on: screen),
                                  duration: 0.24, curve: .easeOut)
            }
        case (true, false):
            // Roll the blind back up first, then narrow to the pill or HUD.
            animateFrame(to: frame(for: wide, on: screen), duration: 0.18, curve: .easeIn) {
                [weak self] in
                guard let self, self.shelfState == new else { return }
                self.animateFrame(to: target, duration: 0.12, curve: .easeIn)
            }
        case (true, true):
            // expanded ⇄ settings: same width, just grow/shrink the height.
            animateFrame(to: target, duration: 0.16, curve: .default)
        default:
            // collapsed ⇄ hud: same height, one sideways animation.
            animateFrame(to: target, duration: 0.15, curve: .easeOut)
        }
    }

    private func size(for state: IslandState) -> NSSize {
        switch state {
        case .collapsed: Layout.collapsedSize
        case .peek: Layout.peekSize
        case .drop: Layout.hudSize
        case .hud, .musicLive, .cleanMode: Layout.hudSize
        case .expanded: Layout.expandedSize
        case .settings: Layout.settingsSize
        }
    }

    private func animateFrame(to target: NSRect, duration: TimeInterval,
                              curve: CAMediaTimingFunctionName,
                              completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: curve)
            animator().setFrame(target, display: true)
        }, completionHandler: completion)
    }

    private func frame(for size: NSSize, on screen: NSScreen) -> NSRect {
        NotchGeometry.shelfFrame(screenFrame: screen.frame, size: size)
    }

    // Keep the shelf centered on the notch screen, anchored to the true top edge
    // (`screen.frame.maxY`) so it hangs from the notch / top of the display.
    private func reposition(for size: NSSize) {
        guard let screen = NotchWindow.notchScreen() else { return }
        setFrame(frame(for: size, on: screen), display: true)
    }

    /// The display the shelf lives on: the user's preferred one if connected,
    /// else the notched screen, else main (see `NotchGeometry.chooseDisplay`).
    /// Everything (window frame, hover zone, notch measure) routes through here,
    /// so the shelf and its hover math always agree on one screen — the fix for
    /// the old multi-display mis-trigger.
    static func notchScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let main = NSScreen.main
        let candidates = screens.map { screen in
            (id: displayID(of: screen),
             hasNotch: NotchGeometry.hasNotch(topSafeAreaInset: screen.safeAreaInsets.top),
             isMain: screen == main)
        }
        let chosen = NotchGeometry.chooseDisplay(
            preferredID: AppSettings.shared.preferredDisplayID, candidates: candidates)
        return screens.first { displayID(of: $0) == chosen } ?? main
    }

    static func displayID(of screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value ?? 0
    }

    /// The real hardware notch's size, measured from the current notch
    /// screen. `nil` when there isn't one (external display, older Mac) — the
    /// collapsed pill should fall back to a generic size in that case rather
    /// than guess at notch dimensions that don't exist.
    static func notchSize() -> NSSize? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["NOTH_NO_NOTCH"] != nil { return nil }
        #endif
        guard let screen = notchScreen(),
              NotchGeometry.hasNotch(topSafeAreaInset: screen.safeAreaInsets.top),
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea
        else { return nil }

        let width = NotchGeometry.notchWidth(leftArea: leftArea, rightArea: rightArea)
        guard width > 0 else { return nil }
        return NSSize(width: width, height: screen.safeAreaInsets.top)
    }

    // Borderless panels can't become key by default; allow it so chip drags work.
    override var canBecomeKey: Bool { true }

    // MARK: Keyboard (only when opened via ⌥⌘J / the menu — the panel is
    // non-activating, so the frontmost app stays active underneath)

    /// Esc: back out of Settings first, then close and return the keyboard.
    override func cancelOperation(_ sender: Any?) {
        if coordinator.showSettings { coordinator.showSettings = false } else { coordinator.closeCommandCenter() }
    }

    /// ⌘1–5 switch Command Center tabs; ⌘, opens the Settings window.
    /// An app-level local monitor, not performKeyEquivalent: the panel is key
    /// while the app stays inactive (no key-equivalent pass), and a focused
    /// text field (Quick notes) would otherwise swallow ⌘-digits first.
    private var commandKeyMonitor: Any?

    private func handleCommandKey(_ event: NSEvent) -> Bool {
        guard coordinator.isExpanded,
              // Only the four real modifiers — keypad/function flags are noise
              // (⌘2 from the keypad or automation carries .numericPad).
              event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
              let key = event.charactersIgnoringModifiers else { return false }
        if let n = Int(key), (1...CommandTab.allCases.count).contains(n) {
            coordinator.showSettings = false
            coordinator.tab = CommandTab.allCases[n - 1]
            return true
        }
        if key == "," { StatusMenuController.shared.openSettings(); return true }
        return false
    }

    /// Glance mode changes the panel size per tab — re-fit while open.
    private func observeSizeChanges() {
        coordinator.$tab.map { _ in () }
            .merge(with: AppSettings.shared.$homeGlance.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self, self.shelfState == .expanded,
                      let screen = NotchWindow.notchScreen() else { return }
                // Defer one runloop so `expandedSize` sees the new values.
                DispatchQueue.main.async {
                    self.animateFrame(to: self.frame(for: Layout.expandedSize, on: screen),
                                      duration: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.01 : 0.2,
                                      curve: .easeInEaseOut)
                }
            }
            .store(in: &keyboardObservers)
    }

    private func observeKeyboard() {
        commandKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self, self.handleCommandKey(event) else { return event }
            return nil
        }
        // Opened by keyboard/menu → take key status so keys reach the panel.
        coordinator.$keyboardOpen
            .removeDuplicates()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.makeKey() }
            .store(in: &keyboardObservers)
        // Closed → give up key status (re-ordering drops it) so typing goes
        // back to the app underneath.
        coordinator.$isExpanded
            .removeDuplicates()
            .filter { !$0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isKeyWindow else { return }
                self.orderOut(nil)
                self.orderFrontRegardless()
            }
            .store(in: &keyboardObservers)
    }

    deinit {
        hoverTimer?.invalidate()
    }
}
