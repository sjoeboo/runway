import Foundation
import GitHubOperations
import GitOperations
import Models
import Persistence
import StatusDetection
import SwiftUI
import Terminal
import TerminalView
import Theme
import Views

/// Root application state — the single source of truth for the Runway app.
@Observable
@MainActor
public final class RunwayStore {
    // MARK: - State
    var sessions: [Session] = []
    var projects: [Project] = []
    var pullRequests: [PullRequest] = []

    var selectedSessionID: String?
    /// Incremented on every selection change to force SwiftUI re-render
    /// when selectedSessionID goes nil→nil (no-op for @Observable).
    var selectionVersion: Int = 0
    var selectedPRID: String?
    var prDetail: PRDetail?
    var prFilter: PRFilter = .mine
    var prLastFetched: Date?
    var isLoadingPRs: Bool = false
    var currentView: AppView = .sessions
    var showNewSessionDialog: Bool = false
    var showNewProjectDialog: Bool = false
    var newSessionProjectID: String?
    var newSessionParentID: String?
    var statusMessage: StatusMessage?
    var tmuxAvailable: Bool = false
    var showSendBar: Bool = false
    var showTerminalSearch: Bool = false
    var sidebarSearchQuery: String = ""
    var focusSidebarSearch: Bool = false

    /// Maps session ID → linked PullRequest (matched by worktree branch)
    var sessionPRs: [String: PullRequest] = [:]

    var selectedProjectID: String?
    var projectIssues: [String: [GitHubIssue]] = [:]
    var isLoadingIssues: Bool = false
    var projectLabels: [String: [IssueLabel]] = [:]
    var issueLastFetched: [String: Date] = [:]  // keyed by project ID

    // MARK: - Managers
    let themeManager: ThemeManager
    let database: Database?
    let hookServer: HookServer
    let statusDetector: StatusDetector
    let worktreeManager: WorktreeManager
    let prManager: PRManager
    let hookInjector: HookInjector
    let tmuxManager: TmuxSessionManager
    let issueManager: IssueManager

    // MARK: - Init

    init() {
        self.themeManager = ThemeManager()
        self.hookServer = HookServer()
        self.statusDetector = StatusDetector()
        self.worktreeManager = WorktreeManager()
        self.prManager = PRManager()
        self.hookInjector = HookInjector()
        self.tmuxManager = TmuxSessionManager()
        self.issueManager = IssueManager()

        // Open database — surface failure to user since silent nil means all writes are lost
        do {
            self.database = try Database()
        } catch {
            print("[Runway] Failed to open database: \(error)")
            self.database = nil
            // Deferred to after init completes since statusMessage triggers UI
            Task { @MainActor [weak self] in
                self?.statusMessage = .error("Database failed to open — session data will not persist. \(error.localizedDescription)")
            }
        }

        // Check tmux availability, load state, then fetch PRs (sequenced so enrichPRs
        // has sessions available for PR-session linking)
        Task {
            tmuxAvailable = await tmuxManager.isAvailable()
            await loadState()
            await fetchPRs()
        }

        // Start hook server + inject Claude hooks (sequenced — inject needs the port)
        Task { await startHookServer() }

        // Load cached PRs synchronously for instant display while background fetch runs
        loadCachedPRs()

        // Start buffer-based status detection for sessions without hook events
        startBufferDetection()
    }

    // MARK: - State Loading

