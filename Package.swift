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
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.4.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
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

        // MARK: - libghostty-vt (C library for VT parsing/state)
        // NOTE: CGhosttyVT headers + static lib are in Sources/CGhosttyVT/ and Frameworks/.
        // Currently not linked due to missing Highway (hwy) SIMD dependency.
        // The GhosttyVTTerminal.swift wrapper is ready — needs linker flags resolved.
        // To enable: add "CGhosttyVT" to Terminal dependencies and uncomment linkerSettings.
        .target(
            name: "CGhosttyVT",
            path: "Sources/CGhosttyVT",
            publicHeadersPath: "include"
        ),

        // MARK: - Terminal Provider Protocol + PTY
        .target(
            name: "Terminal",
            dependencies: ["Models"],
            path: "Sources/Terminal",
            exclude: ["GhosttyVTTerminal.swift"],
            sources: ["TerminalProvider.swift", "PTYProcess.swift", "NativePTYProvider.swift"]
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
    ]
)
