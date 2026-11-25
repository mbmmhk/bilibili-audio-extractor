import AppKit
import SonglineCore
import SonglinePlayer
import SonglineState
import SwiftUI

/// 一场直播回放 = 一张歌单。
struct PlaylistView: View {
    var job: Job
    var library: LibraryModel
    var player: PlayerModel
    @State private var copied = false
    @State private var actionError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if !job.isFinished { progress }
                if let message = job.error ?? actionError { failure(message) }
                if !job.timeline.isEmpty { TrackList(tracks: job.tracks, player: player) }
            }
            .padding(Theme.pagePadding)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 24) {
            CoverImage(url: job.video?.coverURL, size: 190, corner: 12)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            VStack(alignment: .leading, spacing: 10) {
                Text("直播回放").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                Text(job.title).font(.system(size: 26, weight: .bold)).lineLimit(2)
                Text(details).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button {
                        player.play(job.tracks)
                    } label: {
                        Label("播放全部", systemImage: "play.fill").padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(job.timeline.isEmpty)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(job.timelineText, forType: .string)
                        copied = true
                    } label: {
                        Label(copied ? "已复制" : "复制时间轴", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(job.timeline.isEmpty)

                    if let url = URL(string: job.url) {
                        Link(destination: url) { Label("在 B 站打开", systemImage: "arrow.up.right.square") }
                    }
                    Spacer()
                    if job.isFinished {
                        Button("重新识别") { Task { await run { try await library.rerun(job) } } }
                    } else {
                        Button("取消识别") { Task { await library.cancel(job) } }
                    }
                }
                .controlSize(.large)
            }
        }
    }

    private var details: String {
        var parts: [String] = []
        if let owner = job.video?.owner { parts.append(owner) }
        parts.append(job.createdDate.formatted(date: .abbreviated, time: .shortened))
        if !job.timeline.isEmpty { parts.append("\(job.timeline.count) 首") }
        if let d = job.video?.duration { parts.append("时长 \(formatTime(Double(d)))") }
        return parts.joined(separator: " · ")
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: job.progress).tint(Theme.accent)
            Text(job.message.isEmpty ? "处理中…" : job.message).font(.callout).foregroundStyle(.secondary)
            Text("识别出的歌会陆续出现在下面，全部转写完后会再整体校正一遍。")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
    }

    private func failure(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func run(_ action: () async throws -> Void) async {
        do { try await action(); actionError = nil } catch { actionError = error.localizedDescription }
    }
}

/// 歌曲列表：双击或点播放按钮开始播放，正在播放的那首高亮。
struct TrackList: View {
    var tracks: [Track]
    var player: PlayerModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("#").frame(width: 32)
                Text("歌曲")
                Spacer()
                Text("开始于").frame(width: 70, alignment: .trailing)
                Text("时长").frame(width: 56, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            Divider()
            ForEach(Array(tracks.enumerated()), id: \.element.id) { i, track in
                TrackRow(track: track, number: i + 1, isCurrent: player.current?.id == track.id,
                         isPlaying: player.isPlaying, striped: i.isMultiple(of: 2)) {
                    player.play(tracks, startAt: i)
                }
            }
        }
    }
}

struct TrackRow: View {
    var track: Track
    var number: Int
    var isCurrent: Bool
    var isPlaying: Bool
    var striped: Bool
    var play: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack {
            Group {
                if hovering {
                    Button(action: play) { Image(systemName: "play.fill") }.buttonStyle(.plain)
                } else if isCurrent {
                    NowPlayingBars(animating: isPlaying)
                } else {
                    Text("\(number)").foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).foregroundStyle(isCurrent ? Theme.accent : .primary).lineLimit(1)
                if !track.artist.isEmpty {
                    Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(formatTime(track.start)).frame(width: 70, alignment: .trailing)
            Text(formatTime(track.duration)).frame(width: 56, alignment: .trailing)
        }
        .font(.body)
        .monospacedDigit()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: play)
    }

    private var rowBackground: Color {
        if isCurrent { return Theme.accentSoft }
        if hovering { return .primary.opacity(0.06) }
        return striped ? .primary.opacity(0.025) : .clear
    }
}
