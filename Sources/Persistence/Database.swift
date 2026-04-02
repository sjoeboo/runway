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
            // 5-second busy timeout for inter-process serialization
            try db.execute(sql: "PRAGMA busy_timeout = 5000")
        }

        dbQueue = try DatabaseQueue(path: dbPath, configuration: config)
        try migrate()
    }

    /// In-memory database for testing.
    public init(inMemory: Bool) throws {
        precondition(inMemory)
        dbQueue = try DatabaseQueue()
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
            try SessionRecord.fetchAll(db).map { $0.toSession() }
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
            if var record = try SessionRecord.fetchOne(db, key: id) {
                record.status = status.rawValue
                record.lastAccessedAt = Date()
                try record.update(db)
            }
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

    // MARK: - Group CRUD

    public func groups(forProject projectID: String) throws -> [Group] {
        try dbQueue.read { db in
            try GroupRecord
                .filter(Column("projectID") == projectID)
                .order(Column("sortOrder"))
                .fetchAll(db)
                .map { $0.toGroup() }
        }
    }

    public func saveGroup(_ group: Group) throws {
        try dbQueue.write { db in
            var record = GroupRecord(group)
            try record.save(db)
        }
    }

    // MARK: - Todo CRUD

    public func todos(forProject projectID: String) throws -> [Todo] {
        try dbQueue.read { db in
            try TodoRecord
                .filter(Column("projectID") == projectID)
                .order(Column("sortOrder"))
                .fetchAll(db)
                .map { $0.toTodo() }
        }
    }

    public func saveTodo(_ todo: Todo) throws {
        try dbQueue.write { db in
            var record = TodoRecord(todo)
            try record.save(db)
        }
    }

    public func deleteTodo(id: String) throws {
        try dbQueue.write { db in
            _ = try TodoRecord.deleteOne(db, key: id)
        }
    }
}
