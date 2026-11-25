import Foundation
import Observation
import os

/// 后端现在处于哪一步。界面完全根据它决定显示什么。
public enum BackendState: Sendable, Equatable {
    case idle
    /// 首次安装中。`progress` 为 nil 表示无法估计进度。
    case installing(step: String, progress: Double?)
    case starting
    case running(URL)
    /// `detail` 是给开发者看的输出尾部，完整内容在日志文件里。
    case failed(message: String, detail: String)
}

/// 管理 Python 后端：首次安装、启动 `songline serve`、意外退出时重启、App 退出时关闭。
@MainActor @Observable
public final class BackendRuntime {
    public private(set) var state: BackendState = .idle
    public let paths: BackendPaths
    public let port: Int

    public var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    @ObservationIgnored private var server: Process?
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var restarts = 0
    @ObservationIgnored private let logger = Logger(subsystem: "app.songline", category: "backend")

    /// 后端意外退出后最多自动重启几次。
    static let maxRestarts = 3

    public init(paths: BackendPaths = .standard(), port: Int = 8765) {
        self.paths = paths
        self.port = port
    }

    /// 准备好后端并启动。可以重复调用（比如出错后点「重试」）。
    public func start() async {
        if case .running = state { return }
        stopping = false
        state = .starting

        // 已经有一个 Songline 在跑（比如命令行版），直接用它。
        if await isHealthy() {
            logger.info("attaching to the backend already running on \(self.port)")
            state = .running(baseURL)
            return
        }
        do {
            try FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
            try await installIfNeeded()
            try await downloadModelIfNeeded()
            state = .starting
            try launchServer()
            try await waitUntilHealthy(timeout: 90)
            restarts = 0
            state = .running(baseURL)
        } catch {
            logger.error("backend failed: \(error.localizedDescription)")
            stopServer()
            state = .failed(message: Self.friendly(error), detail: error.localizedDescription)
        }
    }

    /// App 退出时调用：先礼貌地请后端退出，3 秒后还没退出就强制结束。
    public func stop() {
        stopping = true
        stopServer()
    }

    // MARK: - 安装

    private func installIfNeeded() async throws {
        guard !paths.isInstalled() else { return }
        guard let uv = paths.findUV() else { throw BackendError.uvMissing }
        guard FileManager.default.fileExists(atPath: paths.source.appending(path: "pyproject.toml").path) else {
            throw BackendError.sourceMissing(paths.source.path)
        }
        state = .installing(step: "安装 Python 和依赖（首次需要几分钟）", progress: nil)
        let fingerprint = try paths.sourceFingerprint()
        try await Subprocess(
            executable: uv,
            arguments: ["sync", "--locked", "--no-dev", "--no-editable", "--quiet"],
            directory: paths.source,
            environment: ["UV_PROJECT_ENVIRONMENT": paths.venv.path]
        ).run(log: openLog())
        try fingerprint.write(to: paths.installStamp, atomically: true, encoding: .utf8)
    }

    private func downloadModelIfNeeded() async throws {
        // 模型已经下好时，这条命令立刻结束、什么也不输出。
        try await Subprocess(executable: paths.songline, arguments: ["setup", "--json-progress"])
            .run(log: openLog()) { [weak self] line in
                guard let p = ModelProgress(line: line) else { return }
                Task { @MainActor in
                    self?.state = .installing(step: p.description, progress: p.fraction)
                }
            }
    }

    // MARK: - 运行

    private func launchServer() throws {
        let process = Process()
        process.executableURL = paths.songline
        process.arguments = ["serve", "--no-open", "--port", String(port)]
        let log = openLog()
        process.standardOutput = log
        process.standardError = log
        process.terminationHandler = { [weak self] p in
            let status = p.terminationStatus
            Task { @MainActor in self?.serverExited(status: status) }
        }
        try process.run()
        server = process
    }

    private func serverExited(status: Int32) {
        server = nil
        guard !stopping else { return }
        logger.error("backend exited unexpectedly (status \(status))")
        guard restarts < Self.maxRestarts else {
            state = .failed(message: "识别服务反复意外退出", detail: "退出码 \(status)，详情见日志")
            return
        }
        restarts += 1
        state = .starting
        Task { await start() }
    }

    private func stopServer() {
        guard let process = server, process.isRunning else { return }
        process.terminate()  // SIGTERM
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning, Date() < deadline { usleep(50_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        server = nil
    }

    private func isHealthy() async -> Bool {
        var request = URLRequest(url: baseURL.appending(path: "api/jobs"))
        request.timeoutInterval = 1
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    private func waitUntilHealthy(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await isHealthy() { return }
            if let server, !server.isRunning { throw BackendError.serverExited }
            try await Task.sleep(for: .milliseconds(300))
        }
        throw BackendError.serverTimeout
    }

    private func openLog() -> FileHandle? {
        let fm = FileManager.default
        if !fm.fileExists(atPath: paths.log.path) { fm.createFile(atPath: paths.log.path, contents: nil) }
        let handle = try? FileHandle(forWritingTo: paths.log)
        _ = try? handle?.seekToEnd()
        return handle
    }

    static func friendly(_ error: Error) -> String {
        switch error {
        case let e as BackendError: e.errorDescription ?? "启动失败"
        case is Subprocess.Failed: "安装没有完成，多半是网络问题。可以点「重试」，已经下载的部分不会重新下载。"
        default: error.localizedDescription
        }
    }
}

enum BackendError: LocalizedError {
    case uvMissing
    case sourceMissing(String)
    case serverExited
    case serverTimeout

    var errorDescription: String? {
        switch self {
        case .uvMissing: "找不到 uv（Python 环境管理工具）。App 里本应自带；开发时请先安装 uv。"
        case let .sourceMissing(path): "App 里缺少后端代码：\(path)"
        case .serverExited: "识别服务启动后马上退出了"
        case .serverTimeout: "识别服务启动超时"
        }
    }
}

/// `songline setup --json-progress` 输出的一行：{"done": 字节, "total": 字节}
struct ModelProgress: Equatable {
    var done: Int
    var total: Int

    init?(line: String) {
        struct Raw: Decodable { var done: Int; var total: Int }
        guard let raw = try? JSONDecoder().decode(Raw.self, from: Data(line.utf8)) else { return nil }
        done = raw.done
        total = raw.total
    }

    var fraction: Double? { total > 0 ? min(1, Double(done) / Double(total)) : nil }

    var description: String {
        let gb = { (b: Int) in String(format: "%.2f", Double(b) / 1e9) }
        let size = total > 0 ? "\(gb(done)) / \(gb(total)) GB" : "\(gb(done)) GB"
        return "下载语音识别模型 \(size)（只需一次）"
    }
}
