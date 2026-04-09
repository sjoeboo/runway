import Models
import SwiftUI
import Theme

/// The kind of session being created.
private enum SessionKind: String, CaseIterable {
    case normal = "New Session"
    case fromTemplate = "From Template"
    case prReview = "PR Review"
}

/// Modal dialog for creating a new AI coding session.
public struct NewSessionDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    // Shared state
    @State private var sessionKind: SessionKind = .normal
    @State private var selectedProjectID: String?
    @AppStorage("defaultPermissionMode") private var defaultPermissionMode: PermissionMode = .default
    @State private var permissionMode: PermissionMode = .default
    @State private var initialPrompt: String = ""
    @State private var validationError: String?

    @FocusState private var titleFocused: Bool

    // Normal session state
    @State private var title: String = ""
    @State private var selectedProfileID: String = "claude"
    @State private var useHappy: Bool = false
    @State private var useWorktree: Bool = true
    @State private var branchName: String = ""
    @State private var branchManuallyEdited: Bool = false

    // PR Review state
    @State private var prNumberText: String = ""
    @State private var reviewSessionName: String = ""
    @State private var isCreatingReview: Bool = false

    let projects: [Project]
    let profiles: [AgentProfile]
    let initialProjectID: String?
    let parentID: String?
    let templates: [SessionTemplate]
    let onCreate: (NewSessionRequest) -> Void
    let onCreateReview: ((ReviewSessionRequest) async throws -> Void)?

    @State private var selectedTemplateID: String?

    public init(
        projects: [Project],
        profiles: [AgentProfile] = AgentProfile.builtIn,
        initialProjectID: String? = nil,
        parentID: String? = nil,
        templates: [SessionTemplate] = [],
        onCreate: @escaping (NewSessionRequest) -> Void,
        onCreateReview: ((ReviewSessionRequest) async throws -> Void)? = nil
    ) {
        self.projects = projects
        self.profiles = profiles
        self.initialProjectID = initialProjectID
        self.parentID = parentID
        self.templates = templates
        self.onCreate = onCreate
        self.onCreateReview = onCreateReview
        self._selectedProjectID = State(initialValue: initialProjectID)
    }

    private var projectsWithRepo: [Project] {
        projects.filter { $0.ghRepo != nil }
    }

    private var selectedTool: Tool {
        switch selectedProfileID {
        case "claude": return .claude
        case "shell": return .shell
        default: return .custom(selectedProfileID)
        }
    }

    private var selectedProject: Project? {
        projects.first(where: { $0.id == selectedProjectID })
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Session type picker
            Picker("Type", selection: $sessionKind) {
                ForEach(SessionKind.allCases, id: \.self) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: sessionKind) {
                validationError = nil
                // Default to first project with repo when switching to PR review
                if sessionKind == .prReview && selectedProjectID == nil {
                    selectedProjectID = projectsWithRepo.first?.id
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                switch sessionKind {
                case .normal:
                    normalSessionFields
                case .fromTemplate:
                    templateSessionFields
                case .prReview:
                    prReviewFields
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

                if sessionKind == .prReview && isCreatingReview {
                    ProgressView()
                        .controlSize(.small)
                    Text("Creating review session…")
                        .font(.caption)
                        .foregroundColor(theme.chrome.textDim)
                }

                Button(sessionKind == .prReview ? "Create Review" : "Create") {
                    switch sessionKind {
                    case .normal:
                        createNormalSession()
                    case .fromTemplate:
                        createFromTemplate()
                    case .prReview:
                        createReviewSession()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    {
                        switch sessionKind {
                        case .normal: title.isEmpty
                        case .fromTemplate: title.isEmpty || selectedTemplateID == nil
                        case .prReview: !canCreateReview
                        }
                    }())
            }
        }
        .padding(24)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            permissionMode = defaultPermissionMode
            titleFocused = true
        }
    }

    // MARK: - Normal Session Fields

    @ViewBuilder
    private var normalSessionFields: some View {
        // Title
        VStack(alignment: .leading, spacing: 4) {
            Text("Session Name")
                .font(.caption)
                .foregroundColor(theme.chrome.textDim)
            TextField("feature-name", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
        }
        .onChange(of: title) {
            if useWorktree && !branchManuallyEdited {
                branchName = autobranchName(from: title)
            }
        }
        .onChange(of: selectedProfileID) {
            if !selectedTool.supportsHappy {
                useHappy = false
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

        // Agent picker
        VStack(alignment: .leading, spacing: 4) {
            Text("Agent")
                .font(.caption)
                .foregroundColor(theme.chrome.textDim)
            Picker("Agent", selection: $selectedProfileID) {
                ForEach(profiles) { profile in
                    Label(profile.name, systemImage: profile.icon).tag(profile.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }

        // Permission mode (only for tools that support it)
        if selectedTool.supportsPermissionModes {
            permissionPicker
        }

        // Happy toggle (only for tools that support it)
        if selectedTool.supportsHappy {
            Toggle("Launch with Happy", isOn: $useHappy)
            if useHappy {
                Text("Wraps session with Happy for mobile access")
                    .font(.caption2)
                    .foregroundColor(theme.chrome.textDim)
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
                        branchManuallyEdited = (newValue != autobranchName(from: title))
                    }
                ), placeholder: "feature/my-feature")
        }

        // Initial prompt (only for tools that support it)
        if selectedTool.supportsInitialPrompt {
            promptEditor
        }
    }

    // MARK: - Template Session Fields

    @ViewBuilder
    private var templateSessionFields: some View {
        // Template picker
        if templates.isEmpty {
            Text("No templates available. Create templates in project settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Template")
                    .font(.caption)
                    .foregroundColor(theme.chrome.textDim)
                Picker("Template", selection: $selectedTemplateID) {
                    Text("Select a template...").tag(String?.none)
                    ForEach(templates) { template in
                        Text(template.name).tag(Optional(template.id))
                    }
                }
                .labelsHidden()
            }
        }

        // Title field
        VStack(alignment: .leading, spacing: 4) {
            Text("Session Name")
                .font(.caption)
                .foregroundColor(theme.chrome.textDim)
            TextField("Session title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
        }

        // Show template details as read-only summary
        if let template = templates.first(where: { $0.id == selectedTemplateID }) {
            Group {
                HStack(spacing: 8) {
                    Text("Tool: \(template.tool.displayName)")
                    Text("·")
                    Text("Mode: \(template.permissionMode.displayName)")
                    if template.useWorktree {
                        Text("·")
                        Text("Worktree")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !template.initialPromptTemplate.isEmpty {
                    Text("Prompt: \(template.initialPromptTemplate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
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
    }

    // MARK: - PR Review Fields

    @ViewBuilder
    private var prReviewFields: some View {
        // PR Number
        field("PR Number", text: $prNumberText, placeholder: "1234")

        // Project picker (only projects with a configured repo)
        VStack(alignment: .leading, spacing: 4) {
            Text("Project")
                .font(.caption)
                .foregroundColor(theme.chrome.textDim)
            if projectsWithRepo.isEmpty {
                Text("No projects with a GitHub repo configured")
                    .font(.caption)
                    .foregroundColor(theme.chrome.orange)
            } else {
                Picker("Project", selection: $selectedProjectID) {
                    ForEach(projectsWithRepo) { project in
                        Text(project.name).tag(project.id as String?)
                    }
                }
                .labelsHidden()
            }
        }

        // Session name (optional override)
        field("Session Name", text: $reviewSessionName, placeholder: "Auto-generated from PR title")

        // Permission mode
        permissionPicker

        // Initial prompt
        field("Initial Prompt", text: $initialPrompt, placeholder: "Review this PR")
            .onAppear {
                if initialPrompt.isEmpty {
                    initialPrompt = "Review this PR"
                }
            }
    }

    // MARK: - Shared Components

    private var permissionPicker: some View {
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

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Initial Prompt")
                .font(.caption)
                .foregroundColor(theme.chrome.textDim)
            TextEditor(text: $initialPrompt)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
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

    // MARK: - Actions

    private var canCreateReview: Bool {
        guard let number = Int(prNumberText), number > 0 else { return false }
        return selectedProject?.ghRepo != nil && !isCreatingReview
    }

    private func autobranchName(from title: String) -> String {
        let sanitized = title.lowercased()
            .replacing(/[^a-z0-9\-]/, with: "-")
            .replacing(/--+/, with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        if sanitized.isEmpty { return "" }
        let prefix = projects.first(where: { $0.id == selectedProjectID })?.branchPrefix ?? "feature/"
        return "\(prefix)\(sanitized)"
    }

    private func createNormalSession() {
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
            tool: selectedTool,
            useWorktree: useWorktree,
            branchName: useWorktree ? branchName : nil,
            permissionMode: selectedTool.supportsPermissionModes ? permissionMode : .default,
            useHappy: selectedTool.supportsHappy ? useHappy : false,
            initialPrompt: (selectedTool.supportsInitialPrompt && !initialPrompt.isEmpty) ? initialPrompt : nil
        )

        onCreate(request)
        dismiss()
    }

    private func createFromTemplate() {
        guard let templateID = selectedTemplateID,
            let template = templates.first(where: { $0.id == templateID }),
            !title.isEmpty
        else {
            validationError = "Select a template and enter a title"
            return
        }

        let resolvedPrompt = template.resolvedPrompt(title: title)
        let project = projects.first(where: { $0.id == selectedProjectID })
        let path = project?.path ?? FileManager.default.currentDirectoryPath
        let branchName: String? =
            template.useWorktree
            ? autobranchName(from: title) : nil

        let request = NewSessionRequest(
            title: title,
            projectID: selectedProjectID,
            parentID: parentID,
            path: path,
            tool: template.tool,
            useWorktree: template.useWorktree,
            branchName: branchName,
            permissionMode: template.permissionMode,
            initialPrompt: resolvedPrompt.isEmpty ? nil : resolvedPrompt
        )
        onCreate(request)
        dismiss()
    }

    private func createReviewSession() {
        guard let number = Int(prNumberText), number > 0 else {
            validationError = "Enter a valid PR number"
            return
        }
        guard let project = selectedProject, let repo = project.ghRepo else {
            validationError = "Select a project with a GitHub repo"
            return
        }

        let sessionName = reviewSessionName.isEmpty ? "Review: PR #\(number)" : reviewSessionName
        let prompt = initialPrompt.isEmpty ? "Review this PR" : initialPrompt

        let request = ReviewSessionRequest(
            prNumber: number,
            repo: repo,
            host: project.ghHost,
            sessionName: sessionName,
            projectID: project.id,
            permissionMode: permissionMode,
            initialPrompt: prompt
        )

        isCreatingReview = true
        validationError = nil

        Task {
            do {
                try await onCreateReview?(request)
                dismiss()
            } catch {
                isCreatingReview = false
                validationError = "Failed to resolve PR #\(number): \(error.localizedDescription)"
            }
        }
    }
}
