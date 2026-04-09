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
    @State private var cursorPushed = false
    @Environment(\.theme) private var theme

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.5) : theme.chrome.border)
            .frame(width: isDragging ? 3 : 1)
            .contentShape(Rectangle().inset(by: -3))
            .onHover { hovering in
                if hovering, !cursorPushed {
                    NSCursor.resizeLeftRight.push()
                    cursorPushed = true
                } else if !hovering, cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
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
            .accessibilityLabel("Resize panel")
            .accessibilityValue("\(Int(width))pt")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: width = min(width + 20, maxWidth)
                case .decrement: width = max(width - 20, minWidth)
                @unknown default: break
                }
            }
    }
}
