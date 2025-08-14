import SwiftUI

// MARK: - Theme

enum GuardianTheme {
    // Clean white and orange theme
    static let primaryOrange = Color.orange
    static let lightOrange = Color.orange.opacity(0.1)
    static let background = Color.white
    static let cardBackground = Color.white
    static let borderColor = Color.gray.opacity(0.15)
    static let textPrimary = Color.black
    static let textSecondary = Color.gray
    
    static let cardRadius: CGFloat = 12
    static let hudWidth: CGFloat = 340
    static let hudHeightCompact: CGFloat = 76
    static let hudHeightExpanded: CGFloat = 120
}

// MARK: - View helpers

struct CleanCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(GuardianTheme.cardBackground, in: RoundedRectangle(cornerRadius: GuardianTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GuardianTheme.cardRadius, style: .continuous)
                    .strokeBorder(GuardianTheme.borderColor, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

extension View {
    func cleanCard() -> some View { modifier(CleanCard()) }
}

// MARK: - Clean window styling

struct CleanWindow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(GuardianTheme.background)
    }
}

extension View {
    /// Applies a clean white background to the main window.
    func cleanWindow() -> some View { modifier(CleanWindow()) }
}

// MARK: - Controls

struct PillTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(GuardianTheme.lightOrange, in: Capsule())
            .overlay(Capsule().strokeBorder(GuardianTheme.borderColor))
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(GuardianTheme.primaryOrange, in: Capsule())
            .overlay(Capsule().strokeBorder(GuardianTheme.primaryOrange.opacity(0.3)))
            .foregroundStyle(.white)
            .shadow(color: GuardianTheme.primaryOrange.opacity(configuration.isPressed ? 0.2 : 0.3),
                    radius: configuration.isPressed ? 4 : 8, x: 0, y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(GuardianTheme.cardBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(GuardianTheme.borderColor))
            .foregroundStyle(GuardianTheme.textPrimary)
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
    }
}

// MARK: - Timing card styling

struct TimingCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: GuardianTheme.cardRadius, style: .continuous)
                    .fill(GuardianTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GuardianTheme.cardRadius, style: .continuous)
                    .strokeBorder(Color.black, lineWidth: 1)
            )
    }
}

extension View {
    func timingCard() -> some View { modifier(TimingCard()) }
}

// MARK: - Placeholder helper

struct PlaceholderTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(GuardianTheme.textSecondary)
                    .padding(.horizontal, 14)
            }
            TextField("", text: $text)
                .textFieldStyle(PillTextFieldStyle())
                .foregroundColor(GuardianTheme.textPrimary)
        }
    }
}

// MARK: - Custom Picker Styles

struct SleekSegmentedPickerStyle: View {
    let options: [(String, String)] // (display, tag)
    @Binding var selection: String
    @State private var hoveredTag: String? = nil
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.1) { option in
                Button(action: { selection = option.1 }) {
                    Text(option.0)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minWidth: 60)
                }
                .buttonStyle(SleekSegmentButtonStyle(isSelected: selection == option.1))
                .scaleEffect(hoveredTag == option.1 ? 1.04 : 1.0)
                .shadow(color: GuardianTheme.primaryOrange.opacity(hoveredTag == option.1 ? 0.2 : 0), radius: hoveredTag == option.1 ? 6 : 0, x: 0, y: hoveredTag == option.1 ? 3 : 0)
                .onHover { isHovering in
                    hoveredTag = isHovering ? option.1 : (hoveredTag == option.1 ? nil : hoveredTag)
                }
            }
        }
        .background(GuardianTheme.lightOrange, in: Capsule())
        .overlay(Capsule().strokeBorder(GuardianTheme.borderColor, lineWidth: 1))
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: hoveredTag)
    }
}

struct SleekSegmentButtonStyle: ButtonStyle {
    let isSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                isSelected ? GuardianTheme.primaryOrange : Color.clear,
                in: Capsule()
            )
            .foregroundStyle(isSelected ? .white : GuardianTheme.textPrimary)
            .shadow(
                color: isSelected ? GuardianTheme.primaryOrange.opacity(0.3) : .clear,
                radius: isSelected ? 4 : 0, x: 0, y: isSelected ? 2 : 0
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isSelected)
            .animation(.spring(response: 0.15, dampingFraction: 0.9), value: configuration.isPressed)
    }
}

// Small light-orange capsule button used in timing controls
struct MiniCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(GuardianTheme.lightOrange, in: Capsule())
            .overlay(Capsule().strokeBorder(GuardianTheme.borderColor))
            .foregroundStyle(GuardianTheme.textPrimary)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.85), value: configuration.isPressed)
    }
}
