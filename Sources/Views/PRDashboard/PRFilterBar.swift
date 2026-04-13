import Models
import SwiftUI
import Theme

/// Persistent filter bar with dropdown menus for each filter dimension.
struct PRFilterBar: View {
    @Binding var filter: PRFilterState
    let pullRequests: [PullRequest]
    @Environment(\.theme) private var theme

    /// Distinct repo values from current PRs, sorted alphabetically.
    private var repoOptions: [String] {
        Array(Set(pullRequests.map(\.repo))).sorted()
    }

    /// Distinct author values from current PRs, sorted alphabetically.
    private var authorOptions: [String] {
        Array(Set(pullRequests.map(\.author))).sorted()
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("Filter:")
                .font(.caption)
                .foregroundColor(theme.chrome.textDim)

            filterMenu("Repo", selection: filter.repo ?? "All", isActive: filter.repo != nil) {
                Button("All") { filter.repo = nil }
                Divider()
                ForEach(repoOptions, id: \.self) { repo in
                    Button(repo) { filter.repo = repo }
                }
            }

            filterMenu("Author", selection: filter.author ?? "All", isActive: filter.author != nil) {
                Button("All") { filter.author = nil }
                Divider()
                ForEach(authorOptions, id: \.self) { author in
                    Button(author) { filter.author = author }
                }
            }

            filterMenu("Age", selection: filter.ageBucket.rawValue, isActive: filter.ageBucket != .any) {
                ForEach(PRAgeBucket.allCases, id: \.self) { bucket in
                    Button(bucket.rawValue) { filter.ageBucket = bucket }
                }
            }

            filterMenu(
                "Checks",
                selection: filter.checks?.label ?? "All",
                isActive: filter.checks != nil
            ) {
                Button("All") { filter.checks = nil }
                Divider()
                Button("Passing") { filter.checks = .passed }
                Button("Failing") { filter.checks = .failed }
                Button("Pending") { filter.checks = .pending }
            }

            filterMenu(
                "Review",
                selection: reviewLabel(filter.review),
                isActive: filter.review != nil
            ) {
                Button("All") { filter.review = nil }
                Divider()
                Button("Approved") { filter.review = .approved }
                Button("Changes Requested") { filter.review = .changesRequested }
                Button("Pending") { filter.review = .pending }
            }

            filterMenu(
                "Merge",
                selection: filter.mergeFilter?.rawValue ?? "All",
                isActive: filter.mergeFilter != nil
            ) {
                Button("All") { filter.mergeFilter = nil }
                Divider()
                ForEach(PRMergeFilter.allCases, id: \.self) { mergeFilter in
                    Button(mergeFilter.rawValue) { filter.mergeFilter = mergeFilter }
                }
            }

            if filter.isActive {
                Button("Clear") { filter.clear() }
                    .font(.caption)
                    .foregroundColor(theme.chrome.accent)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear all filters")
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(theme.chrome.surface)
    }

    private func filterMenu<Content: View>(
        _ label: String,
        selection: String,
        isActive: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            Text("\(label): \(selection)")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? theme.chrome.accent.opacity(0.15) : theme.chrome.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isActive ? theme.chrome.accent.opacity(0.4) : theme.chrome.border, lineWidth: 1)
                )
                .foregroundColor(isActive ? theme.chrome.accent : theme.chrome.textDim)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func reviewLabel(_ decision: ReviewDecision?) -> String {
        switch decision {
        case .some(.approved): "Approved"
        case .some(.changesRequested): "Changes Requested"
        case .some(.pending): "Pending"
        case .some(.none): "All"
        case nil: "All"
        }
    }
}
