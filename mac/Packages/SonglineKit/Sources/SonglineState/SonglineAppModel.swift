import Foundation
import Observation
import SonglineAPI
import SonglineBackend
import SonglinePlayer

/// 把各模块串起来的总状态。App 启动时建一个，传给 `RootView`。
@MainActor @Observable
public final class SonglineAppModel {
    public let backend: BackendRuntime
    /// 后端就绪之后才有。
    public private(set) var library: LibraryModel?
    public private(set) var player: PlayerModel?

    public init(backend: BackendRuntime = BackendRuntime()) {
        self.backend = backend
    }

    /// 预览用：直接连到假数据，不启动后端。
    public convenience init(previewing service: any SonglineService) {
        self.init()
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

    private func connect(_ service: any SonglineService) {
        let library = LibraryModel(service: service)
        self.library = library
        player = PlayerModel(audioURL: { service.audioURL(id: $0) })
        Task { await library.refresh() }
    }
}
