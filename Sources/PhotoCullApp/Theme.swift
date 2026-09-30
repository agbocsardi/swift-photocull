import SwiftUI
import AppKit
import PhotoCullCore

// Theme.swift — the native macOS design system for PhotoCull.
//
// Follows Apple's HIG via the macos-design-skill references:
//  - semantic, appearance-aware colors (no hard-coded dark palette, no forced scheme)
//  - SF Pro for UI, SF Mono only for technical values
//  - materials/vibrancy for sidebar, toolbar and floating chrome
//  - layered shadows (the `0 0 0 0.5px` edge definition is the signature macOS look)
//  - 8pt spacing grid, native corner radii and control heights

// MARK: - Color

/// Semantic colors. These follow the system appearance (light/dark) and the
/// user's accent color, so the app looks at home in either mode.
enum Palette {
    static let window        = Color(nsColor: .windowBackgroundColor)
    static let content       = Color(nsColor: .controlBackgroundColor)
    static let elevated      = Color(nsColor: .controlBackgroundColor)
    static let sidebarRow    = Color(nsColor: .quaternaryLabelColor)

    static let label         = Color(nsColor: .labelColor)
    static let secondary     = Color(nsColor: .secondaryLabelColor)
    static let tertiary      = Color(nsColor: .tertiaryLabelColor)
    static let quaternary    = Color(nsColor: .quaternaryLabelColor)

    static let separator     = Color(nsColor: .separatorColor)
    static let border        = Color(nsColor: .separatorColor).opacity(0.6)

    static let accent        = Color.accentColor
    static let hover         = Color(nsColor: .selectedContentBackgroundColor).opacity(0.10)

    // Semantic cull states. System colors adapt to light/dark automatically.
    static let keep          = Color(nsColor: .systemGreen)
    static let reject        = Color(nsColor: .systemRed)
    static let undecided     = Color(nsColor: .tertiaryLabelColor)
    static let crop          = Color(nsColor: .systemYellow)
    static let raw           = Color(nsColor: .systemTeal)
    static let warning       = Color(nsColor: .systemOrange)
}

// MARK: - Typography

/// Apple's type scale. macOS apps use smaller type than the web: 13pt body.
/// Only technical values (file names, numbers, keycaps) use the monospaced face.
enum Typo {
    static let largeTitle = Font.system(size: 26, weight: .bold)
    static let title1     = Font.system(size: 22, weight: .regular)
    static let title2     = Font.system(size: 17, weight: .regular)
    static let title3     = Font.system(size: 15, weight: .semibold)
    static let headline   = Font.system(size: 13, weight: .semibold)
    static let body       = Font.system(size: 13, weight: .regular)
    static let callout    = Font.system(size: 12, weight: .regular)
    static let caption    = Font.system(size: 11, weight: .regular)
    static let mini       = Font.system(size: 9,  weight: .medium)

    /// Tabular figures for counters so digits do not jitter while navigating.
    static let number     = Font.system(size: 11, weight: .medium).monospacedDigit()
    static let numberBold = Font.system(size: 13, weight: .semibold).monospacedDigit()

    /// Filenames and keycaps only.
    static let mono       = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let monoSmall  = Font.system(size: 10, weight: .regular, design: .monospaced)
}

// MARK: - Metrics

enum Metric {
    static let windowPadding: CGFloat = 16
    static let sectionGap: CGFloat    = 24
    static let cardGap: CGFloat       = 12
    static let elementGap: CGFloat     = 8
    static let dividerMargin: CGFloat  = 8

    static let toolbarHeight: CGFloat  = 52
    static let sidebarRow: CGFloat     = 34
    static let listRow: CGFloat        = 40
    static let controlHeight: CGFloat  = 28
    static let filmstripHeight: CGFloat = 104
    static let inspectorWidth: CGFloat  = 260
    static let sidebarMin: CGFloat      = 200
    static let sidebarIdeal: CGFloat    = 232

    static let radiusWindow: CGFloat  = 10
    static let radiusPanel: CGFloat   = 12
    static let radiusCard: CGFloat    = 8
    static let radiusButton: CGFloat  = 6
    static let radiusInput: CGFloat   = 6
    static let radiusBadge: CGFloat   = 4
    static let radiusThumb: CGFloat   = 6

    /// Space reserved for the traffic lights when the title bar is hidden.
    static let trafficLightInset: CGFloat = 78
}

// MARK: - Motion

enum Motion {
    static let fast   = Animation.easeOut(duration: 0.15)
    static let normal = Animation.timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.25)
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.82)
}

// MARK: - Layered shadows

extension View {
    /// Cards and buttons. The 0.5px ring is what gives macOS edges their definition.
    func shadowSubtle() -> some View {
        shadow(color: .black.opacity(0.16), radius: 1, x: 0, y: 1)
    }

    /// Popovers, dropdowns, the floating action bar.
    func shadowMedium() -> some View {
        shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
    }

    /// Modals and floating panels.
    func shadowHeavy() -> some View {
        shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
    }

    /// A hairline edge, used where a real border would be too heavy.
    func hairlineBorder(_ radius: CGFloat = Metric.radiusCard,
                        color: Color = Palette.border) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: 0.5)
        )
    }
}

// MARK: - Materials

