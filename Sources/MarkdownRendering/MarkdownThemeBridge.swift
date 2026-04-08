import HighlightSwift
import SwiftUI
import Theme

/// Maps the app's ChromePalette to HighlightSwift theme settings.
struct MarkdownThemeBridge {
    let theme: AppTheme

    /// Highlight colors for the current appearance (dark or light).
    var highlightColors: HighlightColors {
        switch theme.appearance {
        case .dark:
            .dark(.tokyoNight)
        case .light:
            .light(.github)
        @unknown default:
            .dark(.tokyoNight)
        }
    }

    /// Colors for CodeText that adapt to dark/light automatically.
    var codeTextColors: CodeTextColors {
        .custom(
            dark: .dark(.tokyoNight),
            light: .light(.github)
        )
    }
}
