import Foundation

// MARK: - Session Snapshot (collector → app)

public struct SessionSnapshot: Codable, Sendable {
    public let schemaVersion: Int
    public let sessionId: String
    public let updatedAt: String
    public let transcriptPath: String?
    public let exceeds200kTokens: Bool?
    public let rateLimits: RateLimits?

    public init(
        schemaVersion: Int = 1,
        sessionId: String,
        updatedAt: String,
        transcriptPath: String?,
        exceeds200kTokens: Bool?,
        rateLimits: RateLimits?
    ) {
        self.schemaVersion = schemaVersion
        self.sessionId = sessionId
        self.updatedAt = updatedAt
        self.transcriptPath = transcriptPath
        self.exceeds200kTokens = exceeds200kTokens
        self.rateLimits = rateLimits
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sessionId = "session_id"
        case updatedAt = "updated_at"
        case transcriptPath = "transcript_path"
        case exceeds200kTokens = "exceeds_200k_tokens"
        case rateLimits = "rate_limits"
    }
}

// MARK: - Rate Limits

public struct RateLimits: Codable, Sendable {
    public let fiveHour: RateLimitWindow?
    public let sevenDay: RateLimitWindow?

    public init(fiveHour: RateLimitWindow?, sevenDay: RateLimitWindow?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        // Legacy key for backward compatibility
        case sevenDayAllModels = "seven_day_all_models"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fiveHour = try container.decodeIfPresent(RateLimitWindow.self, forKey: .fiveHour)
        // Try "seven_day" first, fall back to "seven_day_all_models" for backward compatibility
        if let sd = try container.decodeIfPresent(RateLimitWindow.self, forKey: .sevenDay) {
            self.sevenDay = sd
        } else {
            self.sevenDay = try container.decodeIfPresent(RateLimitWindow.self, forKey: .sevenDayAllModels)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(fiveHour, forKey: .fiveHour)
        try container.encodeIfPresent(sevenDay, forKey: .sevenDay)
    }
}

// MARK: - Rate Limit Window

public struct RateLimitWindow: Codable, Sendable {
    public let resetsAt: Date?
    public let usedPercentage: Double?

    public init(resetsAt: Date?, usedPercentage: Double?) {
        self.resetsAt = resetsAt
        self.usedPercentage = usedPercentage
    }

    enum CodingKeys: String, CodingKey {
        case resetsAt = "resets_at"
        // Legacy key for backward compatibility
        case resetAt = "reset_at"
        case usedPercentage = "used_percentage"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.usedPercentage = try container.decodeIfPresent(Double.self, forKey: .usedPercentage)

        // Decode resets_at: try epoch integer first, then ISO 8601 string, then legacy reset_at key
        if let epoch = try? container.decodeIfPresent(Double.self, forKey: .resetsAt) {
            self.resetsAt = Date(timeIntervalSince1970: epoch)
        } else if let epoch = try? container.decodeIfPresent(Int.self, forKey: .resetsAt) {
            self.resetsAt = Date(timeIntervalSince1970: Double(epoch))
        } else if let isoString = try? container.decodeIfPresent(String.self, forKey: .resetsAt),
                  let date = DateParsing.parseISO8601(isoString) {
            self.resetsAt = date
        } else if let epoch = try? container.decodeIfPresent(Double.self, forKey: .resetAt) {
            self.resetsAt = Date(timeIntervalSince1970: epoch)
        } else if let isoString = try? container.decodeIfPresent(String.self, forKey: .resetAt),
                  let date = DateParsing.parseISO8601(isoString) {
            self.resetsAt = date
        } else {
            self.resetsAt = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let date = resetsAt {
            try container.encode(Int(date.timeIntervalSince1970), forKey: .resetsAt)
        }
        try container.encodeIfPresent(usedPercentage, forKey: .usedPercentage)
    }
}

// MARK: - statusLine Input (Claude Code → collector)

public struct StatusLineInput: Codable, Sendable {
    public let sessionId: String
    public let transcriptPath: String?
    public let exceeds200kTokens: Bool?
    public let rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case exceeds200kTokens = "exceeds_200k_tokens"
        case rateLimits = "rate_limits"
    }
}

// MARK: - History Entry (append-only JSONL)

public struct HistoryEntry: Codable, Sendable {
    public let timestamp: String
    public let fiveHourPct: Double?
    public let sevenDayPct: Double?
    public let sessionId: String

    public init(
        timestamp: String,
        fiveHourPct: Double?,
        sevenDayPct: Double?,
        sessionId: String
    ) {
        self.timestamp = timestamp
        self.fiveHourPct = fiveHourPct
        self.sevenDayPct = sevenDayPct
        self.sessionId = sessionId
    }

    enum CodingKeys: String, CodingKey {
        case timestamp
        case fiveHourPct = "five_hour_pct"
        case sevenDayPct = "seven_day_pct"
        // Legacy key for backward compatibility
        case sevenDayAllModelsPct = "seven_day_all_models_pct"
        case sessionId = "session_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.timestamp = try container.decode(String.self, forKey: .timestamp)
        self.fiveHourPct = try container.decodeIfPresent(Double.self, forKey: .fiveHourPct)
        self.sessionId = try container.decode(String.self, forKey: .sessionId)
        // Try "seven_day_pct" first, fall back to "seven_day_all_models_pct"
        if let sd = try container.decodeIfPresent(Double.self, forKey: .sevenDayPct) {
            self.sevenDayPct = sd
        } else {
            self.sevenDayPct = try container.decodeIfPresent(Double.self, forKey: .sevenDayAllModelsPct)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(fiveHourPct, forKey: .fiveHourPct)
        try container.encodeIfPresent(sevenDayPct, forKey: .sevenDayPct)
        try container.encode(sessionId, forKey: .sessionId)
    }
}

// MARK: - JSON Coding Helpers

extension JSONEncoder {
    public static var usageBar: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    public static var usageBar: JSONDecoder {
        JSONDecoder()
    }
}
