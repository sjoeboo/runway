import Models
import SwiftUI
import Theme

/// Displays a chronological list of hook events for a session.
public struct ActivityLogView: View {
    let events: [SessionEvent]
    @Environment(\.theme) private var theme

    public init(events: [SessionEvent]) {
        self.events = events
    }

    public var body: some View {
        if events.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .font(.title2)
                    .foregroundColor(theme.chrome.textDim)
                Text("No activity yet")
                    .font(.callout)
                    .foregroundColor(theme.chrome.textDim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(events) { event in
                        eventRow(event)
                        Divider().opacity(0.3)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    @ViewBuilder
    private func eventRow(_ event: SessionEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            eventIcon(event.eventType)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(eventLabel(event.eventType))
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text(event.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundColor(theme.chrome.textDim)
                }

                if let prompt = event.prompt {
                    Text(prompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                if let tool = event.toolName {
                    Text(tool)
                        .font(.caption2)
                        .foregroundColor(theme.chrome.textDim)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func eventIcon(_ type: String) -> some View {
        let (name, color): (String, Color) =
            switch type {
            case "SessionStart": ("play.circle.fill", theme.chrome.green)
            case "UserPromptSubmit": ("arrow.up.circle.fill", theme.chrome.accent)
            case "PermissionRequest": ("hand.raised.fill", theme.chrome.orange)
            case "Stop": ("pause.circle.fill", theme.chrome.textDim)
            case "SessionEnd": ("stop.circle.fill", theme.chrome.red)
            case "Notification": ("bell.fill", theme.chrome.yellow)
            default: ("circle.fill", theme.chrome.textDim)
            }
        return Image(systemName: name)
            .font(.caption)
            .foregroundColor(color)
    }

    private func eventLabel(_ type: String) -> String {
        switch type {
        case "SessionStart": "Session Started"
        case "UserPromptSubmit": "Prompt Sent"
        case "PermissionRequest": "Permission Requested"
        case "Stop": "Turn Complete"
        case "SessionEnd": "Session Ended"
        case "Notification": "Notification"
        default: type
        }
    }
}