    func loadState() async {
        guard let db = database else { return }
        do {
            projects = try db.allProjects()
            sessions = try db.allSessions()

            // Auto-detect default branches only for projects that still have the placeholder "main".
            // Projects with an already-detected non-"main" branch skip the git subprocess call.
            for i in projects.indices where projects[i].defaultBranch == "main" {
                let detected = await worktreeManager.detectDefaultBranch(repoPath: projects[i].path)
                if projects[i].defaultBranch != detected {
                    projects[i].defaultBranch = detected
                    try? db.saveProject(projects[i])
                }
            }

            // Reconcile DB sessions with live tmux sessions
            if tmuxAvailable {
                let liveTmux = await tmuxManager.listSessions()
                let liveNames = Set(liveTmux.map(\.name))

                for i in sessions.indices {
                    let expectedName = "runway-\(sessions[i].id)"
                    if sessions[i].status != .stopped {
                        if liveNames.contains(expectedName) {
                            // tmux session alive — mark as idle (hooks will update when reattached)
                            sessions[i].status = .idle
                        } else {
                            // tmux session gone — mark as stopped
                            sessions[i].status = .stopped
                        }
                        try? db.updateSessionStatus(id: sessions[i].id, status: sessions[i].status)
                    }
                }

                // Clean up orphaned tmux sessions (exist in tmux but not in DB)
                // Use prefix matching so shell tabs (runway-{id}-shell1) aren't killed
                let dbPrefixes = sessions.map { "runway-\($0.id)" }
                for tmuxSession in liveTmux {
                    let isOwned = dbPrefixes.contains { tmuxSession.name.hasPrefix($0) }
                    if !isOwned {
                        try? await tmuxManager.killSession(name: tmuxSession.name)
                    }
                }
            }
        } catch {
            print("[Runway] Failed to load state: \(error)")
        }

        // Background prefetch PRs so data is ready when user opens PR dashboard
        loadCachedPRs()
        Task { await fetchPRs() }
    }

    // MARK: - New Session Request (from dialog)

    func handleNewSessionRequest(_ request: NewSessionRequest) async {
        var sessionPath = request.path
        var worktreeBranch: String? = nil

        // Try to create worktree if requested (non-fatal — session still created on failure)
        if request.useWorktree, let branchName = request.branchName, !branchName.isEmpty {
            let project = projects.first(where: { $0.id == request.projectID })
            let baseBranch = project?.defaultBranch ?? "main"

            do {
                sessionPath = try await worktreeManager.createWorktree(
                    repoPath: request.path,
                    branchName: branchName,
                    baseBranch: baseBranch
                )
                worktreeBranch = branchName
            } catch {
                print("[Runway] Worktree creation failed, using project path: \(error)")
                statusMessage = .error("Worktree failed: \(error.localizedDescription)")
            }
        }

        // Resolve permission mode: request > project override > default
        var resolvedMode = request.permissionMode
        if resolvedMode == .default, let projectID = request.projectID,
            let project = projects.first(where: { $0.id == projectID }),
            let projectMode = project.permissionMode
        {
            resolvedMode = projectMode
        }

        var session = Session(
            title: request.title,
            projectID: request.projectID,
            path: sessionPath,
            tool: request.tool,
            status: .starting,
            worktreeBranch: worktreeBranch,
            parentID: request.parentID,
            permissionMode: resolvedMode
        )

        // Create tmux session BEFORE adding to UI — TerminalPane needs it to exist
        // when it tries to attach
        if tmuxAvailable {
            let tmuxName = "runway-\(session.id)"
            let command: String?
            if session.tool == .claude {
                command = ([session.tool.command] + session.permissionMode.cliFlags).joined(separator: " ")
            } else if session.tool != .shell {
                command = session.tool.command
            } else {
                command = nil
            }

            do {
                try await tmuxManager.createSession(
                    name: tmuxName,
                    workDir: sessionPath,
                    command: command,
                    env: [
                        "RUNWAY_SESSION_ID": session.id,
                        "RUNWAY_TITLE": session.title,
                    ]
                )
                session.status = .running
            } catch {
                print("[Runway] Failed to create tmux session: \(error)")
                statusMessage = .error("tmux session failed: \(error.localizedDescription)")
                // Fall through — session still created, TerminalPane will use direct spawn fallback
            }
        }

        // Now add to UI — tmux session is ready for TerminalPane to attach
        sessions.append(session)
        do {
            try database?.saveSession(session)
        } catch {
            print("[Runway] Failed to save session: \(error)")
            statusMessage = .error("Failed to save session: \(error.localizedDescription)")
        }
        selectedSessionID = session.id
    }

    // MARK: - Session Lifecycle

