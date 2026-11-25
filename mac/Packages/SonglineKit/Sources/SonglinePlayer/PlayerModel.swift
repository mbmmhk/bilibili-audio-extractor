import AVFoundation
import Observation
import SonglineCore

/// 播放器：一首歌 = 某场回放音频里的一段。
///
/// 一首播完怎么办由 `mode` 决定：只听歌模式直接跳到下一首，整场模式按原样往下播。
/// 切歌规则都在 `SonglineCore` 的 `TrackQueue` 和 `TickAction` 里，这里只负责驱动 AVPlayer。
@MainActor @Observable
public final class PlayerModel {
    public private(set) var queue = TrackQueue()
    public private(set) var isPlaying = false
    /// 在整场回放音频里的位置（秒）。
    public private(set) var time: Double = 0
    public var mode: PlaybackMode = .songsOnly

    public var current: Track? { queue.current }
    /// 当前这首已经播了多少秒（0...时长）。
    public var elapsed: Double { current.map { min(max(0, time - $0.start), $0.duration) } ?? 0 }
    /// 整场模式下，当前这首已经唱完、正在播歌与歌之间的聊天。
    public var isBetweenSongs: Bool { current.map { time > $0.end } ?? false }

    /// 每开始播一首新歌时调用（用来记录最近播放）。
    @ObservationIgnored public var onTrackStart: ((Track) -> Void)?

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private let audioURL: @Sendable (String) -> URL
    @ObservationIgnored private var loadedJobID: String?
    @ObservationIgnored private var seeking = false
    @ObservationIgnored private var nowPlaying: NowPlayingCenter?

    /// - Parameters:
    ///   - audioURL: 给定回放（任务）id，返回它的音频地址。
    ///   - systemIntegration: 接入媒体键和控制中心的「正在播放」。测试和预览里关掉。
    public init(audioURL: @escaping @Sendable (String) -> URL, systemIntegration: Bool = true) {
        self.audioURL = audioURL
        player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) {
            [weak self] t in
            MainActor.assumeIsolated { self?.tick(t.seconds) }
        }
        if systemIntegration { nowPlaying = NowPlayingCenter(player: self) }
    }

    // MARK: - 播放控制

    /// 用 `tracks` 替换播放队列，从第 `index` 首开始播。
    public func play(_ tracks: [Track], startAt index: Int = 0) {
        queue = TrackQueue(items: tracks, position: index)
        if let track = queue.current { start(track) }
    }

    public func togglePlay() {
        if isPlaying { pause() } else { resume() }
    }

    public func pause() {
        player.pause()
        isPlaying = false
        nowPlaying?.update()
    }

    public func resume() {
        guard current != nil else { return }
        player.play()
        isPlaying = true
        nowPlaying?.update()
    }

    public func next() {
        if let track = queue.advance() { start(track) }
    }

    public func previous() {
        switch queue.back(elapsed: elapsed) {
        case let .restart(track): load(track, from: track.start)
        case let .previous(track): start(track)
        case nil: break
        }
    }

    /// 跳到当前这首的某个位置，`fraction` 是 0...1。
    public func seek(toFraction fraction: Double) {
        guard let track = current else { return }
        seek(to: track.start + track.duration * min(max(fraction, 0), 1))
    }

    /// 跳到当前回放音频的任意位置（秒），比如在歌词页点某一句。
    public func seek(to position: Double) {
        time = position
        seeking = true
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) {
            [weak self] _ in
            Task { @MainActor in
                self?.seeking = false
                self?.nowPlaying?.update()
            }
        }
    }

    // MARK: - 播放队列

    /// 「下一首播放」。没在播放时直接开始播。
    public func playNext(_ tracks: [Track]) {
        guard current != nil else { return play(tracks) }
        queue.insertNext(tracks)
    }

    /// 「添加到播放队列」。没在播放时直接开始播。
    public func addToQueue(_ tracks: [Track]) {
        guard current != nil else { return play(tracks) }
        queue.append(tracks)
    }

    /// 跳到队列里的第 `index` 首播放。
    public func playQueueItem(at index: Int) {
        if let track = queue.jump(to: index) { start(track) }
    }

    /// 从队列里移除。正在播放的那首移不掉，返回 false。
    @discardableResult
    public func removeFromQueue(at index: Int) -> Bool { queue.remove(at: index) }

    public func moveInQueue(from: Int, to: Int) { queue.move(from: from, to: to) }

    public func clearUpcoming() { queue.clearUpcoming() }

    // MARK: - 内部

    /// 开始播一首新歌（从开头）。
    private func start(_ track: Track) {
        load(track, from: track.start)
        onTrackStart?(track)
    }

    private func load(_ track: Track, from position: Double) {
        if loadedJobID != track.jobID {
            player.replaceCurrentItem(with: AVPlayerItem(url: audioURL(track.jobID)))
            loadedJobID = track.jobID
        }
        seek(to: position)
        resume()
        nowPlaying?.trackChanged()
    }

    private func tick(_ seconds: Double) {
        guard !seeking, seconds.isFinite else { return }
        time = seconds
        isPlaying = player.timeControlStatus != .paused
        switch TickAction.at(time: seconds, queue: queue, mode: mode) {
        case .none: break
        case .enteredNext:
            if let track = queue.advance() {
                onTrackStart?(track)
                nowPlaying?.trackChanged()
            }
        case .jumpToNext: next()
        case .stop: pause()
        }
    }
}
