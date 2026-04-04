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

    /// Maximum number of terminal views to keep in cache.
    /// When exceeded, the least-recently-accessed entry is evicted.
    /// Eviction is cheap — the underlying tmux session persists independently;
    /// re-attaching later simply creates a new SwiftTerm view.
    public let maxSize: Int = 10

    private var views: [String: LocalProcessTerminalView] = [:]

    /// Tracks the last-access time for each cache key.
    private var lastAccess: [String: Date] = [:]

    private init() {}

    /// Get or create a terminal view for the given session ID.
    /// If a view already exists, it's returned as-is (preserving the running PTY).
    /// If not, the factory closure creates a new one.
    /// Updates the access timestamp on every call.
    public func terminalView(
        forSessionID id: String,
        tabID: String,
        factory: () -> LocalProcessTerminalView
    ) -> LocalProcessTerminalView {
        let key = "\(id)_\(tabID)"
        if let existing = views[key] {
            lastAccess[key] = Date()
            return existing
        }
        let view = factory()
        views[key] = view
        lastAccess[key] = Date()
        evictIfNeeded()
        return view
    }

    /// Remove a cached terminal (when session is deleted).
    public func remove(sessionID: String, tabID: String) {
        let key = "\(sessionID)_\(tabID)"
        views.removeValue(forKey: key)
        lastAccess.removeValue(forKey: key)
    }

    /// Remove all terminals for a session.
    public func removeAll(forSessionID id: String) {
        let prefix = "\(id)_"
        views = views.filter { !$0.key.hasPrefix(prefix) }
        lastAccess = lastAccess.filter { !$0.key.hasPrefix(prefix) }
    }

    /// Check if a terminal exists for a session.
    public func has(sessionID: String, tabID: String) -> Bool {
        views["\(sessionID)_\(tabID)"] != nil
    }

    /// Get an existing terminal view by its full cache key, without creating one.
    public func existingView(forKey key: String) -> LocalProcessTerminalView? {
        views[key]
    }

    /// Get the terminal view for a session's main tab (if cached).
    public func mainTerminal(forSessionID id: String) -> LocalProcessTerminalView? {
        views["\(id)_\(id)_main"]
    }

    /// Get a cached terminal view by session ID and tab ID, without creating one.
    public func existing(sessionID: String, tabID: String) -> LocalProcessTerminalView? {
        views["\(sessionID)_\(tabID)"]
    }

    // MARK: - LRU Eviction

    /// Evict the least-recently-accessed entry if the cache exceeds `maxSize`.
    private func evictIfNeeded() {
        while views.count > maxSize {
            guard let lruKey = lastAccess.min(by: { $0.value < $1.value })?.key else {
                break
            }
            views.removeValue(forKey: lruKey)
            lastAccess.removeValue(forKey: lruKey)
        }
    }
}
