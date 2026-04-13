import Foundation
import Models

#if canImport(Network)
    import Network
#endif

/// Lightweight HTTP server that receives Claude Code lifecycle hook events.
///
/// Listens for POST requests from Claude Code.
/// Events are decoded and dispatched to registered handlers.
public actor HookServer {
    public typealias EventHandler = @Sendable (HookEvent) -> Void

    private let requestedPort: UInt16
    private var listener: NWListener?
    private var handlers: [EventHandler] = []
    private let connectionQueue = DispatchQueue(label: "runway.hookserver.conn")

    /// The actual port the server is listening on (available after `start()` returns).
    public private(set) var actualPort: UInt16?

    /// Called when the listener enters `.failed` state after initial startup.
    /// The caller can use this to trigger a restart.
    public var onFailure: (@Sendable () -> Void)?

    public init(port: UInt16 = 0) {
        self.requestedPort = port
    }

    /// Set the failure callback (actor-isolated setter for cross-actor access).
    public func setOnFailure(_ handler: @escaping @Sendable () -> Void) {
        self.onFailure = handler
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
        // Bind to loopback only — prevent LAN access to hook events
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: requestedPort == 0
                ? .any
                : NWEndpoint.Port(rawValue: requestedPort) ?? .any
        )
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
        let resolvedPort = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16?, Error>) in
            listener.stateUpdateHandler = { [weak listener] state in
                switch state {
                case .ready:
                    listener?.stateUpdateHandler = nil  // prevent double-resume
                    continuation.resume(returning: listener?.port?.rawValue)
                case .failed(let error):
                    listener?.stateUpdateHandler = nil  // prevent double-resume
                    continuation.resume(throwing: error)
                case .cancelled:
                    listener?.stateUpdateHandler = nil  // prevent double-resume
                    continuation.resume(throwing: HookServerError.cancelled)
                default:
                    break
                }
            }
            listener.start(queue: DispatchQueue(label: "runway.hookserver"))
        }

        // Set actualPort on the actor before returning to caller — no race
        self.actualPort = resolvedPort

        // Monitor for runtime failures after successful startup.
        // If the listener enters .failed state, notify the caller so they can restart.
        let failureCallback = onFailure
        listener.stateUpdateHandler = { state in
            if case .failed = state {
                failureCallback?()
            }
        }
    }

    /// Stop the hook server.
    public func stop() {
        listener?.cancel()
        listener = nil
        actualPort = nil
    }

    // MARK: - Private

    /// Maximum time (seconds) to wait for a complete HTTP request before dropping the connection.
    private static let connectionTimeout: TimeInterval = 30

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: connectionQueue)

        // Schedule a timeout to prevent slow/idle connections from leaking resources
        let timeout = DispatchWorkItem { [weak connection] in
            connection?.cancel()
        }
        connectionQueue.asyncAfter(deadline: .now() + Self.connectionTimeout, execute: timeout)

        accumulateRequest(connection: connection, buffer: Data(), timeout: timeout)
    }

    /// Maximum allowed request size (1 MB) to prevent unbounded memory growth.
    private static let maxRequestSize = 1_048_576

    /// Accumulate HTTP request data until we have the full body (Content-Length aware).
    /// Calls processRequest once the full payload is received.
    nonisolated private func accumulateRequest(connection: NWConnection, buffer: Data, timeout: DispatchWorkItem) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self else {
                // Server was deallocated — clean up the connection to prevent FD leak
                timeout.cancel()
                connection.cancel()
                return
            }
            guard let data, error == nil else {
                timeout.cancel()
                connection.cancel()
                return
            }

            var accumulated = buffer
            accumulated.append(data)

            // Prevent unbounded memory growth from slow/malicious clients
            if accumulated.count > HookServer.maxRequestSize {
                timeout.cancel()
                connection.cancel()
                return
            }

            // Check if we have the full HTTP request
            let separator = Data("\r\n\r\n".utf8)
            if let headerEnd = accumulated.range(of: separator) {
                // Parse Content-Length from headers
                let headerData = accumulated[accumulated.startIndex..<headerEnd.lowerBound]
                let headerStr = String(data: headerData, encoding: .utf8) ?? ""
                let contentLength =
                    headerStr.components(separatedBy: "\r\n")
                    .first(where: { $0.lowercased().hasPrefix("content-length:") })
                    .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) }
                    ?? 0

                let bodyStart = headerEnd.upperBound
                let receivedBody = accumulated.count - bodyStart
                if receivedBody >= contentLength {
                    // Full request received — cancel the connection timeout
                    timeout.cancel()
                    Task { await self.processRequest(data: accumulated, connection: connection) }
                    return
                }
            }

            // Need more data — keep reading
            self.accumulateRequest(connection: connection, buffer: accumulated, timeout: timeout)
        }
    }

    private func processRequest(data: Data, connection: NWConnection) {
        // Send 200 OK response immediately — don't block the agent waiting for
        // handler dispatch, which may await MainActor and exceed the hook timeout.
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
        connection.send(
            content: response.data(using: .utf8),
            completion: .contentProcessed { _ in
                connection.cancel()
            })

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

// MARK: - Errors

public enum HookServerError: Error, LocalizedError {
    case invalidPort(UInt16)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidPort(let port):
            "Invalid port number: \(port)"
        case .cancelled:
            "Hook server listener was cancelled before it could start"
        }
    }
}
