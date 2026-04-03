# Core Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix hook server port conflicts and auto-detect default branch in the new project dialog.

**Architecture:** HookServer switches from hardcoded port 47437 to OS-assigned port 0, exposing the actual port after start. RunwayStore sequences startup so hook injection uses the resolved port. NewProjectDialog auto-detects the default branch when a path is selected.

**Tech Stack:** Swift 6, NWListener (Network.framework), Swift Testing, SwiftUI

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/StatusDetection/HookServer.swift` | Modify | Dynamic port binding, expose actual port |
| `Sources/App/RunwayStore.swift` | Modify | Sequence startup: server → port → inject |
| `Sources/Views/Shared/NewProjectDialog.swift` | Modify | Auto-detect branch on path selection |
| `Tests/StatusDetectionTests/HookServerTests.swift` | Create | Tests for dynamic port behavior |

---

### Task 1: HookServer Dynamic Port — Tests

**Files:**
- Create: `Tests/StatusDetectionTests/HookServerTests.swift`

- [ ] **Step 1: Create test file with first test — server starts and exposes a port**

```swift
import Foundation
import Testing

@testable import StatusDetection

@Test func hookServerStartsAndExposesPort() async throws {
    let server = HookServer(port: 0)
    try await server.start()

    let port = await server.actualPort
    #expect(port != nil)
    #expect(port! > 0)

    await server.stop()
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HookServerTests 2>&1 | tail -20`
Expected: Compilation error — `actualPort` property doesn't exist yet, `start()` is not async.

- [ ] **Step 3: Add second test — server accepts connections on the assigned port**

```swift
@Test func hookServerAcceptsConnections() async throws {
    let server = HookServer(port: 0)
    try await server.start()

    let port = await server.actualPort
    let portValue = try #require(port)

    // Send a minimal HTTP POST to the server
    let url = URL(string: "http://127.0.0.1:\(portValue)/hooks")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("test-session-123", forHTTPHeaderField: "X-Runway-Session-Id")

    let body: [String: Any] = [
        "sessionID": "original-id",
        "event": "SessionStart",
        "timestamp": ISO8601DateFormatter().string(from: Date()),
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (_, response) = try await URLSession.shared.data(for: request)
    let httpResponse = try #require(response as? HTTPURLResponse)
    #expect(httpResponse.statusCode == 200)

    await server.stop()
}
```

- [ ] **Step 4: Add third test — two servers can run simultaneously on different ports**

```swift
@Test func twoHookServersRunSimultaneously() async throws {
    let server1 = HookServer(port: 0)
    let server2 = HookServer(port: 0)

    try await server1.start()
    try await server2.start()

    let port1 = await server1.actualPort
    let port2 = await server2.actualPort

    #expect(port1 != nil)
    #expect(port2 != nil)
    #expect(port1 != port2)

    await server1.stop()
    await server2.stop()
}
```

- [ ] **Step 5: Commit test file**

```bash
git add Tests/StatusDetectionTests/HookServerTests.swift
git commit -m "test: add HookServer dynamic port tests (red)"
```

---

### Task 2: HookServer Dynamic Port — Implementation

**Files:**
- Modify: `Sources/StatusDetection/HookServer.swift`

- [ ] **Step 1: Add `actualPort` property and make `start()` async with continuation**

Replace the entire `HookServer` actor with:

```swift
public actor HookServer {
    public typealias EventHandler = @Sendable (HookEvent) -> Void

    private let requestedPort: UInt16
    private var listener: NWListener?
    private var handlers: [EventHandler] = []

    /// The actual port the server is listening on (available after `start()` returns).
    public private(set) var actualPort: UInt16?

    public init(port: UInt16 = 0) {
        self.requestedPort = port
    }

    /// Register a handler for incoming hook events.
    public func onEvent(_ handler: @escaping EventHandler) {
        handlers.append(handler)
    }

    /// Start listening for hook events.
    ///
    /// Uses port 0 by default (OS assigns an available ephemeral port).
    /// After this method returns, `actualPort` contains the assigned port.
    public func start() async throws {
        let params = NWParameters.tcp
        let nwPort: NWEndpoint.Port
        if requestedPort == 0 {
            nwPort = .any
        } else {
            guard let explicit = NWEndpoint.Port(rawValue: requestedPort) else {
                throw HookServerError.invalidPort(requestedPort)
            }
            nwPort = explicit
        }
        let listener = try NWListener(using: params, on: nwPort)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.handleConnection(connection) }
        }

        // Use a continuation to bridge NWListener's callback into async/await.
        // The continuation resolves when the listener is ready or fails.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    let port = listener.port?.rawValue
                    Task { await self?.setActualPort(port) }
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: DispatchQueue(label: "runway.hookserver"))
        }
    }

    /// Stop the hook server.
    public func stop() {
        listener?.cancel()
        listener = nil
        actualPort = nil
    }

    // MARK: - Private

    private func setActualPort(_ port: UInt16?) {
        self.actualPort = port
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue(label: "runway.hookserver.conn"))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, _, error in
            guard let data, error == nil else {
                connection.cancel()
                return
            }

            Task { await self?.processRequest(data: data, connection: connection) }
        }
    }

    private func processRequest(data: Data, connection: NWConnection) {
        // Parse HTTP request body (skip headers, find blank line)
        if let bodyRange = findHTTPBody(in: data),
            var event = try? JSONDecoder().decode(HookEvent.self, from: data[bodyRange])
        {
            // Use X-Runway-Session-Id header if present
            if let runwayID = extractHeader(named: "X-Runway-Session-Id", from: data),
                !runwayID.isEmpty
            {
                event.sessionID = runwayID
            }
            for handler in handlers {
                handler(event)
            }
        }

        // Send 200 OK response
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
        connection.send(
            content: response.data(using: .utf8),
            completion: .contentProcessed { _ in
                connection.cancel()
            })
    }

    private func extractHeader(named name: String, from data: Data) -> String? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard
            let headerStr = String(
                data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8)
        else { return nil }
        let needle = name.lowercased() + ":"
        for line in headerStr.components(separatedBy: "\r\n")
        where line.lowercased().hasPrefix(needle) {
            return String(line.dropFirst(needle.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func findHTTPBody(in data: Data) -> Range<Data.Index>? {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator) else { return nil }
        let bodyStart = range.upperBound
        guard bodyStart < data.endIndex else { return nil }
        return bodyStart..<data.endIndex
    }
}
```

- [ ] **Step 2: Run the tests**

Run: `swift test --filter HookServerTests 2>&1 | tail -20`
Expected: All 3 tests pass.

- [ ] **Step 3: Run full test suite to check for regressions**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass. (Existing code only references `HookServer()` with default args, which now defaults to port 0 instead of 47437 — behavior change is intentional.)

- [ ] **Step 4: Commit**

```bash
git add Sources/StatusDetection/HookServer.swift
git commit -m "feat: HookServer dynamic port binding via port 0"
```

---

### Task 3: RunwayStore Startup Sequencing

**Files:**
- Modify: `Sources/App/RunwayStore.swift`

- [ ] **Step 1: Update `init()` — remove standalone hook injection Task**

In `RunwayStore.init()`, remove this line:

```swift
        Task { try? hookInjector.inject() }
```

The `init()` should now have these Tasks:

```swift
        // Load initial state
        Task { await loadState() }

        // Start hook server + inject Claude hooks (sequenced — inject needs the port)
        Task { await startHookServer() }

        // Fetch PRs on launch
        Task { await fetchPRs() }
```

- [ ] **Step 2: Update `startHookServer()` — inject hooks after server starts**

Replace the `startHookServer()` method with:

```swift
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
```

- [ ] **Step 3: Build to verify compilation**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 4: Run full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/RunwayStore.swift
git commit -m "feat: sequence hook server startup — inject hooks after port is known"
```

---

### Task 4: Auto-Detect Default Branch — Implementation

**Files:**
- Modify: `Sources/Views/Shared/NewProjectDialog.swift`

- [ ] **Step 1: Add state properties for branch detection**

After the existing `@State private var validationError: String?` line (line 13), add:

```swift
    @State private var isDetectingBranch: Bool = false
    @State private var pathDebounceTask: Task<Void, Never>?
```

- [ ] **Step 2: Add the branch detection method**

After the `create()` method (after line 107), add:

```swift
    private func detectBranch(at repoPath: String) {
        // Cancel any pending detection
        pathDebounceTask?.cancel()

        let expanded = (repoPath as NSString).expandingTildeInPath

        // Quick validation — must be a git repo
        guard FileManager.default.fileExists(atPath: "\(expanded)/.git") else {
            return
        }

        pathDebounceTask = Task {
            isDetectingBranch = true
            defer { isDetectingBranch = false }

            let wm = WorktreeManager()
            let detected = await wm.detectDefaultBranch(repoPath: expanded)

            // Only update if task wasn't cancelled (user may have typed more)
            if !Task.isCancelled {
                defaultBranch = detected
            }
        }
    }
```

- [ ] **Step 3: Add `import GitOperations` at the top of the file**

Add after the existing imports (line 1-3):

```swift
import GitOperations
```

So the imports become:

```swift
import GitOperations
import Models
import SwiftUI
import Theme
```

- [ ] **Step 4: Add `.onChange(of: path)` modifier to trigger detection**

In the `body` computed property, add an `.onChange` modifier to the outermost `VStack`. Change:

```swift
        .padding(24)
        .frame(width: 420)
```

to:

```swift
        .padding(24)
        .frame(width: 420)
        .onChange(of: path) { _, newPath in
            detectBranch(at: newPath)
        }
```

- [ ] **Step 5: Add a loading indicator next to the Default Branch field**

Replace:

```swift
                field("Default Branch", text: $defaultBranch, placeholder: "main")
```

with:

```swift
                HStack {
                    field("Default Branch", text: $defaultBranch, placeholder: "main")
                    if isDetectingBranch {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.top, 16)
                    }
                }
```

- [ ] **Step 6: Build to verify compilation**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 7: Run full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/Views/Shared/NewProjectDialog.swift
git commit -m "feat: auto-detect default branch when selecting project path"
```

---

### Task 5: Update TODO.md

**Files:**
- Modify: `TODO.md`

- [ ] **Step 1: Mark completed items in TODO.md**

Change:

```markdown
- [ ] **Hook server dynamic port** — hook server gets "address in use" errors on startup; switch to dynamic port selection (bind to port 0 or scan for available port) to avoid conflicts. This may be why sidebar session statuses aren't updating
```

to:

```markdown
- [x] **Hook server dynamic port** — hook server gets "address in use" errors on startup; switch to dynamic port selection (bind to port 0 or scan for available port) to avoid conflicts. This may be why sidebar session statuses aren't updating
```

Change:

```markdown
- [ ] **Auto-detect master/main branch** — When adding a new project, auto-detect whether the repo uses `master` or `main` as its default branch
```

to:

```markdown
- [x] **Auto-detect master/main branch** — When adding a new project, auto-detect whether the repo uses `master` or `main` as its default branch
```

- [ ] **Step 2: Commit**

```bash
git add TODO.md
git commit -m "docs: mark hook server dynamic port and auto-detect branch as complete"
```
