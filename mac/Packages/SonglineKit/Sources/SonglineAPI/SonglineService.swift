import Foundation
import SonglineCore

/// 和 Python 后端打交道的全部操作。界面只认这个协议：
/// 运行时用 `HTTPSonglineService`，预览和测试用 `MockSonglineService`。
public protocol SonglineService: Sendable {
    /// 所有识别记录，最新的在前。
    func jobs() async throws -> [Job]
    func job(id: String) async throws -> Job
    /// 新建一个识别任务。`url` 可以是 B 站链接、BV 号或分享文字。
    func createJob(url: String, shazam: Bool) async throws -> Job
    func cancelJob(id: String) async throws -> Job
    func deleteJob(id: String) async throws
    /// 语音转写（歌词）。
    func transcript(id: String) async throws -> [Segment]
    /// 任务的实时进度：每次有变化就推送一次，任务结束后流也结束。
    func events(id: String) -> AsyncThrowingStream<Job, Error>
    /// 这场回放的音频地址（支持按范围读取，可以直接交给 AVPlayer）。
    func audioURL(id: String) -> URL
}

public enum SonglineAPIError: LocalizedError, Equatable {
    /// 后端返回了错误；`detail` 是它给的中文说明（如果有）。
    case http(status: Int, detail: String?)

    public var errorDescription: String? {
        switch self {
        case let .http(status, detail): detail ?? "服务出错（HTTP \(status)）"
        }
    }
}
