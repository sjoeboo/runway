import Foundation

/// Aggregated session status counts for the four statuses surfaced in the toolbar.
/// `starting` and `stopped` are intentionally excluded — see design spec
/// `docs/superpowers/specs/2026-04-16-menu-bar-status-counts-design.md`.
public struct SessionStatusCounts: Sendable, Equatable {
    public let running: Int
    public let waiting: Int
    public let idle: Int
    public let error: Int

    public init(running: Int = 0, waiting: Int = 0, idle: Int = 0, error: Int = 0) {
        self.running = running
        self.waiting = waiting
        self.idle = idle
        self.error = error
    }

    /// True if any of the four tracked statuses has a non-zero count.
    public var hasAny: Bool {
        running > 0 || waiting > 0 || idle > 0 || error > 0
    }
}

extension Array where Element == Session {
    /// Single-pass aggregation of session statuses into toolbar-relevant buckets.
    public var statusCounts: SessionStatusCounts {
        var running = 0
        var waiting = 0
        var idle = 0
        var error = 0
        for session in self {
            switch session.status {
            case .running: running += 1
            case .waiting: waiting += 1
            case .idle: idle += 1
            case .error: error += 1
            case .starting, .stopped: break
            }
        }
        return SessionStatusCounts(
            running: running,
            waiting: waiting,
            idle: idle,
            error: error
        )
    }
}
