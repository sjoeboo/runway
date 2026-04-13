import Models
import SwiftUI
import Theme

/// Confirmation sheet for creating a PR review session.
public struct ReviewPRSheet: View {
    let pr: PullRequest
    let projects: [Project]
    let onCreate: (String, String?, String) -> Void  // (sessionName, projectID, initialPrompt)

    @State private var sessionName: String
    @State private var selectedProjectID: String?
    @State private var initialPrompt: String = "Review this PR"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    public init(
        pr: PullRequest,
        projects: [Project],
        onCreate: @escaping (String, String?, String) -> Void
    ) {
        self.pr = pr
        self.projects = projects
        self.onCreate = onCreate

        let truncatedTitle = pr.title.count > 60 ? String(pr.title.prefix(57)) + "..." : pr.title
        self._sessionName = State(initialValue: "Review: \(truncatedTitle)")
        // Match by ghRepo first, then fall back to project name matching the repo suffix
        let repoLower = pr.repo.lowercased()
        let repoName = repoLower.split(separator: "/").last.map(String.init) ?? repoLower
        let matched =
            projects.first(where: { $0.ghRepo?.lowercased() == repoLower })
            ?? projects.first(where: { $0.name.lowercased() == repoName })
        self._selectedProjectID = State(initialValue: matched?.id)
    }

    private var autoDetected: Bool {
        let repoLower = pr.repo.lowercased()
        let repoName = repoLower.split(separator: "/").last.map(String.init) ?? repoLower
        let matched =
            projects.first(where: { $0.ghRepo?.lowercased() == repoLower })
            ?? projects.first(where: { $0.name.lowercased() == repoName })
        return matched?.id == selectedProjectID
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            prBanner

            VStack(alignment: .leading, spacing: 12) {
                formField("Session Name") {
                    TextField("Session name", text: $sessionName)
                        .textFieldStyle(.roundedBorder)
                }

                formField("Project") {
                    HStack {
                        Picker("Project", selection: $selectedProjectID) {
                            Text("None").tag(nil as String?)
                            ForEach(projects) { project in
                                Text(project.name).tag(project.id as String?)
                            }
                        }
                        .labelsHidden()

                        if autoDetected {
                            Text("Auto-detected")
                                .font(.caption)
                                .foregroundColor(theme.chrome.accent)
                        }
                    }
                }

                formField("Initial Prompt") {
                    TextField("Prompt to pre-fill in terminal", text: $initialPrompt)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create Review Session") {
                    onCreate(sessionName, selectedProjectID, initialPrompt)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(sessionName.isEmpty || selectedProjectID == nil)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 560)
    }

    private var prBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PRStateBadge(state: pr.state)
                Text("#\(pr.number)")
                    .font(.caption)
                    .foregroundColor(theme.chrome.textDim)
            }
            Text(pr.title)
                .font(.headline)
            HStack(spacing: 12) {
                Text("by \(pr.author)")
                    .font(.caption)
                    .foregroundColor(theme.chrome.textDim)
                HStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                    Text(pr.headBranch)
                        .font(.caption)
                        .fontDesign(.monospaced)
                }
                .foregroundColor(theme.chrome.accent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.chrome.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(theme.chrome.textDim)
            content()
        }
    }
}

private struct PRStateBadge: View {
    let state: PRState
    @Environment(\.theme) private var theme

    var body: some View {
        Text(state.rawValue)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundColor(.white)
            .background(badgeColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var badgeColor: Color {
        switch state {
        case .open: theme.chrome.green
        case .draft: theme.chrome.textDim
        case .merged: theme.chrome.purple
        case .closed: theme.chrome.red
        }
    }
}

/// Small dialog for entering a PR number — opened via ⌘⇧R.
public struct ReviewPRNumberDialog: View {
    let projects: [Project]
    let isResolving: Bool
    let onResolve: (Int, String, String?) -> Void  // (number, repo, host)

    @State private var prNumberText: String = ""
    @State private var selectedProjectID: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    public init(
        projects: [Project],
        isResolving: Bool,
        onResolve: @escaping (Int, String, String?) -> Void
    ) {
        self.projects = projects
        self.isResolving = isResolving
        self.onResolve = onResolve
        let firstWithRepo = projects.first(where: { $0.ghRepo != nil })
        self._selectedProjectID = State(initialValue: firstWithRepo?.id)
    }

    private var selectedProject: Project? {
        projects.first(where: { $0.id == selectedProjectID })
    }

    private var projectsWithRepo: [Project] {
        projects.filter { $0.ghRepo != nil }
    }

    private var canResolve: Bool {
        guard let number = Int(prNumberText), number > 0 else { return false }
        return selectedProject?.ghRepo != nil && !isResolving
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review PR")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("PR number", text: $prNumberText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onSubmit { resolve() }

                if projectsWithRepo.count > 1 {
                    Picker("in", selection: $selectedProjectID) {
                        ForEach(projectsWithRepo) { project in
                            Text(project.name).tag(project.id as String?)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 160)
                } else if let project = selectedProject {
                    Text("in \(project.name)")
                        .font(.caption)
                        .foregroundColor(theme.chrome.textDim)
                }
            }

            if isResolving {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Resolving PR...")
                        .font(.caption)
                        .foregroundColor(theme.chrome.textDim)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Resolve") { resolve() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canResolve)
            }
        }
        .padding(20)
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
    }

    private func resolve() {
        guard let number = Int(prNumberText), let project = selectedProject, let repo = project.ghRepo else { return }
        onResolve(number, repo, project.ghHost)
    }
}
