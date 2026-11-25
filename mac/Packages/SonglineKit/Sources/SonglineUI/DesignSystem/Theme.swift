import SwiftUI

/// 整个 App 的配色和尺寸。改外观先改这里。
public enum Theme {
    /// 主色：珊瑚粉，和网页版一致。
    public static let accent = Color(red: 0.93, green: 0.33, blue: 0.47)
    public static let accentSoft = accent.opacity(0.12)

    public static let coverCorner: CGFloat = 8
    public static let pagePadding: CGFloat = 28
}

/// 歌单封面：B 站视频封面，加载不出来时显示一个音符。
public struct CoverImage: View {
    var url: URL?
    var size: CGFloat
    var corner: CGFloat

    public init(url: URL?, size: CGFloat, corner: CGFloat = Theme.coverCorner) {
        self.url = url
        self.size = size
        self.corner = corner
    }

    public var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.12)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: size * 0.32)).foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

/// 正在播放的歌旁边跳动的小音柱。
struct NowPlayingBars: View {
    var animating: Bool

    var body: some View {
        Image(systemName: "waveform")
            .symbolEffect(.variableColor.iterative, isActive: animating)
            .foregroundStyle(Theme.accent)
    }
}
