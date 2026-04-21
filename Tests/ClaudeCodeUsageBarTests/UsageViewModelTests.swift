import Testing
import Foundation
import ClaudeUsageBarCore
@testable import ClaudeCodeUsageBar

@Suite("UsageViewModel Tests")
@MainActor
struct UsageViewModelTests {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-bar-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeSnapshot(_ snapshot: SessionSnapshot, to directory: URL) throws {
        let data = try JSONEncoder.usageBar.encode(snapshot)
        let fileURL = directory.appendingPathComponent("session_\(snapshot.sessionId).json")
        try data.write(to: fileURL)
    }

    /// Create a ViewModel with currentDate pinned so freshness checks pass for test data.
    private func makeViewModel(sessionsDirectory: URL, now: Date) -> UsageViewModel {
        let vm = UsageViewModel(sessionsDirectory: sessionsDirectory)
        vm.currentDate = { now }
        return vm
    }

    /// A fixed "now" that is within 30 minutes of the test data timestamps (2026-04-20T12:xx).
    private var testNow: Date {
        // 2026-04-20T12:10:00Z — 10 minutes after typical test timestamps
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: "2026-04-20T12:10:00Z")!
    }

    private var testNowForOlderSession: Date {
        // 2026-04-20T14:10:00Z — 10 minutes after the "no_limits" session at 14:00
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: "2026-04-20T14:10:00Z")!
    }

    // MARK: - Empty directory → no data

    @Test("Empty directory produces no data")
    func emptyDirectory_noData() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = makeViewModel(sessionsDirectory: dir, now: testNow)
        vm.reload()

        #expect(vm.fiveHourPercentage == nil)
        #expect(vm.sevenDayPercentage == nil)
        #expect(vm.sessionID == nil)
        #expect(vm.sessions.isEmpty)
    }

    // MARK: - Single session → fiveHourPercentage correct

    @Test("Single session provides correct fiveHourPercentage and sevenDayPercentage")
    func singleSession_fiveHourPercentage() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let snapshot = SessionSnapshot(
            schemaVersion: 1,
            sessionId: "single_test",
            updatedAt: "2026-04-20T12:00:00Z",
            transcriptPath: nil,
            exceeds200kTokens: false,
            rateLimits: RateLimits(
                fiveHour: RateLimitWindow(resetsAt: DateParsing.parseISO8601("2026-04-20T17:00:00Z"), usedPercentage: 42.0),
                sevenDay: RateLimitWindow(resetsAt: DateParsing.parseISO8601("2026-04-27T00:00:00Z"), usedPercentage: 15.0)
            )
        )

        try writeSnapshot(snapshot, to: dir)

        let vm = makeViewModel(sessionsDirectory: dir, now: testNow)
        vm.reload()

        #expect(vm.fiveHourPercentage == 42.0)
        #expect(vm.sevenDayPercentage == 15.0)
        #expect(vm.sessionID == "single_test")
    }

    // MARK: - Multiple sessions → latest rate_limits adopted

    @Test("Multiple sessions adopts rate_limits from the latest updated_at")
    func multipleSessions_latestRateLimitsAdopted() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Older session with higher percentages
        let older = SessionSnapshot(
            schemaVersion: 1,
            sessionId: "older_session",
            updatedAt: "2026-04-20T10:00:00Z",
            transcriptPath: nil,
            exceeds200kTokens: false,
            rateLimits: RateLimits(
                fiveHour: RateLimitWindow(resetsAt: DateParsing.parseISO8601("2026-04-20T15:00:00Z"), usedPercentage: 80.0),
                sevenDay: RateLimitWindow(resetsAt: DateParsing.parseISO8601("2026-04-27T00:00:00Z"), usedPercentage: 50.0)
            )
        )

        // Newer session with lower percentages — should be adopted (latest updated_at wins)
        let newer = SessionSnapshot(
            schemaVersion: 1,
            sessionId: "newer_session",
            updatedAt: "2026-04-20T12:00:00Z",
            transcriptPath: nil,
            exceeds200kTokens: false,
            rateLimits: RateLimits(
                fiveHour: RateLimitWindow(resetsAt: DateParsing.parseISO8601("2026-04-20T17:00:00Z"), usedPercentage: 25.0),
                sevenDay: RateLimitWindow(resetsAt: DateParsing.parseISO8601("2026-04-27T00:00:00Z"), usedPercentage: 10.0)
            )
        )

        try writeSnapshot(older, to: dir)
        try writeSnapshot(newer, to: dir)

        let vm = makeViewModel(sessionsDirectory: dir, now: testNow)
        vm.reload()

        // Latest session (newer) rate_limits are adopted
        #expect(vm.fiveHourPercentage == 25.0)
        #expect(vm.sevenDayPercentage == 10.0)
        #expect(vm.sessions.count == 2)
    }

    // MARK: - Sessions with nil rate_limits are skipped

    @Test("Sessions with nil rate_limits are skipped, older session with data used")
    func multipleSessions_nilRateLimitsSkipped() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Newer session without rate_limits
        let noLimits = SessionSnapshot(
            schemaVersion: 1,
            sessionId: "no_limits",
            updatedAt: "2026-04-20T14:00:00Z",
            transcriptPath: nil,
            exceeds200kTokens: nil,
            rateLimits: nil
        )

        // Older session with rate_limits
        let withLimits = SessionSnapshot(
            schemaVersion: 1,
            sessionId: "with_limits",
            updatedAt: "2026-04-20T12:00:00Z",
            transcriptPath: nil,
            exceeds200kTokens: false,
            rateLimits: RateLimits(
                fiveHour: RateLimitWindow(resetsAt: DateParsing.parseISO8601("2026-04-20T17:00:00Z"), usedPercentage: 60.0),
                sevenDay: nil
            )
        )

        try writeSnapshot(noLimits, to: dir)
        try writeSnapshot(withLimits, to: dir)

        // Use a time within 30 min of with_limits session (12:00) — 12:10
        let vm = makeViewModel(sessionsDirectory: dir, now: testNow)
        vm.reload()

        // rate_limits from the session that has them (even though older)
        #expect(vm.fiveHourPercentage == 60.0)
        #expect(vm.sessions.count == 2)
    }

    // MARK: - Unknown schema version skipped

    @Test("Sessions with unknown schema_version are skipped")
    func unknownSchemaVersionSkipped() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let futureSchema = SessionSnapshot(
            schemaVersion: 99,
            sessionId: "future",
            updatedAt: "2026-04-20T12:00:00Z",
            transcriptPath: nil,
            exceeds200kTokens: nil,
            rateLimits: RateLimits(
                fiveHour: RateLimitWindow(resetsAt: DateParsing.parseISO8601("2026-04-20T17:00:00Z"), usedPercentage: 99.0),
                sevenDay: nil
            )
        )

        try writeSnapshot(futureSchema, to: dir)

        let vm = makeViewModel(sessionsDirectory: dir, now: testNow)
        vm.reload()

        #expect(vm.sessions.isEmpty)
        #expect(vm.fiveHourPercentage == nil)
    }

    // MARK: - 30-minute freshness rule

    @Test("Rate limits nil out when data is older than 30 minutes")
    func freshnessRule_staleDataNilsRateLimits() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let snapshot = SessionSnapshot(
            schemaVersion: 1,
            sessionId: "stale_session",
            updatedAt: "2026-04-20T10:00:00Z", // old
            transcriptPath: nil,
            exceeds200kTokens: false,
            rateLimits: RateLimits(
                fiveHour: RateLimitWindow(resetsAt: DateParsing.parseISO8601("2026-04-20T15:00:00Z"), usedPercentage: 80.0),
                sevenDay: nil
            )
        )

        try writeSnapshot(snapshot, to: dir)

        // "now" is 2026-04-20T12:10:00Z — more than 30 min after 10:00
        let vm = makeViewModel(sessionsDirectory: dir, now: testNow)
        vm.reload()

        // Data is stale, should be nil
        #expect(vm.fiveHourPercentage == nil)
        // But session is still loaded
        #expect(vm.sessions.count == 1)
        #expect(vm.sessionID == "stale_session")
    }

    // MARK: - exceeds_200k_tokens across multiple sessions

    @Test("activeSessions contains check for exceeds200kTokens across all sessions")
    func exceeds200kTokens_multipleSessionsChecked() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let session1 = SessionSnapshot(
            schemaVersion: 1,
            sessionId: "session_normal",
            updatedAt: "2026-04-20T12:00:00Z",
            transcriptPath: nil,
            exceeds200kTokens: false,
            rateLimits: nil
        )

        let session2 = SessionSnapshot(
            schemaVersion: 1,
            sessionId: "session_exceeds",
            updatedAt: "2026-04-20T12:05:00Z",
            transcriptPath: nil,
            exceeds200kTokens: true,
            rateLimits: nil
        )

        try writeSnapshot(session1, to: dir)
        try writeSnapshot(session2, to: dir)

        let vm = makeViewModel(sessionsDirectory: dir, now: testNow)
        vm.reload()

        // Both sessions should be active (within 30 min of testNow 12:10)
        #expect(vm.activeSessions.count == 2)
        // At least one session exceeds 200k
        #expect(vm.activeSessions.contains { $0.exceeds200kTokens == true })
    }

    // MARK: - Schema required field missing gracefully handled

    @Test("Malformed JSON files are skipped gracefully")
    func malformedJsonSkipped() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Write a valid session
        let validSnapshot = SessionSnapshot(
            schemaVersion: 1,
            sessionId: "valid_session",
            updatedAt: "2026-04-20T12:00:00Z",
            transcriptPath: nil,
            exceeds200kTokens: nil,
            rateLimits: RateLimits(
                fiveHour: RateLimitWindow(resetsAt: DateParsing.parseISO8601("2026-04-20T17:00:00Z"), usedPercentage: 30.0),
                sevenDay: nil
            )
        )
        try writeSnapshot(validSnapshot, to: dir)

        // Write a malformed JSON file (missing required session_id)
        let malformed = """
        {"schema_version": 1, "updated_at": "2026-04-20T12:01:00Z"}
        """.data(using: .utf8)!
        try malformed.write(to: dir.appendingPathComponent("session_broken.json"))

        let vm = makeViewModel(sessionsDirectory: dir, now: testNow)
        vm.reload()

        // Only valid session is loaded
        #expect(vm.sessions.count == 1)
        #expect(vm.fiveHourPercentage == 30.0)
    }
}
