import Foundation

/// How Strata is installed on the monitored machine.
///
/// Strata ships in two flavours and they expose different APIs:
///
/// - **source build** (a manual `git clone`): the metrics live in `GET /metrics`
///   and carry the engine internals (KV cache, experts, arena).
/// - **desktop app** (the Windows application): the control layer is deeper
///   inside, so the numbers come from `GET /api/monitor`, and the static data
///   (hardware names, the model catalogue) from `GET /api/hardware` and
///   `GET /api/models`.
///
/// The app understands both. The flavour is only needed to pick the right
/// endpoint straight away - with `automatic` the client finds the working one
/// on its own.
public enum StrataFlavor: String, CaseIterable, Identifiable, Sendable {
    /// Try the known endpoints and remember the one that answered.
    case automatic
    /// A build installed from the sources: `GET /metrics`.
    case sourceBuild
    /// The desktop application: `GET /api/monitor`.
    case desktop

    public var id: String { rawValue }

    public func title(language: AppLanguage) -> String {
        Loc.string("flavor.\(rawValue)", language: language)
    }

    /// Paths to try for this flavour.
    public var paths: [String] {
        switch self {
        case .automatic: return ["/api/monitor", "/metrics"]
        case .sourceBuild: return ["/metrics"]
        case .desktop: return ["/api/monitor"]
        }
    }
}
