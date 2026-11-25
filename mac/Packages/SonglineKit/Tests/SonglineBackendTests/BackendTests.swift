import Foundation
import Testing
@testable import SonglineBackend

/// 在临时目录里搭一份假的后端源码。
func fakeBackend() throws -> BackendPaths {
    let root = FileManager.default.temporaryDirectory.appending(path: "songline-test-\(UUID().uuidString)")
    let source = root.appending(path: "backend")
    try FileManager.default.createDirectory(at: source.appending(path: "src/songline"), withIntermediateDirectories: true)
    try "[project]".write(to: source.appending(path: "pyproject.toml"), atomically: true, encoding: .utf8)
    try "lock".write(to: source.appending(path: "uv.lock"), atomically: true, encoding: .utf8)
    try "print(1)".write(to: source.appending(path: "src/songline/cli.py"), atomically: true, encoding: .utf8)
    return BackendPaths(source: source, bundledUV: nil, support: root.appending(path: "support"))
}

@Test func fingerprintChangesWithTheCode() throws {
    let paths = try fakeBackend()
    let before = try paths.sourceFingerprint()
    #expect(try paths.sourceFingerprint() == before)  // 稳定
    try "print(2)".write(to: paths.source.appending(path: "src/songline/cli.py"), atomically: true, encoding: .utf8)
    #expect(try paths.sourceFingerprint() != before)
}

@Test func notInstalledUntilVenvAndStampMatch() throws {
    let paths = try fakeBackend()
    #expect(!paths.isInstalled())
    let bin = paths.songline
    try FileManager.default.createDirectory(at: bin.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh".write(to: bin, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
    try "stale".write(to: paths.installStamp, atomically: true, encoding: .utf8)
    #expect(!paths.isInstalled())
    try paths.sourceFingerprint().write(to: paths.installStamp, atomically: true, encoding: .utf8)
    #expect(paths.isInstalled())
}

@Test func parsesModelProgressLines() {
    #expect(ModelProgress(line: #"{"done": 800000000, "total": 1600000000}"#)?.fraction == 0.5)
    #expect(ModelProgress(line: #"{"done": 5, "total": 0}"#)?.fraction == nil)
    #expect(ModelProgress(line: "Fetching 4 files") == nil)
    #expect(ModelProgress(line: #"{"done": 430000000, "total": 1600000000}"#)?.description.contains("0.43 / 1.60 GB") == true)
}

@Test func subprocessReportsLinesAndFailures() async throws {
    let lines = LockedLines()
    try await Subprocess(executable: URL(filePath: "/bin/sh"), arguments: ["-c", "echo one; echo two"])
        .run(log: nil) { lines.append($0) }
    #expect(lines.all == ["one", "two"])
    await #expect(throws: Subprocess.Failed.self) {
        try await Subprocess(executable: URL(filePath: "/bin/sh"), arguments: ["-c", "echo boom; exit 3"]).run(log: nil)
    }
}

final class LockedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func append(_ s: String) { lock.lock(); lines.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return lines }
}
