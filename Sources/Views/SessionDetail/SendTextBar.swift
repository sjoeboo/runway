import SwiftUI
import Theme

/// Quick input bar for sending text to a session's terminal without focusing it.
///
/// Appears at the bottom of the session detail when triggered (⌘X or button).
/// Useful for sending prompts to Claude while viewing diffs or PRs.
public struct SendTextBar: View {
    @Binding var isVisible: Bool
    let onSend: (String) -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    @Environment(\.theme) private var theme

    public init(isVisible: Binding<Bool>, onSend: @escaping (String) -> Void) {
        self._isVisible = isVisible
        self.onSend = onSend
    }

    public var body: some View {
        if isVisible {
            HStack(spacing: 8) {
                Image(systemName: "text.cursor")
                    .foregroundColor(theme.chrome.accent)
                    .font(.caption)

                TextField("Send to session…", text: $text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit { send() }

                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(text.isEmpty ? theme.chrome.textDim : theme.chrome.accent)
                .disabled(text.isEmpty)

                Button(action: { isVisible = false }) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundColor(theme.chrome.textDim)
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
}
