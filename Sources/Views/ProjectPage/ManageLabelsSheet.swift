import GitHubOperations
import Models
import SwiftUI
import Theme

public struct ManageLabelsSheet: View {
    let availableLabels: [IssueLabel]
    let currentLabels: [IssueDetailLabel]
    let onSave: ([String], [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var selectedNames: Set<String>

    public init(
        availableLabels: [IssueLabel],
        currentLabels: [IssueDetailLabel],
        onSave: @escaping ([String], [String]) -> Void
    ) {
        self.availableLabels = availableLabels
        self.currentLabels = currentLabels
        self.onSave = onSave
        self._selectedNames = State(initialValue: Set(currentLabels.map(\.name)))
    }

    private var originalNames: Set<String> {
        Set(currentLabels.map(\.name))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manage Labels")
                .font(.title3)
                .fontWeight(.semibold)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(availableLabels) { label in
                        Button {
                            if selectedNames.contains(label.name) {
                                selectedNames.remove(label.name)
                            } else {
                                selectedNames.insert(label.name)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selectedNames.contains(label.name) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(selectedNames.contains(label.name) ? theme.chrome.accent : theme.chrome.textDim)
                                Circle()
                                    .fill(Color(hex: label.color) ?? theme.chrome.accent)
                                    .frame(width: 12, height: 12)
                                Text(label.name)
                                    .font(.body)
                                    .foregroundColor(theme.chrome.text)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let add = Array(selectedNames.subtracting(originalNames))
                    let remove = Array(originalNames.subtracting(selectedNames))
                    if !add.isEmpty || !remove.isEmpty {
                        onSave(add, remove)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 350, height: 400)
    }
}
