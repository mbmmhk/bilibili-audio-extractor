import CryptoKit
import Foundation

/// 后端相关的文件都在哪。
public struct BackendPaths: Sendable {
    /// 打包进 App 的后端源码（`Contents/Resources/backend`，由 mac/scripts/bundle-backend.sh 复制）。
    public var source: URL
    /// 打包进 App 的 uv（`Contents/Resources/bin/uv`）。开发时可能没有，会去常见位置找。
    public var bundledUV: URL?
    /// `~/Library/Application Support/Songline`：Python 环境、安装记录、日志。
    public var support: URL

    public init(source: URL, bundledUV: URL?, support: URL) {
        self.source = source
        self.bundledUV = bundledUV
        self.support = support
    }

    /// App 运行时的默认位置。
    public static func standard(bundle: Bundle = .main) -> BackendPaths {
        let resources = bundle.resourceURL ?? bundle.bundleURL
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Songline", directoryHint: .isDirectory)
        return BackendPaths(
            source: resources.appending(path: "backend", directoryHint: .isDirectory),
            bundledUV: resources.appending(path: "bin/uv"),
            support: support
        )
    }

    public var venv: URL { support.appending(path: "venv", directoryHint: .isDirectory) }
    public var songline: URL { venv.appending(path: "bin/songline") }
    public var installStamp: URL { support.appending(path: "installed-backend.sha256") }
    public var log: URL { support.appending(path: "backend.log") }

    /// 找 uv：优先用打包进 App 的，其次是常见的安装位置。
    public func findUV(fileManager: FileManager = .default) -> URL? {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [bundledUV].compactMap { $0 } + [
            home.appending(path: ".local/bin/uv"),
            home.appending(path: ".cargo/bin/uv"),
            URL(filePath: "/opt/homebrew/bin/uv"),
            URL(filePath: "/usr/local/bin/uv"),
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    /// 后端源码和依赖锁的指纹。变了就要重新安装 Python 环境。
    public func sourceFingerprint(fileManager: FileManager = .default) throws -> String {
        var files = ["pyproject.toml", "uv.lock"].map { source.appending(path: $0) }
        if let walker = fileManager.enumerator(at: source.appending(path: "src"), includingPropertiesForKeys: nil) {
            for case let url as URL in walker where url.pathExtension == "py" { files.append(url) }
        }
        var hash = SHA256()
        for url in files.sorted(by: { $0.path < $1.path }) {
            hash.update(data: Data(url.path.dropFirst(source.path.count).utf8))
            hash.update(data: try Data(contentsOf: url))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Python 环境是否已经装好，并且和当前 App 带的后端代码一致。
    public func isInstalled(fileManager: FileManager = .default) -> Bool {
        guard fileManager.isExecutableFile(atPath: songline.path),
              let stamp = try? String(contentsOf: installStamp, encoding: .utf8),
              let current = try? sourceFingerprint(fileManager: fileManager)
        else { return false }
        return stamp.trimmingCharacters(in: .whitespacesAndNewlines) == current
    }
}