    func updateSessionStatus(id: String, status: SessionStatus) {
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].status = status
        }
        do {
            try database?.updateSessionStatus(id: id, status: status)
        } catch {
            print("[Runway] Failed to update session status: \(error)")
        }
    }

    public func restartSession(id: String) async {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions[idx]

        // Kill existing tmux session
        let tmuxName = "runway-\(id)"
        if tmuxAvailable {
            try? await tmuxManager.killSession(name: tmuxName)
        }

        // Clear cached terminal view so TerminalPane creates a fresh one
        TerminalSessionCache.shared.removeAll(forSessionID: id)

        // Recreate tmux session
        if tmuxAvailable {
            let command: String?
            if session.tool == .claude {
                command = ([session.tool.command] + session.permissionMode.cliFlags).joined(separator: " ")
            } else if session.tool != .shell {
                command = session.tool.command
            } else {
                command = nil
            }

            do {
                try await tmuxManager.createSession(
                    name: tmuxName,
                    workDir: session.path,
                    command: command,
                    env: [
                        "RUNWAY_SESSION_ID": session.id,
                        "RUNWAY_TITLE": session.title,
                    ]
                )
                sessions[idx].status = .running
            } catch {
                print("[Runway] Failed to restart tmux session: \(error)")
                sessions[idx].status = .error
            }
        }

        try? database?.updateSessionStatus(id: id, status: sessions[idx].status)
        // Re-select to trigger view refresh
        selectedSessionID = nil
        selectedSessionID = id
    }

    public func deleteSession(id: String, deleteWorktree: Bool = false) {
        // Capture worktree info before removing session from array
        let session = sessions.first(where: { $0.id == id })
        let worktreeBranch = session?.worktreeBranch
        let sessionPath = session?.path
        let projectPath = session.flatMap { sess in
            projects.first(where: { $0.id == sess.projectID })?.path
        }

        // Find next sibling before removing, so we can select it after deletion
        let nextSelection: String? = {
            guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return nil }
            let projectID = sessions[idx].projectID
            let siblings = sessions.filter { $0.projectID == projectID }
            guard let siblingIdx = siblings.firstIndex(where: { $0.id == id }) else { return nil }
            if siblingIdx + 1 < siblings.count {
                return siblings[siblingIdx + 1].id  // next sibling
            } else if siblingIdx > 0 {
                return siblings[siblingIdx - 1].id  // previous sibling
            }
            return nil
        }()

        sessions.removeAll { $0.id == id }
        try? database?.deleteSession(id: id)
        TerminalSessionCache.shared.removeAll(forSessionID: id)
        if selectedSessionID == id {
            selectedSessionID = nextSelection
        }

        // Clean up tmux session and optionally worktree
        Task {
            if tmuxAvailable {
                try? await tmuxManager.killSession(name: "runway-\(id)")
            }

            if deleteWorktree, let repoPath = projectPath, let wtPath = sessionPath,
                worktreeBranch != nil
            {
                do {
                    try await worktreeManager.removeWorktree(
                        repoPath: repoPath, worktreePath: wtPath, deleteBranch: true
                    )
                } catch {
                    await MainActor.run {
                        statusMessage = .error("Worktree cleanup failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - Project Management

    func createProject(name: String, path: String, defaultBranch: String = "main") {
        let project = Project(name: name, path: path, defaultBranch: defaultBranch)
        projects.append(project)
        try? database?.saveProject(project)

        // Auto-detect default branch in background
        let projectID = project.id
        Task {
            let detected = await worktreeManager.detectDefaultBranch(repoPath: path)
            if detected != defaultBranch, let idx = projects.firstIndex(where: { $0.id == projectID }) {
                projects[idx].defaultBranch = detected
                try? database?.saveProject(projects[idx])
            }
        }
    }

    public func deleteProject(id: String) {
        projects.removeAll { $0.id == id }
        try? database?.deleteProject(id: id)
    }

    // MARK: - Navigation

    public func selectProject(_ projectID: String?) {
        selectedProjectID = projectID
        selectedSessionID = nil
        selectionVersion += 1
    }

    public func selectSession(_ sessionID: String?) {
        selectedSessionID = sessionID
        selectedProjectID = nil
        selectionVersion += 1
        if currentView == .prs {
            currentView = .sessions
        }
    }

    // MARK: - Project Settings

    func updateProjectSettings(_ project: Project) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
            try? database?.updateProject(project)
        }
    }

    func detectGHRepo(for project: Project) async -> (repo: String, host: String?)? {
        await issueManager.detectRepo(path: project.path)
    }

    // MARK: - Renaming

    public func renameSession(id: String, title: String) {
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].title = title
            try? database?.saveSession(sessions[idx])
        }
    }

    public func renameProject(id: String, name: String) {
        if let idx = projects.firstIndex(where: { $0.id == id }) {
            projects[idx].name = name
            try? database?.saveProject(projects[idx])
        }
    }

    // MARK: - Reordering

    public func reorderSessions(in projectID: String?, fromOffsets: IndexSet, toOffset: Int) {
        var subset = sessions.filter { $0.projectID == projectID }
        subset.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for (i, session) in subset.enumerated() {
            if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[idx].sortOrder = i
                try? database?.updateSessionSortOrder(id: session.id, sortOrder: i)
            }
        }
    }

    public func reorderProjects(fromOffsets: IndexSet, toOffset: Int) {
        projects.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for i in projects.indices {
            projects[i].sortOrder = i
            try? database?.updateProjectSortOrder(id: projects[i].id, sortOrder: i)
        }
    }

    // MARK: - Hook Server

    private func startHookServer() async {
        await hookServer.onEvent { [weak self] event in
            Task { @MainActor in
                self?.handleHookEvent(event)
            }
        }

        do {
            try await hookServer.start()

            // Always re-inject hooks — port is ephemeral, so previous hooks may point
            // to a stale port from a prior launch.
            if let port = await hookServer.actualPort {
                try hookInjector.inject(port: port, force: true)
            } else {
                print("[Runway] Hook server started but no port available")
            }
        } catch {
            print("[Runway] Failed to start hook server: \(error)")
        }
    }

    private func handleHookEvent(_ event: HookEvent) {
        print("[Runway] Hook event: \(event.event.rawValue) for session \(event.sessionID)")
        switch event.event {
        case .sessionStart:
            updateSessionStatus(id: event.sessionID, status: .running)
        case .sessionEnd:
            updateSessionStatus(id: event.sessionID, status: .stopped)
        case .stop:
            updateSessionStatus(id: event.sessionID, status: .idle)
        case .userPromptSubmit:
            updateSessionStatus(id: event.sessionID, status: .running)
        case .permissionRequest:
            updateSessionStatus(id: event.sessionID, status: .waiting)
        case .notification:
            break
        }
    }

    // MARK: - Buffer-based Status Detection

    /// Polls terminal buffers to detect session status for sessions without hook events.
    /// Runs every 3 seconds and updates status based on terminal content analysis.
    func startBufferDetection() {
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                pollTerminalBuffers()
            }
        }
    }

    private func pollTerminalBuffers() {
        for i in sessions.indices {
            let session = sessions[i]
            guard session.status != .stopped else { continue }

            // Read last 15 lines from the cached terminal view
            guard let terminal = TerminalSessionCache.shared.mainTerminal(forSessionID: session.id) else {
                continue
            }

            let terminalAccess = terminal.getTerminal()
            let rows = terminalAccess.rows
            let startRow = max(0, rows - 15)
            var lines: [String] = []
            for row in startRow..<rows {
                if let line = terminalAccess.getLine(row: row) {
                    lines.append(line.translateToString(trimRight: true))
                }
            }
            let content = lines.joined(separator: "\n")
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            if let detected = statusDetector.detect(content: content, tool: session.tool),
                detected != session.status
            {
                sessions[i].status = detected
                try? database?.updateSessionStatus(id: session.id, status: detected)
            }
        }
    }

    // MARK: - Pull Requests

    /// Load cached PRs from database for instant display on startup.
    func loadCachedPRs() {
        if let cached = try? database?.cachedPRs(maxAge: 3600), !cached.isEmpty {
            pullRequests = cached
        }
    }

    func fetchPRs(filter: PRFilter? = nil) async {
        if let filter { prFilter = filter }
        isLoadingPRs = true
        defer { isLoadingPRs = false }

        do {
            // Search across all repos — like Hangar, shows all user's PRs globally
            let freshPRs = try await prManager.fetchPRs(filter: prFilter)
            prLastFetched = Date()

            // Merge: keep enriched data from cache/previous enrichment where available
            let existingByID = Dictionary(pullRequests.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            pullRequests = freshPRs.map { fresh in
                guard var existing = existingByID[fresh.id] else { return fresh }
                // Update fields that search refreshes (state, title, etc.)
                existing.title = fresh.title
                existing.state = fresh.state
                existing.isDraft = fresh.isDraft
                existing.author = fresh.author
                return existing
            }

            // Background: enrich any PRs that don't have detail data yet
            Task { await enrichPRs() }
        } catch {
            print("[Runway] Failed to fetch PRs: \(error)")
            statusMessage = .error("PR fetch failed: \(error.localizedDescription)")
        }
    }

    /// Background-enrich PRs with checks and review decision only (not full detail).
    /// Like Hangar, fetches only statusCheckRollup+reviewDecision — 1 subprocess per PR
    /// instead of 2 (fetchDetail + REST files).
    private func enrichPRs() async {
        let toEnrich = pullRequests.filter { $0.checks.total == 0 }
        guard !toEnrich.isEmpty else {
            await linkSessionPRs()
            return
        }

        // Lightweight enrichment: checks + review decision only
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

        // Merge in a single pass
        var updated = pullRequests
        for i in updated.indices {
            guard let result = enriched[updated[i].id] else { continue }
            updated[i].checks = result.checks
            updated[i].reviewDecision = result.reviewDecision
            if !result.headBranch.isEmpty {
                updated[i].headBranch = result.headBranch
                updated[i].baseBranch = result.baseBranch
            }
            updated[i].additions = result.additions
            updated[i].deletions = result.deletions
            updated[i].changedFiles = result.changedFiles
        }
        pullRequests = updated

        try? database?.cachePRs(pullRequests)
        try? database?.cleanPRCache()

        await linkSessionPRs()
    }

    /// Link PRs to sessions — concurrent, like Hangar.
    private func linkSessionPRs() async {
        let worktreeSessions = sessions.filter { $0.worktreeBranch != nil }
        guard !worktreeSessions.isEmpty else { return }

        await withTaskGroup(of: (String, PullRequest?).self) { group in
            for session in worktreeSessions {
                group.addTask { [prManager] in
                    let pr = try? await prManager.fetchPRForWorktree(path: session.path)
                    return (session.id, pr)
                }
            }
            for await (sessionID, pr) in group {
                if let pr {
                    sessionPRs[sessionID] = pr
                }
            }
        }
    }

    func refreshPRsIfStale() async {
        let staleness: TimeInterval = 60
        if let last = prLastFetched, Date().timeIntervalSince(last) < staleness { return }
        await fetchPRs()
    }

    /// In-memory detail cache with 5-minute TTL (matches Hangar).
    private var detailCache: [String: (detail: PRDetail, fetchedAt: Date)] = [:]
    private let detailTTL: TimeInterval = 300

    func selectPR(_ pr: PullRequest?, navigate: Bool = true) async {
        selectedPRID = pr?.id
        prDetail = nil
        guard let pr else { return }

        if navigate {
            currentView = .prs
        }

        // Check cache first
        if let cached = detailCache[pr.id], Date().timeIntervalSince(cached.fetchedAt) < detailTTL {
            prDetail = cached.detail
            return
        }

        do {
            let host = prManager.hostFromURL(pr.url)
            let detail = try await prManager.fetchDetail(repo: pr.repo, number: pr.number, host: host)
            detailCache[pr.id] = (detail, Date())
            prDetail = detail
        } catch {
            print("[Runway] Failed to fetch PR detail: \(error)")
        }
    }

    func approvePR(_ pr: PullRequest) async {
        let host = prManager.hostFromURL(pr.url)
        do {
            try await prManager.approve(repo: pr.repo, number: pr.number, host: host)
            statusMessage = .success("Approved #\(pr.number)")
            await fetchPRs()
        } catch {
            statusMessage = .error("Approve failed: \(error.localizedDescription)")
        }
    }

    func commentOnPR(_ pr: PullRequest, body: String) async {
        let host = prManager.hostFromURL(pr.url)
        do {
            try await prManager.comment(repo: pr.repo, number: pr.number, body: body, host: host)
            // Refresh detail to show new comment
            prDetail = try await prManager.fetchDetail(repo: pr.repo, number: pr.number, host: host)
        } catch {
            statusMessage = .error("Comment failed: \(error.localizedDescription)")
        }
    }

    func requestChangesOnPR(_ pr: PullRequest, body: String) async {
        let host = prManager.hostFromURL(pr.url)
        do {
            try await prManager.requestChanges(repo: pr.repo, number: pr.number, body: body, host: host)
            statusMessage = .success("Requested changes on #\(pr.number)")
            prDetail = try await prManager.fetchDetail(repo: pr.repo, number: pr.number, host: host)
            await fetchPRs()
        } catch {
            statusMessage = .error("Request changes failed: \(error.localizedDescription)")
        }
    }

    func mergePR(_ pr: PullRequest, strategy: MergeStrategy = .squash) async {
        let host = prManager.hostFromURL(pr.url)
        do {
            try await prManager.merge(repo: pr.repo, number: pr.number, strategy: strategy, host: host)
            statusMessage = .success("Merged #\(pr.number)")
            await fetchPRs()
        } catch {
            statusMessage = .error("Merge failed: \(error.localizedDescription)")
        }
    }

    func togglePRDraft(_ pr: PullRequest) async {
        let host = prManager.hostFromURL(pr.url)
        do {
            try await prManager.toggleDraft(repo: pr.repo, number: pr.number, makeDraft: !pr.isDraft, host: host)
            statusMessage = .success(pr.isDraft ? "Marked #\(pr.number) as ready" : "Converted #\(pr.number) to draft")
            await fetchPRs()
        } catch {
            statusMessage = .error("Draft toggle failed: \(error.localizedDescription)")
        }
    }

    func openPRInBrowser(_ pr: PullRequest) {
        if let url = URL(string: pr.url) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Issues

    func fetchIssues(forProject projectID: String) async {
        guard let project = projects.first(where: { $0.id == projectID }),
            let repo = project.ghRepo, project.issuesEnabled
        else { return }

        isLoadingIssues = true
        defer { isLoadingIssues = false }

        do {
            let issues = try await issueManager.fetchIssues(repo: repo, host: project.ghHost)
            projectIssues[projectID] = issues
            issueLastFetched[projectID] = Date()
            try? database?.cacheIssues(issues)
        } catch {
            statusMessage = .error("Failed to fetch issues: \(error.localizedDescription)")
        }
    }

    func refreshIssuesIfStale(forProject projectID: String) async {
        let staleness: TimeInterval = 60
        if let last = issueLastFetched[projectID], Date().timeIntervalSince(last) < staleness { return }
        await fetchIssues(forProject: projectID)
    }

    func createIssue(forProject projectID: String, title: String, body: String, labels: [String]) async {
        guard let project = projects.first(where: { $0.id == projectID }),
            let repo = project.ghRepo
        else { return }

        do {
            try await issueManager.createIssue(repo: repo, host: project.ghHost, title: title, body: body, labels: labels)
            statusMessage = .success("Issue created")
            await fetchIssues(forProject: projectID)
        } catch {
            statusMessage = .error("Failed to create issue: \(error.localizedDescription)")
        }
    }

    func fetchLabels(forProject projectID: String) async {
        guard let project = projects.first(where: { $0.id == projectID }),
            let repo = project.ghRepo
        else { return }

        do {
            let labels = try await issueManager.fetchLabels(repo: repo, host: project.ghHost)
            projectLabels[projectID] = labels
        } catch {
            // Labels are optional — don't show error
        }
    }

    func openIssueInBrowser(_ issue: GitHubIssue) {
        if let url = URL(string: issue.url) {
            NSWorkspace.shared.open(url)
        }
    }

}

// MARK: - SidebarActions Conformance

extension RunwayStore: SidebarActions {
    public func newSession(projectID: String?, parentID: String? = nil) {
        newSessionProjectID = projectID
        newSessionParentID = parentID
        showNewSessionDialog = true
    }

    public func newProject() {
        showNewProjectDialog = true
    }
}

// MARK: - Status Message

struct StatusMessage: Equatable {
    enum Kind { case success, info, error }
    let text: String
    let kind: Kind

    static func success(_ text: String) -> StatusMessage { .init(text: text, kind: .success) }
    static func info(_ text: String) -> StatusMessage { .init(text: text, kind: .info) }
    static func error(_ text: String) -> StatusMessage { .init(text: text, kind: .error) }
}
