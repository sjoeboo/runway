import GitHubOperations
import Models
import SwiftUI
import Theme

/// Popover-hosted picker for PR assignees. Shows a top "Assign to me" pill,
/// a search field, and a scrollable list of repo collaborators with
/// check indicators for currently-assigned logins.
public struct AssigneePickerView: View {
    let pr: PullRequest
    let myLogin: String?
    let collaborators: [Collaborator]
    let isLoading: Bool
    let onAssignToMe: () -> Void
    let onUnassignMe: () -> Void
    let onToggle: (String) -> Void

    @State private var query: String = ""
    @Environment(\.theme) private var theme

    public init(
        pr: PullRequest,
        myLogin: String?,
        collaborators: [Collaborator],
        isLoading: Bool,
        onAssignToMe: @escaping () -> Void,
        onUnassignMe: @escaping () -> Void,
        onToggle: @escaping (String) -> Void
    ) {
        self.pr = pr
        self.myLogin = myLogin
        self.collaborators = collaborators
        self.isLoading = isLoading
        self.onAssignToMe = onAssignToMe
        self.onUnassignMe = onUnassignMe
        self.onToggle = onToggle
    }

    public var body: some View {
        VStack(spacing: 8) {
            mePill
            Divider()
            searchField
            Divider()
            listContent
        }
        .padding(12)
        .frame(width: 360, height: 420)
        .background(theme.chrome.surface)
    }

    // MARK: - Pill

    @ViewBuilder
    private var mePill: some View {
        if let myLogin {
            let isAssigned = pr.assignees.contains(myLogin)
            Button {
                if isAssigned { onUnassignMe() } else { onAssignToMe() }
            } label: {
                HStack {
                    Image(
                        systemName: isAssigned
                            ? "person.crop.circle.badge.minus" : "person.crop.circle.badge.plus"
                    )
                    Text(isAssigned ? "Unassign me" : "Assign to me")
                        .fontWeight(.medium)
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.chrome.green.opacity(0.15))
                )
                .foregroundColor(theme.chrome.green)
            }
            .buttonStyle(.plain)
        } else {
            Text("Resolving your login…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter collaborators…", text: $query)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(theme.chrome.background))
    }

    // MARK: - List

    @ViewBuilder
    private var listContent: some View {
        if isLoading && collaborators.isEmpty {
            VStack {
                Spacer()
                ProgressView("Loading collaborators…")
                Spacer()
            }
        } else {
            let filtered = Self.filter(collaborators: collaborators, query: query)
            if filtered.isEmpty {
                VStack {
                    Spacer()
                    Text("No matches").foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filtered) { collab in
                            row(for: collab)
                        }
                    }
                }
            }
        }
    }

    private func row(for collab: Collaborator) -> some View {
        let isAssigned = pr.assignees.contains(collab.login)
        let isMe = collab.login == myLogin
        return Button {
            onToggle(collab.login)
        } label: {
            HStack(spacing: 8) {
                AssigneeAvatar(login: collab.login, isMe: isMe, size: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(collab.login).font(.callout)
                    if let name = collab.name, !name.isEmpty {
                        Text(name).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isAssigned {
                    Image(systemName: "checkmark").foregroundColor(theme.chrome.green)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pure helper (testable)

    nonisolated public static func filter(
        collaborators: [Collaborator], query: String
    )
        -> [Collaborator]
    {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return collaborators }
        return collaborators.filter { collab in
            if collab.login.lowercased().contains(trimmed) { return true }
            if let name = collab.name?.lowercased(), name.contains(trimmed) { return true }
            return false
        }
    }
}
