import Foundation
import SwiftUI
import Models
import Persistence
import Theme
import Terminal
import GitOperations
import StatusDetection

/// Root application state — the single source of truth for the Runway app.
@Observable
@MainActor
public final class RunwayStore {
    // MARK: - State
    var sessions: [Session] = []
    var projects: [Project] = []
    var pullRequests: [PullRequest] = []
    var todos: [Todo] = []

    var selectedSessionID: String?
    var currentView: AppView = .sessions
    var showNewSessionDialog: Bool = false
    var showNewProjectDialog: Bool = false
    var statusMessage: String?

    // MARK: - Managers
    let themeManager: ThemeManager
    let database: Database?
    let hookServer: HookServer
    let statusDetector: StatusDetector
    let worktreeManager: WorktreeManager
    let hookInjector: HookInjector

    // MARK: - Init

    init() {
        self.themeManager = ThemeManager()
        self.hookServer = HookServer()
        self.statusDetector = StatusDetector()
        self.worktreeManager = WorktreeManager()
        self.hookInjector = HookInjector()

        // Open database
        do {
            self.database = try Database()
        } catch {
            print("[Runway] Failed to open database: \(error)")
            self.database = nil
        }

        // Load initial state
        Task { await loadState() }

        // Start hook server + inject Claude hooks
        Task { await startHookServer() }
        Task { try? hookInjector.inject() }
    }

    // MARK: - State Loading

    func loadState() async {
        guard let db = database else { return }
        do {
            projects = try db.allProjects()
            sessions = try db.allSessions()
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
                // Worktree failed — create session at project path instead
                print("[Runway] Worktree creation failed, using project path: \(error)")
                statusMessage = "Worktree failed: \(error.localizedDescription)"
                // Don't return — still create the session
            }
        }

        let session = Session(
            title: request.title,
            groupID: request.projectID,
            path: sessionPath,
            tool: request.tool,
            status: .idle,
            worktreeBranch: worktreeBranch
        )

        sessions.append(session)
        try? database?.saveSession(session)
        selectedSessionID = session.id

        // Note: The terminal is managed by Ghostty's TerminalSurfaceView in the UI.
        // We don't need to start a PTY here — the view handles it when displayed.
    }

    // MARK: - Session Lifecycle

    func updateSessionStatus(id: String, status: SessionStatus) {
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].status = status
        }
        try? database?.updateSessionStatus(id: id, status: status)
    }

    func deleteSession(id: String) {
        sessions.removeAll { $0.id == id }
        try? database?.deleteSession(id: id)
        if selectedSessionID == id {
            selectedSessionID = sessions.first?.id
        }
    }

    // MARK: - Project Management

    func createProject(name: String, path: String, defaultBranch: String = "main") {
        let project = Project(name: name, path: path, defaultBranch: defaultBranch)
        projects.append(project)
        try? database?.saveProject(project)
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
        } catch {
            print("[Runway] Failed to start hook server: \(error)")
        }
    }

    private func handleHookEvent(_ event: HookEvent) {
        switch event.event {
        case .sessionStart:
            updateSessionStatus(id: event.sessionID, status: .running)
        case .sessionEnd, .stop:
            updateSessionStatus(id: event.sessionID, status: .idle)
        case .userPromptSubmit:
            updateSessionStatus(id: event.sessionID, status: .running)
        case .permissionRequest:
            updateSessionStatus(id: event.sessionID, status: .waiting)
        case .notification:
            break
        }
    }
}
