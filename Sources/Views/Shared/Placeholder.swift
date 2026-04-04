import SwiftUI
import Theme

/// Placeholder view shown when no session is selected.
public struct EmptyStateView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Environment(\.theme) private var theme

    public init(title: String, subtitle: String, systemImage: String = "terminal") {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundColor(theme.chrome.textDim)
            Text(title)
                .font(.title2)
                .foregroundColor(theme.chrome.text)
            Text(subtitle)
                .font(.body)
                .foregroundColor(theme.chrome.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.chrome.background)
    }
}
