import AppKit

// A private window-server Space above the lock screen. Ordinary windows —
// even at .screenSaver level — are hidden while the session is locked; a
// SkyLight space with a high absolute level is drawn above it. This is the
// widely used technique (create space → set absolute level → show → move
// windows in); symbols are dlsym'd so a missing one disables the feature
// instead of crashing.
// ponytail: level 400 is empirical (what shipping notch apps use); no API
// documents it. If macOS ever draws the lock UI above it, raise it.
final class LockScreenSpace {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias SetLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias Spaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32
    private typealias RemoveWindows = @convention(c) (Int32, CFArray, CFArray) -> Int32
    private typealias Destroy = @convention(c) (Int32, UInt64) -> Int32

    private struct API {
        let connection: MainConnection, create: SpaceCreate, setLevel: SetLevel
        let show: Spaces, hide: Spaces, add: AddWindows, remove: RemoveWindows, destroy: Destroy
    }

    private static let api: API? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
                             RTLD_NOW) else { return nil }
        func sym<T>(_ name: String, _: T.Type) -> T? { dlsym(h, name).map { unsafeBitCast($0, to: T.self) } }
        guard let connection = sym("SLSMainConnectionID", MainConnection.self),
              let create = sym("SLSSpaceCreate", SpaceCreate.self),
              let setLevel = sym("SLSSpaceSetAbsoluteLevel", SetLevel.self),
              let show = sym("SLSShowSpaces", Spaces.self),
              let hide = sym("SLSHideSpaces", Spaces.self),
              let add = sym("SLSSpaceAddWindowsAndRemoveFromSpaces", AddWindows.self),
              let remove = sym("SLSRemoveWindowsFromSpaces", RemoveWindows.self),
              let destroy = sym("SLSSpaceDestroy", Destroy.self) else { return nil }
        return API(connection: connection, create: create, setLevel: setLevel, show: show,
                   hide: hide, add: add, remove: remove, destroy: destroy)
    }()

    static var isAvailable: Bool { api != nil }

    private let api: API
    private let cid: Int32
    private let space: UInt64
    private var windowNumbers: [Int] = []

    /// nil when SkyLight's symbols aren't there (feature quietly off).
    init?(level: Int32 = 400) {
        guard let api = Self.api else { return nil }
        self.api = api
        cid = api.connection()
        space = api.create(cid, 1, nil)
        guard space != 0 else { return nil }
        _ = api.setLevel(cid, space, level)
        _ = api.show(cid, [space] as CFArray)
    }

    /// Moves already-ordered-in windows (they need a window number) into the
    /// space. Mask 7 = remove from every space they were on.
    func add(_ windows: [NSWindow]) {
        let numbers = windows.map(\.windowNumber).filter { $0 > 0 }
        guard !numbers.isEmpty else { return }
        windowNumbers += numbers
        _ = api.add(cid, space, numbers as CFArray, 7)
    }

    /// Takes our windows back out, hides and destroys the space.
    func tearDown() {
        if !windowNumbers.isEmpty {
            _ = api.remove(cid, windowNumbers as CFArray, [space] as CFArray)
            windowNumbers = []
        }
        _ = api.hide(cid, [space] as CFArray)
        _ = api.destroy(cid, space)
    }
}
