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

/// Root application state — the single source of truth for the Runway app.
@Observable
@MainActor
public final class RunwayStore {
    // MARK: - State
    var sessions: [Session] = []
    var projects: [Project] = []
    var pullRequests: [PullRequest] = []

    var selectedSessionID: String?
    var selectedPRID: String?
    var prDetail: PRDetail?
    var prFilter: PRFilter = .mine
    var prLastFetched: Date?
    var isLoadingPRs: Bool = false
    var currentView: AppView = .sessions
    var showNewSessionDialog: Bool = false
    var showNewProjectDialog: Bool = false
    var newSessionProjectID: String?
    var statusMessage: StatusMessage?
    var tmuxAvailable: Bool = false

    // MARK: - Managers
    let themeManager: ThemeManager
    let database: Database?
    let hookServer: HookServer
    let statusDetector: StatusDetector
    let worktreeManager: WorktreeManager
    let prManager: PRManager
    let hookInjector: HookInjector
    let tmuxManager: TmuxSessionManager

    // MARK: - Init

    init() {
        self.themeManager = ThemeManager()
        self.hookServer = HookServer()
        self.statusDetector = StatusDetector()
        self.worktreeManager = WorktreeManager()
        self.prManager = PRManager()
        self.hookInjector = HookInjector()
        self.tmuxManager = TmuxSessionManager()

        // Open database
        do {
            self.database = try Database()
        } catch {
            print("[Runway] Failed to open database: \(error)")
            self.database = nil
        }

        // Check tmux availability, then load state (reconciliation needs tmux status)
        Task {
            tmuxAvailable = await tmuxManager.isAvailable()
            await loadState()
        }

        // Start hook server + inject Claude hooks (sequenced — inject needs the port)
        Task { await startHookServer() }

        // Fetch PRs on launch
        Task { await fetchPRs() }
    }

    // MARK: - State Loading

    func loadState() async {
        guard let db = database else { return }
        do {
            projects = try db.allProjects()
            sessions = try db.allSessions()

            // Auto-detect default branches for projects that still have the placeholder "main"
            for i in projects.indices {
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

        var session = Session(
            title: request.title,
            groupID: request.projectID,
            path: sessionPath,
            tool: request.tool,
            status: .starting,
            worktreeBranch: worktreeBranch,
            permissionMode: request.permissionMode
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
        try? database?.saveSession(session)
        selectedSessionID = session.id
    }

    // MARK: - Session Lifecycle

    func updateSessionStatus(id: String, status: SessionStatus) {
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].status = status
        }
        try? database?.updateSessionStatus(id: id, status: status)
    }

    func restartSession(id: String) async {
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

    func deleteSession(id: String) {
        sessions.removeAll { $0.id == id }
        try? database?.deleteSession(id: id)
        if selectedSessionID == id {
            selectedSessionID = sessions.first?.id
        }

        // Clean up tmux session
        if tmuxAvailable {
            Task {
                try? await tmuxManager.killSession(name: "runway-\(id)")
            }
        }
    }

    // MARK: - Project Management

    func createProject(name: String, path: String, defaultBranch: String = "main") {
        var project = Project(name: name, path: path, defaultBranch: defaultBranch)
        projects.append(project)
        try? database?.saveProject(project)

        // Auto-detect default branch in background
        Task {
            let detected = await worktreeManager.detectDefaultBranch(repoPath: path)
            if detected != defaultBranch, let idx = projects.firstIndex(where: { $0.id == project.id }) {
                projects[idx].defaultBranch = detected
                project.defaultBranch = detected
                try? database?.saveProject(project)
            }
        }
    }

    func deleteProject(id: String) {
        projects.removeAll { $0.id == id }
        try? database?.deleteProject(id: id)
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

            // Inject Claude hooks with the actual port
            if let port = await hookServer.actualPort {
                try hookInjector.inject(port: port)
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

    // MARK: - Pull Requests

    func fetchPRs(filter: PRFilter? = nil) async {
        if let filter { prFilter = filter }
        isLoadingPRs = true
        defer { isLoadingPRs = false }

        do {
            var allPRs: [PullRequest] = []

            if projects.isEmpty {
                // No projects — fetch for current repo context
                allPRs = try await prManager.fetchPRs(filter: prFilter)
            } else {
                // Fetch PRs for each project's repo
                for project in projects {
                    let repo = await detectRepo(for: project)
                    guard let repo else { continue }
                    let prs = try await prManager.fetchPRs(repo: repo, filter: prFilter)
                    allPRs.append(contentsOf: prs)
                }
            }

            pullRequests = allPRs
            prLastFetched = Date()
        } catch {
            print("[Runway] Failed to fetch PRs: \(error)")
            statusMessage = .error("PR fetch failed: \(error.localizedDescription)")
        }
    }

    func refreshPRsIfStale() async {
        let staleness: TimeInterval = 60
        if let last = prLastFetched, Date().timeIntervalSince(last) < staleness { return }
        await fetchPRs()
    }

    func selectPR(_ pr: PullRequest?) async {
        selectedPRID = pr?.id
        prDetail = nil
        guard let pr else { return }

        do {
            prDetail = try await prManager.fetchDetail(repo: pr.repo, number: pr.number)
        } catch {
            print("[Runway] Failed to fetch PR detail: \(error)")
        }
    }

    func approvePR(_ pr: PullRequest) async {
        do {
            try await prManager.approve(repo: pr.repo, number: pr.number)
            statusMessage = .success("Approved #\(pr.number)")
            await fetchPRs()
        } catch {
            statusMessage = .error("Approve failed: \(error.localizedDescription)")
        }
    }

    func commentOnPR(_ pr: PullRequest, body: String) async {
        do {
            try await prManager.comment(repo: pr.repo, number: pr.number, body: body)
            // Refresh detail to show new comment
            prDetail = try await prManager.fetchDetail(repo: pr.repo, number: pr.number)
        } catch {
            statusMessage = .error("Comment failed: \(error.localizedDescription)")
        }
    }

    func openPRInBrowser(_ pr: PullRequest) {
        if let url = URL(string: pr.url) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Detect the GitHub "owner/repo" slug for a project by running `gh repo view`.
    private func detectRepo(for project: Project) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"]
        process.currentDirectoryURL = URL(fileURLWithPath: project.path)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == false ? output : nil
        } catch {
            return nil
        }
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
