import Foundation

// MARK: - FileChange

public struct FileChange: Identifiable, Sendable, Equatable {
    public var id: String { path }
    public let path: String
    public let status: FileChangeStatus
    public let additions: Int
    public let deletions: Int

    public init(path: String, status: FileChangeStatus, additions: Int, deletions: Int) {
        self.path = path
        self.status = status
        self.additions = additions
        self.deletions = deletions
    }
}

public enum FileChangeStatus: String, Sendable, Equatable {
    case added = "A"
    case modified = "M"
    case deleted = "D"
    case renamed = "R"

    public init(gitCode: String) {
        switch gitCode.prefix(1) {
        case "A": self = .added
        case "D": self = .deleted
        case "R": self = .renamed
        default: self = .modified
        }
    }
}

public enum ChangesMode: String, Sendable, Equatable {
    case branch
    case working
}

// MARK: - FileTreeNode

public enum FileTreeNode: Identifiable, Sendable {
    case directory(name: String, children: [FileTreeNode], additions: Int, deletions: Int)
    case file(FileChange)

    public var id: String {
        switch self {
        case .directory(let name, _, _, _): "dir:\(name)"
        case .file(let fc): fc.path
        }
    }

    public var name: String {
        switch self {
        case .directory(let name, _, _, _):
            return name
        case .file(let fc):
            if let lastSlash = fc.path.lastIndex(of: "/") {
                return String(fc.path[fc.path.index(after: lastSlash)...])
            }
            return fc.path
        }
    }

    public var additions: Int {
        switch self {
        case .directory(_, _, let adds, _): adds
        case .file(let fc): fc.additions
        }
    }

    public var deletions: Int {
        switch self {
        case .directory(_, _, _, let dels): dels
        case .file(let fc): fc.deletions
        }
    }
}

// MARK: - Tree Builder

public func buildFileTree(_ changes: [FileChange]) -> [FileTreeNode] {
    guard !changes.isEmpty else { return [] }

    var rootFiles: [FileChange] = []
    var dirGroups: [String: [FileChange]] = [:]

    for change in changes {
        let parts = change.path.split(separator: "/", maxSplits: 1)
        if parts.count == 1 {
            rootFiles.append(change)
        } else {
            let dir = String(parts[0])
            dirGroups[dir, default: []].append(change)
        }
    }

    var nodes: [FileTreeNode] = []

    for dir in dirGroups.keys.sorted() {
        guard let children = dirGroups[dir] else { continue }
        let stripped = children.map { fc in
            let rest = String(fc.path.drop(while: { $0 != "/" }).dropFirst())
            return FileChange(path: rest, status: fc.status, additions: fc.additions, deletions: fc.deletions)
        }
        let subtree = buildFileTree(stripped)
        let adds = children.reduce(0) { $0 + $1.additions }
        let dels = children.reduce(0) { $0 + $1.deletions }

        if subtree.count == 1, case .directory(let childName, let grandchildren, _, _) = subtree[0] {
            nodes.append(.directory(name: "\(dir)/\(childName)", children: grandchildren, additions: adds, deletions: dels))
        } else {
            nodes.append(.directory(name: "\(dir)/", children: subtree, additions: adds, deletions: dels))
        }
    }

    for file in rootFiles.sorted(by: { $0.path < $1.path }) {
        nodes.append(.file(file))
    }

    return nodes
}
