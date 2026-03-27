import SwiftUI
import Models
import Theme

/// Modal dialog for creating a new AI coding session.
public struct NewSessionDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var title: String = ""
    @State private var selectedProjectID: String?
    @State private var tool: Tool = .claude
    @State private var useWorktree: Bool = true
    @State private var branchName: String = ""
    @State private var validationError: String?

    let projects: [Project]
    let onCreate: (NewSessionRequest) -> Void

    public init(projects: [Project], onCreate: @escaping (NewSessionRequest) -> Void) {
        self.projects = projects
        self.onCreate = onCreate
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("New Session")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                // Title
                field("Session Name", text: $title, placeholder: "feature-name")
                    .onChange(of: title) {
                        if useWorktree && branchName.isEmpty || branchName == autobranchName(from: "") {
                            branchName = autobranchName(from: title)
                        }
                    }

                // Project picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project")
                        .font(.caption)
                        .foregroundColor(theme.chrome.textDim)
                    Picker("Project", selection: $selectedProjectID) {
                        Text("None").tag(nil as String?)
                        ForEach(projects) { project in
                            Text(project.name).tag(project.id as String?)
                        }
                    }
                    .labelsHidden()
                }

                // Tool picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tool")
                        .font(.caption)
                        .foregroundColor(theme.chrome.textDim)
                    Picker("Tool", selection: $tool) {
                        Text("Claude").tag(Tool.claude)
                        Text("Shell").tag(Tool.shell)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Worktree toggle
                Toggle("Create worktree", isOn: $useWorktree)

                // Branch name (visible when worktree enabled)
                if useWorktree {
                    field("Branch Name", text: $branchName, placeholder: "feature/my-feature")
                }
            }

            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(theme.chrome.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(theme.chrome.textDim)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func autobranchName(from title: String) -> String {
        let sanitized = title.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        return sanitized.isEmpty ? "" : "feature/\(sanitized)"
    }

    private func create() {
        guard !title.isEmpty else {
            validationError = "Session name is required"
            return
        }

        let project = projects.first(where: { $0.id == selectedProjectID })
        let path = project?.path ?? FileManager.default.currentDirectoryPath

        let request = NewSessionRequest(
            title: title,
            projectID: selectedProjectID,
            path: path,
            tool: tool,
            useWorktree: useWorktree,
            branchName: useWorktree ? branchName : nil
        )

        onCreate(request)
        dismiss()
    }
}

