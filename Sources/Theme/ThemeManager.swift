import SwiftUI

/// Controls how the theme adapts to system appearance.
public enum ThemeMode: String, CaseIterable, Sendable {
    case manual = "Manual"
    case system = "System"
}

/// Manages theme selection and provides the current theme to the view hierarchy.
@Observable
@MainActor
public final class ThemeManager {
    public var currentTheme: AppTheme
    public var allThemes: [AppTheme]
    public var themeMode: ThemeMode = .manual

    /// The explicitly selected theme (used in manual mode, or as dark theme in system mode).
    public var selectedThemeID: String

    public init(defaultTheme: AppTheme = .tokyoNightStorm) {
        self.currentTheme = defaultTheme
        self.selectedThemeID = defaultTheme.id
        self.allThemes = AppTheme.builtIn
    }

    public func selectTheme(_ theme: AppTheme) {
        selectedThemeID = theme.id
        currentTheme = theme
    }

    public func selectTheme(byID id: String) {
        guard let theme = allThemes.first(where: { $0.id == id }) else { return }
        selectTheme(theme)
    }

    /// Update the effective theme based on system color scheme.
    /// Call this when the system appearance changes.
    public func updateForColorScheme(_ colorScheme: ColorScheme) {
        guard themeMode == .system else { return }

        // Find paired light theme for the selected dark theme (or vice versa)
        let targetAppearance = colorScheme
        if currentTheme.appearance == targetAppearance { return }

        // Look for a pair
        for pair in AppTheme.pairedThemes {
            if selectedThemeID == pair.dark && targetAppearance == .light {
                if let light = allThemes.first(where: { $0.id == pair.light }) {
                    currentTheme = light
                    return
                }
            } else if selectedThemeID == pair.light && targetAppearance == .dark {
                if let dark = allThemes.first(where: { $0.id == pair.dark }) {
                    currentTheme = dark
                    return
                }
            }
        }

        // No pair found — try to find any theme with the right appearance
        if let match = allThemes.first(where: { $0.appearance == targetAppearance }) {
            currentTheme = match
        }
    }

    /// Dark themes only.
    public var darkThemes: [AppTheme] {
        allThemes.filter { $0.appearance == .dark }
    }

    /// Light themes only.
    public var lightThemes: [AppTheme] {
        allThemes.filter { $0.appearance == .light }
    }
}

// MARK: - SwiftUI Environment Key

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .tokyoNightStorm
}

extension EnvironmentValues {
    public var theme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    public func theme(_ theme: AppTheme) -> some View {
        environment(\.theme, theme)
    }
}
