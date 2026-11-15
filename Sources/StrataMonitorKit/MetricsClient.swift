import Foundation

/// HTTP client for Strata metrics.
public struct MetricsClient {
    public enum ClientError: LocalizedError {
        case badURL(String)
        case badStatus(Int)
        case emptyBody

        public var errorDescription: String? {
            switch self {
            case .badURL(let text): return "Некорректный адрес: \(text)"
            case .badStatus(let code): return "Сервер ответил HTTP \(code)"
            case .emptyBody: return "Пустой ответ сервера"
            }
        }
    }

    public let endpoint: URL

    public init(endpoint: URL) {
        self.endpoint = endpoint
    }

    public func fetch() async throws -> MetricsPayload {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.badStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw ClientError.emptyBody }
        return MetricsPayload(root: try JSON(data: data))
    }
}
