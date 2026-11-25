import Foundation

/// 运行一个命令直到结束；逐行回调它的输出，同时写进日志文件。
struct Subprocess {
    var executable: URL
    var arguments: [String]
    var directory: URL?
    var environment: [String: String] = [:]

    struct Failed: LocalizedError {
        var command: String
        var status: Int32
        var tail: String
        var errorDescription: String? { "\(command) 失败（退出码 \(status)）\n\(tail)" }
    }

    /// `onLine` 在后台线程调用。
    func run(log: FileHandle?, onLine: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let collector = LineCollector(log: log, onLine: onLine)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            collector.feed(handle.availableData)
        }
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        collector.feed(pipe.fileHandleForReading.readDataToEndOfFile())
        collector.flush()
        if status != 0 {
            throw Failed(command: executable.lastPathComponent + " " + (arguments.first ?? ""),
                         status: status, tail: collector.tail())
        }
    }
}

/// 把输出切成行；保留最后几行，出错时显示给用户。
final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var recent: [String] = []
    private let log: FileHandle?
    private let onLine: @Sendable (String) -> Void

    init(log: FileHandle?, onLine: @escaping @Sendable (String) -> Void) {
        self.log = log
        self.onLine = onLine
    }

    func feed(_ data: Data) {
        guard !data.isEmpty else { return }
        log?.write(data)
        lock.lock()
        buffer.append(data)
        var lines: [String] = []
        while let nl = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...nl)
        }
        recent = Array((recent + lines).suffix(12))
        lock.unlock()
        lines.forEach(onLine)
    }

    func flush() {
        lock.lock()
        let rest = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll()
        if !rest.isEmpty { recent = Array((recent + [rest]).suffix(12)) }
        lock.unlock()
        if !rest.isEmpty { onLine(rest) }
    }

    func tail() -> String {
        lock.lock()
        defer { lock.unlock() }
        return recent.joined(separator: "\n")
    }
}
