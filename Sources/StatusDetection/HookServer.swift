import Foundation
import Models
#if canImport(Network)
import Network
#endif

/// Lightweight HTTP server that receives Claude Code lifecycle hook events.
///
/// Listens on port 47437 (same as Hangar) for POST requests from Claude Code.
/// Events are decoded and dispatched to registered handlers.
public actor HookServer {
    public typealias EventHandler = @Sendable (HookEvent) -> Void

    private let port: UInt16
    private var listener: NWListener?
    private var handlers: [EventHandler] = []

    public init(port: UInt16 = 47437) {
        self.port = port
    }

    /// Register a handler for incoming hook events.
    public func onEvent(_ handler: @escaping EventHandler) {
        handlers.append(handler)
    }

    /// Start listening for hook events.
    public func start() throws {
        let params = NWParameters.tcp
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.handleConnection(connection) }
        }

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                break
            case .failed(let error):
                print("[HookServer] Failed: \(error)")
            default:
                break
            }
        }

        listener.start(queue: DispatchQueue(label: "runway.hookserver"))
    }

    /// Stop the hook server.
    public func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Private

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue(label: "runway.hookserver.conn"))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
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
           var event = try? JSONDecoder().decode(HookEvent.self, from: data[bodyRange]) {
            // Use X-Runway-Session-Id header if present (bridges Claude's session ID to Runway's)
            if let runwayID = extractHeader(named: "X-Runway-Session-Id", from: data), !runwayID.isEmpty {
                event.sessionID = runwayID
            }
            for handler in handlers {
                handler(event)
            }
        }

        // Send 200 OK response
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func extractHeader(named name: String, from data: Data) -> String? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let headerStr = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        let needle = name.lowercased() + ":"
        for line in headerStr.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix(needle) {
                return String(line.dropFirst(needle.count)).trimmingCharacters(in: .whitespaces)
            }
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
