import Foundation

/// 一场回放的歌词：语音转写，每句带时间。用来显示歌词页、逐句高亮。
public struct Lyrics: Sendable, Equatable {
    /// 按开始时间排好序的所有句子（歌词和聊天都有）。
    public let lines: [Segment]

    public init(segments: [Segment]) {
        lines = segments
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.start < $1.start }
    }

    public static let empty = Lyrics(segments: [])

    /// 和这首歌时间重叠的句子。
    public func lines(for track: Track) -> [Segment] {
        lines(from: track.start, to: track.end)
    }

    public func lines(from start: Double, to end: Double) -> [Segment] {
        lines.filter { $0.end > start && $0.start < end }
    }

    /// `time` 时正在唱的那句在 `lines` 里的下标：最后一句开始时间不晚于 `time` 的。
    /// 还没到第一句时返回 nil。
    public func index(at time: Double, in lines: [Segment]) -> Int? {
        var lo = 0, hi = lines.count  // 找第一句开始时间 > time 的
        while lo < hi {
            let mid = (lo + hi) / 2
            if lines[mid].start <= time { lo = mid + 1 } else { hi = mid }
        }
        return lo == 0 ? nil : lo - 1
    }

    /// 整场回放里 `time` 时的那一句。
    public func index(at time: Double) -> Int? { index(at: time, in: lines) }
}
