import AppKit
import Foundation
import GitHubOperations
import Models
import Persistence
import Views

/// Manages all pull request state and operations, extracted from RunwayStore
/// to reduce @Observable invalidation scope. PR poll ticks no longer trigger
/// re-evaluation of terminal, sidebar, and session detail views.
@Observable
@MainActor
public final class PRCoordinator {
    // MARK: - State

    var pullRequests: [PullRequest] = []
    var selectedPRID: String?
    var prDetail: PRDetail?
    var prTab: PRTab = .mine
    var prLastFetched: Date?
    var isLoadingPRs: Bool = false

    /// Maps session ID → linked PullRequest (matched by worktree branch)
    var sessionPRs: [String: PullRequest] = [:]

    /// Set of PR IDs linked to active Runway sessions — used for the Sessions filter toggle.
    var sessionPRIDs: Set<String> {
        Set(sessionPRs.values.map(\.id))
    }

    var reviewPRCandidate: PullRequest? = nil
    var showReviewPRDialog: Bool = false
    var showReviewPRSheet: Bool = false
    var isResolvingPR: Bool = false

    // MARK: - Private State

    private var prPollTask: Task<Void, Never>?
    private var sessionPRPollTask: Task<Void, Never>?
    private var enrichPRsTask: Task<Void, Never>?
    private var lastPRFingerprint: PRFingerprint?
    private var sessionPRFetchedAt: [String: Date] = [:]
    private let sessionPRTTL: TimeInterval = 60
    private var detailCache: [String: (detail: PRDetail, fetchedAt: Date)] = [:]
    private let detailTTL: TimeInterval = 300

    // MARK: - Dependencies

    let prManager: PRManager
    private let database: Database?

    /// Back-reference to the store for cross-cutting concerns (statusMessage, navigation, sessions).
    /// Weak to avoid retain cycle: RunwayStore → PRCoordinator → RunwayStore.
    weak var store: RunwayStore?

    // MARK: - Init

    init(prManager: PRManager, database: Database?) {
        self.prManager = prManager
        self.database = database
    }

    // MARK: - Session Cleanup

    /// Called by RunwayStore when a session is deleted — clears linked PR and fetch timestamps.
    func sessionDeleted(id: String) {
        sessionPRs.removeValue(forKey: id)
        sessionPRFetchedAt.removeValue(forKey: id)
    }

    // MARK: - PR Detail for Session

    /// Returns PRDetail for the selected session's linked PR, if available.
    func prDetailForSession(_ sessionID: String) -> PRDetail? {
        guard let pr = sessionPRs[sessionID] else { return nil }
        if selectedPRID == pr.id { return prDetail }
        return nil
    }

    // MARK: - PR Loading

    /// Load cached PRs from database for instant display on startup.
    func loadCachedPRs() {
        if let cached = try? database?.cachedPRs(maxAge: 86400), !cached.isEmpty {
            pullRequests = cached
        }
    }

