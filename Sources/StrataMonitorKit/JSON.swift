import Foundation

/// Thin wrapper over JSONSerialization: it survives a server schema change.
/// Any missing or unexpectedly typed field simply becomes nil.
public struct JSON {
    public let value: Any?

    public init(_ value: Any?) { self.value = value }

    public init(data: Data) throws {
        self.value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    public subscript(key: String) -> JSON {
        guard let dict = value as? [String: Any] else { return JSON(nil) }
        return JSON(dict[key])
    }

    public var array: [JSON] {
        guard let items = value as? [Any] else { return [] }
        return items.map(JSON.init)
    }

    public var double: Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let text as String:
            return Double(text)
        case let flag as Bool:
            return flag ? 1 : 0
        default:
            return nil
        }
    }

    public var int: Int? {
        guard let double else { return nil }
        return Int(double)
    }

    public var string: String? {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    public var bool: Bool? {
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }

    public var isNull: Bool { value == nil || value is NSNull }

    /// The key exists (and is not null).
    public var exists: Bool { !isNull }

    /// Array of numbers with possible gaps (null), like in `history`.
    public var doubles: [Double?] { array.map(\.double) }

    /// First value with the given key anywhere in the tree.
    ///
    /// A last resort for server builds whose schema we do not know yet: the
    /// field is looked up by name, so a renamed key does not break the panel.
    public func first(where key: String) -> JSON? {
        if let dict = value as? [String: Any] {
            if let found = dict[key] { return JSON(found) }
            for nested in dict.values {
                if let found = JSON(nested).first(where: key) { return found }
            }
        } else if let items = value as? [Any] {
            for item in items {
                if let found = JSON(item).first(where: key) { return found }
            }
        }
        return nil
    }
}
