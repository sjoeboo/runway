import Foundation

/// Parsed destination from a runway:// URL.
enum DeepLinkDestination {
    case session(id: String)
    case pr(number: Int, repo: String)
    case newSession
}

/// Parses runway:// URLs into navigation destinations.
///
/// Supported routes:
/// - `runway://session/<id>` — navigate to a specific session
/// - `runway://pr/<number>/<owner/repo>` — navigate to a specific PR
/// - `runway://new-session` — open the new session dialog
enum DeepLinkRouter {
    static func parse(_ url: URL) -> DeepLinkDestination? {
        guard url.scheme == "runway" else { return nil }

        switch url.host {
        case "session":
            // runway://session/<id>
            guard let id = url.pathComponents.first(where: { $0 != "/" }), !id.isEmpty else {
                return nil
            }
            return .session(id: id)

        case "pr":
            // runway://pr/<number>/<owner/repo>
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count >= 2, let number = Int(parts[0]) else { return nil }
            let repo = parts.dropFirst().joined(separator: "/")
            return .pr(number: number, repo: repo)

        case "new-session":
            return .newSession

        default:
            return nil
        }
    }
}
