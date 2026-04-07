// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Runway",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Runway", targets: ["App"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", revision: "b6ce28a"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ],
    targets: [
        // MARK: - App Entry Point
        .executableTarget(
            name: "App",
            dependencies: [
                "Models",
                "Persistence",
                "Terminal",
                "TerminalView",
                "GitOperations",
                "GitHubOperations",
                "StatusDetection",
                "Theme",
                "Views",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/App"
        ),

        // MARK: - Core Models
        .target(
            name: "Models",
            path: "Sources/Models"
        ),

        // MARK: - Persistence (GRDB/SQLite)
        .target(
            name: "Persistence",
            dependencies: [
                "Models",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/Persistence"
        ),

        // MARK: - Terminal PTY
        .target(
            name: "Terminal",
            dependencies: ["Models"],
            path: "Sources/Terminal",
            exclude: ["GhosttyVTTerminal.swift"],
            sources: ["PTYProcess.swift", "TmuxSessionManager.swift"]
        ),

        // MARK: - Terminal SwiftUI View (NSViewRepresentable)
        .target(
            name: "TerminalView",
            dependencies: [
                "Terminal",
                "Theme",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/TerminalView"
        ),

        // MARK: - Git Worktree Operations
        .target(
            name: "GitOperations",
            dependencies: ["Models"],
            path: "Sources/GitOperations"
        ),

        // MARK: - GitHub PR Operations (gh CLI)
        .target(
            name: "GitHubOperations",
            dependencies: ["Models"],
            path: "Sources/GitHubOperations"
        ),

        // MARK: - Status Detection (Hooks + Buffer)
        .target(
            name: "StatusDetection",
            dependencies: ["Models"],
            path: "Sources/StatusDetection"
        ),

        // MARK: - Theme System
        .target(
            name: "Theme",
            dependencies: [],
            path: "Sources/Theme"
        ),

        // MARK: - SwiftUI Views
        .target(
            name: "Views",
            dependencies: [
                "Models",
                "Persistence",
                "Terminal",
                "TerminalView",
                "GitOperations",
                "GitHubOperations",
                "StatusDetection",
                "Theme",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Views"
        ),

        // MARK: - Tests
        .testTarget(
            name: "ModelsTests",
            dependencies: ["Models"],
            path: "Tests/ModelsTests"
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence"],
            path: "Tests/PersistenceTests"
        ),
        .testTarget(
            name: "StatusDetectionTests",
            dependencies: ["StatusDetection"],
            path: "Tests/StatusDetectionTests"
        ),
        .testTarget(
            name: "GitOperationsTests",
            dependencies: ["GitOperations"],
            path: "Tests/GitOperationsTests"
        ),
        .testTarget(
            name: "ThemeTests",
            dependencies: ["Theme"],
            path: "Tests/ThemeTests"
        ),
        .testTarget(
            name: "GitHubOperationsTests",
            dependencies: ["GitHubOperations", "Models"],
            path: "Tests/GitHubOperationsTests"
        ),
        .testTarget(
            name: "TerminalTests",
            dependencies: ["Terminal"],
            path: "Tests/TerminalTests"
        ),
    ]
)
