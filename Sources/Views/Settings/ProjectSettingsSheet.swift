import Models
import SwiftUI
import Theme

public struct ProjectSettingsSheet: View {
    @Binding var project: Project
    let themes: [AppTheme]
    let onSave: (Project) -> Void
    let onDetectRepo: () async -> (repo: String, host: String?)?
    @Environment(\.dismiss) private var dismiss

    // Local state initialized from project on appear
    @State private var themeID: String?
    @State private var permissionMode: PermissionMode?
    @State private var issuesEnabled: Bool = false
    @State private var ghRepo: String?
    @State private var ghHost: String?
    @State private var isDetecting: Bool = false
    @State private var branchPrefix: String = ""

    public init(
        project: Binding<Project>,
        themes: [AppTheme],
        onSave: @escaping (Project) -> Void,
        onDetectRepo: @escaping () async -> (repo: String, host: String?)?
    ) {
        self._project = project
        self.themes = themes
        self.onSave = onSave
        self.onDetectRepo = onDetectRepo
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Project Settings")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // Form
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $themeID) {
                        Text("Use Default").tag(String?.none)
                        ForEach(themes, id: \.id) { theme in
                            Text(theme.name).tag(String?.some(theme.id))
                        }
                    }
                }

                Section("Session Defaults") {
                    Picker("Permission Mode", selection: $permissionMode) {
                        Text("Use Default").tag(PermissionMode?.none)
                        ForEach(PermissionMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(PermissionMode?.some(mode))
                        }
                    }

                    TextField("Branch Prefix", text: $branchPrefix, prompt: Text("feature/"))
                        .textFieldStyle(.roundedBorder)
                        .help("Prefix for auto-generated branch names (e.g. feature/, fix/, your-name/)")
                }

                Section("GitHub Issues") {
                    Toggle("Enable GitHub Issues", isOn: $issuesEnabled)
                        .onChange(of: issuesEnabled) { _, newValue in
                            if newValue && ghRepo == nil {
                                Task {
                                    await detectRepo()
                                }
                            }
                        }

                    if issuesEnabled {
                        if isDetecting {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Detecting repository…")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                            }
                        } else if let repo = ghRepo {
                            LabeledContent("Repository") {
                                Text(repo)
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                            }
                        } else {
                            Text("No repository detected")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Buttons
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 400, height: 380)
        .onAppear {
            themeID = project.themeID
            permissionMode = project.permissionMode
            issuesEnabled = project.issuesEnabled
            ghRepo = project.ghRepo
            ghHost = project.ghHost
            branchPrefix = project.branchPrefix ?? ""
        }
    }

    // MARK: - Private

    private func detectRepo() async {
        isDetecting = true
        defer { isDetecting = false }
        if let result = await onDetectRepo() {
            ghRepo = result.repo
            ghHost = result.host
        }
    }

    private func saveAndDismiss() {
        var updated = project
        updated.themeID = themeID
        updated.permissionMode = permissionMode
        updated.issuesEnabled = issuesEnabled
        updated.ghRepo = ghRepo
        updated.ghHost = ghHost
        updated.branchPrefix = branchPrefix.isEmpty ? nil : branchPrefix
        onSave(updated)
        dismiss()
    }
}
