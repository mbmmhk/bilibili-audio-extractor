import Foundation

/// 可以播放的一首歌：某场回放音频里的一段。
public struct Track: Sendable, Hashable, Identifiable, Codable {
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
    /// 来自哪个 B 站视频的哪一 P。收藏靠它对应回原视频（任务删了重识别，jobID 会变）。
    public var bvid: String?
    public var page: Int

    public var id: String { "\(jobID)#\(index)" }
    public var duration: Double { max(0, end - start) }

    public init(
        jobID: String, index: Int, start: Double, end: Double, title: String, artist: String,
        albumTitle: String, coverURL: URL? = nil, bvid: String? = nil, page: Int = 1
    ) {
        self.jobID = jobID
        self.index = index
        self.start = start
        self.end = end
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.coverURL = coverURL
        self.bvid = bvid
        self.page = page
    }
}

extension Job {
    /// 这张歌单里的所有歌，按时间顺序。
    public var tracks: [Track] {
        timeline.enumerated().map { i, e in
            Track(
                jobID: id, index: i, start: e.start, end: e.end, title: e.title, artist: e.artist,
                albumTitle: title, coverURL: video?.coverURL, bvid: video?.bvid, page: video?.page ?? 1
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
    public var next: Track? { position.flatMap { $0 + 1 < items.count ? items[$0 + 1] : nil } }
    /// 当前这首之后还要播的歌。
    public var upcoming: ArraySlice<Track> { position.map { items[($0 + 1)...] } ?? items[...] }

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

    // MARK: - 编辑队列

    /// 跳到队列里的第 `index` 首。
    public mutating func jump(to index: Int) -> Track? {
        guard items.indices.contains(index) else { return nil }
        position = index
        return items[index]
    }

    /// 「下一首播放」：插在当前这首后面。没在播放时插在最前面。
    public mutating func insertNext(_ tracks: [Track]) {
        items.insert(contentsOf: tracks, at: position.map { $0 + 1 } ?? 0)
    }

    /// 「添加到播放队列」：放到最后。
    public mutating func append(_ tracks: [Track]) {
        items.append(contentsOf: tracks)
    }

    /// 从队列里移除一首。正在播放的那首不能移除，返回 false。
    @discardableResult
    public mutating func remove(at index: Int) -> Bool {
        guard items.indices.contains(index), index != position else { return false }
        items.remove(at: index)
        if let p = position, index < p { position = p - 1 }
        return true
    }

    /// 调整顺序：把第 `from` 首挪到第 `to` 个位置（挪完之后它的下标是 `to`）。正在播放的那首跟着走。
    public mutating func move(from: Int, to: Int) {
        guard items.indices.contains(from), items.indices.contains(to), from != to else { return }
        let playing = current?.id
        items.insert(items.remove(at: from), at: to)
        if let playing { position = items.firstIndex { $0.id == playing } }
    }

    /// 清空后面还没播的歌，只留下正在播放的那首。
    public mutating func clearUpcoming() {
        guard let p = position else { items.removeAll(); return }
        items = [items[p]]
        position = 0
    }
}

/// 一首歌播完之后怎么办。
public enum PlaybackMode: String, Sendable, Codable, CaseIterable {
    /// 只听歌：一首播完直接跳到下一首，跳过中间的聊天。
    case songsOnly
    /// 整场：按原样往下播，歌与歌之间的聊天也播。
    case wholeStream
}

/// 播放器每次报告进度时应该做什么。纯逻辑，方便测试。
public enum TickAction: Equatable, Sendable {
    case none
    /// 已经自然播到了队列里的下一首（整场模式），只需要更新「当前歌曲」，不用跳转。
    case enteredNext
    /// 跳到下一首的开头。
    case jumpToNext
    /// 队列播完了，停下。
    case stop

    /// `time`：在当前回放音频里的位置（秒）。
    public static func at(time: Double, queue: TrackQueue, mode: PlaybackMode) -> TickAction {
        guard let current = queue.current else { return .none }
        let next = queue.next
        // 整场模式：下一首就在同一场回放、而且在后面，那就照常往下播，播到它开头时算进入下一首。
        if mode == .wholeStream, let next, next.jobID == current.jobID, next.start >= current.end {
            return time >= next.start ? .enteredNext : .none
        }
        guard time >= current.end else { return .none }
        return next == nil ? (mode == .wholeStream ? .none : .stop) : .jumpToNext
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
