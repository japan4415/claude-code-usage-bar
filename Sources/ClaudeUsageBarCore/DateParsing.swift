import Foundation

/// Shared ISO 8601 date parsing utilities used across the app.
public enum DateParsing {
    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Standard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parse an ISO 8601 date string, trying fractional seconds first, then standard.
    public static func parseISO8601(_ string: String) -> Date? {
        iso8601WithFractional.date(from: string)
            ?? iso8601Standard.date(from: string)
    }

    /// Format a Date as ISO 8601 string (standard, no fractional seconds).
    public static func formatISO8601(_ date: Date) -> String {
        iso8601Standard.string(from: date)
    }
}
