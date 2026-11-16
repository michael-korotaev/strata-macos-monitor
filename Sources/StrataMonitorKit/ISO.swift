import Foundation

/// Dates in the format the server sends them ("2026-11-16T22:01:12.177Z").
enum ISO {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        return withFraction.date(from: text) ?? plain.date(from: text)
    }
}
