# PR/Issue Markdown Rendering Design

## Summary

Replace the current `AttributedString(markdown:)` rendering in PR and issue detail views with a full GitHub-Flavored Markdown renderer built on `swift-markdown` (Apple's CommonMark parser) and `HighlightSwift` (syntax highlighting via JavaScriptCore). The renderer lives in a new `MarkdownRendering` SPM target and exposes a single `MarkdownView` SwiftUI component.

## Problem

The current `renderMarkdown()` function uses Apple's built-in `AttributedString` markdown support, which handles bold, italic, inline code, and links but fails on:
- Headings (no visual hierarchy)
- Fenced code blocks (rendered as inline text, no background or highlighting)
- Tables
- Task lists / checkboxes
- Blockquotes (no accent bar styling)
- Horizontal rules
- Proper paragraph/list spacing

The result is a wall of unstructured text for any PR or issue with structured markdown content.

## Approach

**swift-markdown + HighlightSwift**, rendered as native SwiftUI views.

- **swift-markdown** parses markdown into a typed AST with full GFM support (tables, task lists, strikethrough)
- **HighlightSwift** provides syntax highlighting for code blocks via highlight.js/JavaScriptCore — returns `AttributedString` directly, no WebView
- A custom `MarkupWalker` walks the AST and emits SwiftUI views
- All styling uses the app's `ChromePalette` via the existing theme system

### Why not alternatives?
- **WKWebView**: foreign to native UI, complicates theming, accessibility, and text selection
- **Enhanced AttributedString**: Apple's parser doesn't support tables, task lists, or code blocks — too limited
- **HighlighterSwift**: 185+ languages but returns `NSAttributedString` requiring bridging; 50 languages from HighlightSwift covers all realistic PR content

## Architecture

### New SPM Target: `MarkdownRendering`

**Dependencies:** `Theme`, `swift-markdown`, `HighlightSwift`

**Public API:**
```swift
// Full block-level rendering for PR/issue bodies
MarkdownView(source: body, theme: theme)

// Inline-only mode for comments/reviews
MarkdownView(source: comment.body, theme: theme, mode: .inline)
```

### Internal Structure

```
Sources/MarkdownRendering/
├── MarkdownView.swift          # Public SwiftUI view — the only public API
├── MarkdownRenderer.swift      # MarkupWalker that builds SwiftUI view tree
├── InlineRenderer.swift        # Builds concatenated Text for inline content
├── CodeBlockView.swift         # Code block with highlighting, copy, language label
├── TableView.swift             # Grid-based table rendering
└── MarkdownThemeBridge.swift   # Maps ChromePalette → highlight theme + font config
```

6 files. `MarkdownView` is the only public type — everything else is `internal`.

### Three Internal Layers

1. **Parser** — thin wrapper around `Document(parsing:)` with GFM extensions enabled
2. **Renderer** — `MarkdownRenderer` conforming to swift-markdown's `MarkupWalker`, walking the AST and emitting SwiftUI views
3. **Code Highlighter** — wraps HighlightSwift to produce themed `AttributedString` for fenced code blocks

## Rendering: AST Node → SwiftUI Mapping

| Markdown Element | SwiftUI Rendering |
|---|---|
| Heading (h1–h6) | `Text` with scaled font sizes (`.title` → `.callout`), `chrome.text` color |
| Paragraph | `Text` with concatenated inline children via `+` operator |
| Bold / Italic / Strikethrough | `Text` attributes (`.bold()`, `.italic()`, `.strikethrough()`) |
| Inline code | `Text` with monospace font, `chrome.surface` background via `AttributedString` |
| Link | `Text` with `chrome.accent` color + underline, wrapped in `Link` view |
| Image | `AsyncImage(url:)` with loading placeholder, constrained to max width |
| Code block | `CodeBlockView` — rounded rect, syntax highlighting, language label, copy button |
| Blockquote | `HStack` with 3px `chrome.accent` left bar + indented content, `chrome.textDim` color |
| Unordered list | `VStack` of `HStack(bullet + content)`, nested lists increase indent |
| Ordered list | Same with number labels |
| Task list | List items with `checkmark.square` / `square` SF Symbols, `chrome.accent` for checked |
| Table | `Grid` with `GridRow`s, header row gets `chrome.surface` bg + bold, `chrome.border` cell borders |
| Horizontal rule | `Divider` with `chrome.border` color |
| Line break / Soft break | `\n` in Text concatenation |

**Composition:** Block-level elements compose in a `VStack(alignment: .leading, spacing: 8)`. Inline content within a single block is built as a single `Text` using the `+` concatenation operator for natural text flow and wrapping.

## Code Block Detail

```
┌─ rounded rect (chrome.surface bg, chrome.border stroke) ─────┐
│                                                    "swift"    │
│  let query = SearchRequest()                                  │
│  query.field = "value"                                        │
│                                                         ⧉     │
└───────────────────────────────────────────────────────────────┘
```

- **Language label** — top-right, `chrome.textDim`, `.caption` font. From fenced block language hint. Hidden if unspecified.
- **Copy button** — bottom-right, appears on hover. Copies raw source to `NSPasteboard`.
- **Syntax highlighting** — HighlightSwift's `Highlight` class with language hint when available, auto-detection as fallback.
- **Theme mapping** — pick the closest built-in highlight.js theme to the current appearance (e.g., `atomOneDark` for dark), override background to `chrome.surface`.
- **Scrolling** — `ScrollView(.horizontal)` for long lines, no wrapping.
- **Font** — monospace at the user's configured terminal font size.
- **Async rendering** — plain monospace text rendered immediately, highlighted version swapped in once JavaScriptCore completes. No loading spinner.

## Styling: Theme-Native

All markdown rendering uses the app's `ChromePalette` colors:
- Headings: `chrome.text`
- Body text: `chrome.text`
- Inline code background: `chrome.surface`
- Code block background: `chrome.surface`, border: `chrome.border`
- Links: `chrome.accent`
- Blockquote bar: `chrome.accent`, text: `chrome.textDim`
- Table header bg: `chrome.surface`, borders: `chrome.border`
- Task list checkmarks: `chrome.accent`

This automatically adapts when users switch Runway themes.

## Integration Points

### Call Sites (6 total)

| Location | File | Current | Mode |
|---|---|---|---|
| PR body | `PRDetailDrawer.overviewTab` | `renderMarkdown(body)` | `.full` |
| Review body | `PRDetailDrawer.reviewCard` | `renderMarkdown(review.body, inlineOnly: true)` | `.inline` |
| PR comment | `PRDetailDrawer.commentCard` | `renderMarkdown(comment.body, inlineOnly: true)` | `.inline` |
| Inline code comment | `PRDetailDrawer.inlineCommentCard` | `Text(comment.body)` (plain, upgrade) | `.inline` |
| Issue body | `IssueDetailDrawer.overviewTab` | `renderMarkdown(body)` | `.full` |
| Issue comment | `IssueDetailDrawer.commentCard` | `renderMarkdown(comment.body, inlineOnly: true)` | `.inline` |

### Migration

**Before:**
```swift
renderMarkdown(body)
    .font(.body)
    .foregroundColor(theme.chrome.text)
    .textSelection(.enabled)
```

**After:**
```swift
MarkdownView(source: body, theme: theme)
    .textSelection(.enabled)
```

The two private `renderMarkdown()` functions in `PRDetailDrawer` and `IssueDetailDrawer` are deleted entirely.

### Package.swift Changes

- Add `swift-markdown` and `HighlightSwift` to top-level `dependencies`
- Add `MarkdownRendering` target depending on `Theme`, `swift-markdown`, `HighlightSwift`
- Add `MarkdownRendering` to `Views` target dependencies
- Add `MarkdownRenderingTests` test target

## Testing

| Test file | Coverage |
|---|---|
| `MarkdownRendererTests.swift` | Parse sample markdown, verify correct node types identified and view structure produced |
| `InlineRendererTests.swift` | Verify bold, italic, code, link, strikethrough, and nested inline concatenation |
| `TableViewTests.swift` | Parse GFM tables, verify row/column counts and header detection |
| `MarkdownThemeBridgeTests.swift` | Verify ChromePalette maps to expected highlight theme for dark/light appearances |

Testing strategy: verify the renderer correctly identifies node types, produces expected `AttributedString` output for inline content, parses correct table dimensions, and selects appropriate highlight themes.

## Scope

### In v1
- Headings (h1–h6) with proper sizing
- Paragraphs with proper spacing
- Bold, italic, strikethrough
- Inline code with highlight
- Fenced code blocks with syntax highlighting (50+ languages, auto-detection)
- Unordered and ordered lists (including nested)
- Task lists with checkboxes (read-only)
- Links (clickable)
- Blockquotes with accent bar
- Tables with header styling
- Horizontal rules
- Images (inline from URLs)
- Copy button on code blocks

### Not in v1
- Nested blockquotes (single level only)
- Editable task list checkboxes
- Mermaid/diagram rendering
- Emoji shortcodes (`:rocket:` etc.)
- GitHub @mention linking
- Issue/PR reference linking (`#123`)
