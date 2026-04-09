import AppKit
import SwiftTerm
import SwiftUI

/// Search bar overlay for terminal find (Cmd+F).
///
/// Wraps SwiftTerm's built-in `findNext`/`findPrevious` which handle
/// selection highlighting and scroll-to-match automatically.
/// Shows match feedback: "No results" with red tint when nothing found,
/// or "N matches" when results exist.
public struct TerminalSearchBar: View {
    @Binding var isVisible: Bool
    /// Returns true if a match was found.
    let onFindNext: (String) -> Bool
    /// Returns true if a match was found.
    let onFindPrevious: (String) -> Bool
    /// Returns total match count for the given term, or nil if unavailable.
    let onCountMatches: ((String) -> Int?)?
    let onDismiss: () -> Void

    @State private var searchText: String = ""
    @State private var searchState: SearchFeedback = .idle
    @FocusState private var isFocused: Bool

    enum SearchFeedback: Equatable {
        case idle
        case found(count: Int?)
        case notFound
    }

    public init(
        isVisible: Binding<Bool>,
        onFindNext: @escaping (String) -> Bool,
        onFindPrevious: @escaping (String) -> Bool,
        onCountMatches: ((String) -> Int?)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self._isVisible = isVisible
        self.onFindNext = onFindNext
        self.onFindPrevious = onFindPrevious
        self.onCountMatches = onCountMatches
        self.onDismiss = onDismiss
    }

    public var body: some View {
        if isVisible {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundColor(searchState == .notFound ? .red : .secondary)

                TextField("Find in terminal…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .focused($isFocused)
                    .onSubmit { performSearch(forward: true) }
                    .onChange(of: searchText) { _, _ in
                        // Reset search state on any text change so find buttons
                        // re-enable after editing a "not found" search term
                        searchState = .idle
                    }

                // Match feedback label
                if case .found(let count) = searchState {
                    if let count {
                        Text("\(count) match\(count == 1 ? "" : "es")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else if searchState == .notFound {
                    Text("No results")
                        .font(.caption2)
                        .foregroundColor(.red)
                }

                Button(action: { performSearch(forward: false) }) {
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(searchText.isEmpty || searchState == .notFound)

                Button(action: { performSearch(forward: true) }) {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(searchText.isEmpty || searchState == .notFound)

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(radius: 2)
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .onAppear { isFocused = true }
            .onDisappear {
                // Clear search highlights when the bar disappears — covers both
                // the dismiss() path and the Cmd+F toggle path which bypasses dismiss()
                onDismiss()
            }
            .onExitCommand { dismiss() }
        }
    }

    private func performSearch(forward: Bool) {
        guard !searchText.isEmpty else { return }
        let found = forward ? onFindNext(searchText) : onFindPrevious(searchText)
        if found {
            let count = onCountMatches?(searchText)
            searchState = .found(count: count)
        } else {
            searchState = .notFound
        }
    }

    private func dismiss() {
        searchText = ""
        searchState = .idle
        onDismiss()
        isVisible = false
    }
}
