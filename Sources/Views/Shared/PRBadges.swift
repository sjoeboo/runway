import Models
import SwiftUI
import Theme

// MARK: - CheckSummaryBadge

/// Shared badge showing CI check status: icon (checkmark/xmark/clock) + passed/total count.
///
/// Used in sidebar session rows, session headers, PR dashboard rows, PR detail drawers,
/// and project PR tabs.
public struct CheckSummaryBadge: View {
    let checks: CheckSummary
    @Environment(\.theme) private var theme

    /// Controls the visual density of the badge.
    public enum Style {
        /// Compact: icon + "passed/total" in caption2, spacing 2 (sidebar/row contexts).
        case compact
        /// Inline: icon (caption2) + "passed/total" in caption, spacing 3 (header contexts).
        case inline
    }

    var style: Style = .compact

    public init(checks: CheckSummary, style: Style = .compact) {
        self.checks = checks
        self.style = style
    }

    public var body: some View {
        if checks.total > 0 {
            HStack(spacing: style == .compact ? 2 : 3) {
                Group {
                    if checks.allPassed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(theme.chrome.green)
                    } else if checks.hasFailed {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(theme.chrome.red)
                    } else {
                        Image(systemName: style == .compact ? "circle.fill" : "clock.fill")
                            .foregroundColor(theme.chrome.yellow)
                    }
                }
                .font(style == .compact ? .caption : .caption)
                Text("\(checks.passed)/\(checks.total)")
                    .font(style == .compact ? .caption : .callout)
                    .foregroundStyle(style == .compact ? .secondary : .secondary)
            }
            .font(style == .compact ? .caption : nil)
        }
    }
}

// MARK: - ReviewDecisionBadge

/// Shared badge showing PR review decision (Approved / Changes / Review / none).
///
/// Three visual styles cover the range of contexts:
/// - `.label`: icon + text as a Label (dashboard rows, detail drawer header)
/// - `.capsule`: text in a colored capsule with tinted background (session header)
/// - `.iconOnly`: small icon only (sidebar session rows)
public struct ReviewDecisionBadge: View {
    let decision: ReviewDecision
    @Environment(\.theme) private var theme

    public enum Style {
        /// Label style: `Label("Approved", systemImage:...)` in caption2.
        case label
        /// Capsule style: colored text in a capsule with tinted background.
        case capsule
        /// Icon-only style: small icon for tight spaces (sidebar rows).
        case iconOnly
    }

    var style: Style = .label

    public init(decision: ReviewDecision, style: Style = .label) {
        self.decision = decision
        self.style = style
    }

    public var body: some View {
        switch style {
        case .label:
            labelStyle
        case .capsule:
            capsuleStyle
        case .iconOnly:
            iconOnlyStyle
        }
    }

    // MARK: - Label style (PRRowView, ProjectPRRowView, PRDetailDrawer header)

    @ViewBuilder
    private var labelStyle: some View {
        switch decision {
        case .approved:
            Label("Approved", systemImage: "checkmark")
                .font(.caption)
                .foregroundColor(theme.chrome.green)
        case .changesRequested:
            Label("Changes", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundColor(theme.chrome.orange)
        case .pending:
            Label("Review", systemImage: "clock")
                .font(.caption)
                .foregroundColor(theme.chrome.yellow)
        case .none:
            EmptyView()
        }
    }

    // MARK: - Capsule style (SessionHeaderView)

    @ViewBuilder
    private var capsuleStyle: some View {
        switch decision {
        case .approved:
            capsuleText("Approved", color: theme.chrome.green)
        case .changesRequested:
            capsuleText("Changes", color: theme.chrome.orange)
        case .pending:
            capsuleText("Review", color: theme.chrome.yellow)
        case .none:
            EmptyView()
        }
    }

    private func capsuleText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: - Icon-only style (sidebar session rows)

    @ViewBuilder
    private var iconOnlyStyle: some View {
        switch decision {
        case .approved:
            Image(systemName: "checkmark")
                .font(.caption)
                .foregroundColor(theme.chrome.green)
        case .changesRequested:
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
                .foregroundColor(theme.chrome.orange)
        case .pending, .none:
            EmptyView()
        }
    }
}

// MARK: - MergeStatusBadge

/// Capsule badge showing PR merge status (Clean, Conflicts, Behind, Blocked, etc.).
///
/// Hidden when merge status is unknown or not yet enriched.
public struct MergeStatusBadge: View {
    let mergeable: MergeableState?
    let mergeStateStatus: MergeStateStatus?
    @Environment(\.theme) private var theme

    public init(mergeable: MergeableState?, mergeStateStatus: MergeStateStatus?) {
        self.mergeable = mergeable
        self.mergeStateStatus = mergeStateStatus
    }

    public var body: some View {
        if let badge = badgeInfo {
            Text(badge.text)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(badge.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badge.color.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    private var badgeInfo: (text: String, color: Color)? {
        // Conflicts override everything
        if mergeable == .conflicting {
            return ("\u{26A0} Conflicts", theme.chrome.red)
        }

        switch mergeStateStatus {
        case .blocked:
            return ("\u{2298} Blocked", theme.chrome.orange)
        case .behind:
            return ("\u{2193} Behind", theme.chrome.yellow)
        case .dirty:
            return ("\u{26A0} Dirty", theme.chrome.orange)
        case .unstable:
            return ("~ Unstable", theme.chrome.yellow)
        case .clean, .hasHooks:
            return ("\u{2713} Clean", theme.chrome.green)
        case .unknown, .none:
            // Also check if mergeable is known even without mergeStateStatus
            if mergeable == .mergeable {
                return ("\u{2713} Mergeable", theme.chrome.green)
            }
            return nil
        }
    }
}

// MARK: - SessionStatusIndicator

/// Colored dot/circle showing the current session status.
///
/// Supports configurable size (sidebar uses 8pt, header uses 7pt).
public struct SessionStatusIndicator: View {
    let status: SessionStatus
    var size: CGFloat

    @Environment(\.theme) private var theme

    public init(status: SessionStatus, size: CGFloat = 8) {
        self.status = status
        self.size = size
    }

    public var body: some View {
        indicator
            .help(accessibilityLabel)
            .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var indicator: some View {
        switch status {
        case .running:
            Circle()
                .fill(theme.chrome.green)
                .frame(width: size, height: size)
        case .waiting:
            if size <= 7 {
                // Header style: solid circle
                Circle()
                    .fill(theme.chrome.yellow)
                    .frame(width: size, height: size)
            } else {
                // Sidebar style: half-filled icon
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: size))
                    .foregroundColor(theme.chrome.yellow)
            }
        case .starting:
            ProgressView()
                .controlSize(.mini)
        case .error:
            if size <= 7 {
                Circle()
                    .fill(theme.chrome.red)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: size))
                    .foregroundColor(theme.chrome.red)
            }
        case .idle:
            // Open circle — "ready for input"
            Circle()
                .strokeBorder(theme.chrome.textDim, lineWidth: size <= 7 ? 1.5 : 1)
                .frame(width: size, height: size)
        case .stopped:
            // Filled gray dot — distinctly different from idle's open circle
            Circle()
                .fill(theme.chrome.textDim)
                .frame(width: size, height: size)
                .opacity(0.4)
        }
    }

    private var accessibilityLabel: String {
        switch status {
        case .running: "Running"
        case .waiting: "Waiting for input"
        case .starting: "Starting"
        case .error: "Error"
        case .idle: "Idle"
        case .stopped: "Stopped"
        }
    }
}
