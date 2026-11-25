import Foundation
import SonglineCore

/// 假数据，给 SwiftUI 预览和测试用：不需要启动 Python 后端。
public struct MockSonglineService: SonglineService {
    public var sampleJobs: [Job]

    public init(jobs: [Job] = MockSonglineService.samples) {
        self.sampleJobs = jobs
    }

    public func jobs() async throws -> [Job] { sampleJobs }

    public func job(id: String) async throws -> Job {
        guard let job = sampleJobs.first(where: { $0.id == id }) else {
            throw SonglineAPIError.http(status: 404, detail: "任务不存在")
        }
        return job
    }

    public func createJob(url: String, shazam: Bool) async throws -> Job {
        Job(id: UUID().uuidString, url: url, options: .init(shazam: shazam), stage: .queued, message: "排队中",
            createdAt: Date().timeIntervalSince1970)
    }

    public func cancelJob(id: String) async throws -> Job {
        var job = try await job(id: id)
        job.stage = .cancelled
        return job
    }

    public func deleteJob(id: String) async throws {}

    public func transcript(id: String) async throws -> [Segment] {
        [
            Segment(start: 60, end: 64, text: "今夜的风悄悄月悄悄"),
            Segment(start: 64, end: 68, text: "吻你的眉梢"),
            Segment(start: 68, end: 72, text: "且把酒满倒人醉倒"),
        ]
    }

    public func events(id: String) -> AsyncThrowingStream<Job, Error> {
        let job = sampleJobs.first { $0.id == id }
        return AsyncThrowingStream { continuation in
            if let job { continuation.yield(job) }
            continuation.finish()
        }
    }

    public func audioURL(id: String) -> URL {
        URL(string: "http://127.0.0.1:8765/api/jobs/\(id)/audio")!
    }
}

extension MockSonglineService {
    public static let samples: [Job] = [
        Job(
            id: "demo-1119", url: "https://www.bilibili.com/video/BV1s6sa6aExh", stage: .done, progress: 1,
            message: "完成：识别出 4 首",
            video: VideoInfo(bvid: "BV1s6sa6aExh", title: "2026-11-19 直播回放（晚上）", owner: "示例主播", duration: 4302),
            timeline: [
                TimelineEntry(start: 60, end: 290, song: SongRef(title: "小星星", artist: "汪苏泷"), confidence: 0.95),
                TimelineEntry(start: 480, end: 720, song: SongRef(title: "遇见", artist: "孙燕姿"), confidence: 0.9),
                TimelineEntry(start: 840, end: 1020, song: SongRef(title: "浪漫爱", artist: "刘瑞琦"), confidence: 0.85),
                TimelineEntry(start: 1100, end: 1160, song: nil, confidence: 0.4),
            ],
            createdAt: 1_795_500_000
        ),
        Job(
            id: "demo-running", url: "https://www.bilibili.com/video/BV1CK1FzMEU8", stage: .transcribing,
            progress: 0.42, message: "识别歌词 18:20 / 45:40",
            video: VideoInfo(bvid: "BV1CK1FzMEU8", title: "2026-11-24 直播回放", owner: "示例主播", duration: 2740),
            timeline: [
                TimelineEntry(start: 30, end: 250, song: SongRef(title: "风月吻眉梢", artist: "礼越"), confidence: 0.8),
            ],
            createdAt: 1_795_600_000
        ),
        Job(
            id: "demo-failed", url: "https://www.bilibili.com/video/BV1xx411c7mD", stage: .failed,
            error: "B 站暂时没有返回视频信息（网络不稳定，或请求太频繁被临时限制），请稍等一会儿再点「重新识别」。原因：HTTP 412",
            createdAt: 1_795_400_000
        ),
    ]
}
