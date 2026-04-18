import SwiftUI
import Theme

/// Small circular avatar rendering two-letter initials.
/// Color is deterministically hashed from the login so the same user
/// always gets the same color. The `isMe` variant uses the theme green.
public struct AssigneeAvatar: View {
    public let login: String
    public let isMe: Bool
    public let size: CGFloat

    @Environment(\.theme) private var theme

    public init(login: String, isMe: Bool = false, size: CGFloat = 18) {
        self.login = login
        self.isMe = isMe
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
            Text(Self.initials(for: login))
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .overlay(
            Circle().stroke(theme.chrome.background, lineWidth: 1)
        )
    }

    private var backgroundColor: Color {
        if isMe { return theme.chrome.green }
        let idx = Self.colorIndex(for: login, paletteCount: Self.palette.count)
        return Self.palette[idx]
    }

    // MARK: - Pure helpers (testable)

    /// Two-letter initials. Splits on '-' first (alice-bailey → AB), else first two chars.
    /// Returns "?" for empty strings so the UI never renders a blank circle.
    nonisolated public static func initials(for login: String) -> String {
        guard !login.isEmpty else { return "?" }
        let parts = login.split(separator: "-", maxSplits: 2, omittingEmptySubsequences: true)
        if parts.count >= 2,
            let first = parts[0].first, let second = parts[1].first
        {
            return "\(first)\(second)".uppercased()
        }
        let chars = Array(login)
        if chars.count >= 2 {
            return "\(chars[0])\(chars[1])".uppercased()
        }
        return String(chars[0]).uppercased()
    }

    /// Deterministic palette index for a login. Uses a stable UTF-8 FNV-like hash
    /// so color is consistent across app launches. **Do not use `String.hashValue`**:
    /// Swift randomizes the seed per process, which would change colors every launch.
    nonisolated public static func colorIndex(for login: String, paletteCount: Int) -> Int {
        guard paletteCount > 0 else { return 0 }
        let hash = login.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & Int.max }
        return hash % paletteCount
    }

    private static let palette: [Color] = [
        Color(red: 0.48, green: 0.38, blue: 1.00),
        Color(red: 0.37, green: 0.77, blue: 0.89),
        Color(red: 0.96, green: 0.56, blue: 0.33),
        Color(red: 0.87, green: 0.37, blue: 0.54),
        Color(red: 0.37, green: 0.56, blue: 0.89),
        Color(red: 0.89, green: 0.72, blue: 0.37),
        Color(red: 0.56, green: 0.37, blue: 0.78),
        Color(red: 0.37, green: 0.78, blue: 0.56),
    ]
}
