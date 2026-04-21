import Testing
import Foundation
@testable import ClaudeUsageBarCore

@Suite("SessionSnapshot Codable Tests")
struct SessionSnapshotTests {

    // MARK: - Decode full JSON with ISO 8601 string resets_at (backward compat)

    @Test("Decode full snapshot with ISO 8601 string resets_at")
    func decodeFullSnapshotISO8601() throws {
        let json = """
        {
          "schema_version": 1,
          "session_id": "session_abc123def456",
          "updated_at": "2026-04-20T12:05:30Z",
          "transcript_path": "/tmp/transcript",
          "exceeds_200k_tokens": false,
          "rate_limits": {
            "five_hour": {
              "resets_at": "2026-04-20T15:30:00Z",
              "used_percentage": 42.0
            },
            "seven_day": {
              "resets_at": "2026-04-23T00:00:00Z",
              "used_percentage": 18.5
            }
          }
        }
        """

        let data = json.data(using: .utf8)!
        let snapshot = try JSONDecoder.usageBar.decode(SessionSnapshot.self, from: data)

        #expect(snapshot.schemaVersion == 1)
        #expect(snapshot.sessionId == "session_abc123def456")
        #expect(snapshot.updatedAt == "2026-04-20T12:05:30Z")
        #expect(snapshot.transcriptPath == "/tmp/transcript")
        #expect(snapshot.exceeds200kTokens == false)

        let rateLimits = try #require(snapshot.rateLimits)
        let fiveHour = try #require(rateLimits.fiveHour)
        let expectedFiveHourDate = DateParsing.parseISO8601("2026-04-20T15:30:00Z")
        #expect(fiveHour.resetsAt == expectedFiveHourDate)
        #expect(fiveHour.usedPercentage == 42.0)

        let sevenDay = try #require(rateLimits.sevenDay)
        #expect(sevenDay.usedPercentage == 18.5)
        let expectedSevenDayDate = DateParsing.parseISO8601("2026-04-23T00:00:00Z")
        #expect(sevenDay.resetsAt == expectedSevenDayDate)
    }

    // MARK: - Decode with epoch integer resets_at (new format from Claude Code)

    @Test("Decode snapshot with epoch integer resets_at")
    func decodeEpochIntegerResetsAt() throws {
        let json = """
        {
          "schema_version": 1,
          "session_id": "session_epoch",
          "updated_at": "2026-04-20T12:05:30Z",
          "rate_limits": {
            "five_hour": {
              "used_percentage": 14.000000000000002,
              "resets_at": 1776740400
            },
            "seven_day": {
              "used_percentage": 9,
              "resets_at": 1776992400
            }
          }
        }
        """

        let data = json.data(using: .utf8)!
        let snapshot = try JSONDecoder.usageBar.decode(SessionSnapshot.self, from: data)

        let rateLimits = try #require(snapshot.rateLimits)
        let fiveHour = try #require(rateLimits.fiveHour)
        #expect(fiveHour.usedPercentage == 14.000000000000002)
        #expect(fiveHour.resetsAt == Date(timeIntervalSince1970: 1776740400))

        let sevenDay = try #require(rateLimits.sevenDay)
        #expect(sevenDay.usedPercentage == 9)
        #expect(sevenDay.resetsAt == Date(timeIntervalSince1970: 1776992400))
    }

    // MARK: - Decode without status field (real-world: status is absent)

    @Test("Decode without status field succeeds")
    func decodeWithoutStatus() throws {
        let json = """
        {
          "schema_version": 1,
          "session_id": "session_no_status",
          "updated_at": "2026-04-20T12:05:30Z",
          "rate_limits": {
            "five_hour": {
              "used_percentage": 42.0,
              "resets_at": 1776740400
            }
          }
        }
        """

        let data = json.data(using: .utf8)!
        let snapshot = try JSONDecoder.usageBar.decode(SessionSnapshot.self, from: data)
        let fiveHour = try #require(snapshot.rateLimits?.fiveHour)
        #expect(fiveHour.usedPercentage == 42.0)
        #expect(fiveHour.resetsAt == Date(timeIntervalSince1970: 1776740400))
    }

    // MARK: - Backward compatibility: decode legacy seven_day_all_models key

