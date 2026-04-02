import Testing
import Foundation
@testable import Terminal

// MARK: - TerminalSize

@Test func terminalSizeDefaults() {
    let size = TerminalSize()
    #expect(size.cols == 80)
    #expect(size.rows == 24)
}

@Test func terminalSizeCustom() {
    let size = TerminalSize(cols: 120, rows: 40)
    #expect(size.cols == 120)
    #expect(size.rows == 40)
}

// MARK: - TerminalHandle

@Test func terminalHandleProperties() {
    let handle = TerminalHandle(id: "test-123", pid: 42)
    #expect(handle.id == "test-123")
    #expect(handle.pid == 42)
}

@Test func terminalHandleIdentifiable() {
    let h1 = TerminalHandle(id: "a", pid: 1)
    let h2 = TerminalHandle(id: "b", pid: 2)
    #expect(h1.id != h2.id)
}

// MARK: - RingBuffer

@Test func ringBufferAppendAndTail() {
    let buffer = RingBuffer(capacity: 1024)
    let data = Data("Hello, World!".utf8)
    buffer.append(data)

    let tail = buffer.tail(maxBytes: 1024)
    #expect(String(data: tail, encoding: .utf8) == "Hello, World!")
}

@Test func ringBufferRespectsCapacity() {
    let buffer = RingBuffer(capacity: 10)
    buffer.append(Data("12345".utf8))
    buffer.append(Data("67890".utf8))
    buffer.append(Data("ABCDE".utf8)) // This should push out the oldest data

    let tail = buffer.tail(maxBytes: 100)
    #expect(tail.count <= 10)
    // Should contain the most recent data
    let text = String(data: tail, encoding: .utf8) ?? ""
    #expect(text.hasSuffix("ABCDE"))
}

@Test func ringBufferTailLimitsBytes() {
    let buffer = RingBuffer(capacity: 1024)
    buffer.append(Data("Hello, World!".utf8))

    let tail = buffer.tail(maxBytes: 5)
    #expect(tail.count == 5)
    #expect(String(data: tail, encoding: .utf8) == "orld!")
}

@Test func ringBufferEmptyTail() {
    let buffer = RingBuffer(capacity: 1024)
    let tail = buffer.tail(maxBytes: 100)
    #expect(tail.isEmpty)
}

@Test func ringBufferMultipleAppends() {
    let buffer = RingBuffer(capacity: 1024)
    buffer.append(Data("Hello".utf8))
    buffer.append(Data(", ".utf8))
    buffer.append(Data("World".utf8))

    let tail = buffer.tail(maxBytes: 1024)
    #expect(String(data: tail, encoding: .utf8) == "Hello, World")
}

// MARK: - PTYError

@Test func ptyErrorDescriptions() {
    let forkError = PTYError.forkFailed(errno: 12)
    #expect(forkError.errorDescription?.contains("Failed to fork PTY") == true)

    let notFound = PTYError.commandNotFound("/usr/bin/missing")
    #expect(notFound.errorDescription == "Command not found: /usr/bin/missing")
}
