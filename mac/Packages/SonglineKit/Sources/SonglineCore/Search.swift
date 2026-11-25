import Foundation

/// 搜索结果：匹配的歌，以及标题或 UP 主匹配的歌单。
public struct SearchResults: Sendable, Equatable {
    public var tracks: [Track]
    public var jobs: [Job]

    public init(tracks: [Track] = [], jobs: [Job] = []) {
        self.tracks = tracks
        self.jobs = jobs
    }

    public var isEmpty: Bool { tracks.isEmpty && jobs.isEmpty }
}

/// 跨所有歌单搜歌名、原唱、歌单标题、UP 主。纯逻辑，方便测试。
public enum Search {
    /// 搜索 `jobs`（应按最新在前排好）。空格分开的每个词都要匹配上。
    /// 歌：歌名匹配的排在只有原唱或歌单匹配的前面；同等情况下按原来的顺序（新的歌单在前）。
    public static func run(_ query: String, in jobs: [Job], limit: Int = 200) -> SearchResults {
        let terms = query.split(whereSeparator: \.isWhitespace).map { normalize(String($0)) }.filter { !$0.isEmpty }
        guard !terms.isEmpty else { return SearchResults() }

        var titleHits: [Track] = []
        var otherHits: [Track] = []
        for job in jobs {
            for (entry, track) in zip(job.timeline, job.tracks) where entry.song != nil {
                let title = normalize(track.title)
                let all = title + "|" + normalize(track.artist) + "|" + normalize(job.title)
                guard terms.allSatisfy({ all.contains($0) }) else { continue }
                if terms.contains(where: { title.contains($0) }) { titleHits.append(track) } else { otherHits.append(track) }
            }
        }
        let matchingJobs = jobs.filter { job in
            let text = normalize(job.title) + "|" + normalize(job.video?.owner ?? "")
            return terms.allSatisfy { text.contains($0) }
        }
        return SearchResults(tracks: Array((titleHits + otherHits).prefix(limit)), jobs: matchingJobs)
    }

    /// 忽略大小写、全角半角、空格和标点：「Ｌｏｖｅ」「love」「LOVE!」都算一样。
    public static func normalize(_ text: String) -> String {
        let folded = (text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text).lowercased()
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }
}
