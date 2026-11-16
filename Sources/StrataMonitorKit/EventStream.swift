import Foundation

/// Клиент Server-Sent Events.
///
/// Desktop-версия Strata отдаёт живые метрики только через поток
/// `GET /api/events`: в обычных ответах (`/api/monitor`) фаза и скорость
/// остаются пустыми. В потоке приходит событие `native`, внутри которого
/// `instances[].metrics` — полный набор метрик движка.
public final class EventStream: NSObject, URLSessionDataDelegate {
    /// Событие потока: имя и полезная нагрузка.
    public enum Event {
        case named(String, JSON)
    }

    /// Ответ сервера на попытку открыть поток.
    public private(set) var response: HTTPURLResponse?

    private let url: URL
    private var continuation: AsyncStream<Event>.Continuation?
    private var text = ""
    private var session: URLSession?
    private var task: URLSessionDataTask?

    public init(url: URL) {
        self.url = url
        super.init()
    }

    /// Открывает поток и отдаёт события. Поток закрывается при отмене.
    public func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = .infinity
            configuration.timeoutIntervalForResource = .infinity
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session

            var request = URLRequest(url: url)
            request.timeoutInterval = .infinity
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            let task = session.dataTask(with: request)
            self.task = task
            task.resume()

            continuation.onTermination = { [weak self] _ in self?.stop() }
        }
    }

    /// Закрывает поток.
    public func stop() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        continuation?.finish()
        continuation = nil
    }

    /// Сервер отдал не поток событий (например, веб-страницу) — значит,
    /// такого API у этой установки нет.
    public var isEventStream: Bool {
        guard let response else { return false }
        guard response.statusCode == 200 else { return false }
        let type = response.value(forHTTPHeaderField: "Content-Type") ?? ""
        return type.contains("text/event-stream")
    }

    // MARK: - URLSessionDataDelegate

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        self.response = response as? HTTPURLResponse
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        text += chunk.replacingOccurrences(of: "\r\n", with: "\n")
        // Кадры SSE разделены пустой строкой.
        while let range = text.range(of: "\n\n") {
            let frame = String(text[text.startIndex..<range.lowerBound])
            text = String(text[range.upperBound...])
            emit(frame: frame)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        continuation?.finish()
    }

    // MARK: - Разбор кадра

    private func emit(frame: String) {
        guard let (name, json) = EventStream.parse(frame: frame) else { return }
        continuation?.yield(.named(name, json))
    }

    /// Разбирает один кадр SSE: имя события и полезная нагрузка.
    ///
    /// Кадр - это строки до пустой строки. Комментарии (`: connected`) и
    /// строки без данных игнорируются; несколько строк `data:` соединяются
    /// переводом строки, как требует протокол.
    static func parse(frame: String) -> (name: String, json: JSON)? {
        var name = "message"
        var data = ""
        for line in frame.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("event:") {
                name = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let piece = String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
                data += data.isEmpty ? piece : "\n" + piece
            }
        }
        guard !data.isEmpty, let json = try? JSON(data: Data(data.utf8)) else { return nil }
        return (name, json)
    }
}
