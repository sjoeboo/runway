# PR/Issue Markdown Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the limited `AttributedString(markdown:)` renderer with a full GFM-capable markdown renderer using `swift-markdown` and `HighlightSwift`, exposed as a `MarkdownView` SwiftUI component in a new `MarkdownRendering` SPM target.

**Architecture:** Parse markdown into an AST with `swift-markdown`, walk the tree with a `MarkupVisitor` to emit SwiftUI views. Block-level elements compose in a `VStack`, inline content builds `AttributedString` segments concatenated into `Text`. Code blocks use `HighlightSwift` for async syntax highlighting via JavaScriptCore. All styling derives from the app's `ChromePalette` via `@Environment(\.theme)`.

**Tech Stack:** swift-markdown (AST parser), HighlightSwift (syntax highlighting), SwiftUI, Swift 6 strict concurrency

**Spec:** `docs/superpowers/specs/2026-04-08-pr-markdown-rendering-design.md`

---

### File Structure

**New files to create:**
```
Sources/MarkdownRendering/
├── MarkdownView.swift          # Public SwiftUI view — sole public API
├── MarkdownRenderer.swift      # Block-level rendering: headings, lists, blockquotes, images
├── InlineRenderer.swift        # MarkupVisitor<AttributedString> for inline text
├── CodeBlockView.swift         # Syntax-highlighted code block with copy/language label
├── TableView.swift             # Grid-based GFM table rendering
└── MarkdownThemeBridge.swift   # ChromePalette → HighlightSwift theme mapping

Tests/MarkdownRenderingTests/
├── InlineRendererTests.swift       # Inline formatting: bold, italic, code, links, nesting
└── MarkdownThemeBridgeTests.swift  # Theme mapping verification
```

**Files to modify:**
- `Package.swift` — add dependencies + targets
- `Sources/Views/PRDashboard/PRDetailDrawer.swift` — replace `renderMarkdown()` calls
- `Sources/Views/ProjectPage/IssueDetailDrawer.swift` — replace `renderMarkdown()` calls

---

### Task 1: Add Dependencies and Create Target Skeleton

**Files:**
- Modify: `Package.swift`
- Create: `Sources/MarkdownRendering/MarkdownView.swift`
- Create: `Tests/MarkdownRenderingTests/InlineRendererTests.swift`

- [ ] **Step 1: Add swift-markdown and HighlightSwift to Package.swift dependencies**

In `Package.swift`, add to the `dependencies` array:

```swift
.package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.4.0"),
.package(url: "https://github.com/appstefan/highlightswift.git", from: "1.1.0"),
```

- [ ] **Step 2: Add MarkdownRendering target**

In `Package.swift`, add after the Theme target:

```swift
// MARK: - Markdown Rendering
.target(
    name: "MarkdownRendering",
    dependencies: [
        "Theme",
        .product(name: "Markdown", package: "swift-markdown"),
        .product(name: "HighlightSwift", package: "highlightswift"),
    ],
    path: "Sources/MarkdownRendering"
),
```

- [ ] **Step 3: Add MarkdownRendering to Views target dependencies**

In `Package.swift`, add `"MarkdownRendering"` to the Views target's dependencies array:

```swift
.target(
    name: "Views",
    dependencies: [
        "Models",
        "Persistence",
        "Terminal",
        "TerminalView",
        "GitOperations",
        "GitHubOperations",
        "StatusDetection",
        "Theme",
        "MarkdownRendering",
        .product(name: "Sparkle", package: "Sparkle"),
    ],
    path: "Sources/Views"
),
```

- [ ] **Step 4: Add MarkdownRenderingTests target**

In `Package.swift`, add after the existing test targets:

```swift
.testTarget(
    name: "MarkdownRenderingTests",
    dependencies: [
        "MarkdownRendering",
        "Theme",
        .product(name: "Markdown", package: "swift-markdown"),
    ],
    path: "Tests/MarkdownRenderingTests"
),
```

- [ ] **Step 5: Create placeholder MarkdownView.swift**

Create `Sources/MarkdownRendering/MarkdownView.swift`:

