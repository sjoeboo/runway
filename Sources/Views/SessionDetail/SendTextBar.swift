import Models
import SwiftUI
import Theme

/// Quick input bar for sending text to a session's terminal without focusing it.
///
/// Appears at the bottom of the session detail when triggered (⌘X or button).
/// Useful for sending prompts to Claude while viewing diffs or PRs.
/// Includes a prompt library menu for quick access to saved/built-in prompts.
public struct SendTextBar: View {
    @Binding var isVisible: Bool
    let toolName: String
    let savedPrompts: [SavedPrompt]
    let onSend: (String) -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    @Environment(\.theme) private var theme

    public init(
        isVisible: Binding<Bool>,
        toolName: String = "Agent",
        savedPrompts: [SavedPrompt] = [],
        onSend: @escaping (String) -> Void
    ) {
        self._isVisible = isVisible
        self.toolName = toolName
        self.savedPrompts = savedPrompts
        self.onSend = onSend
    }

    public var body: some View {
        if isVisible {
            HStack(spacing: 8) {
                // Prompt library menu
                Menu {
                    if !SavedPrompt.builtIn.isEmpty {
                        Section("Quick Commands") {
                            ForEach(SavedPrompt.builtIn) { prompt in
                                Button(prompt.name) { sendPrompt(prompt.text) }
                            }
                        }
                    }
                    if !savedPrompts.isEmpty {
                        Section("Saved Prompts") {
                            ForEach(savedPrompts) { prompt in
                                Button(prompt.name) { sendPrompt(prompt.text) }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "text.cursor")
                            .foregroundColor(theme.chrome.accent)
                            .font(.caption)
                        Text(toolName)
                            .font(.caption2)
                            .foregroundColor(theme.chrome.textDim)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(theme.chrome.textDim)
                    }
                }
                .menuStyle(.button)
                .fixedSize()
                .accessibilityLabel("Prompt library")

                TextField("Send to session\u{2026}", text: $text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit { send() }
                    .accessibilityLabel("Message to send to \(toolName)")

                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(text.isEmpty ? theme.chrome.textDim : theme.chrome.accent)
                .disabled(text.isEmpty)
                .accessibilityLabel("Send message")

                Button(action: { isVisible = false }) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundColor(theme.chrome.textDim)
                .accessibilityLabel("Close send bar")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.chrome.surface)
            .onAppear { isFocused = true }
        }
    }

    private func send() {
        guard !text.isEmpty else { return }
        onSend(text)
        text = ""
    }

    private func sendPrompt(_ promptText: String) {
        onSend(promptText)
    }
}
