import Foundation
import Combine
import ClaudeUsageBarCore

/// Display mode for the menu bar status item.
enum DisplayMode: String, CaseIterable, Sendable {
    case standard   // "CC 5h 42% / 7d 18%"
    case compact    // "42% / 18%"
    case minimal    // "42%"
}

/// Notification posted by `UsageViewModel` when label-relevant data changes.
extension Notification.Name {
    static let usageLabelDidChange = Notification.Name("usageLabelDidChange")
}

/// Main view model that loads session snapshots and exposes aggregated usage data.
///
/// Uses `ObservableObject` for the popover content, and posts a plain
/// `Notification` for the menu bar label. Accessing `@Observable` or
/// `@ObservedObject` properties inside a `MenuBarExtra` label ViewBuilder
/// causes the status item to vanish on macOS 14/15 due to a SwiftUI bug.
@MainActor
final class UsageViewModel: ObservableObject {
    // MARK: - Aggregated rate limits (from latest session with rate_limits)

    @Published var fiveHourPercentage: Double?
    @Published var sevenDayPercentage: Double?
    @Published var fiveHourResetsAt: Date?
    @Published var sevenDayResetsAt: Date?

    // MARK: - Latest session info

    @Published var model: String?
    @Published var sessionID: String?
    @Published var lastUpdate: Date?

    // MARK: - All active sessions

    @Published private(set) var sessions: [SessionSnapshot] = []

    // MARK: - Settings

    @Published var displayMode: DisplayMode = .standard

    // MARK: - Internal state

    private var fileWatcher: FileWatcher?
    private let sessionsDirectory: URL
    private let inactiveThreshold: TimeInterval = 30 * 60 // 30 minutes

    /// Overridable "now" for testing freshness logic.
    var currentDate: () -> Date = { Date() }


    // MARK: - Init

    /// - Parameter sessionsDirectory: The directory to watch for session JSON files.
    ///   Defaults to `~/.claude/claude-usage-bar/sessions/`.
    init(sessionsDirectory: URL? = nil) {
        self.sessionsDirectory = sessionsDirectory ?? Self.defaultSessionsDirectory()
    }

    // MARK: - Public API

    /// Start watching the sessions directory and perform an initial reload.
    func start() {
        fileWatcher = FileWatcher(directory: sessionsDirectory) { [weak self] in
            Task { @MainActor [weak self] in
                self?.reload()
            }
        }
        reload()
    }

    /// Stop watching for changes.
    func stop() {
        fileWatcher?.stop()
        fileWatcher = nil
    }

    /// Reload all session data from disk.
    func reload() {
        let snapshots = loadAllSessions()
        self.sessions = snapshots

        // Select latest rate_limits from the session with the newest updated_at that has rate_limits
        let latestWithRateLimits = selectLatestSessionWithRateLimits(sessions: snapshots)
        let rateLimitsDate = latestWithRateLimits.flatMap { parseDate($0.updatedAt) }

        // 30-minute freshness rule: if the latest rate_limits data is older than 30 minutes, nil out
        let isFresh: Bool
        if let date = rateLimitsDate {
            isFresh = currentDate().timeIntervalSince(date) < inactiveThreshold
        } else {
            isFresh = false
        }

        if isFresh, let rateLimits = latestWithRateLimits?.rateLimits {
            self.fiveHourPercentage = rateLimits.fiveHour?.usedPercentage
            self.sevenDayPercentage = rateLimits.sevenDay?.usedPercentage
            self.fiveHourResetsAt = rateLimits.fiveHour?.resetsAt
            self.sevenDayResetsAt = rateLimits.sevenDay?.resetsAt
        } else {
            self.fiveHourPercentage = nil
            self.sevenDayPercentage = nil
            self.fiveHourResetsAt = nil
            self.sevenDayResetsAt = nil
        }

        // Latest session overall (by updated_at) — for lastUpdate display
        if let latest = snapshots.max(by: { compareUpdatedAt($0.updatedAt, $1.updatedAt) }) {
            self.sessionID = latest.sessionId
            self.lastUpdate = parseDate(latest.updatedAt)
        } else {
            self.sessionID = nil
            self.lastUpdate = nil
        }

        // Post notification with label snapshot to avoid ObservableObject
        // tracking inside the MenuBarExtra label.
        let snapshot = UsageLabelSnapshot(
            fiveHourPercentage: self.fiveHourPercentage,
            sevenDayPercentage: self.sevenDayPercentage,
            displayMode: self.displayMode
        )
        NotificationCenter.default.post(
            name: .usageLabelDidChange,
            object: nil,
            userInfo: ["snapshot": snapshot]
        )
    }

    /// Returns only sessions that have been updated within the inactive threshold.
    var activeSessions: [SessionSnapshot] {
        let now = currentDate()
        return sessions.filter { session in
            guard let date = parseDate(session.updatedAt) else { return false }
            return now.timeIntervalSince(date) < inactiveThreshold
        }
    }

    // MARK: - Private helpers

    private func loadAllSessions() -> [SessionSnapshot] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let decoder = JSONDecoder.usageBar
        var snapshots: [SessionSnapshot] = []

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let snapshot = try? decoder.decode(SessionSnapshot.self, from: data) else {
                continue
            }
            // Skip unknown schema versions
            guard snapshot.schemaVersion == 1 else { continue }
            snapshots.append(snapshot)
        }

        return snapshots
    }

    private func selectLatestSessionWithRateLimits(sessions: [SessionSnapshot]) -> SessionSnapshot? {
        sessions
            .filter { $0.rateLimits != nil }
            .max(by: { compareUpdatedAt($0.updatedAt, $1.updatedAt) })
    }

    private func compareUpdatedAt(_ lhs: String, _ rhs: String) -> Bool {
        let lhsDate = parseDate(lhs) ?? .distantPast
        let rhsDate = parseDate(rhs) ?? .distantPast
        return lhsDate < rhsDate
    }

    private func parseDate(_ string: String) -> Date? {
        DateParsing.parseISO8601(string)
    }

    private static func defaultSessionsDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("claude-usage-bar", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }
}