```swift
import SwiftUI
import Theme

/// Rendering mode for markdown content.
public enum MarkdownRenderMode {
    /// Full block-level rendering: headings, code blocks, tables, lists, etc.
    case full
    /// Inline-only rendering: bold, italic, code, links within flowing text.
    case inline
}

/// Renders a markdown string as native SwiftUI views using the app's theme.
public struct MarkdownView: View {
    let source: String
    let theme: AppTheme
    let mode: MarkdownRenderMode

    public init(source: String, theme: AppTheme, mode: MarkdownRenderMode = .full) {
        self.source = source
        self.theme = theme
        self.mode = mode
    }

    public var body: some View {
        // Placeholder — will be implemented in Task 7
        Text(source)
    }
}
```

- [ ] **Step 6: Create placeholder test file**

Create `Tests/MarkdownRenderingTests/InlineRendererTests.swift`:

```swift
import XCTest
@testable import MarkdownRendering
import Theme

final class InlineRendererTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 7: Build to verify dependency resolution and compilation**

Run: `swift build 2>&1 | tail -5`

Expected: Build succeeds. Both new packages resolve and the MarkdownRendering target compiles.

- [ ] **Step 8: Run tests to verify test target links**

Run: `swift test --filter MarkdownRenderingTests 2>&1 | tail -5`

Expected: 1 test passes.

- [ ] **Step 9: Commit**

```bash
git add Package.swift Sources/MarkdownRendering/ Tests/MarkdownRenderingTests/
git commit -m "feat: add MarkdownRendering target with swift-markdown and HighlightSwift deps"
```

---

### Task 2: Implement MarkdownThemeBridge

**Files:**
- Create: `Sources/MarkdownRendering/MarkdownThemeBridge.swift`
- Create: `Tests/MarkdownRenderingTests/MarkdownThemeBridgeTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/MarkdownRenderingTests/MarkdownThemeBridgeTests.swift`:

```swift
import XCTest
@testable import MarkdownRendering
import Theme
import HighlightSwift

final class MarkdownThemeBridgeTests: XCTestCase {
    func testDarkThemeUsesTokyoNight() {
        let bridge = MarkdownThemeBridge(theme: .tokyoNightStorm)
        XCTAssertEqual(bridge.highlightColors, .dark(.tokyoNight))
    }

