import SwiftUI
import Testing

@testable import Theme

// MARK: - Built-in Themes

@Test func builtInThemeCount() {
    #expect(AppTheme.builtIn.count == 6)
}

@Test func builtInThemeIDsAreUnique() {
    let ids = AppTheme.builtIn.map(\.id)
    #expect(Set(ids).count == ids.count)
}

@Test func builtInThemeNamesAreUnique() {
    let names = AppTheme.builtIn.map(\.name)
    #expect(Set(names).count == names.count)
}

@Test func allThemesHave16ANSIColors() {
    for theme in AppTheme.builtIn {
        #expect(theme.terminal.ansi.count == 16, "Theme \(theme.name) should have 16 ANSI colors")
    }
}

@Test func darkThemesHaveDarkAppearance() {
    let darkThemes = [AppTheme.tokyoNightStorm, .ayuMirage, .everforestDark, .oasisLagoonDark]
    for theme in darkThemes {
        #expect(theme.appearance == .dark, "\(theme.name) should be dark")
    }
}

@Test func lightThemesHaveLightAppearance() {
    let lightThemes = [AppTheme.everforestLight, .oasisLagoonLight]
    for theme in lightThemes {
        #expect(theme.appearance == .light, "\(theme.name) should be light")
    }
}

// MARK: - Paired Themes

@Test func pairedThemesExist() {
    #expect(AppTheme.pairedThemes.count == 2)
}

@Test func pairedThemesReferenceValidIDs() {
    let allIDs = Set(AppTheme.builtIn.map(\.id))
    for pair in AppTheme.pairedThemes {
        #expect(allIDs.contains(pair.dark), "Dark theme \(pair.dark) not found in built-in themes")
        #expect(allIDs.contains(pair.light), "Light theme \(pair.light) not found in built-in themes")
    }
}

@Test func pairedThemesHaveCorrectAppearance() {
    for pair in AppTheme.pairedThemes {
        let dark = AppTheme.builtIn.first { $0.id == pair.dark }
        let light = AppTheme.builtIn.first { $0.id == pair.light }
        #expect(dark?.appearance == .dark)
        #expect(light?.appearance == .light)
    }
}

// MARK: - ThemeManager

@Test @MainActor func themeManagerDefaultsToTokyoNight() {
    let manager = ThemeManager()
    #expect(manager.currentTheme.id == "tokyo-night-storm")
    #expect(manager.selectedThemeID == "tokyo-night-storm")
    #expect(manager.themeMode == .manual)
}

@Test @MainActor func themeManagerSelectByTheme() {
    let manager = ThemeManager()
    manager.selectTheme(.ayuMirage)
    #expect(manager.currentTheme.id == "ayu-mirage")
    #expect(manager.selectedThemeID == "ayu-mirage")
}

@Test @MainActor func themeManagerSelectByID() {
    let manager = ThemeManager()
    manager.selectTheme(byID: "everforest-dark")
    #expect(manager.currentTheme.id == "everforest-dark")
}

@Test @MainActor func themeManagerSelectByInvalidIDDoesNothing() {
    let manager = ThemeManager()
    let original = manager.currentTheme.id
    manager.selectTheme(byID: "nonexistent-theme")
    #expect(manager.currentTheme.id == original)
}

@Test @MainActor func themeManagerDarkThemesFilter() {
    let manager = ThemeManager()
    let darkThemes = manager.darkThemes
    #expect(darkThemes.allSatisfy { $0.appearance == .dark })
    #expect(darkThemes.count == 4)
}

@Test @MainActor func themeManagerLightThemesFilter() {
    let manager = ThemeManager()
    let lightThemes = manager.lightThemes
    #expect(lightThemes.allSatisfy { $0.appearance == .light })
    #expect(lightThemes.count == 2)
}

@Test @MainActor func themeManagerAllThemesCountMatchesBuiltIn() {
    let manager = ThemeManager()
    #expect(manager.allThemes.count == AppTheme.builtIn.count)
}

// MARK: - System Mode Switching

@Test @MainActor func systemModeManualIgnoresColorSchemeChange() {
    let manager = ThemeManager()
    manager.themeMode = .manual
    manager.selectTheme(.everforestDark)
    manager.updateForColorScheme(.light)
    // Manual mode: should NOT switch
    #expect(manager.currentTheme.id == "everforest-dark")
}

@Test @MainActor func systemModeSwitchesToPairedLight() {
    let manager = ThemeManager()
    manager.themeMode = .system
    manager.selectTheme(.everforestDark)
    manager.updateForColorScheme(.light)
    #expect(manager.currentTheme.id == "everforest-light")
}

@Test @MainActor func systemModeSwitchesToPairedDark() {
    let manager = ThemeManager()
    manager.themeMode = .system
    // Start from light, select the dark pair's ID as selected
    manager.selectedThemeID = "everforest-light"
    manager.currentTheme = .everforestLight
    manager.updateForColorScheme(.dark)
    #expect(manager.currentTheme.id == "everforest-dark")
}

@Test @MainActor func systemModeNoChangeWhenAlreadyCorrectAppearance() {
    let manager = ThemeManager()
    manager.themeMode = .system
    manager.selectTheme(.everforestDark)
    manager.updateForColorScheme(.dark)
    // Already dark, should stay
    #expect(manager.currentTheme.id == "everforest-dark")
}

@Test @MainActor func systemModeFallbackWhenNoPair() {
    let manager = ThemeManager()
    manager.themeMode = .system
    // Tokyo Night has no paired light theme
    manager.selectTheme(.tokyoNightStorm)
    manager.updateForColorScheme(.light)
    // Should fall back to any light theme
    #expect(manager.currentTheme.appearance == .light)
}

// MARK: - ThemeMode

@Test func themeModeRawValues() {
    #expect(ThemeMode.manual.rawValue == "Manual")
    #expect(ThemeMode.system.rawValue == "System")
}

@Test func themeModeCaseIterable() {
    #expect(ThemeMode.allCases.count == 2)
}
