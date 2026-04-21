import SwiftUI

/// Plain-value snapshot used by `UsageLabel` to avoid `@Observable` tracking
/// inside the `MenuBarExtra` label, which causes the status item to vanish.
struct UsageLabelSnapshot: Equatable {
    var fiveHourPercentage: Double?
    var sevenDayPercentage: Double?
    var displayMode: DisplayMode = .standard
}

/// Menu bar label that shows a compact usage summary.
///
/// Receives a plain `UsageLabelSnapshot` instead of an observable object.
/// This works around a macOS SwiftUI bug where accessing `@Observable`
/// properties inside a `MenuBarExtra` label causes the status item to
/// disappear entirely.
struct UsageLabel: View {
    let snapshot: UsageLabelSnapshot

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
            Text(statusText)
                .monospacedDigit()
        }
        .foregroundStyle(statusColor)
    }

    // MARK: - Status Text

    static func formatTitle(
        fiveHourPercentage: Double?,
        sevenDayPercentage: Double?,
        displayMode: DisplayMode
    ) -> String {
        guard let fiveHour = fiveHourPercentage else {
            return "CC \u{2014}"
        }

        switch displayMode {
        case .standard:
            let fh = formatPercent(fiveHour)
            if let sevenDay = sevenDayPercentage {
                let sd = formatPercent(sevenDay)
                return "CC 5h \(fh)% / 7d \(sd)%"
            }
            return "CC 5h \(fh)%"
        case .compact:
            let fh = formatPercent(fiveHour)
            if let sevenDay = sevenDayPercentage {
                let sd = formatPercent(sevenDay)
                return "CC \(fh) / \(sd)"
            }
            return "CC \(fh)"
        case .minimal:
            let fh = formatPercent(fiveHour)
            return "CC \(fh)%"
        }
    }

    private var statusText: String {
        Self.formatTitle(
            fiveHourPercentage: snapshot.fiveHourPercentage,
            sevenDayPercentage: snapshot.sevenDayPercentage,
            displayMode: snapshot.displayMode
        )
    }

    // MARK: - Status Icon

    private var iconName: String {
        let maxPct = maxPercentage
        switch maxPct {
        case 95...:
            return "exclamationmark.triangle"
        case 85..<95:
            return "gauge.high"
        case 70..<85:
            return "gauge.medium"
        default:
            return "gauge.low"
        }
    }

    // MARK: - Status Color

    private var statusColor: Color {
        let maxPct = maxPercentage
        switch maxPct {
        case 95...:
            return .red
        case 85..<95:
            return .red
        case 70..<85:
            return .orange
        default:
            return .primary
        }
    }

    // MARK: - Helpers

    private var maxPercentage: Double {
        [snapshot.fiveHourPercentage, snapshot.sevenDayPercentage]
            .compactMap { $0 }
            .max() ?? 0
    }

    private static func formatPercent(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }
}
