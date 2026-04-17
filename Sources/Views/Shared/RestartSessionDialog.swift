import Models
import SwiftUI
import Theme

/// Confirmation dialog shown before restarting a session, with an optional
/// Happy-toggle for agents that support it.
public struct RestartSessionDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let session: Session
    let onConfirm: (_ useHappy: Bool) -> Void

    @State private var useHappy: Bool

    public init(session: Session, onConfirm: @escaping (_ useHappy: Bool) -> Void) {
        self.session = session
        self.onConfirm = onConfirm
        self._useHappy = State(initialValue: session.useHappy)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Restart session?")
                    .font(.headline)
                Text(session.title)
                    .font(.callout)
                    .foregroundColor(theme.chrome.textDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text("The current terminal will be closed and the agent relaunched with its resume flag.")
                .font(.callout)
                .foregroundColor(theme.chrome.textDim)
                .fixedSize(horizontal: false, vertical: true)

            if session.tool.supportsHappy {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Launch with Happy", isOn: $useHappy)
                    if useHappy {
                        Text("Wraps \(session.tool.displayName) in the Happy mobile companion.")
                            .font(.caption)
                            .foregroundColor(theme.chrome.textDim)
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Restart") {
                    onConfirm(useHappy)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 380, idealWidth: 420, maxWidth: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}
