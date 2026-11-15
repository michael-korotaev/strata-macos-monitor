import Foundation

/// Number and interval formatting for the interface.
public enum Format {
    public static func number(_ value: Double?, _ digits: Int = 1) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(digits)f", value)
    }

    public static func integer(_ value: Int?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.grouping(.automatic))
    }

    public static func percent(_ value: Double?, _ digits: Int = 0) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(digits)f%%", value)
    }

    public static func bytes(_ value: Int64?) -> String {
        guard let value else { return "—" }
        let gib = Double(value) / 1_073_741_824
        return String(format: "%.1f GiB", gib)
    }

    public static func gib(_ value: Int64?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f", Double(value) / 1_073_741_824)
    }

    /// "2h 41m" / "3d 4h" / "59s".
    public static func duration(_ seconds: Double?, language: AppLanguage = .russian) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        switch language {
        case .russian:
            if days > 0 { return "\(days)д \(hours)ч" }
            if hours > 0 { return "\(hours)ч \(minutes)м" }
            if minutes > 0 { return "\(minutes)м \(total % 60)с" }
            return "\(total)с"
        case .english:
            if days > 0 { return "\(days)d \(hours)h" }
            if hours > 0 { return "\(hours)h \(minutes)m" }
            if minutes > 0 { return "\(minutes)m \(total % 60)s" }
            return "\(total)s"
        }
    }

    public static func seconds(_ value: Double?, language: AppLanguage = .russian) -> String {
        guard let value else { return "—" }
        switch language {
        case .russian: return String(format: "%.2f с", value)
        case .english: return String(format: "%.2f s", value)
        }
    }

    public static func clock(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    public static func tokens(_ value: Int64?) -> String {
        guard let value else { return "—" }
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return String(value)
    }
}
