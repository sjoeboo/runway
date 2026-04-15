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
    var sessionTemplates: [SessionTemplate] = []
    var agentProfiles: [AgentProfile] = []
    var savedPrompts: [SavedPrompt] = []

    var selectedSessionID: String?
    var currentView: AppView = .sessions
    var activeSheet: ActiveSheet?
    var newSessionProjectID: String?
    var newSessionParentID: String?
    var forkSourceSession: Session?
    var statusMessage: StatusMessage?
    var tmuxAvailable: Bool = false
    var ghAvailable: Bool = false
    var showSendBar: Bool = false
    var showTerminalSearch: Bool = false
    /// Incremented to trigger a horizontal split in the active terminal tab.
    var splitHorizontalTrigger: Int = 0
    /// Incremented to trigger a vertical split in the active terminal tab.
    var splitVerticalTrigger: Int = 0
    /// Incremented to force terminal tab reinitialization after restart.
    var terminalRestartTrigger: Int = 0
    var sidebarSearchQuery: String = ""
    var focusSidebarSearch: Bool = false

    /// Session IDs with in-progress worktree creation (transient, not persisted)
    var provisioningWorktreeIDs: Set<String> = []
    /// Tracks provisioning Tasks so they can be cancelled if the session is deleted mid-provision.
    private var provisioningTasks: [String: Task<Void, Never>] = [:]

    func profileForSession(_ session: Session) -> AgentProfile {
        if case .custom(let name) = session.tool,
            let profile = agentProfiles.first(where: { $0.id == name })
        {
            return profile
        }
        return AgentProfile.defaultProfile(for: session.tool)
    }

    // MARK: - Changes Sidebar
    var changesVisible: Bool = false
    var changesMode: ChangesMode = .branch
    var sessionChanges: [String: [FileChange]] = [:]
    var sessionFileTree: [String: [FileTreeNode]] = [:]
    var viewingDiffFile: FileChange? = nil
    var viewingDiffPatch: String? = nil
    var diffOpenTrigger: Int = 0
    var activeDiffPath: String? = nil
    private var changesRefreshTask: Task<Void, Never>?

    /// Update changes for a single session and rebuild only that session's file tree.
    /// Avoids the previous `didSet` pattern that rebuilt ALL sessions on any change.
    func updateChanges(for sessionID: String, changes: [FileChange]) {
        sessionChanges[sessionID] = changes
        sessionFileTree[sessionID] = buildFileTree(changes)
    }

    var selectedProjectID: String?
    var projectIssues: [String: [GitHubIssue]] = [:]
    var isLoadingIssues: Bool = false
    var projectLabels: [String: [IssueLabel]] = [:]
    var issueLastFetched: [String: Date] = [:]  // keyed by project ID
    var selectedIssueID: String?
    var issueDetail: IssueDetail?
    var isLoadingIssueDetail: Bool = false

    /// True when the database failed to open — shown as a persistent warning in the UI.
    /// All session/project data will be lost on restart when this is true.
    var databaseFailed: Bool = false

    // MARK: - Managers
    let themeManager: ThemeManager
    let database: Database?
    var hookServer: HookServer
    let statusDetector: StatusDetector
    let worktreeManager: WorktreeManager
    let prCoordinator: PRCoordinator
    let hookInjector: HookInjector
    let tmuxManager: TmuxSessionManager
    let issueManager: IssueManager
    let notificationManager: NotificationManager

    // MARK: - Init

    init() {
        self.themeManager = ThemeManager()
        self.hookServer = HookServer()
        self.statusDetector = StatusDetector()
        self.worktreeManager = WorktreeManager()
        self.hookInjector = HookInjector()
        self.tmuxManager = TmuxSessionManager()
        self.issueManager = IssueManager()
        self.notificationManager = NotificationManager()

        // Open database — surface failure to user since silent nil means all writes are lost
        var db: Database?
        do {
            db = try Database()
        } catch {
            print("[Runway] Failed to open database: \(error)")
            db = nil
            self.databaseFailed = true
        }
        self.database = db

        // PRCoordinator owns all PR state — separate @Observable reduces view invalidation scope
        self.prCoordinator = PRCoordinator(prManager: PRManager(), database: db)

        // Wire back-reference after all stored properties are initialized
        prCoordinator.store = self

        if databaseFailed {
            Task { @MainActor [weak self] in
                self?.statusMessage = .error("Database failed to open — session data will not persist.")
            }
        }

        // Check tmux availability, load state, then fetch PRs (sequenced so enrichPRs
        // has sessions available for PR-session linking)
        Task {
            tmuxAvailable = await tmuxManager.isAvailable()
            ghAvailable = (try? await ShellRunner.run(executable: "/usr/bin/env", args: ["gh", "--version"])) != nil
            print("[Runway] tmux available: \(tmuxAvailable), gh available: \(ghAvailable)")

            // Surface missing prerequisites as persistent warning
            var missing: [String] = []
            if !tmuxAvailable { missing.append("tmux") }
            if !ghAvailable { missing.append("gh") }
            if !missing.isEmpty {
                statusMessage = .error(
                    "Missing tools: \(missing.joined(separator: ", ")) — install with `brew install \(missing.joined(separator: " "))`")
            }
            await loadState()
            await prCoordinator.fetchPRs()
            await prCoordinator.seedFingerprint()
            prCoordinator.startPRPoll()
            prCoordinator.startSessionPRPoll()
            notificationManager.requestAuthorization()
            notificationManager.onNotificationTapped = { [weak self] sessionID in
                self?.selectSession(sessionID)
                NSApplication.shared.activate()
            }
        }

        // Start hook server + inject Claude hooks (sequenced — inject needs the port)
        Task { await startHookServer() }

        // Load cached PRs synchronously for instant display while background fetch runs
        prCoordinator.loadCachedPRs()

        // Start buffer-based status detection for sessions without hook events
        startBufferDetection()

        // Remove injected hooks and clean up port file on app termination
        // so agents don't block on a dead port after quit.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [hookInjector, portFile = Self.portFilePath] _ in
            for config in HookInjectionConfig.allBuiltIn {
                try? hookInjector.remove(config: config)
            }
            // Remove persisted port file so next launch doesn't try a dead port
            try? FileManager.default.removeItem(atPath: portFile)
        }
    }

    // MARK: - State Loading

    func loadState() async {
        guard let db = database else { return }
        do {
            projects = try db.allProjects()
            sessions = try db.allSessions()
            sessionTemplates = (try? db.allTemplates()) ?? []
            savedPrompts = (try? db.allPrompts()) ?? []
            agentProfiles = AgentProfile.builtIn + AgentProfile.loadUserProfiles()

            // Auto-detect default branches only for projects that still have the placeholder "main".
            // Projects with an already-detected non-"main" branch skip the git subprocess call.
            for i in projects.indices where projects[i].defaultBranch == "main" {
                let detected = await worktreeManager.detectDefaultBranch(repoPath: projects[i].path)
                if projects[i].defaultBranch != detected {
                    projects[i].defaultBranch = detected
                    try? db.saveProject(projects[i])
                }
            }

            // Auto-detect GitHub repo for projects that don't have one yet
            for i in projects.indices where projects[i].ghRepo == nil {
                if let detected = await issueManager.detectRepo(path: projects[i].path) {
                    projects[i].ghRepo = detected.repo
                    projects[i].ghHost = detected.host
                    projects[i].issuesEnabled = true
                    try? db.saveProject(projects[i])
                }
            }

            // Load cached issues for instant display on startup
            for project in projects {
                if let repo = project.ghRepo,
                    let cached = try? db.cachedIssues(repo: repo, maxAge: 86400), !cached.isEmpty
                {
                    projectIssues[project.id] = cached
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

            // Clean up orphaned worktrees (exist on disk but not in DB)
            await cleanOrphanedWorktrees()
        } catch {
            print("[Runway] Failed to load state: \(error)")
        }

        // Note: loadCachedPRs() is NOT called here — init already called it for
        // instant display, and fetchPRs() (also scheduled from init) replaces the
        // cached data with fresh data. A second loadCachedPRs() would overwrite
        // the fresh fetch results with stale cache.
    }

    /// Remove worktrees that exist on disk but have no matching session in the database.
    /// Mirrors the tmux orphan cleanup in `loadState()`. Branches are only deleted
    /// if they have been fully merged into the project's default branch.
    private func cleanOrphanedWorktrees() async {
        // Collect all worktree paths owned by existing sessions
        let ownedPaths = Set(
            sessions
                .filter { $0.worktreeBranch != nil }
                .flatMap { [$0.path, URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path] }
        )

        var removedCount = 0
        var preservedBranches = 0

        for project in projects {
            // Prune stale git references first (e.g., manually-deleted directories)
            try? await worktreeManager.pruneWorktrees(repoPath: project.path)

            guard let worktrees = try? await worktreeManager.listWorktrees(repoPath: project.path) else {
                continue
            }

            let worktreePrefix = "\(project.path)/.worktrees/"
            let orphans = worktrees.filter { wt in
                let resolvedPath = URL(fileURLWithPath: wt.path).resolvingSymlinksInPath().path
                let isManaged =
                    resolvedPath.hasPrefix(worktreePrefix)
                    || wt.path.hasPrefix(worktreePrefix)
                let isOwned =
                    ownedPaths.contains(wt.path)
                    || ownedPaths.contains(resolvedPath)
                return isManaged && !isOwned
            }

            for orphan in orphans {
                let branchName =
                    orphan.branch.isEmpty
                    ? URL(fileURLWithPath: orphan.path).lastPathComponent
                    : orphan.branch
                let merged =
                    (try? await worktreeManager.isBranchMerged(
                        repoPath: project.path, branch: branchName, into: project.defaultBranch
                    )) ?? false

                do {
                    try await worktreeManager.removeWorktree(
                        repoPath: project.path,
                        worktreePath: orphan.path,
                        deleteBranch: merged
                    )
                    removedCount += 1
                    if !merged {
                        preservedBranches += 1
                        print("[Runway] Preserved unmerged branch for orphaned worktree: \(orphan.path)")
                    }
                } catch {
                    print("[Runway] Failed to remove orphaned worktree \(orphan.path): \(error)")
                }
            }
        }

        if removedCount > 0 {
            let message: String
            if preservedBranches > 0 {
                message =
                    "Cleaned up \(removedCount) orphaned worktree\(removedCount == 1 ? "" : "s") (\(preservedBranches) branch\(preservedBranches == 1 ? "" : "es") preserved \u{2014} unmerged)"
            } else {
                message = "Cleaned up \(removedCount) orphaned worktree\(removedCount == 1 ? "" : "s")"
            }
            statusMessage = .info(message)
        }
    }

    // MARK: - Issue-to-Session Dispatch

    func startSessionFromIssue(_ issue: GitHubIssue, projectID: String) async {
        guard let project = projects.first(where: { $0.id == projectID }) else { return }

        let slug = issue.title.lowercased()
            .replacing(/[^a-z0-9\-]/, with: "-")
            .replacing(/--+/, with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        let prefix = project.branchPrefix ?? "fix/"
        let branchName = "\(prefix)\(issue.number)-\(String(slug.prefix(40)))"

        let prompt = "Implement the changes described in issue #\(issue.number): \(issue.title)"

        // Use the project's most recent session tool, defaulting to .claude
        let projectTool = sessions.last(where: { $0.projectID == projectID })?.tool ?? .claude

        let request = NewSessionRequest(
            title: issue.title,
            projectID: projectID,
            path: project.path,
            tool: projectTool,
            useWorktree: true,
            branchName: branchName,
            permissionMode: project.permissionMode ?? .default,
            initialPrompt: prompt,
            issueNumber: issue.number
        )

        await handleNewSessionRequest(request)
    }

    // MARK: - New Session Request (from dialog)

    func handleNewSessionRequest(_ request: NewSessionRequest) async {
        if database == nil {
            statusMessage = .error("Database unavailable — sessions will not persist across restarts")
        }
        let needsWorktree = request.useWorktree && !(request.branchName ?? "").isEmpty

        // Resolve permission mode: request > project override > default
        var resolvedMode = request.permissionMode
        if resolvedMode == .default, let projectID = request.projectID,
            let project = projects.first(where: { $0.id == projectID }),
            let projectMode = project.permissionMode
        {
            resolvedMode = projectMode
        }

        let session = Session(
            title: request.title,
            projectID: request.projectID,
            path: request.path,
            tool: request.tool,
            status: .starting,
            worktreeBranch: needsWorktree ? request.branchName : nil,
            issueNumber: request.issueNumber,
            parentID: request.parentID,
            permissionMode: resolvedMode,
            useHappy: request.useHappy
        )

        // Add session to UI immediately so the user sees it right away
        sessions.append(session)
        do {
            try database?.saveSession(session)
        } catch {
            print("[Runway] Failed to save session: \(error)")
            statusMessage = .error("Failed to save session: \(error.localizedDescription)")
        }
        selectedSessionID = session.id

        // If worktree needed, create it in the background then start the tmux session
        if needsWorktree, let branchName = request.branchName {
            let project = projects.first(where: { $0.id == request.projectID })
            let baseBranch = request.baseBranch ?? project?.defaultBranch ?? "main"

            provisioningWorktreeIDs.insert(session.id)

            let sessionID = session.id
            provisioningTasks[sessionID] = Task {
                defer { provisioningTasks.removeValue(forKey: sessionID) }
                let sessionPath: String
                let actualBranch: String
                do {
                    let result = try await worktreeManager.createWorktree(
                        repoPath: request.path,
                        branchName: branchName,
                        baseBranch: baseBranch
                    )
                    sessionPath = result.path
                    actualBranch = result.branch
                } catch {
                    print("[Runway] Worktree creation failed: \(error)")
                    provisioningWorktreeIDs.remove(session.id)
                    if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                        sessions[idx].lastError = error.localizedDescription
                    }
                    updateSessionStatus(id: session.id, status: .error)
                    statusMessage = .error("Worktree failed — session cannot start without branch isolation: \(error.localizedDescription)")
                    return
                }

                if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                    sessions[idx].path = sessionPath
                    sessions[idx].worktreeBranch = actualBranch
                }
                try? database?.updateSessionPath(id: session.id, path: sessionPath)
                try? database?.updateSessionBranch(id: session.id, branch: actualBranch)

                provisioningWorktreeIDs.remove(session.id)

                // Now start the tmux session with the resolved path
                await startTmuxSession(for: session, path: sessionPath, initialPrompt: request.initialPrompt)
            }
        } else {
            // No worktree needed — start tmux immediately
            await startTmuxSession(for: session, path: request.path, initialPrompt: request.initialPrompt)
        }
    }

    /// Builds the CLI command string for an agent session.
    /// Returns nil for shell sessions (tmux uses its default shell).
    private func buildAgentCommand(
        session: Session,
        profile: AgentProfile,
        resume: Bool = false
    ) -> String? {
        guard profile.id != "shell" else { return nil }
        var parts: [String] = []
        if session.useHappy {
            parts.append("happy")
            parts.append(session.tool.command)
        } else {
            parts.append(profile.command)
        }
        parts.append(contentsOf: profile.arguments)
        if resume {
            parts.append(contentsOf: profile.resumeArguments)
        }
        if session.tool.supportsPermissionModes {
            parts.append(contentsOf: session.permissionMode.cliFlags(for: session.tool))
        }
        return parts.joined(separator: " ")
    }

    /// Creates the tmux session and updates the session status to .running.
    private func startTmuxSession(for session: Session, path: String, initialPrompt: String? = nil) async {
        guard tmuxAvailable else {
            updateSessionStatus(id: session.id, status: .error)
            statusMessage = .error("tmux not found — install it with: brew install tmux")
            return
        }

        let tmuxName = "runway-\(session.id)"
        let profile = profileForSession(session)
        let toolCommand = buildAgentCommand(session: session, profile: profile, resume: false)

        do {
            try await tmuxManager.createSession(
                name: tmuxName,
                workDir: path,
                command: toolCommand,
                env: [
                    "RUNWAY_SESSION_ID": session.id,
                    "RUNWAY_TITLE": session.title,
                ]
            )
            updateSessionStatus(id: session.id, status: .running)

            if let prompt = initialPrompt, !prompt.isEmpty {
                try? await Task.sleep(for: .milliseconds(500))
                try? await tmuxManager.sendText(sessionName: tmuxName, text: prompt)
            }
        } catch {
            print("[Runway] Failed to create tmux session: \(error)")
            updateSessionStatus(id: session.id, status: .error)
            statusMessage = .error("tmux session failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Session Lifecycle

    func updateSessionStatus(id: String, status: SessionStatus) {
        let previousStatus = sessions.first(where: { $0.id == id })?.status
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].status = status
        }
        do {
            try database?.updateSessionStatus(id: id, status: status)
        } catch {
            print("[Runway] Failed to update session status: \(error)")
        }
        let waitingCount = sessions.filter { $0.status == .waiting }.count
        notificationManager.updateDockBadge(waitingCount: waitingCount)

        // Clear delivered notifications when a session is no longer waiting
        if previousStatus == .waiting, status != .waiting {
            notificationManager.clearDeliveredNotifications(forSessionID: id)
        }
    }

    public func restartSession(id: String) async {
        guard let session = sessions.first(where: { $0.id == id }) else { return }

        // Transition to .starting so TerminalTabView clears its tabs
        updateSessionStatus(id: id, status: .starting)

        // Kill existing tmux sessions (main + shell tabs)
        let tmuxName = "runway-\(id)"
        if tmuxAvailable {
            let shellSessions = await tmuxManager.listSessions(prefix: "runway-\(id)-shell")
            for shell in shellSessions {
                try? await tmuxManager.killSession(name: shell.name)
            }
            try? await tmuxManager.killSession(name: tmuxName)
        }

        // Clear cached terminal view and tab state so TerminalPane creates a fresh one
        TerminalSessionCache.shared.removeAll(forSessionID: id)
        TerminalTabStateCache.shared.remove(sessionID: id)

        // Recreate tmux session
        if tmuxAvailable {
            let profile = profileForSession(session)
            let toolCommand = buildAgentCommand(session: session, profile: profile, resume: true)

            do {
                try await tmuxManager.createSession(
                    name: tmuxName,
                    workDir: session.path,
                    command: toolCommand,
                    env: [
                        "RUNWAY_SESSION_ID": session.id,
                        "RUNWAY_TITLE": session.title,
                    ]
                )
                updateSessionStatus(id: id, status: .running)
                terminalRestartTrigger += 1
            } catch {
                print("[Runway] Failed to restart tmux session: \(error)")
                updateSessionStatus(id: id, status: .error)
            }
        }
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
        TerminalTabStateCache.shared.remove(sessionID: id)
        prCoordinator.sessionDeleted(id: id)
        provisioningTasks[id]?.cancel()
        provisioningTasks.removeValue(forKey: id)
        lastHookEventTime.removeValue(forKey: id)
        sessionChanges.removeValue(forKey: id)
        sessionFileTree.removeValue(forKey: id)
        if selectedSessionID == id {
            selectedSessionID = nextSelection
        }

        // Clean up tmux session (main + shell tabs) and optionally worktree
        Task {
            if tmuxAvailable {
                // Kill shell tab sessions first (runway-{id}-shell1, etc.)
                let shellSessions = await tmuxManager.listSessions(prefix: "runway-\(id)-shell")
                for shell in shellSessions {
                    try? await tmuxManager.killSession(name: shell.name)
                }
                try? await tmuxManager.killSession(name: "runway-\(id)")
            }

            if deleteWorktree, let repoPath = projectPath, let wtPath = sessionPath,
                worktreeBranch != nil
            {
                do {
                    try await worktreeManager.removeWorktree(
                        repoPath: repoPath, worktreePath: wtPath,
                        deleteBranch: true, branchName: worktreeBranch
                    )
                } catch {
                    statusMessage = .error("Worktree cleanup failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Batch Session Actions

    /// Restart all sessions with the given IDs.
    func restartSessions(_ ids: [String]) async {
        for id in ids {
            await restartSession(id: id)
        }
    }

    /// Delete all stopped sessions, optionally cleaning up worktrees for merged branches.
    public func deleteStoppedSessions(deleteWorktrees: Bool = false) {
        let stopped = sessions.filter { $0.status == .stopped }
        for session in stopped {
            deleteSession(id: session.id, deleteWorktree: deleteWorktrees)
        }
        if !stopped.isEmpty {
            statusMessage = .info("Deleted \(stopped.count) stopped session\(stopped.count == 1 ? "" : "s")")
        }
    }

    /// Stop all running/waiting/idle sessions.
    public func stopAllSessions() async {
        let active = sessions.filter { [.running, .waiting, .idle].contains($0.status) }
        for session in active {
            if tmuxAvailable {
                try? await tmuxManager.killSession(name: "runway-\(session.id)")
            }
            updateSessionStatus(id: session.id, status: .stopped)
        }
    }

    // MARK: - Session Template Management

    func saveTemplate(_ template: SessionTemplate) {
        do {
            try database?.saveTemplate(template)
            sessionTemplates = (try? database?.allTemplates()) ?? []
        } catch {
            print("[Runway] Failed to save template: \(error)")
        }
    }

    func deleteTemplate(_ id: String) {
        do {
            try database?.deleteTemplate(id: id)
            sessionTemplates.removeAll { $0.id == id }
        } catch {
            print("[Runway] Failed to delete template: \(error)")
        }
    }

    /// All templates available for a project: built-in + global + project-specific
    func availableTemplates(forProjectID projectID: String?) -> [SessionTemplate] {
        let custom = sessionTemplates.filter { $0.projectID == nil || $0.projectID == projectID }
        return SessionTemplate.builtIn + custom
    }

    // MARK: - Project Management

    func createProject(name: String, path: String, defaultBranch: String = "main") {
        let project = Project(name: name, path: path, defaultBranch: defaultBranch)
        projects.append(project)
        try? database?.saveProject(project)

        // Auto-detect default branch and GitHub repo in background
        let projectID = project.id
        Task {
            let detected = await worktreeManager.detectDefaultBranch(repoPath: path)
            if detected != defaultBranch, let idx = projects.firstIndex(where: { $0.id == projectID }) {
                projects[idx].defaultBranch = detected
                try? database?.saveProject(projects[idx])
            }

            if let repo = await issueManager.detectRepo(path: path),
                let idx = projects.firstIndex(where: { $0.id == projectID })
            {
                projects[idx].ghRepo = repo.repo
                projects[idx].ghHost = repo.host
                projects[idx].issuesEnabled = true
                try? database?.saveProject(projects[idx])
            }
        }
    }

    public func deleteProject(id: String) {
        // Delete all sessions belonging to this project first
        let childSessions = sessions.filter { $0.projectID == id }
        for session in childSessions {
            deleteSession(id: session.id)
        }

        projects.removeAll { $0.id == id }
        try? database?.deleteProject(id: id)
    }

    // MARK: - Navigation

    public func selectProject(_ projectID: String?) {
        selectedProjectID = projectID
        selectedSessionID = nil
        if currentView == .prs {
            currentView = .sessions
        }
    }

    public func selectSession(_ sessionID: String?) {
        selectedSessionID = sessionID
        selectedProjectID = nil
        if currentView == .prs {
            currentView = .sessions
        }
    }

    /// Handles a runway:// deep link URL.
    func handleDeepLink(_ url: URL) {
        guard let destination = DeepLinkRouter.parse(url) else {
            print("[Runway] Unrecognized deep link: \(url)")
            return
        }

        switch destination {
        case .session(let id):
            if sessions.contains(where: { $0.id == id }) {
                selectSession(id)
            } else {
                statusMessage = .info("Session not found — it may have been deleted")
            }
            NSApplication.shared.activate()

        case .pr(let number, let repo):
            if let pr = prCoordinator.pullRequests.first(where: { $0.number == number && $0.repo == repo }) {
                Task { await prCoordinator.selectPR(pr) }
            } else {
                statusMessage = .info("PR #\(number) not found in \(repo) — try refreshing the PR list")
            }
            NSApplication.shared.activate()

        case .newSession:
            activeSheet = .newSession
            NSApplication.shared.activate()
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

    /// Path to persist the hook server port across launches.
    private static let portFilePath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.runway/hook_port"

    private func startHookServer() async {
        // Shared event handler — registered BEFORE start() so no events are missed.
        let registerHandler: (HookServer) async -> Void = { [weak self] server in
            await server.onEvent { [weak self] event in
                Task { @MainActor in
                    self?.handleHookEvent(event)
                }
            }
            // Auto-restart on runtime failure
            await server.setOnFailure { [weak self] in
                Task { @MainActor in
                    print("[Runway] Hook server failed at runtime, attempting restart")
                    await self?.startHookServer()
                }
            }
        }

        do {
            // Determine which port to try first, then create the definitive server.
            let previousPort = Self.loadPersistedPort()

            if let previousPort {
                hookServer = HookServer(port: previousPort)
                await registerHandler(hookServer)
                do {
                    try await hookServer.start()
                } catch {
                    // Previous port unavailable — stop old listener and fall back to ephemeral
                    print("[Runway] Previous port \(previousPort) unavailable, using ephemeral")
                    await hookServer.stop()
                    hookServer = HookServer()
                    await registerHandler(hookServer)
                    try await hookServer.start()
                }
            } else {
                // No saved port — use ephemeral
                await registerHandler(hookServer)
                try await hookServer.start()
            }

            if let port = await hookServer.actualPort {
                Self.persistPort(port)
                for config in HookInjectionConfig.allBuiltIn {
                    do {
                        try hookInjector.inject(port: port, config: config, force: true)
                    } catch {
                        print("[Runway] Failed to inject hooks for \(config.agentID): \(error)")
                    }
                }
            } else {
                print("[Runway] Hook server started but no port available")
            }
        } catch {
            print("[Runway] Failed to start hook server: \(error)")
        }
    }

    private static func loadPersistedPort() -> UInt16? {
        guard let data = try? String(contentsOfFile: portFilePath, encoding: .utf8) else { return nil }
        return UInt16(data.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func persistPort(_ port: UInt16) {
        let dir = (portFilePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? String(port).write(toFile: portFilePath, atomically: true, encoding: .utf8)
    }

    /// Tracks when each session last received a hook event.
    /// Buffer polling defers to hook-based status within this cooldown window.
    private var lastHookEventTime: [String: Date] = [:]
    private let hookPriorityCooldown: TimeInterval = 10

    private func handleHookEvent(_ event: HookEvent) {
        print("[Runway] Hook event: \(event.event.rawValue) for session \(event.sessionID)")
        lastHookEventTime[event.sessionID] = Date()

        // Persist event to activity log
        let sessionEvent = SessionEvent(
            sessionID: event.sessionID,
            eventType: event.event.rawValue,
            prompt: event.prompt,
            toolName: event.toolName,
            message: event.message,
            notificationType: event.notificationType
        )
        Task.detached { [database] in
            try? database?.saveEvent(sessionEvent)
        }

        // Capture transcript path from any event (it's a constant field set on every hook)
        if let path = event.transcriptPath, !path.isEmpty,
            let idx = sessions.firstIndex(where: { $0.id == event.sessionID }),
            sessions[idx].transcriptPath == nil
        {
            sessions[idx].transcriptPath = path
            try? database?.saveSession(sessions[idx])
        }

        switch event.event {
        case .sessionStart:
            updateSessionStatus(id: event.sessionID, status: .running)
        case .sessionEnd:
            updateSessionStatus(id: event.sessionID, status: .stopped)
            // Also capture cost data from SessionEnd (some agents send it here)
            if event.totalCostUSD != nil || event.totalInputTokens != nil {
                if let idx = sessions.firstIndex(where: { $0.id == event.sessionID }) {
                    if let cost = event.totalCostUSD { sessions[idx].totalCostUSD = cost }
                    if let input = event.totalInputTokens { sessions[idx].totalInputTokens = input }
                    if let output = event.totalOutputTokens { sessions[idx].totalOutputTokens = output }
                    try? database?.saveSession(sessions[idx])
                }
            }
        case .stop:
            updateSessionStatus(id: event.sessionID, status: .idle)
            // Capture cost/token data from Stop events
            if let idx = sessions.firstIndex(where: { $0.id == event.sessionID }) {
                if let cost = event.totalCostUSD { sessions[idx].totalCostUSD = cost }
                if let input = event.totalInputTokens { sessions[idx].totalInputTokens = input }
                if let output = event.totalOutputTokens { sessions[idx].totalOutputTokens = output }
                if let path = event.transcriptPath { sessions[idx].transcriptPath = path }
                try? database?.saveSession(sessions[idx])
            }
        case .userPromptSubmit:
            updateSessionStatus(id: event.sessionID, status: .running)
        case .permissionRequest:
            updateSessionStatus(id: event.sessionID, status: .waiting)
        case .notification:
            break
        case .beforeAgent:
            updateSessionStatus(id: event.sessionID, status: .running)
        case .afterAgent:
            updateSessionStatus(id: event.sessionID, status: .idle)
        }

        // Update sidebar activity text for UserPromptSubmit events
        if event.event == .userPromptSubmit, let prompt = event.prompt {
            if let idx = sessions.firstIndex(where: { $0.id == event.sessionID }) {
                sessions[idx].lastActivityText = String(prompt.prefix(80))
            }
        }

        // Post system notification for high-value events
        if NotificationManager.shouldNotify(event: event.event.rawValue) {
            let title =
                sessions.first(where: { $0.id == event.sessionID })?.title
                ?? "Session"
            notificationManager.postSessionNotification(
                sessionID: event.sessionID,
                sessionTitle: title,
                event: event.event.rawValue
            )
        }
    }

    func loadEvents(forSessionID sessionID: String) -> [SessionEvent] {
        (try? database?.events(forSessionID: sessionID, limit: 200)) ?? []
    }

    // MARK: - Buffer-based Status Detection

    private var bufferDetectionTask: Task<Void, Never>?

    /// Polls terminal buffers to detect session status for sessions without hook events.
    /// Runs every 3 seconds. Terminal buffer reads and pattern matching happen on-main
    /// (required by SwiftTerm), but only for sessions that need polling.
    func startBufferDetection() {
        bufferDetectionTask?.cancel()
        bufferDetectionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // Add jitter to prevent alignment with other polling timers (PR 30s, session 15s, changes 10s)
                let jitter = Double.random(in: 0...1)
                try? await Task.sleep(for: .seconds(3 + jitter))
                guard let self, !sessions.isEmpty else { continue }
                pollTerminalBuffers()
            }
        }
    }

    private func pollTerminalBuffers() {
        for i in sessions.indices {
            let session = sessions[i]
            guard session.status != .stopped else { continue }

            // Defer to hook-based status if a hook event arrived recently
            if let lastHook = lastHookEventTime[session.id],
                Date().timeIntervalSince(lastHook) < hookPriorityCooldown
            {
                continue
            }

            // Read last 10 lines from the cached terminal view (matches StatusDetector.detect)
            guard let terminal = TerminalSessionCache.shared.mainTerminal(forSessionID: session.id) else {
                continue
            }

            let terminalAccess = terminal.getTerminal()
            let rows = terminalAccess.rows
            let startRow = max(0, rows - 10)
            var lines: [String] = []
            for row in startRow..<rows {
                if let line = terminalAccess.getLine(row: row) {
                    lines.append(line.translateToString(trimRight: true))
                }
            }
            let content = lines.joined(separator: "\n")
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let profile = profileForSession(session)
            if let detected = statusDetector.detect(content: content, profile: profile),
                detected != session.status
            {
                updateSessionStatus(id: session.id, status: detected)
            }
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

    func selectIssue(_ issue: GitHubIssue?) async {
        selectedIssueID = issue?.id
        issueDetail = nil
        guard let issue else { return }

        isLoadingIssueDetail = true
        defer { isLoadingIssueDetail = false }

        do {
            let host = issue.url.contains("github.com") ? nil : extractHost(from: issue.url)
            let detail = try await issueManager.fetchDetail(repo: issue.repo, number: issue.number, host: host)
            issueDetail = detail
        } catch {
            print("[Runway] Failed to fetch issue detail: \(error)")
        }
    }

    private func extractHost(from urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host, host != "github.com" else { return nil }
        return host
    }

    func editIssue(_ issue: GitHubIssue, title: String?, body: String?) async {
        guard let project = projectForIssue(issue) else { return }
        do {
            try await issueManager.editIssue(repo: issue.repo, number: issue.number, host: project.ghHost, title: title, body: body)
            statusMessage = .success("Issue #\(issue.number) updated")
            issueDetail = try? await issueManager.fetchDetail(repo: issue.repo, number: issue.number, host: project.ghHost)
            await fetchIssues(forProject: project.id)
        } catch {
            statusMessage = .error("Edit failed: \(error.localizedDescription)")
        }
    }

    func commentOnIssue(_ issue: GitHubIssue, body: String) async {
        guard let project = projectForIssue(issue) else { return }
        do {
            try await issueManager.addComment(repo: issue.repo, number: issue.number, host: project.ghHost, body: body)
            statusMessage = .success("Commented on #\(issue.number)")
            issueDetail = try? await issueManager.fetchDetail(repo: issue.repo, number: issue.number, host: project.ghHost)
        } catch {
            statusMessage = .error("Comment failed: \(error.localizedDescription)")
        }
    }

    func closeIssue(_ issue: GitHubIssue, reason: CloseReason) async {
        guard let project = projectForIssue(issue) else { return }
        do {
            try await issueManager.closeIssue(repo: issue.repo, number: issue.number, host: project.ghHost, reason: reason)
            statusMessage = .success("Closed #\(issue.number)")
            issueDetail = try? await issueManager.fetchDetail(repo: issue.repo, number: issue.number, host: project.ghHost)
            await fetchIssues(forProject: project.id)
        } catch {
            statusMessage = .error("Close failed: \(error.localizedDescription)")
        }
    }

    func reopenIssue(_ issue: GitHubIssue) async {
        guard let project = projectForIssue(issue) else { return }
        do {
            try await issueManager.reopenIssue(repo: issue.repo, number: issue.number, host: project.ghHost)
            statusMessage = .success("Reopened #\(issue.number)")
            issueDetail = try? await issueManager.fetchDetail(repo: issue.repo, number: issue.number, host: project.ghHost)
            await fetchIssues(forProject: project.id)
        } catch {
            statusMessage = .error("Reopen failed: \(error.localizedDescription)")
        }
    }

    func updateIssueLabels(_ issue: GitHubIssue, add: [String], remove: [String]) async {
        guard let project = projectForIssue(issue) else { return }
        do {
            try await issueManager.updateLabels(repo: issue.repo, number: issue.number, host: project.ghHost, add: add, remove: remove)
            statusMessage = .success("Labels updated")
            issueDetail = try? await issueManager.fetchDetail(repo: issue.repo, number: issue.number, host: project.ghHost)
            await fetchIssues(forProject: project.id)
        } catch {
            statusMessage = .error("Label update failed: \(error.localizedDescription)")
        }
    }

    func updateIssueAssignees(_ issue: GitHubIssue, add: [String], remove: [String]) async {
        guard let project = projectForIssue(issue) else { return }
        do {
            try await issueManager.updateAssignees(repo: issue.repo, number: issue.number, host: project.ghHost, add: add, remove: remove)
            statusMessage = .success("Assignees updated")
            issueDetail = try? await issueManager.fetchDetail(repo: issue.repo, number: issue.number, host: project.ghHost)
            await fetchIssues(forProject: project.id)
        } catch {
            statusMessage = .error("Assignee update failed: \(error.localizedDescription)")
        }
    }

    private func projectForIssue(_ issue: GitHubIssue) -> Project? {
        projects.first(where: { $0.ghRepo == issue.repo })
    }

    // MARK: - PR Review Session

    func handleReviewPR(pr: PullRequest, sessionName: String, projectID: String?, initialPrompt: String) async {
        guard let project = projects.first(where: { $0.id == projectID }) else {
            statusMessage = .error("No project selected for PR review")
            return
        }

        let resolvedMode = project.permissionMode ?? .default

        let session = Session(
            title: sessionName,
            projectID: projectID,
            path: project.path,
            tool: .claude,
            status: .starting,
            worktreeBranch: pr.headBranch,
            prNumber: pr.number,
            permissionMode: resolvedMode
        )

        // Add session to UI immediately so the user sees it right away
        sessions.append(session)
        do {
            try database?.saveSession(session)
        } catch {
            statusMessage = .error("Failed to save session: \(error.localizedDescription)")
        }
        selectedSessionID = session.id
        currentView = .sessions
        prCoordinator.sessionPRs[session.id] = pr

        // Provision worktree in background, then start tmux
        provisioningWorktreeIDs.insert(session.id)

        let reviewSessionID = session.id
        provisioningTasks[reviewSessionID] = Task {
            defer { provisioningTasks.removeValue(forKey: reviewSessionID) }
            let sessionPath: String
            do {
                sessionPath = try await worktreeManager.checkoutWorktree(
                    repoPath: project.path,
                    branch: pr.headBranch,
                    prNumber: pr.number,
                    ghHost: project.ghHost
                )
            } catch {
                print("[Runway] Worktree checkout failed for PR review: \(error)")
                provisioningWorktreeIDs.remove(session.id)
                updateSessionStatus(id: session.id, status: .error)
                statusMessage = .error("Worktree failed — PR review cannot start without branch isolation: \(error.localizedDescription)")
                return
            }

            // Update session path
            if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[idx].path = sessionPath
            }
            try? database?.updateSessionPath(id: session.id, path: sessionPath)

            provisioningWorktreeIDs.remove(session.id)

            await startTmuxSession(for: session, path: sessionPath, initialPrompt: initialPrompt.isEmpty ? nil : initialPrompt)
        }
    }

    /// Creates a PR review session from the new session dialog — resolves the PR then creates the session.
    func handleReviewSessionRequest(_ request: ReviewSessionRequest) async throws {
        let pr = try await prCoordinator.prManager.resolvePR(repo: request.repo, number: request.prNumber, host: request.host)
        await handleReviewPR(
            pr: pr,
            sessionName: request.sessionName,
            projectID: request.projectID,
            initialPrompt: request.initialPrompt
        )
    }

}

// MARK: - SidebarActions Conformance

extension RunwayStore: SidebarActions {
    public func newSession(projectID: String?, parentID: String? = nil) {
        newSessionProjectID = projectID
        newSessionParentID = parentID
        activeSheet = .newSession
    }

    public func forkSession(id: String) {
        guard let session = sessions.first(where: { $0.id == id }),
            session.worktreeBranch != nil
        else { return }
        forkSourceSession = session
        newSessionProjectID = session.projectID
        newSessionParentID = session.id
        activeSheet = .newSession
    }

    public func newProject() {
        activeSheet = .newProject
    }

    // SidebarActions conformance — delegates to PRCoordinator
    public func selectPR(_ pr: PullRequest?) async {
        await prCoordinator.selectPR(pr, navigate: true)
    }

    public func reviewPR(_ pr: PullRequest) {
        prCoordinator.reviewPRCandidate = pr
        activeSheet = .reviewPRSheet
    }

    // MARK: - Changes Sidebar Actions

    func toggleChangesSidebar() {
        changesVisible.toggle()
        if changesVisible {
            startChangesRefresh()
        } else {
            stopChangesRefresh()
        }
    }

    func selectDiffFile(_ file: FileChange) {
        guard let sessionID = selectedSessionID,
            let session = sessions.first(where: { $0.id == sessionID })
        else { return }
        viewingDiffFile = file
        Task {
            let patch = await worktreeManager.fileDiff(
                path: session.path,
                file: file.path,
                mode: changesMode
            )
            viewingDiffPatch = patch
            diffOpenTrigger += 1
        }
    }

    func dismissDiffView() {
        viewingDiffFile = nil
        viewingDiffPatch = nil
    }

    func fetchChangesForCurrentSession() {
        guard let sessionID = selectedSessionID,
            let session = sessions.first(where: { $0.id == sessionID })
        else { return }
        Task {
            let changes = await worktreeManager.changedFiles(
                path: session.path,
                mode: changesMode
            )
            updateChanges(for: sessionID, changes: changes)
        }
    }

    private func startChangesRefresh() {
        stopChangesRefresh()
        fetchChangesForCurrentSession()
        changesRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, changesVisible else { break }
                fetchChangesForCurrentSession()
            }
        }
    }

    private func stopChangesRefresh() {
        changesRefreshTask?.cancel()
        changesRefreshTask = nil
    }
}

// MARK: - Active Sheet

/// Mutually exclusive sheet presentation — replaces 4 independent booleans.
enum ActiveSheet: Identifiable {
    case newSession
    case newProject
    case reviewPRSheet
    case reviewPRDialog

    var id: String {
        switch self {
        case .newSession: "newSession"
        case .newProject: "newProject"
        case .reviewPRSheet: "reviewPRSheet"
        case .reviewPRDialog: "reviewPRDialog"
        }
    }
}

// MARK: - Status Message

struct StatusMessage: Equatable {
    enum Kind: Equatable { case success, info, error }
    let text: String
    let kind: Kind
    /// Unique ID ensures `.task(id:)` restarts for identical consecutive messages
    let id: UUID

    static func success(_ text: String) -> StatusMessage { .init(text: text, kind: .success, id: UUID()) }
    static func info(_ text: String) -> StatusMessage { .init(text: text, kind: .info, id: UUID()) }
    static func error(_ text: String) -> StatusMessage { .init(text: text, kind: .error, id: UUID()) }
}
