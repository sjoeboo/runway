import Foundation
import GRDB
import Models

/// SQLite database manager using GRDB with WAL mode.
public final class Database: Sendable {
    private let dbQueue: DatabaseQueue

    /// Open or create the database at the given path.
    public init(path: String? = nil) throws {
        let dbPath = path ?? Database.defaultPath()

        // Ensure directory exists
        let dir = (dbPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var config = Configuration()
        config.prepareDatabase { db in
            // WAL mode for concurrent readers
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            // NORMAL is safe with WAL — only risks data loss on power failure, not OS crash.
            // Reduces write latency by ~1ms per write (hot path: every hook status update).
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            // 5-second busy timeout for inter-process serialization
            try db.execute(sql: "PRAGMA busy_timeout = 5000")
        }

        dbQueue = try DatabaseQueue(path: dbPath, configuration: config)
        try migrate()
    }

    /// In-memory database for testing.
    public init(inMemory: Bool) throws {
        precondition(inMemory)
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA busy_timeout = 5000")
        }
        dbQueue = try DatabaseQueue(configuration: config)
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

        try migrator.migrate(dbQueue)
    }

    // MARK: - Default Path

    public static func defaultPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.runway/state.db"
    }

    // MARK: - Session CRUD

    public func allSessions() throws -> [Session] {
        try dbQueue.read { db in
            try SessionRecord.order(Column("sortOrder"), Column("createdAt")).fetchAll(db).map { $0.toSession() }
        }
    }

    public func session(id: String) throws -> Session? {
        try dbQueue.read { db in
            try SessionRecord.fetchOne(db, key: id)?.toSession()
        }
    }

    public func saveSession(_ session: Session) throws {
        try dbQueue.write { db in
            var record = SessionRecord(session)
            try record.save(db)
        }
    }

    public func deleteSession(id: String) throws {
        try dbQueue.write { db in
            _ = try SessionRecord.deleteOne(db, key: id)
        }
    }

    public func updateSessionStatus(id: String, status: SessionStatus) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE sessions SET status = ?, lastAccessedAt = ? WHERE id = ?",
                arguments: [status.rawValue, Date(), id]
            )
        }
    }

    public func updateSessionPath(id: String, path: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE sessions SET path = ?, lastAccessedAt = ? WHERE id = ?",
                arguments: [path, Date(), id]
            )
        }
    }

    public func updateSessionSortOrder(id: String, sortOrder: Int) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE sessions SET sortOrder = ? WHERE id = ?",
                arguments: [sortOrder, id]
            )
        }
    }

    public func updateProjectSortOrder(id: String, sortOrder: Int) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE projects SET sortOrder = ? WHERE id = ?",
                arguments: [sortOrder, id]
            )
        }
    }

    // MARK: - Session Event CRUD

    public func saveEvent(_ event: SessionEvent) throws {
        try dbQueue.write { db in
            var record = SessionEventRecord(event)
            try record.insert(db)

            // Cap at 1000 events per session
            let count =
                try SessionEventRecord
                .filter(Column("sessionID") == event.sessionID)
                .fetchCount(db)
            if count > 1000 {
                let excess = count - 1000
                let oldest =
                    try SessionEventRecord
                    .filter(Column("sessionID") == event.sessionID)
                    .order(Column("createdAt"))
                    .limit(excess)
                    .fetchAll(db)
                for old in oldest {
                    try old.delete(db)
                }
            }
        }
    }

    public func events(forSessionID sessionID: String, limit: Int = 100) throws -> [SessionEvent] {
        try dbQueue.read { db in
            try SessionEventRecord
                .filter(Column("sessionID") == sessionID)
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
                .map { $0.toEvent() }
        }
    }

    public func updateSessionIssueNumber(id: String, issueNumber: Int?) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE sessions SET issueNumber = ? WHERE id = ?",
                arguments: [issueNumber, id]
            )
        }
    }

    // MARK: - Project CRUD

    public func allProjects() throws -> [Project] {
        try dbQueue.read { db in
            try ProjectRecord.order(Column("sortOrder")).fetchAll(db).map { $0.toProject() }
        }
    }

    public func saveProject(_ project: Project) throws {
        try dbQueue.write { db in
            var record = ProjectRecord(project)
            try record.save(db)
        }
    }

    public func deleteProject(id: String) throws {
        try dbQueue.write { db in
            _ = try ProjectRecord.deleteOne(db, key: id)
        }
    }

    public func updateProject(_ project: Project) throws {
        try dbQueue.write { db in
            var record = ProjectRecord(project)
            try record.update(db)
        }
    }

    // MARK: - PR Cache

    /// Load all cached PRs that haven't expired.
    public func cachedPRs(maxAge: TimeInterval = 300) throws -> [PullRequest] {
        let cutoff = Date().addingTimeInterval(-maxAge)
        return try dbQueue.read { db in
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
        try dbQueue.write { db in
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
        try dbQueue.write { db in
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
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM pr_cache WHERE fetchedAt < ?", arguments: [cutoff])
        }
    }

    // MARK: - Issue Cache

    /// Load all cached issues for a repo that haven't expired.
    public func cachedIssues(repo: String, maxAge: TimeInterval = 300) throws -> [GitHubIssue] {
        let cutoff = Date().addingTimeInterval(-maxAge)
        let pattern = "\(repo)#%"
        return try dbQueue.read { db in
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
        try dbQueue.write { db in
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
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM issue_cache WHERE fetchedAt < ?", arguments: [cutoff])
        }
    }

}
