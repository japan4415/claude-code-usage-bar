import SwiftUI
import ClaudeUsageBarCore

/// Popover shown when the menu bar item is clicked.
struct PopoverView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            Divider()
            rateLimitsSection
            Divider()
            sessionInfoSection
            Divider()
            footerSection
        }
        .padding()
        .frame(width: 320)
    }

    // MARK: - Header

    private var headerSection: some View {
        Text("Claude Code Usage")
            .font(.headline)
    }

    // MARK: - Rate Limits

    @ViewBuilder
    private var rateLimitsSection: some View {
        if viewModel.fiveHourPercentage != nil || viewModel.sevenDayPercentage != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let pct = viewModel.fiveHourPercentage {
                    rateLimitRow(
                        label: "5h limit",
                        percentage: pct,
                        resetsAt: viewModel.fiveHourResetsAt
                    )
                }
                if let pct = viewModel.sevenDayPercentage {
                    rateLimitRow(
                        label: "7d limit",
                        percentage: pct,
                        resetsAt: viewModel.sevenDayResetsAt
                    )
                }
            }
        } else {
            Text("No rate limit data available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func rateLimitRow(label: String, percentage: Double, resetsAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(percentage.rounded()))%")
                    .font(.caption)
                    .fontWeight(.medium)
                if let resetText = formatResetCountdown(resetsAt) {
                    Text(resetText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: min(percentage, 100.0), total: 100.0)
                .tint(colorForPercentage(percentage))
        }
    }

    // MARK: - Session Info

    @ViewBuilder
    private var sessionInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Exceeds context limit warning — check all active sessions
            if viewModel.activeSessions.contains(where: { $0.exceeds200kTokens == true }) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Context window exceeds 200k tokens")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let lastUpdate = viewModel.lastUpdate {
                infoRow(label: "Last update", value: formatRelativeTime(lastUpdate))
            }

            if viewModel.activeSessions.isEmpty {
                Text("No active sessions. Start Claude Code to begin tracking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if viewModel.activeSessions.count > 1 {
                Divider()
                Text("Active Sessions (\(viewModel.activeSessions.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(viewModel.activeSessions, id: \.sessionId) { session in
                    sessionRow(session)
                }
            }
        }
    }

    private func sessionRow(_ session: SessionSnapshot) -> some View {
        HStack {
            Text(String(session.sessionId.prefix(8)))
                .font(.caption)
                .monospaced()
            Spacer()
            if let date = parseDate(session.updatedAt) {
                Text(formatRelativeTime(date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    // MARK: - Helpers

    private func colorForPercentage(_ pct: Double) -> Color {
        switch pct {
        case 95...: return .red
        case 85..<95: return .red
        case 70..<85: return .orange
        default: return .accentColor
        }
    }

    private func formatResetCountdown(_ resetDate: Date?) -> String? {
        guard let resetDate else { return nil }

        let now = Date()
        let remaining = resetDate.timeIntervalSince(now)

        if remaining < 0 {
            return "reset pending"
        } else if remaining < 60 {
            return "resets soon"
        } else if remaining < 3600 {
            let mins = Int(remaining / 60)
            return "resets in \(mins)m"
        } else {
            let hours = Int(remaining / 3600)
            let mins = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
            return "resets in \(hours)h \(mins)m"
        }
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 {
            return "\(Int(elapsed)) sec ago"
        } else if elapsed < 3600 {
            return "\(Int(elapsed / 60)) min ago"
        } else {
            return "\(Int(elapsed / 3600))h ago"
        }
    }

    private func parseDate(_ string: String) -> Date? {
        DateParsing.parseISO8601(string)
    }
}
