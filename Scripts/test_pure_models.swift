import Foundation

// Framework-free assert harness for FileStore/NotchGeometry — XCTest and Swift
// Testing both require full Xcode, which isn't installed here (see README).
// Run via Scripts/run_tests.sh.
@main
struct PureModelTests {
    static func testUpdateVersions() {
        assert(UpdateCheck.isNewer("v3.2.0", than: "3.1.0"), "minor bump is newer")
        assert(UpdateCheck.isNewer("3.10.0", than: "3.9.0"), "compared as numbers, not text")
        assert(!UpdateCheck.isNewer("3.1", than: "3.1.0"), "missing part counts as 0")
        assert(!UpdateCheck.isNewer("3.0.9", than: "3.1.0"), "older is not newer")
    }

    static func main() {
        testFileStore()
        testUpdateVersions()
        testNotchGeometry()
        testChooseDisplay()
        testBluetoothParse()
        testClipboardHistory()
        testDuePreset()
        testNowPlayingParse()
        testLyrics()
        testDownloads()
        testMeeting()
        testSpectrum()
        testSystemStats()
        testTimeKeeping()
        testTools()
        testCalculator()
        testNoise()
        testPinsAndSnap()
        testIslandStateMachine()
        testRecentActivity()
        testQuickNotes()
        testSiteIcons()
        testWeatherParse()
        print("All tests passed.")
    }

    static func testClipboardHistory() {
        // Security: never capture password-manager / secure-field clips.
        assert(!ClipboardHistory.shouldCapture(types: ["org.nspasteboard.ConcealedType"], text: "hunter2"),
               "concealed pasteboard must be skipped")
        assert(!ClipboardHistory.shouldCapture(types: ["com.apple.is-sensitive"], text: "secret"))
        assert(!ClipboardHistory.shouldCapture(types: ["public.utf8-plain-text"], text: "   "),
               "whitespace-only is not a clip")
        assert(!ClipboardHistory.shouldCapture(types: [], text: nil))
        assert(ClipboardHistory.shouldCapture(types: ["public.utf8-plain-text"], text: "hello"))

        // Ring: newest-first, de-duped, capped.
        var r = ClipboardHistory.insert("a", into: [], max: 3)
        r = ClipboardHistory.insert("b", into: r, max: 3)
        r = ClipboardHistory.insert("a", into: r, max: 3)   // re-copy → moves to front
        assert(r == ["a", "b"], "re-copy dedupes and moves to front")
        r = ClipboardHistory.insert("c", into: r, max: 3)
        r = ClipboardHistory.insert("d", into: r, max: 3)   // over cap → drop oldest
        assert(r == ["d", "c", "a"], "caps at max, oldest dropped")
    }

    static func testDuePreset() {
        let evening = Date(timeIntervalSince1970: 1_000_000)
        let tomorrow = Date(timeIntervalSince1970: 2_000_000)
        let presets: [Date?] = [evening, tomorrow, nil]

        assert(DuePreset.next(after: nil, in: presets) == evening, "nil (cleared) → first preset")
        assert(DuePreset.next(after: evening, in: presets) == tomorrow, "advance to next")
        assert(DuePreset.next(after: tomorrow, in: presets) == nil, "advance to clear")
        assert(DuePreset.next(after: evening.addingTimeInterval(30), in: presets) == tomorrow,
               "within 60s counts as the same preset")
        assert(DuePreset.next(after: Date(timeIntervalSince1970: 9_000_000), in: presets) == evening,
               "custom time not in list → first preset")
    }

    static func testWeatherParse() {
        let json = #"{"current":{"temperature_2m":12.6,"weather_code":3}}"#.data(using: .utf8)!
        let w = Weather.parse(json, unit: "°C")
        assert(w == Weather(temp: 13, unit: "°C", symbol: "cloud.fill"), "rounds temp, maps code 3 → overcast")
        assert(w?.label == "13°C")

        assert(Weather.parse(Data("garbage".utf8), unit: "°C") == nil, "bad JSON is not weather")
        assert(Weather.symbol(for: 0) == "sun.max.fill")
        assert(Weather.symbol(for: 95) == "cloud.bolt.rain.fill")
        assert(Weather.symbol(for: 61) == "cloud.rain.fill")
        assert(Weather.symbol(for: 999) == "cloud.fill", "unknown code falls back")
    }

