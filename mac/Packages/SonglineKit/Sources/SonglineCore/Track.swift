import Foundation

/// 可以播放的一首歌：某场回放音频里的一段。
public struct Track: Sendable, Hashable, Identifiable {
    public var jobID: String
    /// 在这场回放时间线里的序号（从 0 开始）。
    public var index: Int
    public var start: Double
    public var end: Double
    public var title: String
    public var artist: String
    /// 所属歌单（直播回放）的标题和封面。
    public var albumTitle: String
    public var coverURL: URL?

    public var id: String { "\(jobID)#\(index)" }
    public var duration: Double { max(0, end - start) }

    public init(
        jobID: String, index: Int, start: Double, end: Double, title: String, artist: String,
        albumTitle: String, coverURL: URL? = nil
    ) {
        self.jobID = jobID
        self.index = index
        self.start = start
        self.end = end
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.coverURL = coverURL
    }
}

extension Job {
    /// 这张歌单里的所有歌，按时间顺序。
    public var tracks: [Track] {
        timeline.enumerated().map { i, e in
            Track(
                jobID: id, index: i, start: e.start, end: e.end, title: e.title, artist: e.artist,
                albumTitle: title, coverURL: video?.coverURL
            )
        }
    }
}

/// 播放队列的规则。纯逻辑，不碰播放器，方便测试。
public struct TrackQueue: Sendable, Equatable {
    public private(set) var items: [Track]
    public private(set) var position: Int?

    /// 点「上一首」时，当前歌播放超过这么多秒就回到开头，否则才切到上一首（音乐播放器的惯例）。
    public static let restartThreshold: Double = 3

    public init(items: [Track] = [], position: Int? = nil) {
        self.items = items
        self.position = position.flatMap { items.indices.contains($0) ? $0 : nil }
    }

    public var current: Track? { position.map { items[$0] } }
    public var hasNext: Bool { position.map { $0 + 1 < items.count } ?? false }

    /// 切到下一首；已经是最后一首时返回 nil，队列不变。
    public mutating func advance() -> Track? {
        guard let p = position, p + 1 < items.count else { return nil }
        position = p + 1
        return items[p + 1]
    }

    public enum Back: Equatable { case restart(Track), previous(Track) }

    /// 「上一首」：`elapsed` 是当前这首已经播了多少秒。
    public mutating func back(elapsed: Double) -> Back? {
        guard let p = position else { return nil }
        if elapsed > Self.restartThreshold || p == 0 { return .restart(items[p]) }
        position = p - 1
        return .previous(items[p - 1])
    }
}

/// 把秒数格式化成 03:25 或 1:02:03。
public func formatTime(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.isFinite ? seconds : 0))
    let (h, m, sec) = (s / 3600, s % 3600 / 60, s % 60)
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, sec)
        : String(format: "%02d:%02d", m, sec)
}
