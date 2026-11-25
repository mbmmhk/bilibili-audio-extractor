# 给做 Mac App 界面的 AI 助手 / 开发者的说明

先读 [ARCHITECTURE.md](ARCHITECTURE.md) 了解整体设计。这份文件说明做**界面**时的边界和约定。

## 分工

- **界面**（SwiftUI 视图、布局、动画、视觉风格）→ 只改 `Packages/SonglineKit/Sources/SonglineUI/`，需要时可以改 `Songline/`（App 场景、菜单）和 `Songline/Assets.xcassets`。
- **系统层**（`SonglineState`、`SonglineCore`、`SonglineAPI`、`SonglineBackend`、`SonglinePlayer`）和 Python 后端 `backend/` 由另一边负责，**不要改**。界面需要新的数据或操作时，在交付说明里写清楚"需要什么"，不要自己在界面里绕过去实现（比如直接发网络请求、自己开 `AVPlayer`、自己启动进程）。

## 现有界面只是基线

`SonglineUI` 里现在的视图（侧边栏、歌单页、识别页、播放条、引导页）是为了让 App 先跑起来写的，可以整个重做。只需要保留这两个公开入口，因为 App 本体在用：

- `RootView(model: SonglineAppModel)`
- `SonglineCommands(model: SonglineAppModel)`

## 界面可以用的状态和操作

全部是 `@MainActor @Observable`，直接在视图里读；要双向绑定时用 `@Bindable`。

**`SonglineAppModel`**（总入口，在 `SonglineState` 模块）
- `backend: BackendRuntime`、`library: LibraryModel?`、`player: PlayerModel?`：后端就绪前 `library` 和 `player` 为 nil，这时应显示引导页。
- `start()`：启动或重试后端。

**`BackendRuntime.state: BackendState`**
- `.idle` / `.starting`：启动中。
- `.installing(step:progress:)`：首次安装。`step` 是可以直接显示的中文说明；`progress` 为 nil 时无法估计进度。
- `.running(URL)`：已就绪。
- `.failed(message:detail:)`：失败。`message` 给用户看，`detail` 是技术细节；`paths.log` 是日志文件。

**`LibraryModel`**（歌单，在 `SonglineState` 模块）
- `jobs: [Job]`：所有直播回放，最新的在前；识别中的会实时更新。
- `selection: Selection?`：`.recognize`（识别新回放页）或 `.job(id)`。
- `job(_ id:) -> Job?`
- `recognize(_ text:shazam:)`：可以传链接、BV 号或分享文字。
- `rerun(_:)`、`cancel(_:)`、`delete(_:)`、`refresh()`；`loadError`。

**`PlayerModel`**（播放）
- `current: Track?`、`isPlaying`、`elapsed`（当前这首播了几秒）、`time`（在整场回放里的位置）、`queue.hasNext`。
- `play(_ tracks:startAt:)`、`togglePlay()`、`pause()`、`resume()`、`next()`、`previous()`、`seek(toFraction:)`。

**数据（`SonglineCore`）**
- `Job`：一场回放 = 一张歌单。常用：`title`、`video?.owner`、`video?.coverURL`、`stage`、`progress`、`message`、`error`、`isFinished`、`tracks`、`timelineText`、`createdDate`。
- `Track`：一首歌。`title`、`artist`、`start`、`end`、`duration`、`albumTitle`、`coverURL`。
- `TimelineEntry`：`confidence`（0...1）、`sources`（`lyrics` / `shazam` / `spoken`）、`alternatives`（其他可能的歌名）。
- 工具：`formatTime(_:)`、`BiliLink.extract(from:)`、`BiliLink.looksLikeVideo(_:)`。

## 还没有、但计划中的系统能力

下面这些界面暂时**不要自己实现**。需要时提出来，系统层会补上接口：

歌词（转写内容按时间逐句定位）、「只听歌」模式、可编辑的播放队列、媒体键和「正在播放」、我喜欢的歌和最近播放（本地存储）、拖链接到 Dock / `songline://` 链接、菜单栏迷你播放器的数据源。

## 约定

- **视觉**：音乐播放器的常见布局（侧边栏、歌单页、底部播放条、歌词页）。视觉风格是我们自己的：主色用 `Theme.accent`（珊瑚粉），配色和通用组件集中在 `DesignSystem/`。不要照搬任何现有产品（包括网易云音乐）的品牌、图标、配色或素材。
- **文案**：界面文字用简体中文。
- **预览**：每个主要视图都要有 `#Preview`。用 `SonglineAppModel(previewing: MockSonglineService())` 或 `MockSonglineService.samples`，不依赖 Python 后端。需要更多假数据可以加在预览代码里；如果要改 `MockSonglineService` 本身，在说明里写出来。
- **系统版本**：macOS 14 起，可以用 `@Observable`、`ContentUnavailableView`、`symbolEffect` 等。
- **并发**：Swift 6 严格并发。视图里不要做耗时操作，有需要就调用上面这些模型的 `async` 方法。

## 交付前检查

```bash
swift test --package-path mac/Packages/SonglineKit
xcodebuild -project mac/Songline.xcodeproj -scheme Songline -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

两条都通过才算完成。能运行 App 的话，在 Xcode 里点 Run 实际看一遍：引导页、识别一个视频、播放和切歌。

提交信息里不要写 AI 工具的署名（不加 `Co-Authored-By` 之类的行）。
