import SwiftUI
import Theme

/// A vertical divider that can be dragged to resize adjacent panels.
struct ResizableDivider: View {
    @Binding var width: Double
    var minWidth: Double = 200
    var maxWidth: Double = 600
    var inverted: Bool = false

    @State private var isDragging = false
    @State private var dragStart: Double = 0
    @Environment(\.theme) private var theme

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.5) : theme.chrome.border)
            .frame(width: isDragging ? 3 : 1)
            .contentShape(Rectangle().inset(by: -3))
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStart = width
                        }
                        let delta = inverted ? -value.translation.width : value.translation.width
                        let new = dragStart + delta
                        width = min(max(new, minWidth), maxWidth)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .animation(.easeOut(duration: 0.15), value: isDragging)
    }
}