    @Test("Decode legacy seven_day_all_models key as sevenDay")
    func decodeLegacySevenDayAllModels() throws {
        let json = """
        {
          "schema_version": 1,
          "session_id": "session_legacy",
          "updated_at": "2026-04-20T12:05:30Z",
          "rate_limits": {
            "five_hour": {
              "used_percentage": 42.0,
              "reset_at": "2026-04-20T15:30:00Z"
            },
            "seven_day_all_models": {
              "used_percentage": 18.5,
              "reset_at": "2026-04-23T00:00:00Z"
            }
          }
        }
        """

        let data = json.data(using: .utf8)!
        let snapshot = try JSONDecoder.usageBar.decode(SessionSnapshot.self, from: data)

        let rateLimits = try #require(snapshot.rateLimits)
        // seven_day_all_models should be decoded into sevenDay
        let sevenDay = try #require(rateLimits.sevenDay)
        #expect(sevenDay.usedPercentage == 18.5)
        // reset_at (legacy key) should be decoded into resetsAt
        let expectedDate = DateParsing.parseISO8601("2026-04-23T00:00:00Z")
        #expect(sevenDay.resetsAt == expectedDate)
    }

    // MARK: - Decode with missing optional fields

    @Test("Decode with null rate_limits")
    func decodeWithNullRateLimits() throws {
        let json = """
        {
          "schema_version": 1,
          "session_id": "session_xyz789",
          "updated_at": "2026-04-20T12:00:00Z",
          "rate_limits": null
        }
        """

        let data = json.data(using: .utf8)!
        let snapshot = try JSONDecoder.usageBar.decode(SessionSnapshot.self, from: data)

        #expect(snapshot.sessionId == "session_xyz789")
        #expect(snapshot.rateLimits == nil)
        #expect(snapshot.transcriptPath == nil)
        #expect(snapshot.exceeds200kTokens == nil)
    }

    @Test("Decode with partial rate_limits (seven_day absent)")
    func decodeWithPartialRateLimits() throws {
        let json = """
        {
          "schema_version": 1,
          "session_id": "session_partial",
          "updated_at": "2026-04-20T13:00:00Z",
          "rate_limits": {
            "five_hour": {
              "resets_at": "2026-04-20T18:00:00Z",
              "used_percentage": 60.0
            }
          }
        }
        """

        let data = json.data(using: .utf8)!
        let snapshot = try JSONDecoder.usageBar.decode(SessionSnapshot.self, from: data)

        let rateLimits = try #require(snapshot.rateLimits)
        #expect(rateLimits.fiveHour != nil)
        #expect(rateLimits.sevenDay == nil)
    }

    // MARK: - Decode with only five_hour (real-world Claude Code behavior)

    @Test("Decode JSON with only five_hour (no seven_day at all)")
    func decodeWithOnlyFiveHour() throws {
        let json = """
        {
          "schema_version": 1,
          "session_id": "e4a872e6-2949-4f1b-8d96-4e8d571a06f1",
          "updated_at": "2026-04-21T01:31:50Z",
          "exceeds_200k_tokens": false,
          "rate_limits": {
            "five_hour": {
              "used_percentage": 12
            }
          }
        }
        """

        let data = json.data(using: .utf8)!
        let snapshot = try JSONDecoder.usageBar.decode(SessionSnapshot.self, from: data)

        let rateLimits = try #require(snapshot.rateLimits)
        #expect(rateLimits.fiveHour?.usedPercentage == 12)
        #expect(rateLimits.sevenDay == nil)
    }

    // MARK: - Round-trip encode -> decode

