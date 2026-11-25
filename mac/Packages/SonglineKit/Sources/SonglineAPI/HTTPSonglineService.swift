import Foundation
import SonglineCore

/// 通过 HTTP 调用本机的 Songline 后端（`songline serve`）。
public struct HTTPSonglineService: SonglineService {
    public let baseURL: URL
    private let session: URLSession
    /// 实时事件是长连接：识别一段音频可能好几分钟都没有新消息，不能用普通的超时。
    private let streamSession: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60 * 60
        config.timeoutIntervalForResource = 24 * 60 * 60
        self.streamSession = URLSession(configuration: config)
    }

    public func jobs() async throws -> [Job] {
        try await get("api/jobs")
    }

    public func job(id: String) async throws -> Job {
        try await get("api/jobs/\(id)")
    }

    public func createJob(url: String, shazam: Bool) async throws -> Job {
        struct Body: Encodable { var url: String; var options: JobOptions }
        let body = try SonglineJSON.encoder().encode(Body(url: url, options: .init(shazam: shazam)))
        return try await send("POST", "api/jobs", body: body)
    }

    public func cancelJob(id: String) async throws -> Job {
        try await send("POST", "api/jobs/\(id)/cancel")
    }

    public func deleteJob(id: String) async throws {
        _ = try await data("DELETE", "api/jobs/\(id)")
    }

    public func transcript(id: String) async throws -> [Segment] {
        try await get("api/jobs/\(id)/transcript")
    }

    public func audioURL(id: String) -> URL {
        baseURL.appending(path: "api/jobs/\(id)/audio")
    }

    public func events(id: String) -> AsyncThrowingStream<Job, Error> {
        let url = baseURL.appending(path: "api/jobs/\(id)/events")
        let session = streamSession
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(from: url)
                    try Self.check(response, body: nil)
                    for try await line in bytes.lines {
                        guard let job = try Self.parseEvent(line) else { continue }
                        continuation.yield(job)
                        if job.isFinished { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - 内部

    /// 解析一行 Server-Sent Events。只有 `data: {...}` 行带数据，其他行返回 nil。
    static func parseEvent(_ line: String) throws -> Job? {
        guard line.hasPrefix("data:") else { return nil }
        let json = line.dropFirst(5).drop(while: { $0 == " " })
        return try SonglineJSON.decoder().decode(Job.self, from: Data(json.utf8))
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await send("GET", path)
    }

    private func send<T: Decodable>(_ method: String, _ path: String, body: Data? = nil) async throws -> T {
        try SonglineJSON.decoder().decode(T.self, from: await data(method, path, body: body))
    }

    private func data(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        try Self.check(response, body: data)
        return data
    }

    static func check(_ response: URLResponse, body: Data?) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        // FastAPI 的错误格式：{"detail": "说明"}
        struct Detail: Decodable { var detail: String }
        let detail = body.flatMap { try? JSONDecoder().decode(Detail.self, from: $0).detail }
        throw SonglineAPIError.http(status: http.statusCode, detail: detail)
    }
}
