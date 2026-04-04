import Models
import SwiftUI
import Theme

extension PullRequest {
    /// Color for the PR number badge, following GitHub's state conventions:
    /// open → green, draft → textDim, merged → purple, closed → red.
    public func numberColor(chrome: ChromePalette) -> Color {
        if isDraft { return chrome.textDim }
        switch state {
        case .open: return chrome.green
        case .draft: return chrome.textDim
        case .merged: return chrome.purple
        case .closed: return chrome.red
        }
    }
}
