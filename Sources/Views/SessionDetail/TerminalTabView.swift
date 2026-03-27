import SwiftUI
import Models
import Theme
import TerminalView

/// A tab model for terminal instances within a session.
struct TerminalTab: Identifiable {
    let id: String
    let title: String
    let config: TerminalConfig
    let isMain: Bool

    init(id: String = UUID().uuidString, title: String, config: TerminalConfig, isMain: Bool = false) {
        self.id = id
        self.title = title
        self.config = config
        self.isMain = isMain
    }
}

/// Tab bar + terminal pane container for multiple terminals per session.
public struct TerminalTabView: View {
    let session: Session
    @State private var tabs: [TerminalTab] = []
    @State private var selectedTabID: String?
    @Environment(\.theme) private var theme

    public init(session: Session) {
        self.session = session
    }

    public var body: some View {
        VStack(spacing: 0) {
            if tabs.count > 1 {
                tabBar
                Divider()
            }

            // Terminal for selected tab
            if let tab = selectedTab {
                TerminalPane(config: tab.config)
                    .id(tab.id) // Force new view per tab
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { initializeTabs() }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                tabButton(tab)
            }

            // Add tab button
            Button(action: addShellTab) {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundColor(theme.chrome.textDim)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("New shell tab")

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(theme.chrome.surface)
    }

    private func tabButton(_ tab: TerminalTab) -> some View {
        let isSelected = tab.id == selectedTabID

        return HStack(spacing: 4) {
            if tab.isMain {
                Image(systemName: "terminal")
                    .font(.caption2)
            }
            Text(tab.title)
                .font(.caption)
                .lineLimit(1)

            if !tab.isMain && tabs.count > 1 {
                Button(action: { closeTab(tab.id) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(theme.chrome.textDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? theme.chrome.background : theme.chrome.surface)
        .foregroundColor(isSelected ? theme.chrome.text : theme.chrome.textDim)
        .cornerRadius(4)
        .onTapGesture { selectedTabID = tab.id }
    }

    // MARK: - Tab Management

    private var selectedTab: TerminalTab? {
        tabs.first(where: { $0.id == selectedTabID }) ?? tabs.first
    }

    private func initializeTabs() {
        guard tabs.isEmpty else { return }

        let mainTab = TerminalTab(
            title: session.tool.displayName,
            config: TerminalConfig(
                command: session.tool.command,
                arguments: [],
                workingDirectory: session.path,
                environment: [
                    "RUNWAY_SESSION_ID": session.id,
                    "RUNWAY_TITLE": session.title,
                ]
            ),
            isMain: true
        )

        tabs = [mainTab]
        selectedTabID = mainTab.id
    }

    private func addShellTab() {
        let shellCount = tabs.filter { !$0.isMain }.count + 1
        let tab = TerminalTab(
            title: "Shell \(shellCount)",
            config: TerminalConfig(
                command: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
                workingDirectory: session.path,
                environment: [
                    "RUNWAY_SESSION_ID": session.id,
                ]
            )
        )

        tabs.append(tab)
        selectedTabID = tab.id
    }

    private func closeTab(_ id: String) {
        tabs.removeAll { $0.id == id }
        if selectedTabID == id {
            selectedTabID = tabs.first?.id
        }
    }
}
