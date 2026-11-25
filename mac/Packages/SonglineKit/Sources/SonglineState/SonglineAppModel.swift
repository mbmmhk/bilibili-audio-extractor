import Foundation
import Observation
import SonglineAPI
import SonglineBackend
import SonglineCore
import SonglinePlayer
import SonglineStore

/// 把各模块串起来的总状态。App 启动时建一个，传给 `RootView`。
@MainActor @Observable
public final class SonglineAppModel {
    public let backend: BackendRuntime
    /// 我喜欢的歌、最近播放。不依赖后端，一开始就有。
    public let store: LibraryStore
    /// 后端就绪之后才有。
    public private(set) var library: LibraryModel?
    public private(set) var player: PlayerModel?
    /// 打开链接失败时的说明（比如链接不是 B 站视频），给界面显示。
    public var openError: String?

    @ObservationIgnored private let systemIntegration: Bool
    /// 后端还没就绪时收到的链接，就绪后再打开。
    @ObservationIgnored private var pendingLinks: [String] = []

    public init(backend: BackendRuntime = BackendRuntime(), store: LibraryStore = LibraryStore(file: LibraryStore.standardFile())) {
        self.backend = backend
        self.store = store
        self.systemIntegration = true
    }

    /// 预览、测试用：直接连到假数据，不启动后端，不接入媒体键，收藏只存在内存里。
    public init(previewing service: any SonglineService) {
        backend = BackendRuntime()
        store = LibraryStore(file: nil)
        systemIntegration = false
        connect(service)
    }

    /// 准备并启动后端；就绪后加载资料库。出错后可以再次调用来重试。
    public func start() async {
        await backend.start()
        if library == nil, case let .running(url) = backend.state {
            connect(HTTPSonglineService(baseURL: url))
        }
    }

    /// App 退出前调用。
    public func shutdown() {
        player?.pause()
        backend.stop()
    }

    // MARK: - 打开链接

    /// 打开外部来的链接：
    /// - `songline://open?url=<B 站链接>`（浏览器书签、其他 App 调用）
    /// - 直接是 B 站视频链接（拖进窗口或 Dock 图标）
    /// 已经识别过的视频直接打开结果，没识别过的开始识别。
    public func open(_ url: URL) {
        guard let link = Self.videoLink(in: url) else {
            openError = "不是 B 站视频链接：\(url.absoluteString)"
            return
        }
        open(link: link)
    }

    /// 打开粘贴或拖进来的文字（链接、BV 号或分享文字）。
    public func open(link text: String) {
        openError = nil
        guard let library else {
            pendingLinks.append(text)
            return
        }
        Task {
            do { try await library.open(text) } catch { openError = error.localizedDescription }
        }
    }

    /// 从 URL 里取出要识别的 B 站链接。
    nonisolated static func videoLink(in url: URL) -> String? {
        if url.scheme == "songline" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return items.first { $0.name == "url" }?.value.flatMap { BiliLink.looksLikeVideo($0) ? $0 : nil }
        }
        let text = url.absoluteString
        return BiliLink.looksLikeVideo(text) ? text : nil
    }

    // MARK: - 收藏 / 最近播放 → 可以播放的歌

    /// 把收藏或最近播放的歌对应回现在能播的歌。
    /// 原视频的识别记录被删了、或者重新识别后这首歌不见了的，会被略过。
    public func tracks(for saved: [SavedSong]) -> [Track] {
        guard let library else { return [] }
        return saved.compactMap { song in
            guard let job = library.jobs.first(where: { $0.stage == .done && $0.isVideo(bvid: song.bvid, page: song.page) })
            else { return nil }
            // 重新识别后时间可能有几秒出入：取开始时间最接近、且差距在 30 秒内的那首。
            return job.tracks
                .filter { abs($0.start - song.start) <= 30 }
                .min { abs($0.start - song.start) < abs($1.start - song.start) }
        }
    }

    // MARK: - 内部

    private func connect(_ service: any SonglineService) {
        let library = LibraryModel(service: service)
        self.library = library
        let player = PlayerModel(audioURL: { service.audioURL(id: $0) }, systemIntegration: systemIntegration)
        let store = self.store
        player.onTrackStart = { store.recordPlay($0) }
        self.player = player
        Task {
            await library.refresh()
            let links = pendingLinks
            pendingLinks = []
            links.forEach { open(link: $0) }
        }
    }
}
