import AppKit
import SwiftTerm
import SwiftUI

/// Search bar overlay for terminal find (Cmd+F).
///
/// Wraps SwiftTerm's built-in `findNext`/`findPrevious` which handle
/// selection highlighting and scroll-to-match automatically.
public struct TerminalSearchBar: View {
    @Binding var isVisible: Bool
    let onFindNext: (String) -> Void
    let onFindPrevious: (String) -> Void
    let onDismiss: () -> Void

    @State private var searchText: String = ""
    @FocusState private var isFocused: Bool

    public init(
        isVisible: Binding<Bool>,
        onFindNext: @escaping (String) -> Void,
        onFindPrevious: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self._isVisible = isVisible
        self.onFindNext = onFindNext
        self.onFindPrevious = onFindPrevious
        self.onDismiss = onDismiss
    }

    public var body: some View {
        if isVisible {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Find in terminal…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isFocused)
                    .onSubmit { onFindNext(searchText) }

                Button(action: { onFindPrevious(searchText) }) {
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(searchText.isEmpty)

                Button(action: { onFindNext(searchText) }) {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(searchText.isEmpty)

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
            .cornerRadius(6)
            .shadow(radius: 2)
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .onAppear { isFocused = true }
            .onExitCommand { dismiss() }
        }
    }

    private func dismiss() {
        searchText = ""
        onDismiss()
        isVisible = false
    }
}
