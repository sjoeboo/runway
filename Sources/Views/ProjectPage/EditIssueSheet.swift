import Models
import SwiftUI
import Theme

public struct EditIssueSheet: View {
    let issue: GitHubIssue
    let currentBody: String
    let onSave: (String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var title: String
    @State private var issueBody: String

    public init(
        issue: GitHubIssue,
        currentBody: String,
        onSave: @escaping (String?, String?) -> Void
    ) {
        self.issue = issue
        self.currentBody = currentBody
        self.onSave = onSave
        self._title = State(initialValue: issue.title)
        self._issueBody = State(initialValue: currentBody)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Issue #\(issue.number)")
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .font(.caption)
                    .foregroundColor(theme.chrome.textDim)
                TextField("Issue title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Body")
                    .font(.caption)
                    .foregroundColor(theme.chrome.textDim)
                TextEditor(text: $issueBody)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(theme.chrome.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Spacer(minLength: 0)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let newTitle = title != issue.title ? title : nil
                    let newBody = issueBody != currentBody ? issueBody : nil
                    if newTitle != nil || newBody != nil {
                        onSave(newTitle, newBody)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500, height: 450)
    }
}
