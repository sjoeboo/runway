import Foundation
import SwiftUI
import Models
import Persistence
import Theme
import Terminal
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

    // MARK: - Managers
    let themeManager: ThemeManager
    let database: Database?
    let hookServer: HookServer
    let statusDetector: StatusDetector
    let terminalProvider: NativePTYProvider

    // MARK: - Init

    init() {
        self.themeManager = ThemeManager()
        self.hookServer = HookServer()
        self.statusDetector = StatusDetector()
        self.terminalProvider = NativePTYProvider()

        // Open database
        do {
            self.database = try Database()
        } catch {
            print("[RunwayStore] Failed to open database: \(error)")
            self.database = nil
        }

        // Load initial state
        Task { await loadState() }

        // Start hook server
        Task { await startHookServer() }
    }

    // MARK: - State Loading

    func loadState() async {
        guard let db = database else { return }
        do {
            projects = try db.allProjects()
            sessions = try db.allSessions()
        } catch {
            print("[RunwayStore] Failed to load state: \(error)")
        }
    }

    // MARK: - Session Lifecycle

    func createSession(
        title: String,
        projectID: String?,
        path: String,
        tool: Tool = .claude,
        worktreeBranch: String? = nil
    ) async {
        let session = Session(
            title: title,
            groupID: projectID,
            path: path,
            tool: tool,
            worktreeBranch: worktreeBranch
        )

        sessions.append(session)
        try? database?.saveSession(session)
        selectedSessionID = session.id

        // Start the terminal process
        await startSession(session)
    }

    func startSession(_ session: Session) async {
        let command = session.command ?? session.tool.command
        let env: [String: String] = [
            "RUNWAY_SESSION_ID": session.id,
            "RUNWAY_TITLE": session.title,
            "RUNWAY_TOOL": session.tool.displayName,
        ]

        do {
            let handle = try await terminalProvider.createTerminal(
                id: session.id,
                command: command,
                arguments: [],
                cwd: URL(fileURLWithPath: session.path),
                env: env,
                size: TerminalSize(cols: 120, rows: 40)
            )
            updateSessionStatus(id: session.id, status: .running)
            _ = handle // Will be used by terminal view
        } catch {
            updateSessionStatus(id: session.id, status: .error)
            print("[RunwayStore] Failed to start session: \(error)")
        }
    }

    func stopSession(id: String) async {
        await terminalProvider.terminate(terminal: TerminalHandle(id: id, pid: 0))
        updateSessionStatus(id: id, status: .stopped)
    }

    func deleteSession(id: String) {
        sessions.removeAll { $0.id == id }
        try? database?.deleteSession(id: id)
        if selectedSessionID == id {
            selectedSessionID = sessions.first?.id
        }
    }

    private func updateSessionStatus(id: String, status: SessionStatus) {
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].status = status
        }
        try? database?.updateSessionStatus(id: id, status: status)
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
            print("[RunwayStore] Failed to start hook server: \(error)")
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
