import Models
import SwiftUI
import Theme

public struct ManageAssigneesSheet: View {
    let currentAssignees: [String]
    let onSave: ([String], [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var assignees: [String]
    @State private var newAssignee: String = ""

    public init(
        currentAssignees: [String],
        onSave: @escaping ([String], [String]) -> Void
    ) {
        self.currentAssignees = currentAssignees
        self.onSave = onSave
        self._assignees = State(initialValue: currentAssignees)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manage Assignees")
                .font(.title3)
                .fontWeight(.semibold)

            HStack(spacing: 8) {
                TextField("Username", text: $newAssignee)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addAssignee() }
                Button("Add") { addAssignee() }
                    .disabled(newAssignee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if assignees.isEmpty {
                Text("No assignees")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(assignees, id: \.self) { assignee in
                            HStack {
                                Label(assignee, systemImage: "person")
                                    .font(.body)
                                Spacer()
                                Button {
                                    assignees.removeAll { $0 == assignee }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(theme.chrome.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let originalSet = Set(currentAssignees)
                    let currentSet = Set(assignees)
                    let add = Array(currentSet.subtracting(originalSet))
                    let remove = Array(originalSet.subtracting(currentSet))
                    if !add.isEmpty || !remove.isEmpty {
                        onSave(add, remove)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 350, height: 350)
    }

    private func addAssignee() {
        let trimmed = newAssignee.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !assignees.contains(trimmed) else { return }
        assignees.append(trimmed)
        newAssignee = ""
    }
}
