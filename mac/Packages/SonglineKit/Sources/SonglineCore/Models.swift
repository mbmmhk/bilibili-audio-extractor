import Foundation

// 与 Python 后端（backend/src/songline/models.py）的 JSON 一一对应。
// 字段名用 Swift 风格，解码时自动从 snake_case 转换（见 SonglineJSON）。

/// 识别任务进行到哪一步。
public enum Stage: String, Codable, Sendable, CaseIterable {
    case queued, resolving, downloading, transcribing, matching, verifying, done, failed, cancelled
    /// 后端以后加了新阶段、这边还不认识时用它，不至于整条记录解析失败。
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Stage(rawValue: raw) ?? .unknown
    }

    public var isFinished: Bool { self == .done || self == .failed || self == .cancelled }
}

public struct JobOptions: Codable, Sendable, Hashable {
    public var shazam: Bool
    public init(shazam: Bool = true) { self.shazam = shazam }
}

public struct VideoPage: Codable, Sendable, Hashable {
    public var page: Int
    public var cid: Int
    public var title: String
    public var duration: Int

    public init(page: Int, cid: Int, title: String, duration: Int) {
        self.page = page
        self.cid = cid
        self.title = title
        self.duration = duration
    }
}

public struct VideoInfo: Codable, Sendable, Hashable {
    public var bvid: String
    public var aid: Int
    public var title: String
    public var owner: String
    public var cover: String
    public var duration: Int
    public var page: Int
    public var pages: [VideoPage]
    public var description: String

    public init(
        bvid: String, aid: Int = 0, title: String, owner: String, cover: String = "",
        duration: Int, page: Int = 1, pages: [VideoPage] = [], description: String = ""
    ) {
        self.bvid = bvid
        self.aid = aid
        self.title = title
        self.owner = owner
        self.cover = cover
        self.duration = duration
        self.page = page
        self.pages = pages
        self.description = description
    }

    public var coverURL: URL? { URL(string: cover) }
}

/// 一首歌（标题 + 原唱）。
public struct SongRef: Codable, Sendable, Hashable {
    public var title: String
    public var artist: String
    public var neteaseId: Int?

    public init(title: String, artist: String, neteaseId: Int? = nil) {
        self.title = title
        self.artist = artist
        self.neteaseId = neteaseId
    }
}

/// 时间线上的一段：通常是一首歌。
public struct TimelineEntry: Codable, Sendable, Hashable {
    public var start: Double
    public var end: Double
    /// nil = 检测到在唱歌，但没认出是哪首。
    public var song: SongRef?
    public var confidence: Double
    public var sources: [String]
    public var evidence: String
    public var alternatives: [SongRef]

    public init(
        start: Double, end: Double, song: SongRef?, confidence: Double = 1,
        sources: [String] = ["lyrics"], evidence: String = "", alternatives: [SongRef] = []
    ) {
        self.start = start
        self.end = end
        self.song = song
        self.confidence = confidence
        self.sources = sources
        self.evidence = evidence
        self.alternatives = alternatives
    }

    public var duration: Double { max(0, end - start) }
    public var title: String { song?.title ?? "未识别" }
    public var artist: String { song?.artist ?? "" }
}

/// 一句语音转写（歌词或聊天）。
public struct Segment: Codable, Sendable, Hashable {
    public var start: Double
    public var end: Double
    public var text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// 一次识别任务，也就是播放器里的一张「歌单」。
public struct Job: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var url: String
    public var options: JobOptions
    public var stage: Stage
    /// 整个任务的进度，0...1。
    public var progress: Double
    public var message: String
    public var error: String?
    public var video: VideoInfo?
    public var timeline: [TimelineEntry]
    public var createdAt: Double
    public var updatedAt: Double

    public init(
        id: String, url: String, options: JobOptions = .init(), stage: Stage, progress: Double = 0,
        message: String = "", error: String? = nil, video: VideoInfo? = nil,
        timeline: [TimelineEntry] = [], createdAt: Double, updatedAt: Double? = nil
    ) {
        self.id = id
        self.url = url
        self.options = options
        self.stage = stage
        self.progress = progress
        self.message = message
        self.error = error
        self.video = video
        self.timeline = timeline
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public var isFinished: Bool { stage.isFinished }
    public var title: String { video?.title ?? "解析中…" }
    public var createdDate: Date { Date(timeIntervalSince1970: createdAt) }
}

/// 和后端约定好的 JSON 编解码设置。
public enum SonglineJSON {
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }
}
