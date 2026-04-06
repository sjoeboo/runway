import AppKit

/// Loads the Runway app icon from the images directory and sets it as the dock icon.
///
/// Since SPM executables don't have an asset catalog, the icon PNG is loaded
/// at launch and set via NSApplication.applicationIconImage. When running as
/// a packaged .app bundle, the .icns in Resources handles Finder/Spotlight,
/// but we still need this for the Dock during development (`swift run`).
@MainActor
enum AppIcon {
    static func install() {
        // Try bundle Resources first (packaged .app), then source tree (swift run)
        let image: NSImage? =
            if let bundlePath = Bundle.main.path(forResource: "App-icon-1024", ofType: "png") {
                NSImage(contentsOfFile: bundlePath)
            } else {
                findInSourceTree()
            }

        if let image {
            NSApplication.shared.applicationIconImage = applyRoundedMask(image)
        }
    }

    /// Apply the macOS squircle mask. The standard macOS icon corner radius
    /// is ~22.37% of the icon size, using a continuous (superellipse) curve.
    private static func applyRoundedMask(_ source: NSImage) -> NSImage {
        let size = NSSize(width: 1024, height: 1024)
        let cornerRadius: CGFloat = 1024 * 0.2237

        let result = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            path.addClip()
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        return result
    }

    /// Walk up from the executable to find images/App-icon-1024.png in the source tree.
    /// This handles `swift run` where the executable lives in .build/debug/.
    private static func findInSourceTree() -> NSImage? {
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var dir = executableURL.deletingLastPathComponent()

        // Walk up at most 10 levels looking for the images directory
        for _ in 0..<10 {
            let candidate = dir.appendingPathComponent("images/App-icon-1024.png")
            if FileManager.default.fileExists(atPath: candidate.path),
                let img = NSImage(contentsOfFile: candidate.path)
            {
                return img
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }
}
