import Foundation

/// B 站链接相关的小工具。
public enum BiliLink {
    /// 从粘贴的内容里取出链接：App 里「分享」复制出来的文字常常把链接夹在中间。
    public static func extract(from text: String) -> String {
        if let r = text.range(of: #"https?://[^\s，。]+"#, options: .regularExpression) { return String(text[r]) }
        if let r = text.range(of: #"BV[0-9A-Za-z]{10}"#, options: .regularExpression) { return String(text[r]) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 看起来是不是 B 站视频（用来决定要不要自动填进输入框）。
    public static func looksLikeVideo(_ text: String) -> Bool {
        text.contains("bilibili.com/video") || text.contains("b23.tv")
            || text.range(of: #"BV[0-9A-Za-z]{10}"#, options: .regularExpression) != nil
    }
}

extension Job {
    /// 可以直接贴到评论区的时间轴，每行「0:01:00 歌名 - 原唱」。
    public var timelineText: String {
        let lines = timeline.map { e -> String in
            let s = Int(e.start)
            let time = String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
            return e.artist.isEmpty ? "\(time) \(e.title)" : "\(time) \(e.title) - \(e.artist)"
        }
        return ([title] + lines).joined(separator: "\n")
    }
}
