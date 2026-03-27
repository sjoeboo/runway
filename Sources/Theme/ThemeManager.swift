import SwiftUI

/// Manages theme selection and provides the current theme to the view hierarchy.
@Observable
@MainActor
public final class ThemeManager {
    public var currentTheme: AppTheme
    public var allThemes: [AppTheme]

    public init(defaultTheme: AppTheme = .tokyoNightStorm) {
        self.currentTheme = defaultTheme
        self.allThemes = AppTheme.builtIn
    }

    public func selectTheme(_ theme: AppTheme) {
        currentTheme = theme
    }

    public func selectTheme(byID id: String) {
        if let theme = allThemes.first(where: { $0.id == id }) {
            currentTheme = theme
        }
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
