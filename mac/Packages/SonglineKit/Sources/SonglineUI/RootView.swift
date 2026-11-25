import SonglineAPI
import SonglinePlayer
import SonglineState
import SwiftUI

/// App 的根界面：后端没就绪时显示引导页，就绪后显示播放器。
public struct RootView: View {
    var model: SonglineAppModel

    public init(model: SonglineAppModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if let library = model.library, let player = model.player {
                MainView(library: library, player: player)
            } else {
                OnboardingView(backend: model.backend) { Task { await model.start() } }
            }
        }
        .frame(minWidth: 880, minHeight: 560)
    }
}

struct MainView: View {
    var library: LibraryModel
    var player: PlayerModel

    var body: some View {
        NavigationSplitView {
            SidebarView(library: library)
                .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 320)
        } detail: {
            detail
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlayerBar(player: player)
        }
    }

    @ViewBuilder private var detail: some View {
        switch library.selection {
        case let .job(id):
            if let job = library.job(id) {
                PlaylistView(job: job, library: library, player: player).id(id)
            } else {
                ContentUnavailableView("找不到这张歌单", systemImage: "music.note.list", description: Text("可能已经被删除了。"))
            }
        case .recognize, nil:
            RecognizeView(library: library)
        }
    }
}

/// 菜单栏里的命令：⌘N 识别新回放，⌘← / ⌘→ 切歌。
public struct SonglineCommands: Commands {
    var model: SonglineAppModel

    public init(model: SonglineAppModel) {
        self.model = model
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("识别新回放") { model.library?.selection = .recognize }
                .keyboardShortcut("n")
                .disabled(model.library == nil)
        }
        CommandMenu("播放") {
            Button(model.player?.isPlaying == true ? "暂停" : "播放") { model.player?.togglePlay() }
                .keyboardShortcut("p")
                .disabled(model.player?.current == nil)
            Button("上一首") { model.player?.previous() }
                .keyboardShortcut(.leftArrow)
                .disabled(model.player?.current == nil)
            Button("下一首") { model.player?.next() }
                .keyboardShortcut(.rightArrow)
                .disabled(model.player?.queue.hasNext != true)
        }
    }
}

#Preview("播放器") {
    RootView(model: SonglineAppModel(previewing: MockSonglineService()))
        .frame(width: 1100, height: 720)
}
