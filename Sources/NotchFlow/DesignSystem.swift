import AppKit
import SwiftUI

// NØTH design system: one place for color, spacing, radius, type and motion,
// plus the small set of controls every surface uses. Components carry the
// accessibility basics (labels, ≥24 pt hit areas, hover/press states, Reduce
// Motion) so individual views don't have to remember them.
//
// Contrast (WCAG, computed from these hex values): primary text ≥12.7:1 and
// secondary ≥5.8:1 on every surface; tertiary is for the two darkest surfaces
// only (≥4.6:1). The outer pill stays pure black so it blends with the
// hardware notch; content surfaces sit on top of it.
enum Theme {
    enum Palette {
        static let pill = Color.black                       // must match the notch
        // Colors resolve against the view's color scheme: dark everywhere,
        // except the light glass panel. On glass, cards are tints so the
        // frosted desktop shows through. Glass is read from defaults, not
        // AppSettings, so the pure-model test harness still compiles this file.
        private static var glass: Bool { UserDefaults.standard.bool(forKey: "glassPanel") }
        static var surface: Color {                         // cards
            glass ? adaptive(.white.withAlphaComponent(0.08), .white.withAlphaComponent(0.42)) : Color(hex: 0x151619)
        }
        static var elevated: Color {                        // chips, inputs
            glass ? adaptive(.white.withAlphaComponent(0.12), .black.withAlphaComponent(0.07)) : Color(hex: 0x202228)
        }
        static let interactive = adaptive(ns(0x292C33), .black.withAlphaComponent(0.12))   // hovered controls
        static let border = adaptive(.white.withAlphaComponent(0.08), .black.withAlphaComponent(0.10))
        static let text = adaptive(ns(0xF4F4F5), ns(0x16171B))
        static let textSecondary = adaptive(ns(0xA3A6B0), ns(0x454953))
        static let textTertiary = adaptive(ns(0x7C808C), ns(0x5E626C))
        static let accent = adaptive(ns(0x8AB4FF), ns(0x1D5FD6))
        static let onAccent = adaptive(ns(0x0B0C0F), .white)   // 9.4:1 dark, 5.9:1 light
        static let success = adaptive(ns(0x4ADE80), ns(0x15803D))
        static let warning = adaptive(ns(0xF5B451), ns(0xB45309))
        static let danger = adaptive(ns(0xF2777A), ns(0xC2410C))

        private static func adaptive(_ dark: NSColor, _ light: NSColor) -> Color {
            Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .aqua ? light : dark })
        }
        private static func ns(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        // Status colors mirror macOS's own privacy dots.
        static let camera = Color(hex: 0x4ADE80)
        static let microphone = Color(hex: 0xF5B451)
    }

    enum Space {
        static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 8, card: CGFloat = 14, panel: CGFloat = 24
    }

    /// macOS minimum is 10 pt; nothing in NØTH goes below it.
    enum Typo {
        static let caption = Font.system(size: 10, weight: .medium)
        static let label = Font.system(size: 11, weight: .medium)
        static let body = Font.system(size: 12)
        static let bodyEmphasis = Font.system(size: 12, weight: .semibold)
        static let title = Font.system(size: 13, weight: .semibold)
        static let value = Font.system(size: 15, weight: .semibold).monospacedDigit()
        static let display = Font.system(size: 20, weight: .semibold)
        /// Section eyebrows: small caps-style, tracked.
        static let eyebrow = Font.system(size: 10, weight: .semibold)
    }

    /// Durations from the motion spec; `Theme.motion(_:)` collapses them to
    /// nil under Reduce Motion so state changes are instant.
    enum Motion {
        static let hover = 0.14, press = 0.1, state = 0.2, panel = 0.28, notice = 0.2
    }

    /// The minimum clickable size for icon controls (desktop min 20, default 28).
    static let hitSize: CGFloat = 26
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double(hex >> 16 & 0xFF) / 255,
                  green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Motion

extension Animation {
    static func nf(_ duration: Double) -> Animation { .easeInOut(duration: duration) }
}

/// Applies `animation` only when Reduce Motion is off.
private struct MotionAware<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    func nfAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionAware(animation: animation, value: value))
    }

    /// Card surface: the standard container for a Command Center section.
    func nfCard(padding: CGFloat = Theme.Space.m) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Palette.border))
    }
}

// MARK: - Components

/// Icon-only button: ≥26 pt hit area, hover + press feedback, tooltip, and a
/// VoiceOver label (icon-only controls must always have one).
struct NIconButton: View {
    let symbol: String
    let label: String
    var tint: Color = Theme.Palette.text
    var size: CGFloat = 13
    var role: ButtonRole? = nil
    /// Toolbar style: always-visible elevated fill (hover lifts it).
    var filled = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(role == .destructive && hovering ? Theme.Palette.danger : tint)
                .frame(width: filled ? 32 : Theme.hitSize, height: filled ? 30 : Theme.hitSize)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.control)
                    .fill(hovering ? Theme.Palette.interactive
                          : (filled ? Theme.Palette.elevated : Color.clear)))
                .contentShape(Rectangle())
        }
        .buttonStyle(NPressStyle())
        .onHover { hovering = $0 }
        .nfAnimation(.nf(Theme.Motion.hover), value: hovering)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Text (+ optional icon) chip. `selected` uses the accent fill with dark
/// text — and a weight change, so state isn't conveyed by color alone.
struct NChip: View {
    let title: String
    var icon: String? = nil
    var selected = false
    var help: String? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 10, weight: .medium)) }
                Text(title).font(selected ? Theme.Typo.bodyEmphasis : Theme.Typo.body).lineLimit(1)
            }
            .foregroundColor(selected ? Theme.Palette.onAccent : Theme.Palette.text)
            .padding(.horizontal, 9)
            .frame(minHeight: 24)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.control).fill(
                selected ? Theme.Palette.accent
                    : (hovering ? Theme.Palette.interactive : Theme.Palette.elevated)))
            .contentShape(Rectangle())
        }
        .buttonStyle(NPressStyle())
        .onHover { hovering = $0 }
        .nfAnimation(.nf(Theme.Motion.hover), value: hovering)
        .help(help ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Spoken names for media transport glyphs.
func transportLabel(_ symbol: String) -> String {
    switch symbol {
    case "backward.fill": "Previous track"
    case "forward.fill": "Next track"
    case "play.fill": "Play"
    case "pause.fill": "Pause"
    default: symbol
    }
}

/// Subtle press feedback for every NØTH control.
struct NPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Section eyebrow with an optional trailing accessory.
struct NSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(Theme.Typo.eyebrow)
                .kerning(0.6)
                .foregroundColor(Theme.Palette.textSecondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing()
        }
    }
}

extension NSectionHeader where Trailing == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}

/// Readable status block for permission and empty/error states — replaces
/// one-line clipped messages. The action is optional.
struct NStatusBanner: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = Theme.Palette.warning
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.Typo.bodyEmphasis).foregroundColor(Theme.Palette.text)
                Text(message)
                    .font(Theme.Typo.label)
                    .foregroundColor(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    NChip(title: actionTitle, action: action).padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Opens the right pane of System Settings › Privacy & Security.
enum SystemSettingsLink {
    static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
