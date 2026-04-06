import AppKit

/// Programmatic app icon for Runway — a runway strip with terminal cursor.
///
/// Since SPM executables don't have an asset catalog, the icon is generated
/// at launch and set via NSApplication.applicationIconImage.
enum AppIcon {
    static func install() {
        let size = NSSize(width: 1024, height: 1024)
        let image = NSImage(size: size, flipped: false) { rect in
            // Background — rounded rect with gradient (dark charcoal)
            let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: 40, dy: 40), xRadius: 180, yRadius: 180)
            let gradient = NSGradient(
                starting: NSColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1),
                ending: NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1)
            )
            gradient?.draw(in: bgPath, angle: -45)

            // Runway strip — vertical line in center
            let stripWidth: CGFloat = 60
            let stripRect = NSRect(
                x: rect.midX - stripWidth / 2,
                y: rect.minY + 160,
                width: stripWidth,
                height: rect.height - 320
            )
            let stripPath = NSBezierPath(roundedRect: stripRect, xRadius: 8, yRadius: 8)
            NSColor(red: 0.3, green: 0.3, blue: 0.35, alpha: 1).setFill()
            stripPath.fill()

            // Dashed center line on runway
            let dashPath = NSBezierPath()
            let dashY1 = stripRect.minY + 40
            let dashY2 = stripRect.maxY - 40
            let dashCount = 7
            let dashSpacing = (dashY2 - dashY1) / CGFloat(dashCount)
            for i in 0..<dashCount {
                let dashOriginY = dashY1 + CGFloat(i) * dashSpacing + dashSpacing * 0.2
                let dashRect = NSRect(x: rect.midX - 8, y: dashOriginY, width: 16, height: dashSpacing * 0.5)
                dashPath.appendRoundedRect(dashRect, xRadius: 3, yRadius: 3)
            }
            NSColor(red: 0.8, green: 0.8, blue: 0.7, alpha: 0.8).setFill()
            dashPath.fill()

            // Terminal cursor — blinking block at top
            let cursorSize: CGFloat = 80
            let cursorRect = NSRect(
                x: rect.midX - cursorSize / 2 + 140,
                y: rect.midY + 80,
                width: cursorSize,
                height: cursorSize * 1.3
            )
            let cursorPath = NSBezierPath(roundedRect: cursorRect, xRadius: 6, yRadius: 6)
            NSColor(red: 0.3, green: 0.85, blue: 0.5, alpha: 0.9).setFill()
            cursorPath.fill()

            // ">" prompt symbol
            let promptAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 200, weight: .bold),
                .foregroundColor: NSColor(red: 0.3, green: 0.85, blue: 0.5, alpha: 1),
            ]
            let prompt = NSAttributedString(string: ">_", attributes: promptAttrs)
            let promptSize = prompt.size()
            let promptOrigin = NSPoint(
                x: rect.midX - promptSize.width / 2 + 20,
                y: rect.midY - promptSize.height / 2 - 60
            )
            prompt.draw(at: promptOrigin)

            return true
        }

        NSApplication.shared.applicationIconImage = image
    }
}
