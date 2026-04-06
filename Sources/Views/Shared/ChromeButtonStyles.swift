import SwiftUI
import Theme

// MARK: - ChromeButtonStyle

/// Button style that shows a subtle rounded background on hover,
/// giving plain-looking buttons clear interactive affordance.
public struct ChromeButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @State private var isHovered = false

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return theme.chrome.surface.opacity(0.8)
        } else if isHovered {
            return theme.chrome.surface.opacity(0.5)
        } else {
            return .clear
        }
    }
}

// MARK: - IconButtonStyle

/// Hover-highlighted icon button — for gear icons, refresh buttons, etc.
public struct IconButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @State private var isHovered = false

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return theme.chrome.surface.opacity(0.8)
        } else if isHovered {
            return theme.chrome.surface.opacity(0.5)
        } else {
            return .clear
        }
    }
}

// MARK: - LinkButtonStyle

/// Makes text buttons look like clickable links with underline on hover.
public struct LinkButtonStyle: ButtonStyle {
    @State private var isHovered = false

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .underline(isHovered)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