    static func testNowPlayingParse() {
        let us = NowPlaying.separator
        // Fixed 6-field line: flag, title, artist, artwork, position, duration.
        let ok = NowPlaying.parse("1\(us)Green Light\(us)Lorde\(us)\(us)0\(us)0", app: .spotify)
        assert(ok == NowPlaying(app: .spotify, title: "Green Light", artist: "Lorde",
                                playing: true, artworkURL: nil, position: 0, duration: 0))

        let paused = NowPlaying.parse("0\(us)Song\(us)Artist\(us)\(us)0\(us)0", app: .music)
        assert(paused?.playing == false)

        // 4th field = artwork URL (Spotify); 5th/6th = position/duration seconds.
        let art = NowPlaying.parse("1\(us)T\(us)A\(us)https://i.scdn.co/x.jpg\(us)42.5\(us)180", app: .spotify)
        assert(art?.artworkURL == "https://i.scdn.co/x.jpg")
        assert(art?.position == 42.5 && art?.duration == 180)
        // Empty 4th field → no artwork.
        assert(NowPlaying.parse("1\(us)T\(us)A\(us)\(us)0\(us)0", app: .spotify)?.artworkURL == nil)

        assert(NowPlaying.parse("", app: .music) == nil, "empty output is not a track")
        assert(NowPlaying.parse("garbage", app: .music) == nil)
        assert(NowPlaying.parse("2\(us)a\(us)b\(us)\(us)0\(us)0", app: .music) == nil, "flag must be 0/1")
        assert(NowPlaying.parse("1\(us)only-two-fields", app: .music) == nil, "wrong field count rejected")

        // mediaremote-adapter `get --now` JSON.
        let yt = NowPlaying.parseAdapter(Data("""
            {"bundleIdentifier":"com.google.Chrome","playing":true,"title":"Vid","artist":"Ch",
             "duration":200,"elapsedTime":10,"elapsedTimeNow":12.5,"artworkData":"AQID"}
            """.utf8))
        assert(yt?.app == nil && yt?.title == "Vid" && yt?.artist == "Ch" && yt?.playing == true)
        assert(yt?.position == 12.5 && yt?.duration == 200, "prefers elapsedTimeNow")
        assert(yt?.artworkData == Data([1, 2, 3]))
        let sp = NowPlaying.parseAdapter(Data(#"{"bundleIdentifier":"com.spotify.client","playing":false,"title":"S","elapsedTime":3}"#.utf8))
        assert(sp?.app == .spotify && sp?.playing == false && sp?.position == 3 && sp?.artist == "")
        assert(NowPlaying.parseAdapter(Data("null".utf8)) == nil, "null = nothing playing")
        assert(NowPlaying.parseAdapter(Data(#"{"playing":true,"title":""}"#.utf8)) == nil, "no title")
        assert(NowPlaying.parseAdapter(Data("junk".utf8)) == nil)
    }

    static func testSiteIcons() {
        let u = URL(string: "https://www.github.com/manugowda19?tab=repos")!
        assert(SiteIcon.candidates(for: u).map(\.absoluteString)
               == ["https://www.github.com/apple-touch-icon.png", "https://www.github.com/favicon.ico"],
               "only the site itself, never a third-party service")
        assert(SiteIcon.host(u) == "github.com" && SiteIcon.monogram("github.com") == "G")
        assert(SiteIcon.monogram("9gag.com") == "G", "first letter, skipping digits")
        assert(SiteIcon.paletteIndex("github.com", count: 6) == SiteIcon.paletteIndex("github.com", count: 6))
        assert((0..<6).contains(SiteIcon.paletteIndex("x.io", count: 6)))
        assert(SiteIcon.candidates(for: URL(string: "mailto:a@b.c")!).isEmpty)
    }

    static func testQuickNotes() {
        let t0 = Date(timeIntervalSince1970: 0)
        var list = QuickNote.adding("  Drink water \n", tag: .blue, to: [], now: t0)
        assert(list.count == 1 && list[0].text == "Drink water" && list[0].tag == .blue, "trimmed, tagged")
        assert(QuickNote.adding("   ", tag: .red, to: list).count == 1, "blank ignored")
        list = QuickNote.adding("Call Sam", tag: .none, to: list, now: t0.addingTimeInterval(60))
        assert(list.map(\.text) == ["Call Sam", "Drink water"], "newest first")
        list[0].done = true
        assert(QuickNote.sorted(list).map(\.text) == ["Drink water", "Call Sam"], "done notes sink")
        let data = try! JSONEncoder().encode(list)
        assert(try! JSONDecoder().decode([QuickNote].self, from: data) == list, "persists round-trip")
    }

    static func testRecentActivity() {
        let t = Date(timeIntervalSince1970: 0)
        func item(_ k: RecentItem.Kind, _ d: String) -> RecentItem { RecentItem(kind: k, title: d, detail: d, date: t) }
        var list: [RecentItem] = []
        list = RecentItem.adding(item(.color, "#111111"), to: list)
        list = RecentItem.adding(item(.qr, "https://a.io"), to: list)
        list = RecentItem.adding(item(.color, "#111111"), to: list)
        assert(list.map(\.detail) == ["#111111", "https://a.io"], "repeat moves to top, no duplicate")
        for i in 0..<10 { list = RecentItem.adding(item(.download, "/f\(i)"), to: list) }
        assert(list.count == 8 && list.first?.detail == "/f9", "capped at 8, newest first")
        assert(item(.qr, "https://a.io").actionTitle == "Open" && item(.qr, "WIFI:S:x;;").actionTitle == "Copy",
               "only http(s) payloads get Open")
        assert(item(.download, "/x").actionTitle == "Reveal" && item(.color, "#000000").actionTitle == "Copy")
        assert(item(.qr, "a") != item(.color, "a") && item(.qr, "a").id != item(.color, "a").id, "kind is part of identity")
    }

        static func testIslandStateMachine() {
        let r = IslandStateMachine.resolve
        assert(r(IslandSignals()) == .collapsed, "idle = bare pill")
        assert(r(IslandSignals(peeking: true)) == .peek)
        assert(r(IslandSignals(musicPlaying: true)) == .musicLive)
        assert(r(IslandSignals(musicPlaying: true, persistent: true)) == .musicLive,
               "persistent activity doesn't displace music")
        assert(r(IslandSignals(persistent: true)) == .hud, "persistent promotes the resting pill")
        assert(r(IslandSignals(peeking: true, persistent: true)) == .peek, "hover still peeks over persistent")
        assert(r(IslandSignals(peeking: true, transient: true)) == .hud, "a live flash trumps peek")
        assert(r(IslandSignals(musicPlaying: true, transient: true)) == .hud, "and music")
        assert(r(IslandSignals(dropShowing: true, levelHUD: true)) == .drop, "drag beats HUD")
        assert(r(IslandSignals(expanded: true, dropShowing: true)) == .expanded, "open Command Center wins")
        assert(r(IslandSignals(expanded: true, showSettings: true)) == .settings)
        assert(r(IslandSignals(showSettings: true)) == .collapsed, "settings flag alone doesn't open")
        assert(r(IslandSignals(expanded: true, cleaning: true)) == .cleanMode, "clean mode overrides all")
        assert(IslandState.expanded.isBig && IslandState.settings.isBig && !IslandState.hud.isBig)
    }

    static func testPinsAndSnap() {
        assert(Pins.adding("  hi \n", to: ["a"]) == ["hi", "a"], "trimmed, front")
        assert(Pins.adding("a", to: ["b", "a"]) == ["a", "b"], "dedupe moves to front")
        assert(Pins.adding("   ", to: ["a"]) == ["a"], "blank ignored")
        assert(Pins.adding("z", to: ["1", "2"], max: 2) == ["z", "1"], "capped")
        assert(Pins.linkTitle(URL(string: "https://www.github.com/manugowda19/repo")!) == "github.com/manugowda19")
        assert(Pins.linkTitle(URL(string: "https://example.com")!) == "example.com")
        assert(Pins.snippetTitle("line one\nline two") == "line one")
        assert(Pins.snippetTitle(String(repeating: "x", count: 40)).count == 28)

        // Primary display 1728×1117 pt; menu bar 37 pt → visible y 0…1080 (AppKit).
        let v = CGRect(x: 0, y: 0, width: 1728, height: 1080)
        assert(Snap.frame(.left, visible: v, primaryHeight: 1117) == CGRect(x: 0, y: 37, width: 864, height: 1080),
               "left half sits under the menu bar in AX coords")
        assert(Snap.frame(.right, visible: v, primaryHeight: 1117) == CGRect(x: 864, y: 37, width: 864, height: 1080))
        assert(Snap.frame(.maximize, visible: v, primaryHeight: 1117) == CGRect(x: 0, y: 37, width: 1728, height: 1080))
        assert(Snap.frame(.center, visible: v, primaryHeight: 1117, current: CGSize(width: 800, height: 600))
               == CGRect(x: 464, y: 277, width: 800, height: 600))
        // Secondary display above the primary (AppKit y 1117…2557): AX y goes negative.
        let above = CGRect(x: 0, y: 1117, width: 2560, height: 1415)
        assert(Snap.frame(.maximize, visible: above, primaryHeight: 1117).minY == -1415, "flip across displays")
        assert(Snap.frame(.center, visible: v, primaryHeight: 1117, current: CGSize(width: 3000, height: 2000)).size
               == CGSize(width: 1728, height: 1080), "center clamps oversize windows")
    }

    static func testNoise() {
        for kind in NoiseGenerator.Kind.allCases {
            var g = NoiseGenerator(kind)
            let s = (0..<44_100).map { _ in g.next() }
            let peak = s.map(abs).max()!
            let rms = (s.map { $0 * $0 }.reduce(0, +) / Float(s.count)).squareRoot()
            assert(peak <= 1, "\(kind) stays in range: \(peak)")
            assert(rms > 0.05 && rms < 0.5, "\(kind) is audible but not loud: \(rms)")
        }
        // Low-frequency weight: mean |Δ| between samples (per unit RMS) shrinks
        // white → pink → brown.
        func smoothness(_ k: NoiseGenerator.Kind) -> Float {
            var g = NoiseGenerator(k)
            let s = (0..<44_100).map { _ in g.next() }
            let rms = (s.map { $0 * $0 }.reduce(0, +) / Float(s.count)).squareRoot()
            return zip(s, s.dropFirst()).map { abs($1 - $0) }.reduce(0, +) / Float(s.count) / rms
        }
        assert(smoothness(.white) > smoothness(.pink) && smoothness(.pink) > smoothness(.brown),
               "spectra tilt darker: white > pink > brown")
    }

    static func testCalculator() {
        let e = Calculator.evaluate
        assert(e("2+3*4") == 14, "precedence")
        assert(e("(2+3)*4") == 20)
        assert(e("2^3^2") == 512, "right-assoc power")
        assert(e("-3^2") == -9, "minus binds looser than ^")
        assert(e("2^-1") == 0.5, "negative exponent")
        assert(e("10 % 4") == 2 && e("7 ÷ 2") == 3.5 && e("6 × 7") == 42)
        assert(e("1,250 * 2") == 2500, "thousands commas")
        assert(e("--4") == 4 && e("3*-2") == -6)
        assert(e("1/0") == nil, "divide by zero")
        assert(e("42") == nil, "lone number searches instead")
        assert(e("hello world") == nil && e("2+") == nil && e("(1+2") == nil && e("1+2)") == nil)
        assert(e("") == nil && e("1.2.3+1") == nil)
        assert(Calculator.format(42) == "42" && Calculator.format(3.5) == "3.5")
        assert(Calculator.format(1.0 / 3) == "0.3333333333")
        assert(Calculator.format(-2) == "-2")
    }

    static func testTools() {
        assert(Tools.hex(red: 1, green: 0, blue: 0) == "#FF0000")
        assert(Tools.hex(red: 0.2275, green: 0.4824, blue: 0.8353) == "#3A7BD5")
        assert(Tools.hex(red: -1, green: 2, blue: 0.5) == "#00FF80", "clamped + rounded")
        let c = Tools.components("#3A7BD5")
        assert(c != nil && Tools.hex(red: c!.0, green: c!.1, blue: c!.2) == "#3A7BD5", "round-trips")
        assert(Tools.components("zzz") == nil && Tools.components("#12345") == nil)
        assert(Tools.pushing("b", onto: ["a", "b", "c"]) == ["b", "a", "c"], "existing moves to front")
        assert(Tools.pushing("x", onto: ["1", "2", "3"], max: 3) == ["x", "1", "2"], "capped")
        assert(Tools.openableURL(" https://example.com/a?b=1 ")?.host == "example.com")
        assert(Tools.openableURL("http://x.io") != nil)
        assert(Tools.openableURL("javascript:alert(1)") == nil)
        assert(Tools.openableURL("file:///etc/passwd") == nil)
        assert(Tools.openableURL("WIFI:S:home;T:WPA;P:secret;;") == nil)
        assert(Tools.openableURL("just text") == nil)
    }

    static func testTimeKeeping() {
        let t0 = Date(timeIntervalSince1970: 0)
        var sw = Stopwatch()
        assert(!sw.running && sw.elapsed(at: t0) == 0)
        sw.start(at: t0)
        sw.start(at: t0.addingTimeInterval(5))      // double start is a no-op
        assert(sw.elapsed(at: t0.addingTimeInterval(10)) == 10)
        sw.pause(at: t0.addingTimeInterval(10))
        assert(!sw.running && sw.elapsed(at: t0.addingTimeInterval(99)) == 10, "paused time frozen")
        sw.start(at: t0.addingTimeInterval(100))
        assert(sw.elapsed(at: t0.addingTimeInterval(130)) == 40, "resumes from accumulated")
        sw.reset()
        assert(sw == Stopwatch())
        assert(Stopwatch.label(65) == "1:05" && Stopwatch.label(3725) == "1:02:05" && Stopwatch.label(0) == "0:00")

        let cd = Countdown(seconds: 1500, from: t0)
        assert(cd.remaining(at: t0) == 1500 && !cd.isFinished(at: t0))
        assert(cd.remaining(at: t0.addingTimeInterval(0.4)) == 1500, "rounds up")
        assert(cd.remaining(at: t0.addingTimeInterval(1499.5)) == 1)
        assert(cd.remaining(at: t0.addingTimeInterval(3600)) == 0 && cd.isFinished(at: t0.addingTimeInterval(1500)),
               "a late wake (sleep) lands on 0, not negative")

        var pc = PomodoroCycle()
        var trace: [String] = []
        for _ in 0..<9 { trace.append("\(pc.label)\(pc.phase)"); pc.advance() }
        assert(trace == ["1/4work", "1/4rest", "2/4work", "2/4rest", "3/4work", "3/4rest",
                         "4/4work", "4/4longRest", "1/4work"], "set of 4 with a long break: \(trace)")
        assert(PomodoroCycle(session: 4, phase: .longRest).minutes(work: 25) == 15)
        assert(PomodoroCycle(session: 2, phase: .rest).minutes(work: 25) == 5)
        assert(PomodoroCycle().minutes(work: 50) == 50)

        var bt = BreakTimer(threshold: 600, idleReset: 120)
        assert(!bt.update(now: t0, idle: 0), "starts a session")
        assert(!bt.update(now: t0.addingTimeInterval(599), idle: 10))
        assert(bt.update(now: t0.addingTimeInterval(600), idle: 10), "fires at threshold")
        assert(!bt.update(now: t0.addingTimeInterval(700), idle: 0), "new session after firing")
        assert(!bt.update(now: t0.addingTimeInterval(800), idle: 130), "idle ends the session")
        assert(bt.activeSince == nil)
        assert(!bt.update(now: t0.addingTimeInterval(900), idle: 30))
        assert(bt.activeSince == t0.addingTimeInterval(870), "session dated from last input")
    }

    static func testSystemStats() {
        // user, system, idle, nice: 30 busy + 70 idle over the interval.
        assert(SystemStats.cpuUsage(previous: [100, 50, 1000, 0], current: [120, 60, 1070, 0]) == 0.3)
        assert(SystemStats.cpuUsage(previous: [1, 1, 1, 1], current: [1, 1, 1, 1]) == nil, "no ticks elapsed")
        assert(SystemStats.cpuUsage(previous: [UInt32.max - 9, 0, 0, 0], current: [10, 0, 20, 0]) == 0.5,
               "UInt32 rollover")
        assert(SystemStats.cpuUsage(previous: [1], current: [1, 2, 3, 4]) == nil)
        assert(SystemStats.rate(previous: 1_000, current: 5_000, interval: 2) == 2_000)
        assert(SystemStats.rate(previous: 5_000, current: 1_000, interval: 2) == 0, "counter wrap")
        assert(SystemStats.rate(previous: 0, current: 10, interval: 0) == 0)
        assert(SystemStats.formatRate(500) == "0 KB/s")
        assert(SystemStats.formatRate(820_000) == "820 KB/s")
        assert(SystemStats.formatRate(1_440_000) == "1.4 MB/s")
        assert(SystemStats.formatGB(8_589_934_592) == "8.0 GB")
    }

    static func testSpectrum() {
        let sr = 48_000.0
        func tone(_ hz: Double, _ amp: Float = 1) -> [Float] {
            (0..<Spectrum.fftSize).map { amp * Float(sin(2 * .pi * hz * Double($0) / sr)) }
        }
        let silent = Spectrum.levels([Float](repeating: 0, count: 1024), sampleRate: sr, bands: 7)
        assert(silent.count == 7 && silent.allSatisfy { $0 == 0 }, "silence = all zero")
        let low = Spectrum.levels(tone(100), sampleRate: sr, bands: 7)
        let high = Spectrum.levels(tone(8_000), sampleRate: sr, bands: 7)
        assert(low.firstIndex(of: low.max()!)! <= 1, "100 Hz peaks in the low end: \(low)")
        assert(low[4...].allSatisfy { $0 < 0.1 }, "no 100 Hz energy up high: \(low)")
        assert(high.firstIndex(of: high.max()!) == 6, "8 kHz peaks in the last band: \(high)")
        assert(low.max()! > 0.9, "full-scale sine ≈ 0 dBFS: \(low)")
        let quiet = Spectrum.levels(tone(100, 0.01), sampleRate: sr, bands: 7)
        assert(quiet.max()! > 0.2 && quiet.max()! < low.max()! - 0.4, "−40 dB tone is clearly lower: \(quiet)")
        assert(Spectrum.levels([], sampleRate: sr, bands: 0).isEmpty)
    }

    static func testMeeting() {
        assert(Meeting.joinURL(in: [nil, "Room 4", "Join: https://us02web.zoom.us/j/123456?pwd=ab. Thanks"])?
            .absoluteString == "https://us02web.zoom.us/j/123456?pwd=ab", "zoom in notes, trailing dot trimmed")
        assert(Meeting.joinURL(in: ["https://meet.google.com/abc-defg-hij"])?.host == "meet.google.com")
        assert(Meeting.joinURL(in: ["<https://teams.microsoft.com/l/meetup-join/19%3a>"])?.host == "teams.microsoft.com")
        assert(Meeting.joinURL(in: ["https://acme.webex.com/meet/bob"]) != nil)
        assert(Meeting.joinURL(in: ["https://example.com/zoom.us/j/1", "lunch"]) == nil, "lookalike rejected")
        assert(Meeting.joinURL(in: []) == nil)

        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let a = Meeting(id: "a", title: "A", start: t0, joinURL: nil)
        let b = Meeting(id: "b", title: "B", start: t0.addingTimeInterval(120), joinURL: nil)
        assert(Meeting.alerting([a, b], now: t0.addingTimeInterval(-301)) == nil, "too early")
        assert(Meeting.alerting([b, a], now: t0.addingTimeInterval(-300)) == a, "lead edge, earliest wins")
        assert(Meeting.alerting([a, b], now: t0.addingTimeInterval(299)) == a, "within grace")
        assert(Meeting.alerting([a, b], now: t0.addingTimeInterval(300)) == b, "a's grace over")
        assert(Meeting.alerting([a, b], now: t0, dismissed: ["a"]) == b, "dismissed skipped")
    }

    static func testDownloads() {
        let ls = ["b.zip.crdownload", "a.dmg.download", "x.iso.part", "done.pdf", "notes.txt.bak"]
        assert(Downloads.inProgress(ls) == ["a.dmg.download", "b.zip.crdownload", "x.iso.part"])
        assert(Downloads.finalName("a.dmg.download") == "a.dmg")
        assert(Downloads.safariProgress(["DownloadEntryProgressBytesSoFar": 25,
                                         "DownloadEntryProgressTotalToLoad": 100]) == 0.25)
        assert(Downloads.safariProgress(["DownloadEntryProgressBytesSoFar": 5,
                                         "DownloadEntryProgressTotalToLoad": 0]) == nil, "unknown total")
        assert(Downloads.safariProgress([:]) == nil)
        // a finished (final file exists), b cancelled (no final file), c still going.
        let fin = Downloads.finished(previous: ["a.dmg.download", "b.zip.crdownload", "c.part"],
                                     current: ["c.part"], files: ["a.dmg", "c.part"])
        assert(fin == ["a.dmg"])
    }

    static func testLyrics() {
        let l = Lyrics.parse("""
            [ar:Lorde]
            [00:08.39] second
            [00:00.60] first
            [00:15.40][01:00.00] chorus
            untimed junk
            [00:20.00]
            """)
        assert(l?.lines.count == 5, "metadata + untimed skipped, multi-tag expanded")
        assert(l?.line(at: 0) == nil, "before first line")
        assert(l?.line(at: 1) == "first")
        assert(l?.line(at: 8.39) == "second", "boundary is inclusive")
        assert(l?.line(at: 16) == "chorus")
        assert(l?.line(at: 30) == "", "empty tag = instrumental gap")
        assert(l?.line(at: 61) == "chorus", "repeated tag")
        assert(l?.window(at: 0).current == nil && l?.window(at: 0).next == "first")
        assert(l?.window(at: 9).current == "second" && l?.window(at: 9).next == "chorus")
        assert(l?.window(at: 16).next == "chorus", "skips the empty gap line")
        assert(l?.window(at: 61).next == nil, "last line has no next")
        assert(Lyrics.parse("plain unsynced text") == nil)
        assert(Lyrics.parse("") == nil)
    }

    static func testFileStore() {
        let store = FileStore()
        let a = URL(fileURLWithPath: "/tmp/a.txt")
        let b = URL(fileURLWithPath: "/tmp/b.txt")

        assert(store.isEmpty)
        assert(store.add(a) == true, "first add should succeed")
        assert(store.add(a) == false, "duplicate add should no-op")
        assert(store.count == 1)

        let added = store.add(contentsOf: [a, b])
        assert(added == [b], "add(contentsOf:) should skip existing and return only new URLs")
        assert(store.count == 2)

        assert(store.joinedPaths == "\(a.path)\n\(b.path)", "joinedPaths should be newline-joined POSIX paths")

        assert(store.remove(a) == true)
        assert(store.remove(a) == false, "removing an absent URL should return false")
        assert(store.count == 1)

        store.clear()
        assert(store.isEmpty)
    }

    static func testBluetoothParse() {
        // AirPods (split L/R + case), a mouse (main), and a device with no battery.
        let json = """
        {"SPBluetoothDataType":[{"device_connected":[
          {"AirPods Pro":{"device_batteryLevelLeft":"80%","device_batteryLevelRight":"75%","device_batteryLevelCase":"100%"}},
          {"Magic Mouse":{"device_batteryLevelMain":"55%"}},
          {"Old Headset":{"device_minorType":"Headphones"}}
        ]}]}
        """.data(using: .utf8)!
        let devices = Bluetooth.parse(json)
        assert(devices.contains(BTDevice(name: "AirPods Pro", battery: 75)), "split earbuds report the lower side")
        assert(devices.contains(BTDevice(name: "Magic Mouse", battery: 55)))
        assert(!devices.contains { $0.name == "Old Headset" }, "no battery field → skipped")
        assert(devices.count == 2)

        assert(Bluetooth.parse(Data("garbage".utf8)).isEmpty, "bad JSON → empty")
        // Case-only device falls back to the case level.
        let caseOnly = #"{"SPBluetoothDataType":[{"device_connected":[{"Buds":{"device_batteryLevelCase":"90%"}}]}]}"#.data(using: .utf8)!
        assert(Bluetooth.parse(caseOnly) == [BTDevice(name: "Buds", battery: 90)])
    }

    static func testChooseDisplay() {
        typealias D = (id: UInt32, hasNotch: Bool, isMain: Bool)
        let external: D = (id: 1, hasNotch: false, isMain: true)   // external set as main
        let macbook: D = (id: 2, hasNotch: true, isMain: false)    // notch laptop

        // Auto: prefer the notched display even when the external is main.
        assert(NotchGeometry.chooseDisplay(preferredID: 0, candidates: [external, macbook]) == 2)
        // Preferred wins when still connected.
        assert(NotchGeometry.chooseDisplay(preferredID: 1, candidates: [external, macbook]) == 1)
        // Preferred gone → fall back to notched.
        assert(NotchGeometry.chooseDisplay(preferredID: 99, candidates: [external, macbook]) == 2)
        // No notch anywhere → main.
        assert(NotchGeometry.chooseDisplay(preferredID: 0, candidates: [external]) == 1)
        // Nothing at all → nil.
        assert(NotchGeometry.chooseDisplay(preferredID: 0, candidates: []) == nil)
    }

    static func testNotchGeometry() {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let size = CGSize(width: 200, height: 32)
        let frame = NotchGeometry.shelfFrame(screenFrame: screen, size: size)

        assert(frame.width == size.width && frame.height == size.height)
        assert(frame.midX == screen.midX, "shelf should be horizontally centered on the screen")
        assert(frame.maxY == screen.maxY, "shelf should hang from the screen's top edge")

        assert(NotchGeometry.hasNotch(topSafeAreaInset: 32) == true)
        assert(NotchGeometry.hasNotch(topSafeAreaInset: 0) == false)

        // Real 14"/16" MacBook Pro auxiliary-area values (measured via NSScreen).
        let left = CGRect(x: 0, y: 950, width: 663, height: 32)
        let right = CGRect(x: 848, y: 950, width: 664, height: 32)
        assert(NotchGeometry.notchWidth(leftArea: left, rightArea: right) == 185,
               "notch width should be the gap between the two flanking areas")

        let overlapping = CGRect(x: 0, y: 950, width: 900, height: 32)
        assert(NotchGeometry.notchWidth(leftArea: overlapping, rightArea: right) == 0,
               "overlapping/non-existent notch should clamp to 0, not go negative")
    }
}
