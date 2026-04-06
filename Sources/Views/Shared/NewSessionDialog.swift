import Models
import SwiftUI
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
    @State private var branchManuallyEdited: Bool = false
    @AppStorage("defaultPermissionMode") private var defaultPermissionMode: PermissionMode = .default
    @State private var permissionMode: PermissionMode = .default
    @State private var validationError: String?

    let projects: [Project]
    let initialProjectID: String?
    let parentID: String?
    let onCreate: (NewSessionRequest) -> Void

    public init(
        projects: [Project],
        initialProjectID: String? = nil,
        parentID: String? = nil,
        onCreate: @escaping (NewSessionRequest) -> Void
    ) {
        self.projects = projects
        self.initialProjectID = initialProjectID
        self.parentID = parentID
        self.onCreate = onCreate
        self._selectedProjectID = State(initialValue: initialProjectID)
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
                        if useWorktree && !branchManuallyEdited {
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

                // Permission mode (only for Claude sessions)
                if tool == .claude {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Permissions")
                            .font(.caption)
                            .foregroundColor(theme.chrome.textDim)
                        Picker("Permissions", selection: $permissionMode) {
                            ForEach(PermissionMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        if permissionMode == .bypassAll {
                            Text("Skips all permission prompts — use with caution")
                                .font(.caption2)
                                .foregroundColor(theme.chrome.orange)
                        }
                    }
                }

                // Worktree toggle
                Toggle("Create worktree", isOn: $useWorktree)

                // Branch name (visible when worktree enabled)
                if useWorktree {
                    field(
                        "Branch Name",
                        text: Binding(
                            get: { branchName },
                            set: { newValue in
                                branchName = newValue
                                // If user edits branch to differ from auto, mark as manually edited
                                branchManuallyEdited = (newValue != autobranchName(from: title))
                            }
                        ), placeholder: "feature/my-feature")
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
        .onAppear {
            permissionMode = defaultPermissionMode
        }
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
        // Strip all git-illegal characters: ~, ^, :, ?, *, [, \, control chars, spaces, ..
        let sanitized = title.lowercased()
            .replacing(/[^a-z0-9\-]/, with: "-")
            .replacing(/--+/, with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        if sanitized.isEmpty { return "" }
        let prefix = projects.first(where: { $0.id == selectedProjectID })?.branchPrefix ?? "feature/"
        return "\(prefix)\(sanitized)"
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
            parentID: parentID,
            path: path,
            tool: tool,
            useWorktree: useWorktree,
            branchName: useWorktree ? branchName : nil,
            permissionMode: tool == .claude ? permissionMode : .default
        )

        onCreate(request)
        dismiss()
    }
}
