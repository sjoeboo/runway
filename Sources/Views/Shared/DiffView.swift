import Models
import SwiftUI
import Theme

/// Renders a unified diff with syntax-highlighted additions/deletions.
public struct DiffView: View {
    let files: [DiffFile]
    @State private var expandedFiles: Set<String>
    @Environment(\.theme) private var theme
    @AppStorage("terminalFontFamily") private var fontFamily: String = "MesloLGS Nerd Font"
    @AppStorage("terminalFontSize") private var fontSize: Double = 13

    public init(files: [DiffFile]) {
        self.files = files
        // Auto-expand all files for small diffs, none for large ones
        let initial = files.count <= 8 ? Set(files.map(\.path)) : Set<String>()
        self._expandedFiles = State(initialValue: initial)
    }

    /// Initialize from a raw unified diff string.
    public init(patch: String) {
        self.init(files: DiffFile.parse(patch: patch))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Summary header
                diffSummary

                // File list
                ForEach(files) { file in
                    fileSection(file)
                }
            }
        }
    }

    private var diffSummary: some View {
        HStack(spacing: 8) {
            Text("\(files.count) file\(files.count == 1 ? "" : "s")")
                .foregroundColor(theme.chrome.text)
            Text("+\(totalAdditions)")
                .foregroundColor(theme.chrome.green)
            Text("-\(totalDeletions)")
                .foregroundColor(theme.chrome.red)
        }
        .font(.callout)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.chrome.surface)
    }

    private var singleFile: Bool { files.count == 1 }

    private func fileSection(_ file: DiffFile) -> some View {
        let isExpanded = singleFile || expandedFiles.contains(file.path)

        return VStack(alignment: .leading, spacing: 0) {
            // File header — static when single file, toggleable when multiple
            if singleFile {
                fileHeader(file)
            } else {
                Button(action: { toggleFile(file.path) }) {
                    HStack(spacing: 6) {
                        Image(
                            systemName: isExpanded
                                ? "chevron.down" : "chevron.right"
                        )
                        .font(.caption2)
                        .foregroundColor(theme.chrome.textDim)

                        fileHeader(file)
                    }
                }
                .buttonStyle(.plain)
            }

            // Diff content
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(file.lines) { line in
                        diffLine(line)
                    }
                }
            }

            Divider()
        }
    }

    private func fileHeader(_ file: DiffFile) -> some View {
        HStack(spacing: 6) {
            Text(file.path)
                .font(.custom(fontFamily, size: fontSize - 1))
                .foregroundColor(theme.chrome.text)

            Spacer()

            HStack(spacing: 4) {
                Text("+\(file.additions)")
                    .foregroundColor(theme.chrome.green)
                Text("-\(file.deletions)")
                    .foregroundColor(theme.chrome.red)
            }
            .font(.custom(fontFamily, size: fontSize - 2))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(theme.chrome.surface.opacity(0.7))
    }

    private func diffLine(_ line: DiffLine) -> some View {
        HStack(spacing: 0) {
            // Line numbers
            HStack(spacing: 0) {
                Text(line.oldLineNo.map { String($0) } ?? "")
                    .frame(width: 40, alignment: .trailing)
                Text(line.newLineNo.map { String($0) } ?? "")
                    .frame(width: 40, alignment: .trailing)
            }
            .font(.custom(fontFamily, size: fontSize - 2))
            .foregroundColor(theme.chrome.comment)
            .padding(.trailing, 4)

            // Content
            Text(line.content)
                .font(.custom(fontFamily, size: fontSize))
                .foregroundColor(lineColor(line.type))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(lineBackground(line.type))
    }

    private func lineColor(_ type: DiffLineType) -> SwiftUI.Color {
        switch type {
        case .addition: theme.chrome.green
        case .deletion: theme.chrome.red
        case .context: theme.chrome.text
        case .hunk: theme.chrome.cyan
        }
    }

    private func lineBackground(_ type: DiffLineType) -> SwiftUI.Color {
        switch type {
        case .addition: theme.chrome.green.opacity(0.1)
        case .deletion: theme.chrome.red.opacity(0.1)
        case .context: .clear
        case .hunk: theme.chrome.surface.opacity(0.5)
        }
    }

    private func toggleFile(_ path: String) {
        if expandedFiles.contains(path) {
            expandedFiles.remove(path)
        } else {
            expandedFiles.insert(path)
        }
    }

    private var totalAdditions: Int { files.reduce(0) { $0 + $1.additions } }
    private var totalDeletions: Int { files.reduce(0) { $0 + $1.deletions } }
}

// MARK: - Diff Data Models

public struct DiffFile: Identifiable, Sendable {
    public let id: String
    public let path: String
    public let additions: Int
    public let deletions: Int
    public let lines: [DiffLine]

    /// Parse a unified diff string into structured file changes.
    public static func parse(patch: String) -> [DiffFile] {
        var files: [DiffFile] = []
        var currentPath: String?
        var currentLines: [DiffLine] = []
        var additions = 0
        var deletions = 0
        var oldLine = 0
        var newLine = 0
        var lineIndex = 0

        for rawLine in patch.components(separatedBy: "\n") {
            if rawLine.hasPrefix("diff --git") {
                // Save previous file
                if let path = currentPath {
                    files.append(
                        DiffFile(id: "file-\(files.count)", path: path, additions: additions, deletions: deletions, lines: currentLines))
                }
                currentLines = []
                additions = 0
                deletions = 0
                currentPath = nil
            } else if rawLine.hasPrefix("+++ b/") {
                currentPath = String(rawLine.dropFirst("+++ b/".count))
            } else if rawLine.hasPrefix("--- ") {
                continue  // skip old file header
            } else if rawLine.hasPrefix("@@") {
                // Parse hunk header: @@ -oldStart,count +newStart,count @@
                let parts = rawLine.components(separatedBy: " ")
                if parts.count >= 3 {
                    let newPart = parts[2]  // "+newStart,count" or "+newStart"
                    let nums = newPart.dropFirst().components(separatedBy: ",")
                    newLine = Int(nums[0]) ?? 0
                    let oldPart = parts[1]  // "-oldStart,count"
                    let oldNums = oldPart.dropFirst().components(separatedBy: ",")
                    oldLine = Int(oldNums[0]) ?? 0
                }
                currentLines.append(DiffLine(index: lineIndex, type: .hunk, content: rawLine, oldLineNo: nil, newLineNo: nil))
                lineIndex += 1
            } else if rawLine.hasPrefix("+") {
                additions += 1
                currentLines.append(
                    DiffLine(index: lineIndex, type: .addition, content: String(rawLine.dropFirst()), oldLineNo: nil, newLineNo: newLine))
                lineIndex += 1
                newLine += 1
            } else if rawLine.hasPrefix("-") {
                deletions += 1
                currentLines.append(
                    DiffLine(index: lineIndex, type: .deletion, content: String(rawLine.dropFirst()), oldLineNo: oldLine, newLineNo: nil))
                lineIndex += 1
                oldLine += 1
            } else if rawLine.hasPrefix(" ") {
                currentLines.append(
                    DiffLine(index: lineIndex, type: .context, content: String(rawLine.dropFirst()), oldLineNo: oldLine, newLineNo: newLine)
                )
                lineIndex += 1
                oldLine += 1
                newLine += 1
            } else if rawLine.isEmpty, currentPath != nil {
                // Empty line without leading space — blank context line
                currentLines.append(
                    DiffLine(index: lineIndex, type: .context, content: "", oldLineNo: oldLine, newLineNo: newLine))
                lineIndex += 1
                oldLine += 1
                newLine += 1
            }
        }

        // Save last file
        if let path = currentPath {
            files.append(DiffFile(id: "file-\(files.count)", path: path, additions: additions, deletions: deletions, lines: currentLines))
        }

        return files
    }
}

public struct DiffLine: Identifiable, Sendable {
    public let id: String
    public let type: DiffLineType
    public let content: String
    public let oldLineNo: Int?
    public let newLineNo: Int?

    public init(index: Int, type: DiffLineType, content: String, oldLineNo: Int?, newLineNo: Int?) {
        self.id = "line-\(index)"
        self.type = type
        self.content = content
        self.oldLineNo = oldLineNo
        self.newLineNo = newLineNo
    }
}

public enum DiffLineType: Sendable {
    case addition
    case deletion
    case context
    case hunk
}
