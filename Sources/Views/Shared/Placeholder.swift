import SwiftUI
import Theme

/// Placeholder view shown when no session is selected.
public struct EmptyStateView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var actionTitle: String?
    var onAction: (() -> Void)?
    @Environment(\.theme) private var theme

    public init(
        title: String,
        subtitle: String,
        systemImage: String = "terminal",
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.onAction = onAction
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundColor(theme.chrome.textDim)
            Text(title)
                .font(.title2)
                .foregroundColor(theme.chrome.text)
            Text(subtitle)
                .font(.body)
                .foregroundColor(theme.chrome.textDim)
                .multilineTextAlignment(.center)
            if let actionTitle, let onAction {
                Button(actionTitle, action: onAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
    }
}
