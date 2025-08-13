import SwiftUI

// MARK: - Theme

enum GuardianTheme {
    static let accent = Color.accentColor   // change in Assets if you want a custom brand color
    static let cardRadius: CGFloat = 16
    static let hudWidth: CGFloat = 340
    static let hudHeightCompact: CGFloat = 76
    static let hudHeightExpanded: CGFloat = 120
}

// MARK: - View helpers

struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: GuardianTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GuardianTheme.cardRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.09))
            )
            .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 10)
    }
}

extension View {
    func glassCard() -> some View { modifier(GlassCard()) }
}

// MARK: - Controls

struct PillTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(GuardianTheme.accent, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(configuration.isPressed ? 0.25 : 0.15)))
            .foregroundStyle(.white)
            .shadow(color: GuardianTheme.accent.opacity(configuration.isPressed ? 0.2 : 0.35),
                    radius: configuration.isPressed ? 6 : 12, x: 0, y: configuration.isPressed ? 2 : 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            .foregroundStyle(.primary)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
    }
}