    @Test("Round-trip encode then decode preserves all values")
    func roundTrip() throws {
        let fiveHourDate = Date(timeIntervalSince1970: 1776740400)
        let sevenDayDate = Date(timeIntervalSince1970: 1776992400)
        let original = SessionSnapshot(
            schemaVersion: 1,
            sessionId: "roundtrip_test",
            updatedAt: "2026-04-21T00:00:00Z",
            transcriptPath: "/path/to/transcript",
            exceeds200kTokens: true,
            rateLimits: RateLimits(
                fiveHour: RateLimitWindow(resetsAt: fiveHourDate, usedPercentage: 55.5),
                sevenDay: RateLimitWindow(resetsAt: sevenDayDate, usedPercentage: 30.0)
            )
        )

        let data = try JSONEncoder.usageBar.encode(original)
        let decoded = try JSONDecoder.usageBar.decode(SessionSnapshot.self, from: data)

        #expect(decoded.schemaVersion == original.schemaVersion)
        #expect(decoded.sessionId == original.sessionId)
        #expect(decoded.updatedAt == original.updatedAt)
        #expect(decoded.transcriptPath == original.transcriptPath)
        #expect(decoded.exceeds200kTokens == original.exceeds200kTokens)
        #expect(decoded.rateLimits?.fiveHour?.usedPercentage == original.rateLimits?.fiveHour?.usedPercentage)
        #expect(decoded.rateLimits?.sevenDay?.usedPercentage == original.rateLimits?.sevenDay?.usedPercentage)
        #expect(decoded.rateLimits?.fiveHour?.resetsAt == original.rateLimits?.fiveHour?.resetsAt)
        #expect(decoded.rateLimits?.sevenDay?.resetsAt == original.rateLimits?.sevenDay?.resetsAt)
    }

    // MARK: - Round-trip verifies encoded keys are "seven_day" and "resets_at"

    @Test("Encode uses seven_day and resets_at keys (not legacy names)")
    func encodeUsesCorrectKeys() throws {
        let snapshot = SessionSnapshot(
            schemaVersion: 1,
            sessionId: "key_test",
            updatedAt: "2026-04-21T00:00:00Z",
            transcriptPath: nil,
            exceeds200kTokens: nil,
            rateLimits: RateLimits(
                fiveHour: RateLimitWindow(resetsAt: Date(timeIntervalSince1970: 1776740400), usedPercentage: 10.0),
                sevenDay: RateLimitWindow(resetsAt: Date(timeIntervalSince1970: 1776992400), usedPercentage: 20.0)
            )
        )

        let data = try JSONEncoder.usageBar.encode(snapshot)
        let jsonString = String(data: data, encoding: .utf8)!

        // Should use "seven_day", not "seven_day_all_models"
        #expect(jsonString.contains("\"seven_day\""))
        #expect(!jsonString.contains("\"seven_day_all_models\""))
        // Should use "resets_at", not "reset_at"
        #expect(jsonString.contains("\"resets_at\""))
        #expect(!jsonString.contains("\"reset_at\""))
        // resets_at should be encoded as epoch integer
        #expect(jsonString.contains("1776740400"))
    }

    // MARK: - Encode resets_at as epoch integer

    @Test("Encode resets_at as epoch integer, not ISO 8601 string")
    func encodeResetsAtAsEpoch() throws {
        let window = RateLimitWindow(resetsAt: Date(timeIntervalSince1970: 1776740400), usedPercentage: 42.0)
        let data = try JSONEncoder.usageBar.encode(window)
        let jsonString = String(data: data, encoding: .utf8)!

        // Should contain the epoch integer, not a date string
        #expect(jsonString.contains("1776740400"))
        #expect(!jsonString.contains("2026"))
    }

    // MARK: - StatusLineInput decoding

    @Test("Decode StatusLineInput with seven_day")
    func decodeStatusLineInput() throws {
        let json = """
        {
          "session_id": "session_input_test",
          "transcript_path": "/tmp/test",
          "exceeds_200k_tokens": false,
          "rate_limits": {
            "five_hour": {
              "resets_at": "2026-04-20T15:30:00Z",
              "used_percentage": 42.0
            },
            "seven_day": {
              "used_percentage": 18.5,
              "resets_at": "2026-04-23T00:00:00Z"
            }
          }
        }
        """

        let data = json.data(using: .utf8)!
        let input = try JSONDecoder.usageBar.decode(StatusLineInput.self, from: data)

        #expect(input.sessionId == "session_input_test")
        #expect(input.transcriptPath == "/tmp/test")
        #expect(input.exceeds200kTokens == false)
        #expect(input.rateLimits?.fiveHour?.usedPercentage == 42.0)
        #expect(input.rateLimits?.sevenDay?.usedPercentage == 18.5)
    }

