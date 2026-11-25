# 给做 Mac App 界面的 AI 助手 / 开发者的说明

先读 [ARCHITECTURE.md](ARCHITECTURE.md) 了解整体设计。这份文件说明做**界面**时的边界和约定。

## 分工

- **界面**（SwiftUI 视图、布局、动画、视觉风格）→ 只改 `Packages/SonglineKit/Sources/SonglineUI/`，需要时可以改 `Songline/`（App 场景、菜单）和 `Songline/Assets.xcassets`。
- **系统层**（`SonglineState`、`SonglineCore`、`SonglineAPI`、`SonglineBackend`、`SonglinePlayer`、`SonglineStore`）和 Python 后端 `backend/` 由另一边负责，**不要改**。界面需要新的数据或操作时，在交付说明里写清楚"需要什么"，不要自己在界面里绕过去实现（比如直接发网络请求、自己开 `AVPlayer`、自己启动进程）。

## 现有界面只是基线

`SonglineUI` 里现在的视图（侧边栏、歌单页、识别页、播放条、引导页）是为了让 App 先跑起来写的，可以整个重做。只需要保留这两个公开入口，因为 App 本体在用：

- `RootView(model: SonglineAppModel)`
- `SonglineCommands(model: SonglineAppModel)`

## 界面可以用的状态和操作

全部是 `@MainActor @Observable`，直接在视图里读；要双向绑定时用 `@Bindable`。

**`SonglineAppModel`**（总入口，在 `SonglineState` 模块）
- `backend: BackendRuntime`、`library: LibraryModel?`、`player: PlayerModel?`：后端就绪前 `library` 和 `player` 为 nil，这时应显示引导页。
- `store: LibraryStore`：我喜欢的歌、最近播放（一直都有，不等后端）。
- `start()`：启动或重试后端。
- `open(link:)`：打开拖进窗口或粘贴的 B 站链接 / BV 号 / 分享文字。识别过的直接选中那张歌单，没识别过的开始识别；后端还没就绪时会先记下，就绪后再打开。`open(_ url: URL)` 用于 `songline://` 链接，App 本体已经接好。
- `openError: String?`：打开链接失败的说明，可以显示出来。
- `tracks(for: [SavedSong]) -> [Track]`：把收藏或最近播放的歌变成能播的歌（原记录被删的会略过），再交给 `player.play(_:startAt:)`。

**`BackendRuntime.state: BackendState`**
- `.idle` / `.starting`：启动中。
- `.installing(step:progress:)`：首次安装。`step` 是可以直接显示的中文说明；`progress` 为 nil 时无法估计进度。
- `.running(URL)`：已就绪。
- `.failed(message:detail:)`：失败。`message` 给用户看，`detail` 是技术细节；`paths.log` 是日志文件。

**`LibraryModel`**（歌单，在 `SonglineState` 模块）
- `jobs: [Job]`：所有直播回放，最新的在前；识别中的会实时更新。
- `selection: Selection?`：`.recognize`（识别新回放页）或 `.job(id)`。
- `job(_ id:) -> Job?`
- `recognize(_ text:shazam:)`：可以传链接、BV 号或分享文字。一般用 `open(_:)` 更好：识别过的视频不会重复识别。
- `lyrics(for jobID:) async throws -> Lyrics`：这场回放的歌词（语音转写）。
- `search(_ query:) -> SearchResults`：跨所有歌单搜歌名、原唱、歌单标题、UP 主，空格分开的每个词都要匹配。结果里 `tracks` 是歌（歌名匹配的排前面），`jobs` 是歌单。同步返回，可以边输入边搜。
- `rerun(_:)`、`cancel(_:)`、`delete(_:)`、`refresh()`；`loadError`。

**`PlayerModel`**（播放）
- `current: Track?`、`isPlaying`、`elapsed`（当前这首播了几秒）、`time`（在整场回放里的位置，歌词高亮用它）。
- `mode: PlaybackMode`：`.songsOnly`（只听歌，跳过歌与歌之间的聊天，默认）或 `.wholeStream`（整场按原样播）。可以直接赋值。
- `isBetweenSongs`：整场模式下，当前这首唱完了、正在播聊天。
- `play(_ tracks:startAt:)`、`togglePlay()`、`pause()`、`resume()`、`next()`、`previous()`。
- `seek(toFraction:)`：在当前这首里拖进度；`seek(to: 秒)`：跳到回放里的任意位置（比如点歌词里的某一句）。
- 播放队列：`queue.items`、`queue.position`（正在播第几首）、`queue.upcoming`、`queue.hasNext`；`playNext(_:)`（下一首播放）、`addToQueue(_:)`、`playQueueItem(at:)`、`removeFromQueue(at:)`（正在播的那首移不掉）、`moveInQueue(from:to:)`、`clearUpcoming()`。
- 媒体键、耳机按键、控制中心和锁屏的「正在播放」已经由系统层接好，界面不用管。

**`LibraryStore`**（我喜欢的歌、最近播放，在 `SonglineStore` 模块）
- `favorites: [SavedSong]`（最新收藏的在前）、`recent: [SavedSong]`（最近播放的在前，最多 200 首）。
- `isFavorite(_ track:)`、`toggleFavorite(_ track:)`、`removeFavorite(id:)`、`clearRecent()`。播放时会自动记录最近播放。
- `SavedSong`：`title`、`artist`、`albumTitle`、`coverURL`、`duration`、`date`（收藏或播放的时间）。

**数据（`SonglineCore`）**
- `Job`：一场回放 = 一张歌单。常用：`title`、`video?.owner`、`video?.coverURL`、`stage`、`progress`、`message`、`error`、`isFinished`、`tracks`、`timelineText`、`createdDate`。
- `Track`：一首歌。`title`、`artist`、`start`、`end`、`duration`、`albumTitle`、`coverURL`。
- `Lyrics`：`lines`（整场的句子，按时间排好）、`lines(for: track)`（这首歌的句子）、`index(at: time, in: lines)`（`time` 时唱到第几句，没开始时为 nil）。每句是 `Segment`：`start`、`end`、`text`。
- `TimelineEntry`：`confidence`（0...1）、`sources`（`lyrics` / `shazam` / `spoken`）、`alternatives`（其他可能的歌名）。
- 工具：`formatTime(_:)`、`BiliLink.extract(from:)`、`BiliLink.looksLikeVideo(_:)`。

## 界面要做的（系统接口都已经有了）

- **歌词页**：`library.lyrics(for:)` + `Lyrics.lines(for:)` + `index(at: player.time, in:)` 逐句高亮；点一句用 `player.seek(to: line.start)`。
- **「只听歌」开关**：绑定 `player.mode`。
- **播放队列面板**：用上面 `PlayerModel` 的队列接口。
- **我喜欢的歌 / 最近播放**：侧边栏入口 + 列表页，用 `store` 和 `tracks(for:)`。
- **拖链接进窗口**：`.onDrop` / `.dropDestination` 拿到文字或 URL 后调用 `model.open(link:)`。
- **菜单栏迷你播放器**：用 `MenuBarExtra` 场景，数据全部来自 `PlayerModel`。

- **搜索**：搜索框 + 结果页，用 `library.search(_:)`。

切回 App 时会自动刷新记录（最多每 5 秒一次），在网页版或命令行里的改动也能看到。界面不用自己刷新。

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
