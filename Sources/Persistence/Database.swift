import Foundation
import GRDB
import Models

/// SQLite database manager using GRDB.
/// Production uses DatabasePool (WAL, concurrent reads during writes).
/// Tests use DatabaseQueue (in-memory, serial).
public final class Database: Sendable {
    private let db: any DatabaseWriter

    /// Open or create the database at the given path.
    /// Uses DatabasePool for concurrent reads during writes.
    public init(path: String? = nil) throws {
        let dbPath = path ?? Database.defaultPath()

        // Ensure directory exists
        let dir = (dbPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var config = Configuration()
        config.prepareDatabase { db in
            // NORMAL is safe with WAL — only risks data loss on power failure, not OS crash.
            // Reduces write latency by ~1ms per write (hot path: every hook status update).
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            // 5-second busy timeout for inter-process serialization
            try db.execute(sql: "PRAGMA busy_timeout = 5000")
        }

        // DatabasePool enables concurrent reads during writes via WAL mode
        db = try DatabasePool(path: dbPath, configuration: config)
        try migrate()
    }

    /// In-memory database for testing.
    /// Uses DatabaseQueue since DatabasePool requires a file path for WAL.
    public init(inMemory: Bool) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA busy_timeout = 5000")
        }
        db = try DatabaseQueue(configuration: config)
        try migrate()
    }

    // MARK: - Migrations

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "projects") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("path", .text).notNull()
                t.column("defaultBranch", .text).notNull().defaults(to: "main")
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "groups") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("projectID", .text).notNull()
                    .references("projects", onDelete: .cascade)
                t.column("parentGroupID", .text)
                    .references("groups", onDelete: .setNull)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("isExpanded", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "sessions") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("groupID", .text)
                    .references("groups", onDelete: .setNull)
                t.column("path", .text).notNull()
                t.column("tool", .text).notNull().defaults(to: "claude")
                t.column("status", .text).notNull().defaults(to: "starting")
                t.column("worktreeBranch", .text)
                t.column("parentID", .text)
                    .references("sessions", onDelete: .setNull)
                t.column("command", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("lastAccessedAt", .datetime).notNull()
            }

            try db.create(table: "todos") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("prompt", .text)
                t.column("projectID", .text)
                    .references("projects", onDelete: .setNull)
                t.column("sessionID", .text)
                    .references("sessions", onDelete: .setNull)
                t.column("status", .text).notNull().defaults(to: "todo")
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "metadata") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }

            // Set schema version
            try db.execute(sql: "INSERT INTO metadata (key, value) VALUES ('schema_version', '1')")
        }

        migrator.registerMigration("v2_permission_mode") { db in
            try db.alter(table: "sessions") { t in
                t.add(column: "permissionMode", .text).notNull().defaults(to: "default")
            }
        }

        // Fix: sessions.groupID referenced "groups" table but code stores project IDs.
        // GRDB enforces FK constraints by default, so saveSession() silently failed
        // for any session assigned to a project. Recreate without the FK constraint.
        migrator.registerMigration("v3_fix_session_groupid_fk") { db in
            try db.create(table: "sessions_new") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("groupID", .text)  // No FK — stores project ID directly
                t.column("path", .text).notNull()
                t.column("tool", .text).notNull().defaults(to: "claude")
                t.column("status", .text).notNull().defaults(to: "starting")
                t.column("worktreeBranch", .text)
                t.column("parentID", .text)
                t.column("command", .text)
                t.column("permissionMode", .text).notNull().defaults(to: "default")
                t.column("createdAt", .datetime).notNull()
                t.column("lastAccessedAt", .datetime).notNull()
            }

            try db.execute(
                sql: """
                    INSERT INTO sessions_new
                    SELECT id, title, groupID, path, tool, status, worktreeBranch,
                           parentID, command, permissionMode, createdAt, lastAccessedAt
                    FROM sessions
                    """)

            try db.drop(table: "sessions")
            try db.rename(table: "sessions_new", to: "sessions")
        }

        migrator.registerMigration("v4_pr_cache") { db in
            try db.create(table: "pr_cache") { t in
                t.primaryKey("id", .text)  // "owner/repo#number"
                t.column("json", .text).notNull()  // Full PullRequest as JSON
                t.column("fetchedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v5_session_sort_order") { db in
            try db.alter(table: "sessions") { t in
                t.add(column: "sortOrder", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("v6_project_settings_and_issues") { db in
            try db.alter(table: "projects") { t in
                t.add(column: "themeID", .text)
                t.add(column: "permissionMode", .text)
                t.add(column: "ghRepo", .text)
                t.add(column: "ghHost", .text)
                t.add(column: "issuesEnabled", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "issue_cache") { t in
                t.primaryKey("id", .text)
                t.column("json", .text).notNull()
                t.column("fetchedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v7_rename_groupid_to_projectid") { db in
            try db.alter(table: "sessions") { t in
                t.rename(column: "groupID", to: "projectID")
            }
        }

        migrator.registerMigration("v8_project_branch_prefix") { db in
            try db.alter(table: "projects") { t in
                t.add(column: "branchPrefix", .text)
            }
        }

        migrator.registerMigration("v9_session_pr_number") { db in
            try db.alter(table: "sessions") { t in
                t.add(column: "prNumber", .integer)
            }
        }

        migrator.registerMigration("v10_indexes") { db in
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_sessions_projectid ON sessions(projectID)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_sessions_status ON sessions(status)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_pr_cache_fetchedat ON pr_cache(fetchedAt)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_issue_cache_fetchedat ON issue_cache(fetchedAt)")
        }

        migrator.registerMigration("v11_session_issue_number") { db in
            try db.alter(table: "sessions") { t in
                t.add(column: "issueNumber", .integer)
            }
        }

        migrator.registerMigration("v12_session_events") { db in
            try db.create(table: "session_events") { t in
                t.column("id", .text).primaryKey()
                t.column("sessionID", .text).notNull()
                t.column("eventType", .text).notNull()
                t.column("prompt", .text)
                t.column("toolName", .text)
                t.column("message", .text)
                t.column("notificationType", .text)
                t.column("createdAt", .datetime).notNull()
            }
            try db.execute(
                sql: "CREATE INDEX idx_session_events_session ON session_events(sessionID, createdAt)"
            )
        }

        migrator.registerMigration("v13_session_templates") { db in
            try db.create(table: "session_templates") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("projectID", .text)
                t.column("tool", .text).notNull().defaults(to: "claude")
                t.column("useWorktree", .boolean).notNull().defaults(to: true)
                t.column("branchPrefix", .text)
                t.column("permissionMode", .text).notNull().defaults(to: "default")
                t.column("initialPromptTemplate", .text).notNull().defaults(to: "")
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v14_session_use_happy") { db in
            try db.alter(table: "sessions") { t in
                t.add(column: "useHappy", .boolean).notNull().defaults(to: false)
            }
        }

        // Drop unused legacy tables from v1 that are no longer referenced by any code.
        migrator.registerMigration("v15_drop_unused_tables") { db in
            try db.drop(table: "todos")
            try db.drop(table: "groups")
            try db.drop(table: "metadata")
        }

        migrator.registerMigration("v16_saved_prompts") { db in
            try db.create(table: "saved_prompts") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("text", .text).notNull()
                t.column("projectID", .text)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v17_session_cost_tracking") { db in
            try db.alter(table: "sessions") { t in
                t.add(column: "totalCostUSD", .double)
                t.add(column: "totalInputTokens", .integer)
                t.add(column: "totalOutputTokens", .integer)
                t.add(column: "transcriptPath", .text)
            }
        }

        try migrator.migrate(db)
    }

    // MARK: - Default Path

    public static func defaultPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.runway/state.db"
    }

    // MARK: - Session CRUD

    public func allSessions() throws -> [Session] {
        try db.read { db in
            try SessionRecord.order(Column("sortOrder"), Column("createdAt")).fetchAll(db).map { $0.toSession() }
        }
    }

    public func session(id: String) throws -> Session? {
        try db.read { db in
            try SessionRecord.fetchOne(db, key: id)?.toSession()
        }
    }

    public func saveSession(_ session: Session) throws {
        try db.write { db in
            var record = SessionRecord(session)
            try record.save(db)
        }
    }

    public func deleteSession(id: String) throws {
        try db.write { db in
            _ = try SessionRecord.deleteOne(db, key: id)
        }
    }

    public func updateSessionStatus(id: String, status: SessionStatus) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE sessions SET status = ?, lastAccessedAt = ? WHERE id = ?",
                arguments: [status.rawValue, Date(), id]
            )
        }
    }

    public func updateSessionPath(id: String, path: String) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE sessions SET path = ?, lastAccessedAt = ? WHERE id = ?",
                arguments: [path, Date(), id]
            )
        }
    }

    public func updateSessionBranch(id: String, branch: String) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE sessions SET worktreeBranch = ?, lastAccessedAt = ? WHERE id = ?",
                arguments: [branch, Date(), id]
            )
        }
    }

    public func updateSessionSortOrder(id: String, sortOrder: Int) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE sessions SET sortOrder = ? WHERE id = ?",
                arguments: [sortOrder, id]
            )
        }
    }

    public func updateSessionUseHappy(id: String, useHappy: Bool) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE sessions SET useHappy = ? WHERE id = ?",
                arguments: [useHappy, id]
            )
        }
    }

    public func updateProjectSortOrder(id: String, sortOrder: Int) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE projects SET sortOrder = ? WHERE id = ?",
                arguments: [sortOrder, id]
            )
        }
    }

    // MARK: - Session Event CRUD

    public func saveEvent(_ event: SessionEvent) throws {
        try db.write { db in
            var record = SessionEventRecord(event)
            try record.insert(db)

            // Cap at 1000 events per session using a single SQL DELETE
            // instead of fetching and deleting row-by-row (O(n) → O(1)).
            try db.execute(
                sql: """
                    DELETE FROM session_events WHERE id IN (
                        SELECT id FROM session_events
                        WHERE sessionID = ?
                        ORDER BY createdAt
                        LIMIT max(0, (SELECT count(*) FROM session_events WHERE sessionID = ?) - 1000)
                    )
                    """,
                arguments: [event.sessionID, event.sessionID]
            )
        }
    }

    public func events(forSessionID sessionID: String, limit: Int = 100) throws -> [SessionEvent] {
        try db.read { db in
            try SessionEventRecord
                .filter(Column("sessionID") == sessionID)
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
                .map { $0.toEvent() }
        }
    }

    public func updateSessionIssueNumber(id: String, issueNumber: Int?) throws {
        try db.write { db in
            try db.execute(
                sql: "UPDATE sessions SET issueNumber = ? WHERE id = ?",
                arguments: [issueNumber, id]
            )
        }
    }

    // MARK: - Project CRUD

    public func allProjects() throws -> [Project] {
        try db.read { db in
            try ProjectRecord.order(Column("sortOrder")).fetchAll(db).map { $0.toProject() }
        }
    }

    public func saveProject(_ project: Project) throws {
        try db.write { db in
            var record = ProjectRecord(project)
            try record.save(db)
        }
    }

    public func deleteProject(id: String) throws {
        try db.write { db in
            _ = try ProjectRecord.deleteOne(db, key: id)
        }
    }

    public func updateProject(_ project: Project) throws {
        try db.write { db in
            let record = ProjectRecord(project)
            try record.update(db)
        }
    }

    // MARK: - PR Cache

    /// Load all cached PRs that haven't expired.
    public func cachedPRs(maxAge: TimeInterval = 300) throws -> [PullRequest] {
        let cutoff = Date().addingTimeInterval(-maxAge)
        return try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT json FROM pr_cache WHERE fetchedAt > ?",
                arguments: [cutoff]
            )
            return rows.compactMap { row -> PullRequest? in
                guard let jsonStr = row["json"] as? String,
                    let data = jsonStr.data(using: .utf8)
                else { return nil }
                return try? JSONDecoder().decode(PullRequest.self, from: data)
            }
        }
    }

    /// Save or update a PR in the cache.
    public func cachePR(_ pr: PullRequest) throws {
        let data = try JSONEncoder().encode(pr)
        let json = String(data: data, encoding: .utf8) ?? ""
        try db.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO pr_cache (id, json, fetchedAt) VALUES (?, ?, ?)",
                arguments: [pr.id, json, Date()]
            )
        }
    }

    /// Save multiple PRs to the cache.
    public func cachePRs(_ prs: [PullRequest]) throws {
        let encoder = JSONEncoder()
        let now = Date()
        try db.write { db in
            for pr in prs {
                let data = try encoder.encode(pr)
                let json = String(data: data, encoding: .utf8) ?? ""
                try db.execute(
                    sql: "INSERT OR REPLACE INTO pr_cache (id, json, fetchedAt) VALUES (?, ?, ?)",
                    arguments: [pr.id, json, now]
                )
            }
        }
    }

    /// Clear expired PR cache entries.
    public func cleanPRCache(maxAge: TimeInterval = 86400) throws {
        let cutoff = Date().addingTimeInterval(-maxAge)
        try db.write { db in
            try db.execute(sql: "DELETE FROM pr_cache WHERE fetchedAt < ?", arguments: [cutoff])
        }
    }

    // MARK: - Issue Cache

    /// Load all cached issues for a repo that haven't expired.
    public func cachedIssues(repo: String, maxAge: TimeInterval = 300) throws -> [GitHubIssue] {
        let cutoff = Date().addingTimeInterval(-maxAge)
        let pattern = "\(repo)#%"
        return try db.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT json FROM issue_cache WHERE id LIKE ? AND fetchedAt > ?",
                arguments: [pattern, cutoff]
            )
            return rows.compactMap { row -> GitHubIssue? in
                guard let jsonStr = row["json"] as? String,
                    let data = jsonStr.data(using: .utf8)
                else { return nil }
                return try? JSONDecoder().decode(GitHubIssue.self, from: data)
            }
        }
    }

    /// Save multiple issues to the cache.
    public func cacheIssues(_ issues: [GitHubIssue]) throws {
        let encoder = JSONEncoder()
        let now = Date()
        try db.write { db in
            for issue in issues {
                let data = try encoder.encode(issue)
                let json = String(data: data, encoding: .utf8) ?? ""
                try db.execute(
                    sql: "INSERT OR REPLACE INTO issue_cache (id, json, fetchedAt) VALUES (?, ?, ?)",
                    arguments: [issue.id, json, now]
                )
            }
        }
    }

    /// Clear expired issue cache entries.
    public func cleanIssueCache(maxAge: TimeInterval = 86400) throws {
        let cutoff = Date().addingTimeInterval(-maxAge)
        try db.write { db in
            try db.execute(sql: "DELETE FROM issue_cache WHERE fetchedAt < ?", arguments: [cutoff])
        }
    }

    // MARK: - Session Template CRUD

    public func allTemplates() throws -> [SessionTemplate] {
        try db.read { db in
            try SessionTemplateRecord
                .order(Column("sortOrder"), Column("createdAt"))
                .fetchAll(db)
                .map { $0.toTemplate() }
        }
    }

    public func templates(forProjectID projectID: String?) throws -> [SessionTemplate] {
        try db.read { db in
            try SessionTemplateRecord
                .filter(Column("projectID") == projectID)
                .order(Column("sortOrder"), Column("createdAt"))
                .fetchAll(db)
                .map { $0.toTemplate() }
        }
    }

    public func saveTemplate(_ template: SessionTemplate) throws {
        try db.write { db in
            var record = SessionTemplateRecord(template)
            try record.save(db)
        }
    }

    public func deleteTemplate(id: String) throws {
        try db.write { db in
            _ = try SessionTemplateRecord.deleteOne(db, key: id)
        }
    }

    // MARK: - Saved Prompt CRUD

    public func allPrompts() throws -> [SavedPrompt] {
        try db.read { db in
            try SavedPromptRecord
                .order(Column("sortOrder"), Column("createdAt"))
                .fetchAll(db)
                .map { $0.toPrompt() }
        }
    }

    public func prompts(forProjectID projectID: String?) throws -> [SavedPrompt] {
        try db.read { db in
            try SavedPromptRecord
                .filter(Column("projectID") == projectID)
                .order(Column("sortOrder"), Column("createdAt"))
                .fetchAll(db)
                .map { $0.toPrompt() }
        }
    }

    public func savePrompt(_ prompt: SavedPrompt) throws {
        try db.write { db in
            var record = SavedPromptRecord(prompt)
            try record.save(db)
        }
    }

    public func deletePrompt(id: String) throws {
        try db.write { db in
            _ = try SavedPromptRecord.deleteOne(db, key: id)
        }
    }

    // MARK: - Housekeeping

    /// Delete stopped sessions older than the given age.
    /// Returns the number of sessions deleted.
    @discardableResult
    public func cleanStoppedSessions(maxAge: TimeInterval = 7 * 86400) throws -> Int {
        let cutoff = Date().addingTimeInterval(-maxAge)
        return try db.write { db in
            try db.execute(
                sql: "DELETE FROM sessions WHERE status = 'stopped' AND lastAccessedAt < ?",
                arguments: [cutoff]
            )
            return db.changesCount
        }
    }

    /// Delete old session events across all sessions.
    /// Returns the number of events deleted.
    @discardableResult
    public func cleanOldEvents(maxAge: TimeInterval = 7 * 86400) throws -> Int {
        let cutoff = Date().addingTimeInterval(-maxAge)
        return try db.write { db in
            try db.execute(
                sql: "DELETE FROM session_events WHERE createdAt < ?",
                arguments: [cutoff]
            )
            return db.changesCount
        }
    }

    /// Run SQLite VACUUM to reclaim disk space after bulk deletions.
    /// Must run outside a transaction — SQLite prohibits VACUUM within transactions.
    public func vacuum() throws {
        try db.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM")
        }
    }

    /// Get the database file size in bytes.
    public func fileSize() -> Int64? {
        let path = Database.defaultPath()
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return attrs[.size] as? Int64
    }

}