    func testCodeTextColorsUseTokyoNightDarkAndGithubLight() {
        let bridge = MarkdownThemeBridge(theme: .tokyoNightStorm)
        let colors = bridge.codeTextColors
        let expected = CodeTextColors.custom(
            dark: .dark(.tokyoNight),
            light: .light(.github)
        )
        XCTAssertEqual(colors, expected)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MarkdownThemeBridgeTests 2>&1 | tail -10`

Expected: FAIL — `MarkdownThemeBridge` does not exist.

- [ ] **Step 3: Implement MarkdownThemeBridge**

Create `Sources/MarkdownRendering/MarkdownThemeBridge.swift`:

```swift
import HighlightSwift
import SwiftUI
import Theme

/// Maps the app's ChromePalette to HighlightSwift theme settings.
struct MarkdownThemeBridge {
    let theme: AppTheme

    /// Highlight colors for the current appearance (dark or light).
    var highlightColors: HighlightColors {
        switch theme.appearance {
        case .dark:
            .dark(.tokyoNight)
        case .light:
            .light(.github)
        @unknown default:
            .dark(.tokyoNight)
        }
    }

    /// Colors for CodeText that adapt to dark/light automatically.
    var codeTextColors: CodeTextColors {
        .custom(
            dark: .dark(.tokyoNight),
            light: .light(.github)
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MarkdownThemeBridgeTests 2>&1 | tail -10`

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MarkdownRendering/MarkdownThemeBridge.swift Tests/MarkdownRenderingTests/MarkdownThemeBridgeTests.swift
git commit -m "feat: add MarkdownThemeBridge mapping ChromePalette to HighlightSwift themes"
```

---

### Task 3: Implement InlineRenderer

**Files:**
- Create: `Sources/MarkdownRendering/InlineRenderer.swift`
- Modify: `Tests/MarkdownRenderingTests/InlineRendererTests.swift`

- [ ] **Step 1: Write failing tests for core inline formatting**

Replace the contents of `Tests/MarkdownRenderingTests/InlineRendererTests.swift`:

```swift
import XCTest
@testable import MarkdownRendering
import Markdown
import Theme

final class InlineRendererTests: XCTestCase {
    let theme = AppTheme.tokyoNightStorm

    // MARK: - Helper

    private func renderInline(_ markdown: String) -> AttributedString {
        let document = Document(parsing: markdown)
        guard let paragraph = document.children.first(where: { $0 is Paragraph }) else {
            return AttributedString()
        }
        var renderer = InlineRenderer(theme: theme)
        return renderer.visit(paragraph)
    }

    // MARK: - Plain Text

    func testPlainText() {
        let result = renderInline("Hello world")
        XCTAssertEqual(String(result.characters), "Hello world")
    }

    // MARK: - Bold

    func testBoldText() {
        let result = renderInline("Hello **world**")
        let runs = Array(result.runs)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(String(result.characters[runs[0].range]), "Hello ")
        XCTAssertNil(runs[0].inlinePresentationIntent)
        XCTAssertEqual(String(result.characters[runs[1].range]), "world")
        XCTAssertTrue(runs[1].inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false)
    }

    // MARK: - Italic

    func testItalicText() {
        let result = renderInline("Hello *world*")
        let runs = Array(result.runs)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(String(result.characters[runs[1].range]), "world")
        XCTAssertTrue(runs[1].inlinePresentationIntent?.contains(.emphasized) ?? false)
    }

    // MARK: - Bold + Italic Nested

    func testBoldItalicNested() {
        let result = renderInline("***both***")
        let runs = Array(result.runs)
        XCTAssertEqual(runs.count, 1)
        let intent = runs[0].inlinePresentationIntent ?? []
        XCTAssertTrue(intent.contains(.stronglyEmphasized))
        XCTAssertTrue(intent.contains(.emphasized))
    }

    // MARK: - Strikethrough

    func testStrikethrough() {
        let result = renderInline("~~removed~~")
        let runs = Array(result.runs)
        XCTAssertEqual(runs.count, 1)
        XCTAssertTrue(runs[0].inlinePresentationIntent?.contains(.strikethrough) ?? false)
    }

    // MARK: - Inline Code

    func testInlineCode() {
        let result = renderInline("Use `field_required` here")
        let runs = Array(result.runs)
        // "Use " + "field_required" (code) + " here"
        XCTAssertEqual(runs.count, 3)
        XCTAssertEqual(String(result.characters[runs[1].range]), "field_required")
        XCTAssertTrue(runs[1].inlinePresentationIntent?.contains(.code) ?? false)
    }

    // MARK: - Link

    func testLink() {
        let result = renderInline("See [docs](https://example.com)")
        let runs = Array(result.runs)
        // "See " + "docs" (link)
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(String(result.characters[runs[1].range]), "docs")
        XCTAssertEqual(runs[1].link, URL(string: "https://example.com"))
    }

    // MARK: - Soft Break

    func testSoftBreakRendersAsSpace() {
        // A soft break in markdown (single newline) should render as a space
        let result = renderInline("line one\nline two")
        XCTAssertTrue(String(result.characters).contains(" "))
    }

    // MARK: - Mixed Content

    func testMixedInlineContent() {
        let result = renderInline("Hello **bold** and *italic* with `code`")
        let text = String(result.characters)
        XCTAssertEqual(text, "Hello bold and italic with code")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter InlineRendererTests 2>&1 | tail -10`

Expected: FAIL — `InlineRenderer` does not exist.

- [ ] **Step 3: Implement InlineRenderer**

Create `Sources/MarkdownRendering/InlineRenderer.swift`:

```swift
import Foundation
import Markdown
import SwiftUI
import Theme

/// Walks inline markdown nodes and produces a styled AttributedString.
///
/// Uses `inlinePresentationIntent` for bold/italic/strikethrough/code,
/// which SwiftUI's `Text(AttributedString)` renders natively.
struct InlineRenderer: MarkupVisitor {
    typealias Result = AttributedString

    let theme: AppTheme

    /// Tracks nested inline intents (bold inside italic, etc.)
    private var currentIntent: InlinePresentationIntent = []

    init(theme: AppTheme) {
        self.theme = theme
    }

    // MARK: - Default

    mutating func defaultVisit(_ markup: any Markup) -> AttributedString {
        var result = AttributedString()
        for child in markup.children {
            result += visit(child)
        }
        return result
    }

    // MARK: - Text

    mutating func visitText(_ text: Markdown.Text) -> AttributedString {
        var attr = AttributedString(text.string)
        if !currentIntent.isEmpty {
            attr.inlinePresentationIntent = currentIntent
        }
        return attr
    }

    // MARK: - Emphasis (italic)

    mutating func visitEmphasis(_ emphasis: Emphasis) -> AttributedString {
        currentIntent.insert(.emphasized)
        let result = defaultVisit(emphasis)
        currentIntent.remove(.emphasized)
        return result
    }

    // MARK: - Strong (bold)

    mutating func visitStrong(_ strong: Strong) -> AttributedString {
        currentIntent.insert(.stronglyEmphasized)
        let result = defaultVisit(strong)
        currentIntent.remove(.stronglyEmphasized)
        return result
    }

    // MARK: - Strikethrough

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> AttributedString {
        currentIntent.insert(.strikethrough)
        let result = defaultVisit(strikethrough)
        currentIntent.remove(.strikethrough)
        return result
    }

    // MARK: - Inline Code

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> AttributedString {
        var attr = AttributedString(inlineCode.code)
        var intent = currentIntent
        intent.insert(.code)
        attr.inlinePresentationIntent = intent
        attr.font = .system(.body, design: .monospaced)
        attr.backgroundColor = theme.chrome.surface
        return attr
    }

    // MARK: - Link

    mutating func visitLink(_ link: Link) -> AttributedString {
        var attr = defaultVisit(link)
        if let destination = link.destination, let url = URL(string: destination) {
            attr.link = url
        }
        attr.foregroundColor = theme.chrome.accent
        attr.underlineStyle = .single
        return attr
    }

    // MARK: - Image (inline: render alt text)

    mutating func visitImage(_ image: Image) -> AttributedString {
        // At inline level, render alt text. Block-level handles AsyncImage.
        let altText = image.plainText
        if altText.isEmpty {
            return AttributedString("[image]")
        }
        var attr = AttributedString(altText)
        attr.foregroundColor = theme.chrome.textDim
        return attr
    }

    // MARK: - Breaks

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> AttributedString {
        AttributedString(" ")
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> AttributedString {
        AttributedString("\n")
    }

    // MARK: - HTML (render as plain text)

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> AttributedString {
        AttributedString(inlineHTML.rawHTML)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter InlineRendererTests 2>&1 | tail -15`

Expected: All 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MarkdownRendering/InlineRenderer.swift Tests/MarkdownRenderingTests/InlineRendererTests.swift
git commit -m "feat: add InlineRenderer for bold, italic, code, links, strikethrough"
```

---

### Task 4: Implement CodeBlockView

**Files:**
- Create: `Sources/MarkdownRendering/CodeBlockView.swift`

- [ ] **Step 1: Create CodeBlockView with plain text and async highlighting**

Create `Sources/MarkdownRendering/CodeBlockView.swift`:

```swift
import HighlightSwift
import SwiftUI
import Theme

/// Renders a fenced code block with syntax highlighting, language label, and copy button.
struct CodeBlockView: View {
    let code: String
    let language: String?
    let theme: AppTheme

    @State private var highlighted: AttributedString?
    @State private var isHovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language label bar (only if language specified)
            if let language, !language.isEmpty {
                HStack {
                    Spacer()
                    Text(language)
                        .font(.caption2)
                        .foregroundColor(theme.chrome.textDim)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
            }

            // Code content with horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                SwiftUI.Text(highlighted ?? plainAttributed)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.chrome.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.chrome.border, lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if isHovering {
                copyButton
                    .padding(6)
            }
        }
        .onHover { isHovering = $0 }
        .task(id: code) {
            await highlightCode()
        }
    }

    /// Plain monospace AttributedString shown before highlighting completes.
    private var plainAttributed: AttributedString {
        var attr = AttributedString(code)
        attr.foregroundColor = theme.chrome.text
        return attr
    }

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundColor(theme.chrome.textDim)
                .padding(4)
                .background(theme.chrome.surface.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private func highlightCode() async {
        let themeBridge = MarkdownThemeBridge(theme: theme)
        let highlight = Highlight()
        do {
            if let language, !language.isEmpty {
                highlighted = try await highlight.attributedText(
                    code, language: language, colors: themeBridge.highlightColors
                )
            } else {
                highlighted = try await highlight.attributedText(
                    code, colors: themeBridge.highlightColors
                )
            }
        } catch {
            // Keep plain text on failure — no crash, no spinner
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -5`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/MarkdownRendering/CodeBlockView.swift
git commit -m "feat: add CodeBlockView with async syntax highlighting and copy button"
```

---

### Task 5: Implement TableView

**Files:**
- Create: `Sources/MarkdownRendering/TableView.swift`

- [ ] **Step 1: Create TableView with Grid layout**

Create `Sources/MarkdownRendering/TableView.swift`:

```swift
import Markdown
import SwiftUI
import Theme

/// Renders a GFM table as a native SwiftUI Grid.
struct TableView: View {
    let table: Markdown.Table
    let theme: AppTheme

    var body: some View {
        let alignments = table.columnAlignments
        let headerCells = extractCells(from: table.head)
        let bodyRows = extractBodyRows()

        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            // Header row
            GridRow {
                ForEach(Array(headerCells.enumerated()), id: \.offset) { index, cell in
                    cellView(cell, isHeader: true, alignment: columnAlignment(alignments, index))
                }
            }

            // Separator
            Divider()
                .background(theme.chrome.border)

            // Body rows
            ForEach(Array(bodyRows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                        cellView(cell, isHeader: false, alignment: columnAlignment(alignments, index))
                    }
                }
                Divider()
                    .background(theme.chrome.border)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.chrome.border, lineWidth: 1)
        )
    }

    // MARK: - Cell Rendering

    @ViewBuilder
    private func cellView(
        _ cell: Markdown.Table.Cell,
        isHeader: Bool,
        alignment: Alignment
    ) -> some View {
        let attributed = renderCellContent(cell)
        SwiftUI.Text(attributed)
            .font(isHeader ? .callout.bold() : .callout)
            .foregroundColor(theme.chrome.text)
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHeader ? theme.chrome.surface : Color.clear)
    }

    // MARK: - Helpers

    private func renderCellContent(_ cell: Markdown.Table.Cell) -> AttributedString {
        var renderer = InlineRenderer(theme: theme)
        return renderer.visit(cell)
    }

    private func extractCells(from head: Markdown.Table.Head) -> [Markdown.Table.Cell] {
        head.children.compactMap { $0 as? Markdown.Table.Cell }
    }

    private func extractBodyRows() -> [[Markdown.Table.Cell]] {
        table.body.children.compactMap { $0 as? Markdown.Table.Row }.map { row in
            row.children.compactMap { $0 as? Markdown.Table.Cell }
        }
    }

    private func columnAlignment(
        _ alignments: [Markdown.Table.ColumnAlignment?], _ index: Int
    ) -> Alignment {
        guard index < alignments.count, let align = alignments[index] else {
            return .leading
        }
        switch align {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -5`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/MarkdownRendering/TableView.swift
git commit -m "feat: add TableView with Grid layout, header styling, and column alignment"
```

---

### Task 6: Implement MarkdownRenderer (Block-Level)

**Files:**
- Create: `Sources/MarkdownRendering/MarkdownRenderer.swift`

- [ ] **Step 1: Create MarkdownRenderer with all block-level elements**

Create `Sources/MarkdownRendering/MarkdownRenderer.swift`:

```swift
import Markdown
import SwiftUI
import Theme

/// Walks a parsed markdown Document and renders block-level elements as SwiftUI views.
struct MarkdownRenderer {
    let theme: AppTheme

    // MARK: - Document

    @ViewBuilder
    func render(_ document: Document) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(document.children.enumerated()), id: \.offset) { _, child in
                renderBlock(child)
            }
        }
    }

    // MARK: - Block Dispatch

    @ViewBuilder
    func renderBlock(_ markup: any Markup) -> some View {
        if let heading = markup as? Heading {
            renderHeading(heading)
        } else if let paragraph = markup as? Paragraph {
            renderParagraph(paragraph)
        } else if let codeBlock = markup as? CodeBlock {
            CodeBlockView(
                code: codeBlock.code.trimmingCharacters(in: .newlines),
                language: codeBlock.language,
                theme: theme
            )
        } else if let blockQuote = markup as? BlockQuote {
            renderBlockQuote(blockQuote)
        } else if let orderedList = markup as? OrderedList {
            renderOrderedList(orderedList)
        } else if let unorderedList = markup as? UnorderedList {
            renderUnorderedList(unorderedList)
        } else if let table = markup as? Markdown.Table {
            TableView(table: table, theme: theme)
        } else if markup is ThematicBreak {
            Divider()
                .background(theme.chrome.border)
                .padding(.vertical, 4)
        } else if let htmlBlock = markup as? HTMLBlock {
            SwiftUI.Text(htmlBlock.rawHTML)
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(theme.chrome.textDim)
        } else {
            // Fallback: recurse into children
            ForEach(Array(markup.children.enumerated()), id: \.offset) { _, child in
                renderBlock(child)
            }
        }
    }

    // MARK: - Heading

    @ViewBuilder
    private func renderHeading(_ heading: Heading) -> some View {
        SwiftUI.Text(renderInline(heading))
            .font(headingFont(heading.level))
            .foregroundColor(theme.chrome.text)
            .fontWeight(.semibold)
            .padding(.top, heading.level <= 2 ? 4 : 2)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title
        case 2: .title2
        case 3: .title3
        case 4: .headline
        case 5: .subheadline
        default: .callout
        }
    }

    // MARK: - Paragraph

    @ViewBuilder
    private func renderParagraph(_ paragraph: Paragraph) -> some View {
        // Check for standalone image
        if paragraph.childCount == 1, let image = paragraph.children.first as? Markdown.Image {
            renderImage(image)
        } else {
            SwiftUI.Text(renderInline(paragraph))
                .font(.body)
                .foregroundColor(theme.chrome.text)
        }
    }

    // MARK: - Image

    @ViewBuilder
    private func renderImage(_ image: Markdown.Image) -> some View {
        if let source = image.source, let url = URL(string: source) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 600)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                case .failure:
                    SwiftUI.Text(image.plainText.isEmpty ? "[image]" : image.plainText)
                        .foregroundColor(theme.chrome.textDim)
                        .italic()
                default:
                    ProgressView()
                        .frame(height: 100)
                }
            }
        } else {
            SwiftUI.Text(image.plainText.isEmpty ? "[image]" : image.plainText)
                .foregroundColor(theme.chrome.textDim)
                .italic()
        }
    }

    // MARK: - Block Quote

    @ViewBuilder
    private func renderBlockQuote(_ blockQuote: BlockQuote) -> some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1)
                .fill(theme.chrome.accent)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(blockQuote.children.enumerated()), id: \.offset) { _, child in
                    renderBlock(child)
                }
            }
            .padding(.leading, 12)
        }
        .foregroundColor(theme.chrome.textDim)
    }

    // MARK: - Ordered List

    @ViewBuilder
    private func renderOrderedList(_ list: OrderedList) -> some View {
        let startIndex = Int(list.startIndex)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(list.children.enumerated()), id: \.offset) { index, child in
                if let item = child as? ListItem {
                    renderListItem(item, bullet: "\(startIndex + index).")
                }
            }
        }
    }

    // MARK: - Unordered List

    @ViewBuilder
    private func renderUnorderedList(_ list: UnorderedList) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(list.children.enumerated()), id: \.offset) { _, child in
                if let item = child as? ListItem {
                    renderListItem(item, bullet: nil)
                }
            }
        }
    }

    // MARK: - List Item

    @ViewBuilder
    private func renderListItem(_ item: ListItem, bullet: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // Checkbox, number, or bullet
            if let checkbox = item.checkbox {
                SwiftUI.Image(
                    systemName: checkbox == .checked
                        ? "checkmark.square.fill" : "square"
                )
                .font(.callout)
                .foregroundColor(
                    checkbox == .checked ? theme.chrome.accent : theme.chrome.textDim
                )
            } else if let bullet {
                SwiftUI.Text(bullet)
                    .font(.callout)
                    .foregroundColor(theme.chrome.textDim)
                    .frame(minWidth: 16, alignment: .trailing)
            } else {
                SwiftUI.Text("\u{2022}")
                    .font(.callout)
                    .foregroundColor(theme.chrome.textDim)
            }

            // Item content
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                    renderBlock(child)
                }
            }
        }
        .padding(.leading, 4)
    }

    // MARK: - Inline Helper

    private func renderInline(_ markup: any Markup) -> AttributedString {
        var renderer = InlineRenderer(theme: theme)
        return renderer.visit(markup)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -5`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/MarkdownRendering/MarkdownRenderer.swift
git commit -m "feat: add MarkdownRenderer with headings, lists, blockquotes, images, tables"
```

---

### Task 7: Wire Up MarkdownView (Public API)

**Files:**
- Modify: `Sources/MarkdownRendering/MarkdownView.swift`

- [ ] **Step 1: Implement MarkdownView with full and inline modes**

Replace the body of `MarkdownView` in `Sources/MarkdownRendering/MarkdownView.swift`:

```swift
import Markdown
import SwiftUI
import Theme

/// Rendering mode for markdown content.
public enum MarkdownRenderMode: Sendable {
    /// Full block-level rendering: headings, code blocks, tables, lists, etc.
    case full
    /// Inline-only rendering: bold, italic, code, links within flowing text.
    case inline
}

/// Renders a markdown string as native SwiftUI views using the app's theme.
public struct MarkdownView: View {
    let source: String
    let theme: AppTheme
    let mode: MarkdownRenderMode

    public init(source: String, theme: AppTheme, mode: MarkdownRenderMode = .full) {
        self.source = source
        self.theme = theme
        self.mode = mode
    }

    public var body: some View {
        let document = Document(parsing: source)
        switch mode {
        case .full:
            MarkdownRenderer(theme: theme).render(document)
        case .inline:
            inlineView(document)
        }
    }

    /// Inline mode: render all content as flowing text with inline formatting only.
    @ViewBuilder
    private func inlineView(_ document: Document) -> some View {
        let attributed = renderDocumentInline(document)
        Text(attributed)
            .font(.body)
            .foregroundColor(theme.chrome.text)
    }

    /// Walk all top-level children and concatenate their inline content.
    private func renderDocumentInline(_ document: Document) -> AttributedString {
        var renderer = InlineRenderer(theme: theme)
        var result = AttributedString()
        var first = true
        for child in document.children {
            if !first {
                result += AttributedString("\n")
            }
            result += renderer.visit(child)
            first = false
        }
        return result
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -5`

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/MarkdownRendering/MarkdownView.swift
git commit -m "feat: wire up MarkdownView public API with full and inline modes"
```

---

### Task 8: Integrate into PRDetailDrawer and IssueDetailDrawer

**Files:**
- Modify: `Sources/Views/PRDashboard/PRDetailDrawer.swift`
- Modify: `Sources/Views/ProjectPage/IssueDetailDrawer.swift`

- [ ] **Step 1: Add import to PRDetailDrawer**

At the top of `Sources/Views/PRDashboard/PRDetailDrawer.swift`, add:

```swift
import MarkdownRendering
```

- [ ] **Step 2: Replace renderMarkdown calls in PRDetailDrawer**

In `PRDetailDrawer.overviewTab` (around line 433–437), replace:

```swift
                    renderMarkdown(body)
                        .font(.body)
                        .foregroundColor(theme.chrome.text)
                        .textSelection(.enabled)
```

with:

```swift
                    MarkdownView(source: body, theme: theme)
                        .textSelection(.enabled)
```

In `PRDetailDrawer.reviewCard` (around line 733), replace:

```swift
                    renderMarkdown(review.body, inlineOnly: true)
                        .font(.body)
                        .foregroundColor(theme.chrome.text)
```

with:

```swift
                    MarkdownView(source: review.body, theme: theme, mode: .inline)
```

In `PRDetailDrawer.commentCard` (around line 765), replace:

```swift
            renderMarkdown(comment.body, inlineOnly: true)
                .font(.body)
                .foregroundColor(theme.chrome.text)
                .textSelection(.enabled)
```

with:

```swift
            MarkdownView(source: comment.body, theme: theme, mode: .inline)
                .textSelection(.enabled)
```

In `PRDetailDrawer.inlineCommentCard` (around line 793), replace:

```swift
            Text(comment.body)
                .font(.caption)
                .foregroundColor(theme.chrome.textDim)
                .textSelection(.enabled)
```

with:

```swift
            MarkdownView(source: comment.body, theme: theme, mode: .inline)
                .font(.caption)
                .textSelection(.enabled)
```

- [ ] **Step 3: Delete the old renderMarkdown and stripHTML functions from PRDetailDrawer**

Delete lines 848–870 (the `renderMarkdown` function and the `stripHTML` function) from `Sources/Views/PRDashboard/PRDetailDrawer.swift`.

- [ ] **Step 4: Add import to IssueDetailDrawer**

At the top of `Sources/Views/ProjectPage/IssueDetailDrawer.swift`, add:

```swift
import MarkdownRendering
```

- [ ] **Step 5: Replace renderMarkdown calls in IssueDetailDrawer**

In `IssueDetailDrawer.overviewTab` (around line 278–282), replace:

```swift
                    renderMarkdown(body)
                        .font(.body)
                        .foregroundColor(theme.chrome.text)
                        .textSelection(.enabled)
```

with:

```swift
                    MarkdownView(source: body, theme: theme)
                        .textSelection(.enabled)
```

In `IssueDetailDrawer.commentCard` (around line 384), replace:

```swift
                renderMarkdown(comment.body, inlineOnly: true)
                    .font(.body)
                    .foregroundColor(theme.chrome.text)
                    .textSelection(.enabled)
```

with:

```swift
                MarkdownView(source: comment.body, theme: theme, mode: .inline)
                    .textSelection(.enabled)
```

- [ ] **Step 6: Delete the old renderMarkdown function from IssueDetailDrawer**

Delete lines 507–516 (the `renderMarkdown` function) from `Sources/Views/ProjectPage/IssueDetailDrawer.swift`.

- [ ] **Step 7: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`

Expected: Build succeeds with no errors. All references to the deleted `renderMarkdown` functions are replaced.

- [ ] **Step 8: Commit**

```bash
git add Sources/Views/PRDashboard/PRDetailDrawer.swift Sources/Views/ProjectPage/IssueDetailDrawer.swift
git commit -m "feat: replace renderMarkdown with MarkdownView in PR and issue detail views"
```

---

### Task 9: Final Build and Test Verification

**Files:** None (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `swift test 2>&1 | tail -20`

Expected: All tests pass, including the new MarkdownRenderingTests.

- [ ] **Step 2: Run a clean build**

Run: `swift build 2>&1 | tail -5`

Expected: Build succeeds with no warnings related to MarkdownRendering.

- [ ] **Step 3: Verify no stale references to old renderMarkdown**

Run: `grep -r "renderMarkdown" Sources/`

Expected: No results. All old call sites are replaced.

- [ ] **Step 4: Commit any test fixes if needed, then tag completion**

If any tests needed fixes:
```bash
git add -A
git commit -m "fix: resolve test issues from markdown rendering integration"
```
