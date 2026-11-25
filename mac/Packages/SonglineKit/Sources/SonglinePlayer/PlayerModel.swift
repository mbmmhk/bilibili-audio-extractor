import AVFoundation
import Observation
import SonglineCore

/// 播放器：一首歌 = 某场回放音频里的一段，播到这首的结尾就自动切下一首。
@MainActor @Observable
public final class PlayerModel {
    public private(set) var queue = TrackQueue()
    public private(set) var isPlaying = false
    /// 在整场回放音频里的位置（秒）。
    public private(set) var time: Double = 0

    public var current: Track? { queue.current }
    /// 当前这首已经播了多少秒。
    public var elapsed: Double { current.map { min(max(0, time - $0.start), $0.duration) } ?? 0 }

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private let audioURL: @Sendable (String) -> URL
    @ObservationIgnored private var loadedJobID: String?
    @ObservationIgnored private var seeking = false

    /// `audioURL`：给定回放（任务）id，返回它的音频地址。
    public init(audioURL: @escaping @Sendable (String) -> URL) {
        self.audioURL = audioURL
        player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) {
            [weak self] t in
            MainActor.assumeIsolated { self?.tick(t.seconds) }
        }
    }

    /// 从 `tracks` 的第 `index` 首开始播放，后面的歌依次排进队列。
    public func play(_ tracks: [Track], startAt index: Int = 0) {
        queue = TrackQueue(items: tracks, position: index)
        if let track = queue.current { load(track, from: track.start) }
    }

    public func togglePlay() {
        guard current != nil else { return }
        if isPlaying { pause() } else { resume() }
    }

    public func pause() {
        player.pause()
        isPlaying = false
    }

    public func resume() {
        guard current != nil else { return }
        player.play()
        isPlaying = true
    }

    public func next() {
        if let track = queue.advance() { load(track, from: track.start) }
    }

    public func previous() {
        switch queue.back(elapsed: elapsed) {
        case let .restart(track), let .previous(track): load(track, from: track.start)
        case nil: break
        }
    }

    /// 跳到当前这首的某个位置，`fraction` 是 0...1。
    public func seek(toFraction fraction: Double) {
        guard let track = current else { return }
        seek(to: track.start + track.duration * min(max(fraction, 0), 1))
    }

    // MARK: - 内部

    private func load(_ track: Track, from position: Double) {
        if loadedJobID != track.jobID {
            player.replaceCurrentItem(with: AVPlayerItem(url: audioURL(track.jobID)))
            loadedJobID = track.jobID
        }
        seek(to: position)
        resume()
    }

    private func seek(to position: Double) {
        time = position
        seeking = true
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) {
            [weak self] _ in
            Task { @MainActor in self?.seeking = false }
        }
    }

    private func tick(_ seconds: Double) {
        guard !seeking, seconds.isFinite else { return }
        time = seconds
        isPlaying = player.timeControlStatus != .paused
        // 播到这首歌的结尾：切下一首；已经是最后一首就停下。
        if let track = current, seconds >= track.end {
            if queue.hasNext { next() } else { pause() }
        }
    }
}
