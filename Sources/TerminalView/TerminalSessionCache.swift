import AppKit
import SwiftTerm

/// Caches LocalProcessTerminalView instances so terminal sessions persist
/// across SwiftUI view lifecycle (tab switches, navigation changes).
///
/// Without this, SwiftUI destroys the terminal view when the user switches
/// to the PR or Todo tab, killing the PTY process. The cache keeps views
/// alive and returns the existing instance when the session is re-selected.
@MainActor
public final class TerminalSessionCache {
    public static let shared = TerminalSessionCache()

    private var views: [String: LocalProcessTerminalView] = [:]

    private init() {}

    /// Get or create a terminal view for the given session ID.
    /// If a view already exists, it's returned as-is (preserving the running PTY).
    /// If not, the factory closure creates a new one.
    public func terminalView(
        forSessionID id: String,
        tabID: String,
        factory: () -> LocalProcessTerminalView
    ) -> LocalProcessTerminalView {
        let key = "\(id)_\(tabID)"
        if let existing = views[key] {
            return existing
        }
        let view = factory()
        views[key] = view
        return view
    }

    /// Remove a cached terminal (when session is deleted).
    public func remove(sessionID: String, tabID: String) {
        let key = "\(sessionID)_\(tabID)"
        views.removeValue(forKey: key)
    }

    /// Remove all terminals for a session.
    public func removeAll(forSessionID id: String) {
        views = views.filter { !$0.key.hasPrefix("\(id)_") }
    }

    /// Check if a terminal exists for a session.
    public func has(sessionID: String, tabID: String) -> Bool {
        views["\(sessionID)_\(tabID)"] != nil
    }
}
