import AppKit
import SwiftTerm
import Testing

@testable import TerminalView

// MARK: - LRU Eviction

@MainActor @Test func cacheEvictsLeastRecentlyUsedEntry() {
    let cache = TerminalSessionCache(maxSize: 2)

    // Insert two entries — cache at capacity
    let view1 = cache.terminalView(forSessionID: "s1", tabID: "t1") {
        LocalProcessTerminalView(frame: .zero)
    }
    let view2 = cache.terminalView(forSessionID: "s2", tabID: "t2") {
        LocalProcessTerminalView(frame: .zero)
    }

    #expect(cache.has(sessionID: "s1", tabID: "t1"))
    #expect(cache.has(sessionID: "s2", tabID: "t2"))

    // Insert a third — oldest (s1) should be evicted
    let view3 = cache.terminalView(forSessionID: "s3", tabID: "t3") {
        LocalProcessTerminalView(frame: .zero)
    }

    #expect(!cache.has(sessionID: "s1", tabID: "t1"))  // evicted
    #expect(cache.has(sessionID: "s2", tabID: "t2"))  // kept
    #expect(cache.has(sessionID: "s3", tabID: "t3"))  // new
}

@MainActor @Test func accessRefreshesLRUOrder() {
    let cache = TerminalSessionCache(maxSize: 2)

    // Insert s1 first, then s2
    _ = cache.terminalView(forSessionID: "s1", tabID: "t1") {
        LocalProcessTerminalView(frame: .zero)
    }
    _ = cache.terminalView(forSessionID: "s2", tabID: "t2") {
        LocalProcessTerminalView(frame: .zero)
    }

    // Access s1 again — this should refresh its timestamp
    _ = cache.terminalView(forSessionID: "s1", tabID: "t1") {
        LocalProcessTerminalView(frame: .zero)  // factory won't be called (cache hit)
    }

    // Insert s3 — s2 should now be evicted (it's the oldest)
    _ = cache.terminalView(forSessionID: "s3", tabID: "t3") {
        LocalProcessTerminalView(frame: .zero)
    }

    #expect(cache.has(sessionID: "s1", tabID: "t1"))  // refreshed, kept
    #expect(!cache.has(sessionID: "s2", tabID: "t2"))  // evicted
    #expect(cache.has(sessionID: "s3", tabID: "t3"))  // new
}

// MARK: - Get-or-Create

@MainActor @Test func cacheReturnsSameViewOnHit() {
    let cache = TerminalSessionCache(maxSize: 5)

    let view1 = cache.terminalView(forSessionID: "s1", tabID: "t1") {
        LocalProcessTerminalView(frame: .zero)
    }

    var factoryCalled = false
    let view2 = cache.terminalView(forSessionID: "s1", tabID: "t1") {
        factoryCalled = true
        return LocalProcessTerminalView(frame: .zero)
    }

    #expect(view1 === view2)
    #expect(!factoryCalled)
}

// MARK: - Removal

@MainActor @Test func removeAllClearsAllTabsForSession() {
    let cache = TerminalSessionCache(maxSize: 10)

    _ = cache.terminalView(forSessionID: "s1", tabID: "tab-a") {
        LocalProcessTerminalView(frame: .zero)
    }
    _ = cache.terminalView(forSessionID: "s1", tabID: "tab-b") {
        LocalProcessTerminalView(frame: .zero)
    }
    _ = cache.terminalView(forSessionID: "s2", tabID: "tab-a") {
        LocalProcessTerminalView(frame: .zero)
    }

    cache.removeAll(forSessionID: "s1")

    #expect(!cache.has(sessionID: "s1", tabID: "tab-a"))
    #expect(!cache.has(sessionID: "s1", tabID: "tab-b"))
    #expect(cache.has(sessionID: "s2", tabID: "tab-a"))  // unaffected
}

@MainActor @Test func removeSingleEntry() {
    let cache = TerminalSessionCache(maxSize: 10)

    _ = cache.terminalView(forSessionID: "s1", tabID: "tab-a") {
        LocalProcessTerminalView(frame: .zero)
    }
    _ = cache.terminalView(forSessionID: "s1", tabID: "tab-b") {
        LocalProcessTerminalView(frame: .zero)
    }

    cache.remove(sessionID: "s1", tabID: "tab-a")

    #expect(!cache.has(sessionID: "s1", tabID: "tab-a"))
    #expect(cache.has(sessionID: "s1", tabID: "tab-b"))
}

// MARK: - Read-only Accessors

@MainActor @Test func mainTerminalUsesExpectedKeyFormat() {
    let cache = TerminalSessionCache(maxSize: 10)

    // mainTerminal looks for key "id_id_main"
    _ = cache.terminalView(forSessionID: "sess-1", tabID: "sess-1_main") {
        LocalProcessTerminalView(frame: .zero)
    }

    let terminal = cache.mainTerminal(forSessionID: "sess-1")
    #expect(terminal != nil)
}

@MainActor @Test func existingReturnsNilForMissingEntry() {
    let cache = TerminalSessionCache(maxSize: 10)
    #expect(cache.existing(sessionID: "nonexistent", tabID: "t1") == nil)
}
