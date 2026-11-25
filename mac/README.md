# Songline for Mac

把 B 站直播回放当歌单来听的原生 Mac 播放器。设计和模块划分见 [ARCHITECTURE.md](ARCHITECTURE.md)。

## 开始开发

需要：Apple Silicon 的 Mac、macOS 14 以上、Xcode 16 以上，以及 [uv](https://docs.astral.sh/uv/)（Python 环境管理工具）：

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

1. 用 Xcode 打开 `mac/Songline.xcodeproj`。
2. 选 `Songline` scheme，点 Run（⌘R）。

第一次运行时，App 会自己装好 Python 环境，并下载语音模型（约 1.6 GB），窗口里会显示进度。之后再打开就很快了。

- 构建时，`scripts/bundle-backend.sh` 会把 `backend/` 和 uv 复制进 App；改了 Python 代码，重新 Run 就会自动更新。
- Python 环境装在 `~/Library/Application Support/Songline/venv`，日志在同目录的 `backend.log`。
- 识别记录在 `~/.songline`，和命令行版、一键安装版共用。
- 如果 8765 端口已经有一个 Songline 在跑（比如你同时开着 `songline serve`），App 会直接用那个。

## 打包和发布

```bash
mac/scripts/package.sh 0.1.0
```

生成 `mac/dist/Songline-0.1.0.dmg`：Release 版 App，只支持 Apple Silicon，uv 也打在里面，朋友的电脑上不用装 Xcode 或 uv。

正式发布：给要发布的提交打一个版本号标签并推上去，CI 会自动打包，并发布到 GitHub Releases：

```bash
git tag v0.1.0
git push origin v0.1.0
```

App 目前用的是本机签名（ad-hoc），没有经过 Apple 公证。朋友第一次打开时，要在「系统设置 → 隐私与安全性」里点「仍要打开」。

App 图标由 `scripts/make-icon.swift` 画出来，想改设计就改这个脚本，再运行 `swift mac/scripts/make-icon.swift`。

## 只改界面

不想跑 Python 也行：每个界面都有 `#Preview`，用的是 `MockSonglineService` 里的假数据。打开 `Packages/SonglineKit/Sources/SonglineUI/RootView.swift`，在 Xcode 右侧打开 Canvas（⌥⌘↩）就能看到整个播放器。

## 测试

```bash
swift test --package-path mac/Packages/SonglineKit
```

CI 每次提交都会跑这些测试，并用 `package.sh` 打一个 `.dmg`（在 CI 运行页面的 Artifacts 里，可以下载下来试用）。

## 代码放哪

| 要做的事 | 放在 |
|---|---|
| 新界面 | `Packages/SonglineKit/Sources/SonglineUI/功能名/`（约定见 [AGENTS.md](AGENTS.md)） |
| App 级状态（歌单列表、选中项、识别进度） | `SonglineState` |
| 颜色、字体、通用组件 | `SonglineUI/DesignSystem/` |
| 新的后端接口 | `SonglineAPI`：先改 `SonglineService` 协议，再分别实现 HTTP 版和 Mock 版 |
| 纯逻辑（切歌规则、时间格式等） | `SonglineCore`，并配上测试 |
| 播放相关（队列、只听歌、媒体键） | `SonglinePlayer` |
| 收藏、最近播放 | `SonglineStore` |
| 安装、启动后端 | `SonglineBackend` |

App 本体（`Songline/`）只负责组装，尽量不在里面写业务代码。