    func fetchPRs() async {
        guard !isLoadingPRs else { return }
        isLoadingPRs = true
        defer { isLoadingPRs = false }

        do {
            let freshPRs = try await prManager.fetchAllPRs()
            prLastFetched = Date()

            // Merge: keep enriched data from cache/previous enrichment where available
            let existingByID = Dictionary(
                pullRequests.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            pullRequests = freshPRs.map { fresh in
                guard var existing = existingByID[fresh.id] else { return fresh }
                existing.title = fresh.title
                existing.state = fresh.state
                existing.isDraft = fresh.isDraft
                existing.author = fresh.author
                existing.origin = fresh.origin
                existing.createdAt = fresh.createdAt
                existing.updatedAt = fresh.updatedAt
                return existing
            }

            // Cancel any in-flight enrichment to prevent stale results overwriting fresh data
            enrichPRsTask?.cancel()
            enrichPRsTask = Task { await enrichPRs() }
        } catch {
            print("[Runway] Failed to fetch PRs: \(error)")
            store?.statusMessage = .error("PR fetch failed: \(error.localizedDescription)")
        }
    }

    func refreshPRsIfStale() async {
        let staleness: TimeInterval = 60
        if let last = prLastFetched, Date().timeIntervalSince(last) < staleness { return }
        await fetchPRs()
    }

    // MARK: - PR Enrichment

    /// Background-enrich PRs with checks and review decision only (not full detail).
    private func enrichPRs() async {
        let toEnrich = pullRequests.filter { $0.needsEnrichment }
        guard !toEnrich.isEmpty else {
            await linkSessionPRs()
            return
        }

        var enriched: [String: PREnrichResult] = [:]
        await withTaskGroup(of: (String, PREnrichResult?).self) { group in
            var inFlight = 0
            let maxConcurrency = 5

            for pr in toEnrich {
                if inFlight >= maxConcurrency {
                    if let (id, result) = await group.next() {
                        if let result { enriched[id] = result }
                        inFlight -= 1
                    }
                }

                let host = prManager.hostFromURL(pr.url)
                group.addTask { [prManager] in
                    let result = try? await prManager.enrichChecks(
                        repo: pr.repo, number: pr.number, host: host
                    )
                    return (pr.id, result)
                }
                inFlight += 1
            }

            for await (id, result) in group {
                if let result { enriched[id] = result }
            }
        }

        guard !Task.isCancelled else { return }

        var updated = pullRequests
        for i in updated.indices {
            guard let result = enriched[updated[i].id] else { continue }
            applyEnrichment(result, to: &updated[i])
        }
        pullRequests = updated

        try? database?.cachePRs(pullRequests)
        try? database?.cleanPRCache()
        try? database?.cleanIssueCache()

        await linkSessionPRs()
    }

    /// Re-enrich a single PR immediately (called after user actions like approve/merge).
    private func reEnrichPR(_ pr: PullRequest) async {
        let host = prManager.hostFromURL(pr.url)
        guard
            let result = try? await prManager.enrichChecks(
                repo: pr.repo, number: pr.number, host: host
            )
        else { return }

        if let idx = pullRequests.firstIndex(where: { $0.id == pr.id }) {
            applyEnrichment(result, to: &pullRequests[idx])
            try? database?.cachePR(pullRequests[idx])
        }
    }

    private func applyEnrichment(_ result: PREnrichResult, to pr: inout PullRequest) {
        pr.checks = result.checks
        pr.reviewDecision = result.reviewDecision
        if !result.headBranch.isEmpty {
            pr.headBranch = result.headBranch
            pr.baseBranch = result.baseBranch
        }
        pr.additions = result.additions
        pr.deletions = result.deletions
        pr.changedFiles = result.changedFiles
        pr.mergeable = result.mergeable
        pr.mergeStateStatus = result.mergeStateStatus
        pr.autoMergeEnabled = result.autoMergeEnabled
        pr.enrichedAt = Date()
    }

    // MARK: - Session PR Linking

    /// Link PRs to sessions — concurrent, like Hangar.
    private func linkSessionPRs() async {
        guard let store else { return }
        let worktreeSessions = store.sessions.filter {
            $0.worktreeBranch != nil && !store.provisioningWorktreeIDs.contains($0.id)
        }
        guard !worktreeSessions.isEmpty else { return }
        let now = Date()

        await withTaskGroup(of: (String, PullRequest?).self) { group in
            for session in worktreeSessions {
                group.addTask { [prManager] in
                    let pr = try? await prManager.fetchPRForWorktree(path: session.path)
                    return (session.id, pr)
                }
            }
            for await (sessionID, pr) in group {
                sessionPRFetchedAt[sessionID] = now
                if let pr {
                    sessionPRs[sessionID] = pr
                } else {
                    sessionPRs.removeValue(forKey: sessionID)
                }
            }
        }
    }

    // MARK: - Polling

    /// Seed the fingerprint so the first poll doesn't trigger a redundant fetch.
    func seedFingerprint() async {
        lastPRFingerprint = await prManager.prFingerprint(filter: .mine)
    }

    /// Start a lightweight background poll that checks for PR changes every 30 seconds.
    func startPRPoll() {
        prPollTask?.cancel()
        prPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let jitter = Double.random(in: 0...3)
                try? await Task.sleep(for: .seconds(30 + jitter))
                guard !Task.isCancelled, let self else { return }
                guard !self.isLoadingPRs else { continue }
                let fingerprint = await self.prManager.prFingerprint(filter: .mine)
                let isStale = self.prLastFetched.map { Date().timeIntervalSince($0) > 300 } ?? true
                if let fingerprint, fingerprint != self.lastPRFingerprint {
                    self.lastPRFingerprint = fingerprint
                    await self.fetchPRs()
                } else if isStale {
                    await self.fetchPRs()
                }
            }
        }
    }

    /// Independent session→PR linking loop with 60s TTL per session.
    func startSessionPRPoll() {
        sessionPRPollTask?.cancel()
        sessionPRPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let jitter = Double.random(in: 0...2)
                try? await Task.sleep(for: .seconds(15 + jitter))
                guard !Task.isCancelled, let self else { return }
                await self.freshenSessionPRs()
            }
        }
    }

    /// Check each worktree session's PR status, respecting per-session TTL.
    private func freshenSessionPRs() async {
        guard let store else { return }
        let now = Date()
        let worktreeSessions = store.sessions.filter {
            $0.worktreeBranch != nil && !store.provisioningWorktreeIDs.contains($0.id)
        }
        guard !worktreeSessions.isEmpty else { return }

        let stale = worktreeSessions.filter { session in
            guard let fetchedAt = sessionPRFetchedAt[session.id] else { return true }
            return now.timeIntervalSince(fetchedAt) >= sessionPRTTL
        }
        guard !stale.isEmpty else { return }

        await withTaskGroup(of: (String, PullRequest?).self) { group in
            for session in stale {
                group.addTask { [prManager] in
                    let pr = try? await prManager.fetchPRForWorktree(path: session.path)
                    return (session.id, pr)
                }
            }
            for await (sessionID, pr) in group {
                sessionPRFetchedAt[sessionID] = now
                if let pr {
                    sessionPRs[sessionID] = pr
                } else {
                    sessionPRs.removeValue(forKey: sessionID)
                }
            }
        }
    }

    // MARK: - PR Selection

    func selectPR(_ pr: PullRequest?, navigate: Bool = true) async {
        selectedPRID = pr?.id
        prDetail = nil
        guard let pr else { return }

        if navigate {
            store?.currentView = .prs
        }

        // Check cache first
        if let cached = detailCache[pr.id], Date().timeIntervalSince(cached.fetchedAt) < detailTTL {
            prDetail = cached.detail
            return
        }

        do {
            let host = prManager.hostFromURL(pr.url)
            let detail = try await prManager.fetchDetail(
                repo: pr.repo, number: pr.number, host: host)
            detailCache[pr.id] = (detail, Date())
            prDetail = detail
        } catch {
            print("[Runway] Failed to fetch PR detail: \(error)")
        }
    }

    // MARK: - PR Actions

    /// Unified post-action refresh: wait 1s for GitHub to propagate, then re-enrich
    /// the PR list entry and refresh the detail view if this PR is currently selected.
    private func refreshPRAfterAction(_ pr: PullRequest) async {
        try? await Task.sleep(for: .seconds(1))
        await reEnrichPR(pr)
        if selectedPRID == pr.id {
            let host = prManager.hostFromURL(pr.url)
            if let detail = try? await prManager.fetchDetail(
                repo: pr.repo, number: pr.number, host: host
            ) {
                detailCache[pr.id] = (detail, Date())
                prDetail = detail
            }
        }
    }

    func approvePR(_ pr: PullRequest) async {
        let host = prManager.hostFromURL(pr.url)
        do {
            try await prManager.approve(repo: pr.repo, number: pr.number, host: host)
            store?.statusMessage = .success("Approved #\(pr.number)")
            await refreshPRAfterAction(pr)
        } catch {
            store?.statusMessage = .error("Approve failed: \(error.localizedDescription)")
        }
    }

    func commentOnPR(_ pr: PullRequest, body: String) async {
        let host = prManager.hostFromURL(pr.url)
        do {
            try await prManager.comment(
                repo: pr.repo, number: pr.number, body: body, host: host)
            store?.statusMessage = .success("Commented on #\(pr.number)")
            await refreshPRAfterAction(pr)
        } catch {
            store?.statusMessage = .error("Comment failed: \(error.localizedDescription)")
        }
    }

    func requestChangesOnPR(_ pr: PullRequest, body: String) async {
        let host = prManager.hostFromURL(pr.url)
        do {
            try await prManager.requestChanges(
                repo: pr.repo, number: pr.number, body: body, host: host)
            store?.statusMessage = .success("Requested changes on #\(pr.number)")
            await refreshPRAfterAction(pr)
        } catch {
            store?.statusMessage = .error(
                "Request changes failed: \(error.localizedDescription)")
        }
    }

    func mergePR(_ pr: PullRequest, strategy: MergeStrategy = .squash) async {
        let host = prManager.hostFromURL(pr.url)
        do {
            try await prManager.merge(
                repo: pr.repo, number: pr.number, strategy: strategy, host: host)
            store?.statusMessage = .success("Merged #\(pr.number)")
            await refreshPRAfterAction(pr)
        } catch {
            store?.statusMessage = .error("Merge failed: \(error.localizedDescription)")
        }
    }

    func closePR(_ pr: PullRequest) async {
        let host = prManager.hostFromURL(pr.url)
        do {
            try await prManager.close(repo: pr.repo, number: pr.number, host: host)
            store?.statusMessage = .success("Closed #\(pr.number)")
            await refreshPRAfterAction(pr)
        } catch {
            store?.statusMessage = .error("Close failed: \(error.localizedDescription)")
        }
    }

    func updatePRBranch(_ pr: PullRequest, rebase: Bool = false) async {
        let host = prManager.hostFromURL(pr.url)
        do {
            try await prManager.updateBranch(
                repo: pr.repo, number: pr.number, rebase: rebase, host: host)
            store?.statusMessage = .success(
                "Updated #\(pr.number) with latest \(pr.baseBranch)")
            await refreshPRAfterAction(pr)
        } catch {
            store?.statusMessage = .error(
                "Branch update failed: \(error.localizedDescription)")
        }
    }

    func togglePRDraft(_ pr: PullRequest) async {
        let host = prManager.hostFromURL(pr.url)
        do {
            try await prManager.toggleDraft(
                repo: pr.repo, number: pr.number, makeDraft: !pr.isDraft, host: host)
            store?.statusMessage = .success(
                pr.isDraft
                    ? "Marked #\(pr.number) as ready"
                    : "Converted #\(pr.number) to draft")
            await refreshPRAfterAction(pr)
        } catch {
            store?.statusMessage = .error(
                "Draft toggle failed: \(error.localizedDescription)")
        }
    }

    func enableAutoMerge(_ pr: PullRequest, strategy: MergeStrategy = .squash) async {
        let host = prManager.hostFromURL(pr.url)
        do {
            try await prManager.enableAutoMerge(
                repo: pr.repo, number: pr.number, strategy: strategy, host: host)
            store?.statusMessage = .success("Auto-merge enabled for #\(pr.number)")
            await refreshPRAfterAction(pr)
        } catch {
            store?.statusMessage = .error(
                "Auto-merge failed: \(error.localizedDescription)")
        }
    }

    func disableAutoMerge(_ pr: PullRequest) async {
        let host = prManager.hostFromURL(pr.url)
        do {
            try await prManager.disableAutoMerge(
                repo: pr.repo, number: pr.number, host: host)
            store?.statusMessage = .success("Auto-merge disabled for #\(pr.number)")
            await refreshPRAfterAction(pr)
        } catch {
            store?.statusMessage = .error(
                "Disable auto-merge failed: \(error.localizedDescription)")
        }
    }

    func openPRInBrowser(_ pr: PullRequest) {
        if let url = URL(string: pr.url) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - PR Review Resolution

    func resolvePRForReview(number: Int, repo: String, host: String?) async {
        isResolvingPR = true
        defer { isResolvingPR = false }

        do {
            let pr = try await prManager.resolvePR(repo: repo, number: number, host: host)
            reviewPRCandidate = pr
            showReviewPRSheet = true
        } catch {
            store?.statusMessage = .error(
                "Failed to resolve PR #\(number): \(error.localizedDescription)")
        }
    }
}
