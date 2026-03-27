import SwiftUI
import Models
import Theme

/// Modal dialog for registering a new project (git repository).
public struct NewProjectDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var name: String = ""
    @State private var path: String = ""
    @State private var defaultBranch: String = "main"
    @State private var validationError: String?

    let onCreate: (String, String, String) -> Void

    public init(onCreate: @escaping (String, String, String) -> Void) {
        self.onCreate = onCreate
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("New Project")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                field("Name", text: $name, placeholder: "my-project")
                pathField
                field("Default Branch", text: $defaultBranch, placeholder: "main")
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
                    .disabled(name.isEmpty || path.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var pathField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Path")
                .font(.caption)
                .foregroundColor(theme.chrome.textDim)
            HStack {
                TextField("~/code/project", text: $path)
                    .textFieldStyle(.roundedBorder)
                Button("Browse…") { browseFolder() }
            }
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

    private func browseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select project directory"

        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
            if name.isEmpty {
                name = url.lastPathComponent
            }
        }
    }

    private func create() {
        let expanded = (path as NSString).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: expanded) else {
            validationError = "Directory does not exist"
            return
        }

        // Check if it's a git repo
        let gitDir = "\(expanded)/.git"
        guard FileManager.default.fileExists(atPath: gitDir) else {
            validationError = "Not a git repository (no .git directory)"
            return
        }

        onCreate(name, expanded, defaultBranch)
        dismiss()
    }
}