enum Surface {
    /// Sidebar, toolbar, filmstrip — anything that should let the desktop through.
    static let chrome: Material = .bar
    static let panel: Material  = .regularMaterial
    static let floating: Material = .thickMaterial
    static let overlay: Material = .ultraThickMaterial
}

// MARK: - Model presentation

extension Decision {
    var color: Color {
        switch self {
        case .keep: return Palette.keep
        case .reject: return Palette.reject
        case .undecided: return Palette.undecided
        }
    }
    var glyph: String {
        switch self {
        case .keep: return "✓"
        case .reject: return "✗"
        case .undecided: return "·"
        }
    }
    var label: String { rawValue.uppercased() }
}

extension FolderStatus {
    var color: Color {
        switch self {
        case .empty, .unstarted: return Palette.secondary
        case .inProgress: return Palette.warning
        case .complete: return Palette.keep
        }
    }
}

// MARK: - Components

/// Native-looking status pill. Tinted text on a low-opacity fill, 4pt radius.
struct DecisionBadge: View {
    let text: String
    var color: Color = Palette.secondary
    var filled: Bool = false
    var compact: Bool = false

    var body: some View {
        Text(text)
            .font(compact ? Typo.mini : Typo.caption.weight(.semibold))
            .foregroundStyle(filled ? Color.white : color)
            .padding(.horizontal, compact ? 4 : 6)
            .padding(.vertical, compact ? 1 : 2)
            .background(
                RoundedRectangle(cornerRadius: Metric.radiusBadge, style: .continuous)
                    .fill(filled ? color : color.opacity(0.15))
            )
    }
}

/// Keycap in the macOS cheat-sheet style: quiet, monospaced, low contrast.
struct Keycap: View {
    let key: String
    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Palette.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Palette.quaternary.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Palette.separator, lineWidth: 0.5)
            )
    }
}

/// Button that behaves like a native toolbar control: hover tint, press feedback.
struct ToolbarButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        ToolbarButtonBody(prominent: prominent, configuration: configuration)
    }
}

private struct ToolbarButtonBody: View {
    let prominent: Bool
    let configuration: ToolbarButtonStyle.Configuration
    @StateObject private var hover = ViewState(false)

    var body: some View {
        configuration.label
            .font(Typo.body)
            .foregroundStyle(prominent ? Color.white : Palette.label)
            .padding(.horizontal, 8)
            .frame(height: Metric.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: Metric.radiusButton, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metric.radiusButton, style: .continuous)
                    .strokeBorder(Palette.separator, lineWidth: prominent ? 0 : 0.5)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .onHover { hover.value = $0 }
    }

    private var background: Color {
        if prominent { return Palette.accent }
        return hover.value ? Palette.hover : Color.clear
    }
}

/// Native-style empty state: icon, one line of explanation, optional call to action.
struct EmptyState: View {
    let icon: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Palette.quaternary)
            Text(title)
                .font(Typo.title3)
                .foregroundStyle(Palette.secondary)
            if let message {
                Text(message)
                    .font(Typo.callout)
                    .foregroundStyle(Palette.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(ToolbarButtonStyle())
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Metric.sectionGap)
    }
}

/// Two-column inspector row (label left, value right) in the macOS inspector idiom.
struct InspectorRow: View {
    let label: String
    let value: String?
    var mono: Bool = false
    var tint: Color?

    var body: some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.tertiary)
                    .frame(width: 62, alignment: .leading)
                Text(value)
                    .font(mono ? Typo.mono : Typo.callout)
                    .foregroundStyle(tint ?? Palette.label)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 1.5)
        }
    }
}

/// The numeral that identifies a pane. Panes are addressable with the 1-4 keys,
/// so each one is labelled and lights up while it has keyboard focus.
struct PaneBadge: View {
    let number: Int
    var focused: Bool = false
    var large: Bool = false

    var body: some View {
        Text("\(number)")
            .font(.system(size: large ? 11 : 9, weight: .bold, design: .rounded))
            .foregroundStyle(focused ? Color.white : Palette.secondary)
            .frame(width: large ? 18 : 14, height: large ? 18 : 14)
            .background(
                Circle().fill(focused ? Palette.accent : Palette.quaternary.opacity(0.5))
            )
            .overlay(
                Circle().strokeBorder(Palette.separator, lineWidth: focused ? 0 : 0.5)
            )
            .animation(Motion.fast, value: focused)
    }
}

/// Section header in the small-caps style used by native sidebars and inspectors.
struct SectionHeader: View {
    let text: String
    var number: Int?
    var focused: Bool = false
    var trailing: AnyView?

    var body: some View {
        HStack(spacing: 6) {
            if let number { PaneBadge(number: number, focused: focused) }
            Text(text.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(focused ? Palette.label : Palette.tertiary)
            Spacer(minLength: 0)
            if let trailing { trailing }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 3)
    }
}

/// Thin progress line used in session rows.
struct ProgressLine: View {
    let value: Double
    var tint: Color = Palette.accent
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.quaternary.opacity(0.35))
                Capsule().fill(tint.opacity(0.85))
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: 2.5)
        .animation(Motion.fast, value: value)
    }
}

// MARK: - ViewState

/// Replacement for `@State`.
///
/// A CommandLineTools-only Swift toolchain ships no SwiftUIMacros plugin, so the
/// `@State` macro cannot be expanded. `@StateObject` is an ordinary property
/// wrapper and works, so local view state lives here instead.
final class ViewState<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}
