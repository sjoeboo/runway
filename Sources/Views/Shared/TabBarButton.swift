import SwiftUI
import Theme

/// Reusable tab bar button for section navigation (project page, PR dashboard).
/// Shows title + optional count badge with an underline indicator for the active tab.
public struct TabBarButton: View {
    let title: String
    let count: Int?
    let isActive: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme

    public init(title: String, count: Int? = nil, isActive: Bool, action: @escaping () -> Void) {
        self.title = title
        self.count = count
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.callout)
                        .fontWeight(isActive ? .semibold : .regular)
                        .foregroundColor(isActive ? theme.chrome.text : theme.chrome.textDim)

                    if let count {
                        Text("\(count)")
                            .font(.caption)
                            .foregroundColor(isActive ? theme.chrome.text : theme.chrome.textDim)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(theme.chrome.surface.opacity(0.6))
                            )
                    }
                }

                Rectangle()
                    .fill(isActive ? theme.chrome.accent : Color.clear)
                    .frame(height: 2)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
