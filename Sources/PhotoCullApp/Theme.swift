import SwiftUI
import AppKit
import PhotoCullCore

/// Everforest Dark palette, matching the Go webapp's identity.
enum EF {
    static let bg      = Color(hex: 0x2D3549)
    static let bg1     = Color(hex: 0x374149)
    static let bg2     = Color(hex: 0x3D484D)
    static let bg3     = Color(hex: 0x475258)
    static let subtle  = Color(hex: 0x859289)
    static let text    = Color(hex: 0xD3C6AA)
    static let green   = Color(hex: 0xA7C080)
    static let red     = Color(hex: 0xE67E80)
    static let yellow  = Color(hex: 0xDBBC7F)
    static let aqua    = Color(hex: 0x83C092)
    static let blue    = Color(hex: 0x7FBBB3)
    static let orange  = Color(hex: 0xE69875)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue:  Double(hex & 0xFF) / 255.0,
                  opacity: 1.0)
    }
}

extension Decision {
    var color: Color {
        switch self {
        case .keep: return EF.green
        case .reject: return EF.red
        case .undecided: return EF.subtle
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
        case .empty: return EF.bg3
        case .unstarted: return EF.bg3
        case .inProgress: return EF.orange
        case .complete: return EF.green
        }
    }
}

// MARK: - Reusable chrome

/// Small pill used for status / counts.
struct Badge: View {
    let text: String
    var color: Color = EF.subtle
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(filled ? EF.bg : color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(filled ? color : color.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(color.opacity(filled ? 0 : 0.35), lineWidth: 0.5)
            )
    }
}

/// Pane frame with a numbered header, mirroring the webapp's `.pane`.
struct PaneBox<Content: View>: View {
    let number: Int
    let title: String
    var focused: Bool = false
    var trailing: AnyView? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("\(number)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(focused ? EF.bg : EF.subtle)
                    .frame(width: 14, height: 14)
                    .background(RoundedRectangle(cornerRadius: 3)
                        .fill(focused ? EF.blue : EF.bg3.opacity(0.5)))
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(focused ? EF.text : EF.subtle)
                Spacer(minLength: 0)
                if let trailing { trailing }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(EF.bg1)

            Divider().overlay(EF.bg3)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(EF.bg)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(focused ? EF.blue : EF.bg3, lineWidth: focused ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

/// Monospaced keycap hint used in the footer and help overlay.
struct Keycap: View {
    let key: String
    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(EF.aqua)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(EF.bg1))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(EF.bg3, lineWidth: 0.5))
    }
}


/// Replacement for `@State`.
///
/// A CommandLineTools-only Swift toolchain ships no SwiftUIMacros plugin, so the
/// `@State` macro cannot be expanded. `@StateObject` is an ordinary property
/// wrapper and works, so local view state lives here instead.
final class ViewState<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}
