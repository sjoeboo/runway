import Foundation
import SwiftUI
import Theme

/// Displays a Claude Code session transcript from a JSONL file.
///
/// Reads the transcript file path from the session, parses each line as JSON,
/// and renders messages in a scrollable list with role-based styling.
public struct TranscriptView: View {
    let transcriptPath: String
    @State private var entries: [TranscriptEntry] = []
    @State private var isLoading = true
    @State private var error: String?
    @Environment(\.theme) private var theme

    public init(transcriptPath: String) {
        self.transcriptPath = transcriptPath
    }

    public var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading transcript\u{2026}")
            } else if let error {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.title2)
                        .foregroundColor(theme.chrome.textDim)
                    Text("Could not load transcript")
                        .font(.callout)
                        .foregroundColor(theme.chrome.textDim)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(theme.chrome.red)
                }
            } else if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.title2)
                        .foregroundColor(theme.chrome.textDim)
                    Text("Transcript is empty")
                        .font(.callout)
                        .foregroundColor(theme.chrome.textDim)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(entries) { entry in
                            entryRow(entry)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await loadTranscript() }
    }

    @ViewBuilder
    private func entryRow(_ entry: TranscriptEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Role indicator
            Text(entry.role.prefix(1).uppercased())
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(roleColor(entry.role))
                .frame(width: 20, height: 20)
                .background(roleColor(entry.role).opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.role.capitalized)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(roleColor(entry.role))

                if let text = entry.text {
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(theme.chrome.text)
                        .textSelection(.enabled)
                } else if let toolName = entry.toolName {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench")
                            .font(.caption2)
                        Text(toolName)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(theme.chrome.cyan)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "user": theme.chrome.green
        case "assistant": theme.chrome.accent
        case "tool": theme.chrome.cyan
        default: theme.chrome.textDim
        }
    }

    private func loadTranscript() async {
        defer { isLoading = false }

        guard FileManager.default.fileExists(atPath: transcriptPath) else {
            error = "File not found: \(transcriptPath)"
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: transcriptPath))
            let lines = String(data: data, encoding: .utf8)?.components(separatedBy: "\n") ?? []
            var parsed: [TranscriptEntry] = []

            for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                guard let lineData = line.data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
                else { continue }

                // Claude Code transcripts have "type" and "message" or "content" fields
                let type = json["type"] as? String ?? ""
                let role = (json["role"] as? String) ?? type

                var text: String?
                var toolName: String?

                if let content = json["content"] as? String {
                    text = String(content.prefix(2000))
                } else if let message = json["message"] as? [String: Any] {
                    if let content = message["content"] as? String {
                        text = String(content.prefix(2000))
                    }
                    if let tool = message["tool_name"] as? String {
                        toolName = tool
                    }
                }

                // Skip entries with no displayable content
                guard text != nil || toolName != nil else { continue }

                parsed.append(
                    TranscriptEntry(
                        id: "\(parsed.count)",
                        role: role,
                        text: text,
                        toolName: toolName
                    ))
            }

            entries = parsed
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Transcript Entry

struct TranscriptEntry: Identifiable {
    let id: String
    let role: String
    let text: String?
    let toolName: String?
}
