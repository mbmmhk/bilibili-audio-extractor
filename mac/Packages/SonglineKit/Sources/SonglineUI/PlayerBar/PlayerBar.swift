import SonglineCore
import SonglinePlayer
import SonglineState
import SwiftUI

/// 窗口底部的播放条。
struct PlayerBar: View {
    var player: PlayerModel
    /// 拖动进度条时的临时位置（0...1），松手才真正跳转。
    @State private var scrubbing: Double?

    var body: some View {
        HStack(spacing: 16) {
            nowPlaying.frame(width: 240, alignment: .leading)
            Spacer(minLength: 0)
            controls.frame(maxWidth: 520)
            Spacer(minLength: 0)
            Color.clear.frame(width: 240)  // 第 2 步放歌词、播放队列按钮
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var nowPlaying: some View {
        HStack(spacing: 10) {
            CoverImage(url: player.current?.coverURL, size: 44, corner: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.current?.title ?? "没有在播放").lineLimit(1)
                Text(player.current.map { [$0.artist, $0.albumTitle].filter { !$0.isEmpty }.joined(separator: " · ") } ?? "在歌单里双击一首歌开始")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 4) {
            HStack(spacing: 22) {
                Button(action: player.previous) { Image(systemName: "backward.fill") }
                    .help("上一首")
                Button(action: player.togglePlay) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.accent, in: Circle())
                }
                .help(player.isPlaying ? "暂停" : "播放")
                Button(action: player.next) { Image(systemName: "forward.fill") }
                    .help("下一首")
                    .disabled(!player.queue.hasNext)
            }
            .buttonStyle(.plain)
            .font(.system(size: 14))
            .disabled(player.current == nil)

            HStack(spacing: 8) {
                Text(formatTime(shownElapsed)).frame(width: 44, alignment: .trailing)
                Slider(value: Binding(get: { scrubbing ?? fraction }, set: { scrubbing = $0 })) { editing in
                    if !editing, let target = scrubbing {
                        player.seek(toFraction: target)
                        scrubbing = nil
                    }
                }
                .controlSize(.mini)
                .tint(Theme.accent)
                .disabled(player.current == nil)
                Text(formatTime(player.current?.duration ?? 0)).frame(width: 44, alignment: .leading)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var fraction: Double {
        guard let d = player.current?.duration, d > 0 else { return 0 }
        return player.elapsed / d
    }

    private var shownElapsed: Double {
        guard let s = scrubbing, let d = player.current?.duration else { return player.elapsed }
        return s * d
    }
}
