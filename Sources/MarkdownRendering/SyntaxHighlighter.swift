import Foundation
import JavaScriptCore

/// Loads highlight.js and runs syntax highlighting via JSContext,
/// avoiding HighlightSwift's Bundle.module which fatalErrors in packaged .app bundles.
///
/// SPM's generated resource accessor uses Bundle.main.bundleURL (the .app root)
/// where code signing prevents placing files. This actor loads highlight.min.js
/// from Bundle.main.resourceURL (Contents/Resources/) for packaged apps,
/// falling back to the SPM build location for development.
final actor SyntaxHighlighter {
    static let shared = SyntaxHighlighter()

    private var hljs: JSValue?

    private func load() throws -> JSValue {
        if let hljs { return hljs }

        guard let jsPath = findHighlightJS() else {
            throw SyntaxHighlighterError.jsFileNotFound
        }
        guard let context = JSContext() else {
            throw SyntaxHighlighterError.jsContextFailed
        }
        let script = try String(contentsOfFile: jsPath)
        context.evaluateScript(script)
        guard let hljs = context.objectForKeyedSubscript("hljs") else {
            throw SyntaxHighlighterError.hljsNotFound
        }
        self.hljs = hljs
        return hljs
    }

    /// Highlight code with a specific language.
    func highlight(_ text: String, language: String) throws -> HighlightJSResult {
        let hljs = try load()
        let options: [String: Any] = ["language": language]
        let result = hljs.invokeMethod("highlight", withArguments: [text, options])
        return try parseResult(result)
    }

    /// Highlight code with automatic language detection.
    func highlightAuto(_ text: String) throws -> HighlightJSResult {
        let hljs = try load()
        let result = hljs.invokeMethod("highlightAuto", withArguments: [text])
        return try parseResult(result)
    }

    /// Convert highlight.js HTML output to an AttributedString.
    func attributedText(html: String, css: String) throws -> AttributedString {
        let fullHTML =
            "<style>\n\(css)\n</style>\n<pre><code class=\"hljs\">\(html.trimmingCharacters(in: .whitespacesAndNewlines))</code></pre>"
        guard let data = fullHTML.data(using: .utf8) else {
            throw SyntaxHighlighterError.htmlConversionFailed
        }
        let mutable = try NSMutableAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        )
        // Remove the font so SwiftUI applies its own monospace font
        mutable.removeAttribute(.font, range: NSRange(location: 0, length: mutable.length))
        let range = NSRange(location: 0, length: max(mutable.length - 1, 0))
        let trimmed = mutable.attributedSubstring(from: range)
        return try AttributedString(trimmed, including: \.appKit)
    }

    // MARK: - Private

    private func parseResult(_ result: JSValue?) throws -> HighlightJSResult {
        guard let result else { throw SyntaxHighlighterError.hljsNotFound }
        guard let value = result.objectForKeyedSubscript("value").toString(),
            let language = result.objectForKeyedSubscript("language").toString()
        else {
            throw SyntaxHighlighterError.hljsNotFound
        }
        return HighlightJSResult(
            value: value,
            language: language,
            relevance: result.objectForKeyedSubscript("relevance").toInt32()
        )
    }

    /// Search for highlight.min.js in multiple locations:
    /// 1. Bundle.main.resourceURL — packaged .app (Contents/Resources/)
    /// 2. SPM resource bundle alongside executable — development (swift run)
    private func findHighlightJS() -> String? {
        // Packaged .app: Contents/Resources/highlight.min.js
        if let resourceURL = Bundle.main.resourceURL {
            let path = resourceURL.appendingPathComponent("highlight.min.js").path
            if FileManager.default.fileExists(atPath: path) { return path }
        }

        // Development: SPM resource bundle alongside executable
        let spmBundlePath = Bundle.main.bundleURL
            .appendingPathComponent("HighlightSwift_HighlightSwift.bundle")
            .appendingPathComponent("highlight.min.js").path
        if FileManager.default.fileExists(atPath: spmBundlePath) { return spmBundlePath }

        return nil
    }
}

struct HighlightJSResult: Sendable {
    let value: String
    let language: String
    let relevance: Int32
}

enum SyntaxHighlighterError: Error {
    case jsFileNotFound
    case jsContextFailed
    case hljsNotFound
    case htmlConversionFailed
}
