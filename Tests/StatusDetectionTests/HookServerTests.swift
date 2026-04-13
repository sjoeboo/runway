import Foundation
import Models
import Testing

@testable import StatusDetection

@Test func hookServerStartsAndExposesPort() async throws {
    let server = HookServer(port: 0)
    try await server.start()
    defer { Task { await server.stop() } }

    let portValue = try #require(await server.actualPort)
    #expect(portValue > 0)
}

@Test func hookServerAcceptsConnections() async throws {
    let server = HookServer(port: 0)
    try await server.start()
    defer { Task { await server.stop() } }

    let portValue = try #require(await server.actualPort)

    // Send a minimal HTTP POST to the server
    let url = try #require(URL(string: "http://127.0.0.1:\(portValue)/hooks"))
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
}

@Test func hookServerDispatchesDecodedEventToHandler() async throws {
    let server = HookServer(port: 0)

    // Register handler BEFORE start — same pattern as RunwayStore.startHookServer()
    let receivedEvent = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HookEvent, Error>) in
        Task {
            await server.onEvent { event in
                continuation.resume(returning: event)
            }

            try await server.start()
            let portValue = try #require(await server.actualPort)

            // Build a proper JSON body using HookEvent's snake_case CodingKeys
            let body: [String: Any] = [
                "session_id": "original-session-id",
                "hook_event_name": "Stop",
                "cwd": "/tmp/test",
                "total_cost_usd": 0.42,
                "total_input_tokens": 1000,
                "total_output_tokens": 500,
            ]

            let url = try #require(URL(string: "http://127.0.0.1:\(portValue)/hooks"))
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // X-Runway-Session-Id overrides session_id in the body
            request.setValue("runway-session-abc", forHTTPHeaderField: "X-Runway-Session-Id")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (_, response) = try await URLSession.shared.data(for: request)
            let httpResponse = try #require(response as? HTTPURLResponse)
            #expect(httpResponse.statusCode == 200)
        }
    }
    defer { Task { await server.stop() } }

    // Verify the handler received the correctly decoded event
    // sessionID should be overridden by the X-Runway-Session-Id header
    #expect(receivedEvent.sessionID == "runway-session-abc")
    #expect(receivedEvent.event == .stop)
    #expect(receivedEvent.cwd == "/tmp/test")
    #expect(receivedEvent.totalCostUSD == 0.42)
    #expect(receivedEvent.totalInputTokens == 1000)
    #expect(receivedEvent.totalOutputTokens == 500)
}

@Test func hookServerDispatchesEventWithOriginalSessionID() async throws {
    let server = HookServer(port: 0)

    let receivedEvent = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HookEvent, Error>) in
        Task {
            await server.onEvent { event in
                continuation.resume(returning: event)
            }

            try await server.start()
            let portValue = try #require(await server.actualPort)

            // No X-Runway-Session-Id header — should use session_id from body
            let body: [String: Any] = [
                "session_id": "body-session-id",
                "hook_event_name": "SessionStart",
            ]

            let url = try #require(URL(string: "http://127.0.0.1:\(portValue)/hooks"))
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            _ = try await URLSession.shared.data(for: request)
        }
    }
    defer { Task { await server.stop() } }

    // Without the header override, sessionID comes from the JSON body
    #expect(receivedEvent.sessionID == "body-session-id")
    #expect(receivedEvent.event == .sessionStart)
}

@Test func twoHookServersRunSimultaneously() async throws {
    let server1 = HookServer(port: 0)
    let server2 = HookServer(port: 0)

    try await server1.start()
    defer { Task { await server1.stop() } }
    try await server2.start()
    defer { Task { await server2.stop() } }

    let port1 = try #require(await server1.actualPort)
    let port2 = try #require(await server2.actualPort)

    #expect(port1 != port2)
}
