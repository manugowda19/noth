import Foundation
import ServiceManagement

// The app's first real persisted preferences — gates what the expanded shelf
// shows. Plain ObservableObject backed by UserDefaults directly rather than
// @AppStorage, which is designed for use inside SwiftUI Views and doesn't
// reliably notify observers when used on a standalone class.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var showCalendarSection: Bool {
        didSet { UserDefaults.standard.set(showCalendarSection, forKey: "showCalendarSection") }
    }
    @Published var showRemindersSection: Bool {
        didSet { UserDefaults.standard.set(showRemindersSection, forKey: "showRemindersSection") }
    }

    /// Replace the system volume bezel with the notch HUD. Needs Accessibility
    /// permission; the toggle snaps back off when it isn't granted yet.
    @Published var hudReplacement: Bool {
        didSet {
            UserDefaults.standard.set(hudReplacement, forKey: "hudReplacement")
            if hudReplacement {
                if !MediaKeyInterceptor.shared.start() {
                    DispatchQueue.main.async { self.hudReplacement = false }
                }
            } else {
                MediaKeyInterceptor.shared.stop()
            }
        }
    }

    /// Start NotchFlow at login. SMAppService is the source of truth (no
    /// UserDefaults mirror); on failure the toggle snaps back to reality.
    @Published var launchAtLogin: Bool {
        didSet {
            guard oldValue != launchAtLogin else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                DispatchQueue.main.async {
                    self.launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
        }
    }

    /// Clean-mode keyboard-lock duration, seconds.
    @Published var cleanModeDuration: Int {
        didSet { UserDefaults.standard.set(cleanModeDuration, forKey: "cleanModeDuration") }
    }

    /// App launcher in the shelf: a row of favorite apps to click-launch.
    @Published var showLauncher: Bool {
        didSet { UserDefaults.standard.set(showLauncher, forKey: "showLauncher") }
    }
    /// Paths of launcher apps (.app bundles), persisted.
    @Published private(set) var launcherApps: [String] {
        didSet { UserDefaults.standard.set(launcherApps, forKey: "launcherApps") }
    }

    func addLauncherApp(_ path: String) {
        guard path.hasSuffix(".app"), !launcherApps.contains(path) else { return }
        launcherApps.append(path)
    }

    func removeLauncherApp(_ path: String) {
        launcherApps.removeAll { $0 == path }
    }

    /// Show the day-progress timeline (events + reminders vs now) in the shelf.
    @Published var showDayProgress: Bool {
        didSet { UserDefaults.standard.set(showDayProgress, forKey: "showDayProgress") }
    }

    /// Track & show self-tracked screen time (top apps today) in the shelf. Opt-in.
    @Published var showScreenTime: Bool {
        didSet {
            UserDefaults.standard.set(showScreenTime, forKey: "showScreenTime")
            if showScreenTime { ScreenTimeManager.shared.start() }
            else { ScreenTimeManager.shared.stop() }
        }
    }

    /// Keep the Mac awake (prevent idle sleep) via IOPMAssertion. Persists.
    @Published var keepAwake: Bool {
        didSet {
            UserDefaults.standard.set(keepAwake, forKey: "keepAwake")
            KeepAwakeManager.shared.set(keepAwake)
        }
    }

    /// Global action hotkeys (⌥⌘N/P/S). Opt-in — needs Input Monitoring, prompted
    /// by macOS on first enable.
    @Published var globalShortcuts: Bool {
        didSet {
            UserDefaults.standard.set(globalShortcuts, forKey: "globalShortcuts")
            if globalShortcuts { ShortcutManager.shared.start() }
            else { ShortcutManager.shared.stop() }
        }
    }

    /// Show connected Bluetooth devices' battery in the open shelf. Opt-in —
    /// polling `system_profiler` only runs while on.
    @Published var showBluetooth: Bool {
        didSet {
            UserDefaults.standard.set(showBluetooth, forKey: "showBluetooth")
            if showBluetooth { BluetoothManager.shared.start() }
            else { BluetoothManager.shared.stop() }
        }
    }

    /// Keep the battery % + icon always visible in the collapsed notch (persistent
    /// wings). Opt-in — off by default it leaves the resting pill bare and notch-sized.
    @Published var showBatteryInNotch: Bool {
        didSet { UserDefaults.standard.set(showBatteryInNotch, forKey: "showBatteryInNotch") }
    }

    /// Which display to pin the shelf to (`CGDirectDisplayID`). 0 = auto (prefer
    /// the notched display). Lets multi-display users force the shelf onto a
    /// specific screen; auto falls back gracefully when it's unplugged.
    @Published var preferredDisplayID: UInt32 {
        didSet { UserDefaults.standard.set(Int(preferredDisplayID), forKey: "preferredDisplayID") }
    }

    /// Bottom corner radius of the shelf — a light theme knob. The pill stays
    /// black to blend with the notch; only the roundness is user-tunable.
    /// ponytail: radius only. Notch color/material deferred — recoloring the
    /// pill breaks the seamless-notch look and needs a product call first.
    @Published var cornerRadius: Double {
        didSet { UserDefaults.standard.set(cornerRadius, forKey: "cornerRadius") }
    }

    /// Show a little companion that peeks from the notch when a reminder is due.
    @Published var showCompanion: Bool {
        didSet { UserDefaults.standard.set(showCompanion, forKey: "showCompanion") }
    }

    /// Show local weather in the open shelf. Opt-in — starting it prompts for
    /// location the first time.
    @Published var showWeather: Bool {
        didSet {
            UserDefaults.standard.set(showWeather, forKey: "showWeather")
            if showWeather { WeatherManager.shared.start() }
            else { WeatherManager.shared.stop() }
        }
    }

    /// Keep a short in-memory clipboard history in the shelf. Opt-in — polling
    /// only runs while on, and secrets are never captured.
    @Published var showClipboard: Bool {
        didSet {
            UserDefaults.standard.set(showClipboard, forKey: "showClipboard")
            if showClipboard { ClipboardManager.shared.start() }
            else { ClipboardManager.shared.stop() }
        }
    }

    /// Synced lyrics under Now Playing. Opt-in — sends the track's title and
    /// artist to lrclib.net.
    @Published var showLyrics: Bool {
        didSet { UserDefaults.standard.set(showLyrics, forKey: "showLyrics") }
    }

    /// Download progress in the notch. Opt-in — reading ~/Downloads prompts
    /// for the Downloads folder once.
    @Published var showDownloads: Bool {
        didSet {
            UserDefaults.standard.set(showDownloads, forKey: "showDownloads")
            if showDownloads { DownloadsManager.shared.start() }
            else { DownloadsManager.shared.stop() }
        }
    }

    /// Camera/mic in-use indicator in the notch, plus mic mute (shelf button,
    /// ⌥⌘M with global shortcuts). Opt-in.
    @Published var showPrivacy: Bool {
        didSet {
            UserDefaults.standard.set(showPrivacy, forKey: "showPrivacy")
            if showPrivacy { PrivacyManager.shared.start() }
            else { PrivacyManager.shared.stop() }
        }
    }

    /// "Meeting soon" alert in the notch with a Join button in the shelf.
    /// Opt-in; uses the calendar access already granted for Calendar.
    @Published var meetingAlerts: Bool {
        didSet {
            UserDefaults.standard.set(meetingAlerts, forKey: "meetingAlerts")
            if meetingAlerts { MeetingAlertManager.shared.start() }
            else { MeetingAlertManager.shared.stop() }
        }
    }

    /// Audio-reactive bars next to the playing track. Opt-in — taps system
    /// audio output (asks for System Audio Recording once).
    @Published var showVisualizer: Bool {
        didSet { UserDefaults.standard.set(showVisualizer, forKey: "showVisualizer") }
    }

    /// Now Playing / next event / weather card on the lock screen. Opt-in and
    /// experimental — uses a private SkyLight space (see LockScreenSpace).
    @Published var lockScreenWidgets: Bool {
        didSet {
            UserDefaults.standard.set(lockScreenWidgets, forKey: "lockScreenWidgets")
            if lockScreenWidgets { LockScreenManager.shared.start() }
            else { LockScreenManager.shared.stop() }
        }
    }

    /// Flash a wing when Caps Lock turns on/off. Opt-in.
    @Published var capsLockHUD: Bool {
        didSet {
            UserDefaults.standard.set(capsLockHUD, forKey: "capsLockHUD")
            if capsLockHUD { CapsLockManager.shared.start() } else { CapsLockManager.shared.stop() }
        }
    }

    /// Output-device picker card in the shelf. Opt-in.
    @Published var showOutputSwitcher: Bool {
        didSet { UserDefaults.standard.set(showOutputSwitcher, forKey: "showOutputSwitcher") }
    }

    /// CPU / memory / network card in the shelf. Opt-in — samples every 2 s.
    @Published var showSystemStats: Bool {
        didSet {
            UserDefaults.standard.set(showSystemStats, forKey: "showSystemStats")
            if showSystemStats { SystemStatsManager.shared.start() } else { SystemStatsManager.shared.stop() }
        }
    }

    /// Notch notice when a drive mounts/ejects or a display (dis)connects.
    @Published var deviceNotices: Bool {
        didSet {
            UserDefaults.standard.set(deviceNotices, forKey: "deviceNotices")
            if deviceNotices { DeviceNoticeManager.shared.start() } else { DeviceNoticeManager.shared.stop() }
        }
    }

    /// "Time for a break" after 50 minutes of continuous activity. Opt-in.
    @Published var breakReminders: Bool {
        didSet {
            UserDefaults.standard.set(breakReminders, forKey: "breakReminders")
            if breakReminders { BreakReminderManager.shared.start() } else { BreakReminderManager.shared.stop() }
        }
    }

    /// Stopwatch card in the shelf. Opt-in.
    @Published var showStopwatch: Bool {
        didSet { UserDefaults.standard.set(showStopwatch, forKey: "showStopwatch") }
    }

    /// Tools card in the shelf: color picker, QR scan, emoji palette. Opt-in.
    @Published var showTools: Bool {
        didSet { UserDefaults.standard.set(showTools, forKey: "showTools") }
    }

    /// Focus-sounds card (generated white/pink/brown noise). Opt-in.
    @Published var showFocusSounds: Bool {
        didSet {
            UserDefaults.standard.set(showFocusSounds, forKey: "showFocusSounds")
            if !showFocusSounds { FocusSoundsManager.shared.stop() }
        }
    }

    /// Pinned snippets & links card in the shelf. Opt-in.
    @Published var showPins: Bool {
        didSet { UserDefaults.standard.set(showPins, forKey: "showPins") }
    }

    /// ⌃⌥ arrow window snapping. Opt-in; works through the global-shortcuts
    /// key monitor, so it also needs Global shortcuts on (Accessibility).
    @Published var windowSnapping: Bool {
        didSet { UserDefaults.standard.set(windowSnapping, forKey: "windowSnapping") }
    }

    /// Menu-bar item with Open / Settings… ⌘, / Quit. On by default — it's
    /// the standard way into an agent app's settings.
    @Published var showMenuBarIcon: Bool {
        didSet {
            UserDefaults.standard.set(showMenuBarIcon, forKey: "showMenuBarIcon")
            StatusMenuController.shared.setMenuBarIconVisible(showMenuBarIcon)
        }
    }

    /// Feature toggles back to first-launch values (off, except Calendar and
    /// Reminders). Leaves data alone: shelf files, pins, launcher apps.
    func resetToDefaults() {
        let off: [ReferenceWritableKeyPath<AppSettings, Bool>] = [
            \.showCompanion, \.showWeather, \.showClipboard, \.showBluetooth, \.globalShortcuts,
            \.keepAwake, \.showScreenTime, \.showDayProgress, \.showLauncher, \.showBatteryInNotch,
            \.hudReplacement, \.showLyrics, \.showDownloads, \.showPrivacy, \.meetingAlerts,
            \.showVisualizer, \.lockScreenWidgets, \.capsLockHUD, \.showOutputSwitcher,
            \.showSystemStats, \.deviceNotices, \.breakReminders, \.showStopwatch, \.showTools,
            \.showFocusSounds, \.showPins, \.windowSnapping, \.showQuickNotes, \.siteIcons,
        ]
        for key in off where self[keyPath: key] { self[keyPath: key] = false }
        showCalendarSection = true
        showRemindersSection = true
        homeGlance = true
        glassPanel = false
        lightPanel = false
        showMenuBarIcon = true
        cornerRadius = 14
        cleanModeDuration = 30
    }

    /// Inline quick notes (color tags) on Home. Opt-in.
    @Published var showQuickNotes: Bool {
        didSet { UserDefaults.standard.set(showQuickNotes, forKey: "showQuickNotes") }
    }

    /// Fetch each pinned site's own icon (once, cached). Off: monogram tiles.
    @Published var siteIcons: Bool {
        didSet {
            UserDefaults.standard.set(siteIcons, forKey: "siteIcons")
            if !siteIcons { SiteIconStore.shared.clearCache() }
        }
    }

    /// Home tab layout: "glance" — one wide strip, everything at once — or
    /// "cards" — the stacked cards.
    @Published var homeGlance: Bool {
        didSet { UserDefaults.standard.set(homeGlance, forKey: "homeGlance") }
    }

    /// See-through Command Center (frosted glass over the desktop) instead of
    /// solid black. The collapsed pill and the notch band stay black.
    @Published var glassPanel: Bool {
        didSet { UserDefaults.standard.set(glassPanel, forKey: "glassPanel") }
    }

    /// Light frosted glass with dark text (needs Glass panel).
    @Published var lightPanel: Bool {
        didSet { UserDefaults.standard.set(lightPanel, forKey: "lightPanel") }
    }

    private init() {
        let defaults = UserDefaults.standard
        glassPanel = defaults.bool(forKey: "glassPanel")
        lightPanel = defaults.bool(forKey: "lightPanel")
        showCalendarSection = defaults.object(forKey: "showCalendarSection") as? Bool ?? true
        showRemindersSection = defaults.object(forKey: "showRemindersSection") as? Bool ?? true
        hudReplacement = defaults.object(forKey: "hudReplacement") as? Bool ?? false
        cleanModeDuration = defaults.object(forKey: "cleanModeDuration") as? Int ?? 30
        cornerRadius = defaults.object(forKey: "cornerRadius") as? Double ?? 14
        showBluetooth = defaults.object(forKey: "showBluetooth") as? Bool ?? false
        globalShortcuts = defaults.object(forKey: "globalShortcuts") as? Bool ?? false
        keepAwake = defaults.object(forKey: "keepAwake") as? Bool ?? false
        showScreenTime = defaults.object(forKey: "showScreenTime") as? Bool ?? false
        showDayProgress = defaults.object(forKey: "showDayProgress") as? Bool ?? false
        showLauncher = defaults.object(forKey: "showLauncher") as? Bool ?? false
        launcherApps = defaults.stringArray(forKey: "launcherApps") ?? []
        showBatteryInNotch = defaults.object(forKey: "showBatteryInNotch") as? Bool ?? false
        preferredDisplayID = UInt32(defaults.object(forKey: "preferredDisplayID") as? Int ?? 0)
        showCompanion = defaults.object(forKey: "showCompanion") as? Bool ?? false
        showWeather = defaults.object(forKey: "showWeather") as? Bool ?? false
        showClipboard = defaults.object(forKey: "showClipboard") as? Bool ?? false
        showLyrics = defaults.object(forKey: "showLyrics") as? Bool ?? false
        showDownloads = defaults.object(forKey: "showDownloads") as? Bool ?? false
        showPrivacy = defaults.object(forKey: "showPrivacy") as? Bool ?? false
        meetingAlerts = defaults.object(forKey: "meetingAlerts") as? Bool ?? false
        showVisualizer = defaults.object(forKey: "showVisualizer") as? Bool ?? false
        lockScreenWidgets = defaults.object(forKey: "lockScreenWidgets") as? Bool ?? false
        showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        capsLockHUD = defaults.object(forKey: "capsLockHUD") as? Bool ?? false
        showOutputSwitcher = defaults.object(forKey: "showOutputSwitcher") as? Bool ?? false
        showSystemStats = defaults.object(forKey: "showSystemStats") as? Bool ?? false
        deviceNotices = defaults.object(forKey: "deviceNotices") as? Bool ?? false
        breakReminders = defaults.object(forKey: "breakReminders") as? Bool ?? false
        showStopwatch = defaults.object(forKey: "showStopwatch") as? Bool ?? false
        showTools = defaults.object(forKey: "showTools") as? Bool ?? false
        showFocusSounds = defaults.object(forKey: "showFocusSounds") as? Bool ?? false
        showPins = defaults.object(forKey: "showPins") as? Bool ?? false
        showQuickNotes = defaults.object(forKey: "showQuickNotes") as? Bool ?? false
        siteIcons = defaults.object(forKey: "siteIcons") as? Bool ?? false
        homeGlance = defaults.object(forKey: "homeGlance") as? Bool ?? true
        windowSnapping = defaults.object(forKey: "windowSnapping") as? Bool ?? false
        launchAtLogin = SMAppService.mainApp.status == .enabled

        // didSet doesn't fire during init: start the interceptor for a stored
        // "on" without prompting — if permission was revoked since, flip off.
        if hudReplacement, !MediaKeyInterceptor.shared.start(promptIfNeeded: false) {
            hudReplacement = false
        }
        // didSet doesn't fire in init: resume weather if it was on (location
        // grant persists, so no re-prompt).
        if showWeather { WeatherManager.shared.start() }
        if showClipboard { ClipboardManager.shared.start() }
        if showDownloads { DownloadsManager.shared.start() }
        if showPrivacy { PrivacyManager.shared.start() }
        if meetingAlerts { MeetingAlertManager.shared.start() }
        if lockScreenWidgets { LockScreenManager.shared.start() }
        if capsLockHUD { CapsLockManager.shared.start() }
        if showSystemStats { SystemStatsManager.shared.start() }
        if deviceNotices { DeviceNoticeManager.shared.start() }
        if breakReminders { BreakReminderManager.shared.start() }
        if showBluetooth { BluetoothManager.shared.start() }
        if globalShortcuts { ShortcutManager.shared.start() }
        if showScreenTime { ScreenTimeManager.shared.start() }
        if keepAwake { KeepAwakeManager.shared.set(true) }
    }
}
