import Foundation

// Pure due-time preset cycling, split from ReminderView so the wrap/match logic
// is unit-testable without a real reminder or the current wall clock.
enum DuePreset {
    /// The next preset after `current`: find where `current` sits in `presets`
    /// (matching within 60s; nil matches nil), then advance with wrap-around. An
    /// unknown/custom `current` (no match) starts at the first preset.
    static func next(after current: Date?, in presets: [Date?]) -> Date? {
        let idx = presets.firstIndex { preset in
            switch (preset, current) {
            case (nil, nil): return true
            case let (a?, b?): return abs(a.timeIntervalSince(b)) < 60
            default: return false
            }
        } ?? -1
        return presets[(idx + 1) % presets.count]
    }
}