    @Test("Decode StatusLineInput with epoch integer resets_at")
    func decodeStatusLineInputEpoch() throws {
        let json = """
        {
          "session_id": "session_input_epoch",
          "rate_limits": {
            "five_hour": {
              "used_percentage": 14,
              "resets_at": 1776740400
            },
            "seven_day": {
              "used_percentage": 9,
              "resets_at": 1776992400
            }
          }
        }
        """

        let data = json.data(using: .utf8)!
        let input = try JSONDecoder.usageBar.decode(StatusLineInput.self, from: data)

        #expect(input.rateLimits?.fiveHour?.usedPercentage == 14)
        #expect(input.rateLimits?.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1776740400))
        #expect(input.rateLimits?.sevenDay?.usedPercentage == 9)
        #expect(input.rateLimits?.sevenDay?.resetsAt == Date(timeIntervalSince1970: 1776992400))
    }

    @Test("Decode StatusLineInput with only five_hour (no seven_day)")
    func decodeStatusLineInputFiveHourOnly() throws {
        let json = """
        {
          "session_id": "session_input_test2",
          "rate_limits": {
            "five_hour": {
              "used_percentage": 42.0
            }
          }
        }
        """

        let data = json.data(using: .utf8)!
        let input = try JSONDecoder.usageBar.decode(StatusLineInput.self, from: data)

        #expect(input.rateLimits?.fiveHour?.usedPercentage == 42.0)
        #expect(input.rateLimits?.sevenDay == nil)
    }

    // MARK: - Full real-world JSON from Claude Code statusLine

    @Test("Decode full real-world statusLine JSON payload with epoch resets_at")
    func decodeRealWorldPayload() throws {
        let json = """
        {
          "session_id": "e4a872e6-2949-4f1b-8d96-4e8d571a06f1",
          "transcript_path": "/Users/test/.claude/projects/test/e4a872e6.jsonl",
          "exceeds_200k_tokens": false,
          "rate_limits": {
            "five_hour": {"used_percentage":14.000000000000002, "resets_at":1776740400},
            "seven_day": {"used_percentage":9, "resets_at":1776992400}
          }
        }
        """

        let data = json.data(using: .utf8)!
        let input = try JSONDecoder.usageBar.decode(StatusLineInput.self, from: data)

        #expect(input.sessionId == "e4a872e6-2949-4f1b-8d96-4e8d571a06f1")
        #expect(input.exceeds200kTokens == false)

        let rateLimits = try #require(input.rateLimits)
        let fiveHour = try #require(rateLimits.fiveHour)
        #expect(fiveHour.usedPercentage == 14.000000000000002)
        #expect(fiveHour.resetsAt == Date(timeIntervalSince1970: 1776740400))

        let sevenDay = try #require(rateLimits.sevenDay)
        #expect(sevenDay.usedPercentage == 9)
        #expect(sevenDay.resetsAt == Date(timeIntervalSince1970: 1776992400))
    }

    // MARK: - HistoryEntry round-trip

    @Test("HistoryEntry encode-decode round-trip")
    func historyEntryRoundTrip() throws {
        let entry = HistoryEntry(
            timestamp: "2026-04-20T12:05:30Z",
            fiveHourPct: 42.0,
            sevenDayPct: 18.5,
            sessionId: "session_abc"
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: data)

        #expect(decoded.timestamp == entry.timestamp)
        #expect(decoded.fiveHourPct == entry.fiveHourPct)
        #expect(decoded.sevenDayPct == entry.sevenDayPct)
        #expect(decoded.sessionId == entry.sessionId)
    }

    @Test("HistoryEntry decode legacy seven_day_all_models_pct key")
    func historyEntryDecodeLegacy() throws {
        let json = """
        {"timestamp":"2026-04-20T12:05:30Z","five_hour_pct":42.0,"seven_day_all_models_pct":18.5,"session_id":"session_abc"}
        """

        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: data)

        #expect(decoded.sevenDayPct == 18.5)
    }

    @Test("HistoryEntry encodes with seven_day_pct key")
    func historyEntryEncodesCorrectKey() throws {
        let entry = HistoryEntry(
            timestamp: "2026-04-20T12:05:30Z",
            fiveHourPct: 42.0,
            sevenDayPct: 18.5,
            sessionId: "session_abc"
        )

        let data = try JSONEncoder().encode(entry)
        let jsonString = String(data: data, encoding: .utf8)!

        #expect(jsonString.contains("\"seven_day_pct\""))
        #expect(!jsonString.contains("\"seven_day_all_models_pct\""))
    }
}
