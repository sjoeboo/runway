import Foundation
import Testing

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

// MARK: - PTYError

@Test func ptyErrorDescriptions() {
    let forkError = PTYError.forkFailed(errno: 12)
    #expect(forkError.errorDescription?.contains("Failed to fork PTY") == true)

    let notFound = PTYError.commandNotFound("/usr/bin/missing")
    #expect(notFound.errorDescription == "Command not found: /usr/bin/missing")
}
