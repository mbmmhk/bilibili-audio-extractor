import AppKit
import MediaPlayer
import SonglineCore

/// 接入系统：键盘媒体键、耳机按键、控制中心和锁屏的「正在播放」。
/// 显示的进度是「这首歌」的，不是整场回放的。
@MainActor
final class NowPlayingCenter {
    private weak var player: PlayerModel?
    private var artworkTask: Task<Void, Never>?
    private var artwork: MPMediaItemArtwork?

    init(player: PlayerModel) {
        self.player = player
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in self?.run { $0.resume() } ?? .commandFailed }
        commands.pauseCommand.addTarget { [weak self] _ in self?.run { $0.pause() } ?? .commandFailed }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in self?.run { $0.togglePlay() } ?? .commandFailed }
        commands.nextTrackCommand.addTarget { [weak self] _ in self?.run { $0.next() } ?? .commandFailed }
        commands.previousTrackCommand.addTarget { [weak self] _ in self?.run { $0.previous() } ?? .commandFailed }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            return self?.run { p in
                if let d = p.current?.duration, d > 0 { p.seek(toFraction: position / d) }
            } ?? .commandFailed
        }
    }

    /// 系统的回调可能不在主线程上，这里统一切回主线程执行。
    private nonisolated func run(_ action: @escaping @MainActor (PlayerModel) -> Void) -> MPRemoteCommandHandlerStatus {
        Task { @MainActor [weak self] in
            if let player = self?.player { action(player) }
        }
        return .success
    }

    /// 换歌了：更新歌名并重新加载封面。
    func trackChanged() {
        artwork = nil
        artworkTask?.cancel()
        update()
        guard let url = player?.current?.coverURL else { return }
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data), !Task.isCancelled else { return }
            let box = ImageBox(image: image)
            self?.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in box.image }
            self?.update()
        }
    }

    /// 播放状态或进度变了。
    func update() {
        let center = MPNowPlayingInfoCenter.default()
        guard let player, let track = player.current else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.albumTitle,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? 1.0 : 0.0,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        center.nowPlayingInfo = info
        center.playbackState = player.isPlaying ? .playing : .paused
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = player.queue.hasNext
    }
}

/// 封面图交给系统时要跨线程。图片加载完就不再改动，所以可以安全共享。
/// （新版 SDK 里 NSImage 已经是 Sendable，旧版还不是，用这个包装两边都能编译。）
private final class ImageBox: @unchecked Sendable {
    let image: NSImage
    init(image: NSImage) { self.image = image }
}
