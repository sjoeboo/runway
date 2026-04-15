/// Persists terminal tab state (tabs, selection, shell counter) across SwiftUI
/// view lifecycle.
///
/// When the user navigates away from a session, SwiftUI destroys
/// `TerminalTabView` and its `@State` properties reset. The underlying tmux
/// sessions survive, so `initializeTabs()` can rediscover them — but the async
/// discovery introduces a visible flash and, under rapid navigation, a race
/// where the guard rejects the results.
///
/// This cache stores the tab state outside the view hierarchy so that
/// returning to a session instantly restores the exact tab layout without
/// needing async rediscovery.
@MainActor
public final class TerminalTabStateCache {
    public static let shared = TerminalTabStateCache()

    struct TabState {
        var tabs: [TerminalTab]
        var selectedTabID: String?
        var shellCounter: Int
    }

    private var states: [String: TabState] = [:]

    private init() {}

    func state(for sessionID: String) -> TabState? {
        states[sessionID]
    }

    func save(_ state: TabState, for sessionID: String) {
        states[sessionID] = state
    }

    public func remove(sessionID: String) {
        states.removeValue(forKey: sessionID)
    }
}
