# Songline · B 站歌单时间轴

[![CI](https://github.com/mbmmhk/bilibili-audio-extractor/actions/workflows/ci.yml/badge.svg)](https://github.com/mbmmhk/bilibili-audio-extractor/actions/workflows/ci.yml)

输入一个 B 站视频链接，输出视频里唱了哪些歌、每首在什么时间。适合翻唱、弹唱、直播回放这类视频。

```
00:01:00  风月吻眉梢 - 礼越        可靠  歌词+指纹
00:08:41  爱的华尔兹 - 俞灏明      可靠  歌词+口播
00:13:18  当初的我们 - 大壮        可靠  歌词+口播
...
```

## 工作原理

翻唱、弹唱的录音和原唱不同，单靠"听歌识曲"（音频指纹）识别不出来，所以组合了几种线索：

1. **转写**：用 Whisper（Apple Silicon 上跑 MLX 版本）在本地把音频转成文字，歌词和聊天都会被转写出来。1 小时音频大约需要 2 分钟。
2. **歌词检索**：每 15 秒取一个 30 秒的窗口，拿里面的句子去网易云曲库按歌词搜索；再算这些句子有多大比例出现在候选歌的歌词里。唱歌时这个比例很高，聊天时很低，所以同一个分数既能认出是哪首歌，也能区分唱歌和说话。
3. **合并成时间线**：连续命中同一首歌的窗口合并成一个时间段（中间有短暂聊天也不会被拆开），并按歌词把开始和结束时间向两边延伸。歌名在所有命中结果里投票选出，排除那些用歌词当歌名的 DJ 版、翻唱版。
4. **交叉核对**：
   - **口播**：主播说过的"下一首是……"或观众点的歌名
   - **音频指纹**：主播常用原版伴奏，所以 Shazam 也能命中。它还会扫一遍歌词没覆盖到的长空白段，补上漏掉的歌。

识别结果会边转写边显示，全部转写完后再整体校正一遍。

## 安装

只支持 **macOS + Apple Silicon**（M1/M2/M3/M4 芯片），因为语音识别用的是 Apple 的 MLX。

### 1. 装好两个工具

在「终端」里执行：

```bash
# uv：管理 Python 和依赖（会自动装好 Python 3.12，不需要自己装 Python）
curl -LsSf https://astral.sh/uv/install.sh | sh

# Node.js 20.19 以上：只用来构建网页界面
brew install node
```

没有 Homebrew 的话，可以从 [nodejs.org](https://nodejs.org) 下载安装包。ffmpeg 不用装，它会随 Python 依赖一起装好。

装完后**重新打开一个终端窗口**，让新命令生效。

### 2. 下载代码并安装

```bash
git clone git@github.com:mbmmhk/bilibili-audio-extractor.git
cd bilibili-audio-extractor

# 构建网页界面（只需做一次，前端代码更新后再做）
cd frontend && npm install && npm run build && cd ..

# 安装后端依赖
cd backend && uv sync
```

## 使用

### 网页版（推荐）

```bash
cd bilibili-audio-extractor/backend
uv run songline serve
```

浏览器会自动打开 <http://127.0.0.1:8765>。用完在终端按 `Ctrl+C` 关掉。

1. 把 B 站视频链接粘贴进输入框，点「开始识别」。
   - 支持完整链接、BV 号、b23.tv 短链，也可以直接粘贴 App 里「分享」复制出来的整段文字。
   - 多 P 视频：链接里带上 `?p=2` 就识别第 2P。
2. 「音频指纹交叉核对」默认打开，结果更准，但会多花几分钟；只想快点出结果可以关掉。
3. 等待识别。认出来的歌会边转写边显示，全部转写完后会整体校正一遍。1 小时的视频大约需要 3～5 分钟。
4. 看结果：
   - 点歌名旁边的时间可以从这里播放；点 B 站图标会在 B 站打开到这个时间点。
   - 「复制时间轴」：复制成文本，可以直接贴到评论区或动态里。
   - 也可以导出 JSON、下载音频、查看和搜索完整的语音转写。
5. 左侧（手机上在页面下方）是历史记录。同一个视频再次识别时，会复用已下载的音频和已有的转写，速度快很多。

**第一次运行**会下载 Whisper 语音模型（约 1.6 GB），需要等一会儿，之后就不用再下载了。

### 命令行版

不想开网页，也可以在终端里直接出结果：

```bash
cd bilibili-audio-extractor/backend
uv run songline run "https://www.bilibili.com/video/BV1zgWq6eEQT"   # 打印成表格
uv run songline run BV1zgWq6eEQT --no-shazam                        # 不做指纹核对，更快
uv run songline run BV1zgWq6eEQT --json > 歌单.json                  # 输出 JSON
```

### 更新到最新版

```bash
cd bilibili-audio-extractor
git pull
cd frontend && npm install && npm run build && cd ..
cd backend && uv sync
```

### 常见问题

- **打开网页是 `{"detail":"Not Found"}`**：网页界面还没构建，先执行上面的 `npm run build`。
- **提示端口 8765 被占用**：之前的服务还开着。关掉那个终端窗口，或者换个端口：`uv run songline serve --port 8766`。
- **视频需要登录才能看 / 下载失败**：设置下面的 `SONGLINE_BILI_SESSDATA`。
- **识别不全或歌名不对**：可以打开「音频指纹交叉核对」再识别一次；纯伴奏、没有歌词的段落本来就很难认出来，见「已知局限」。

### 开发

```bash
cd frontend && npm run dev            # http://localhost:5173 ，/api 会代理到 8765 端口
cd backend && uv run pytest           # 跑测试
cd backend && uv run python eval/run_eval.py -v   # 用手工核对过的歌单给识别结果打分
```

`eval/truth.json` 是三个直播回放的人工核对歌单。评测直接用本机已缓存的转写（`~/.songline/audio`），所以要先用网页版或命令行把这三个视频识别一遍。改匹配逻辑前后各跑一次，就能看出准确率是升了还是降了。

开发前端时需要同时开着 `uv run songline serve`。

### 配置（环境变量）

在启动命令前面加上就行，例如 `SONGLINE_DATA=~/songline-data uv run songline serve`。

| 变量 | 默认值 | 说明 |
|---|---|---|
| `SONGLINE_DATA` | `~/.songline` | 数据目录：音频、转写缓存、任务数据库 |
| `SONGLINE_WHISPER_MODEL` | `mlx-community/whisper-large-v3-turbo` | 语音识别模型 |
| `SONGLINE_CHUNK_SECONDS` | `600` | 分段转写的长度，决定进度和结果多久刷新一次 |
| `SONGLINE_BILI_SESSDATA` | — | 可选，B 站登录 cookie，用于需要登录才能看的视频 |

## 项目结构

```
backend/src/songline/
  bili.py         链接解析（BV / av / b23.tv / 分P）、视频信息、只下载音频轨
  audio.py        ffmpeg 解码、截取片段
  transcribe.py   Whisper 分段转写
  lyrics.py       网易云歌词搜索；找原唱（originSongSimpleData）
  matcher.py      核心：滑动窗口 → 打分 → 合并 → 投票选歌名 → 延伸边界 → 口播加分
  fingerprint.py  Shazam 核对，补上歌词漏掉的歌
  pipeline.py     串起全流程，汇报进度
  jobs.py         SQLite 任务存储、单 worker 队列、实时事件推送
  api.py          FastAPI 接口 + SSE 推送，同时提供网页前端
  cli.py          songline run / serve
frontend/         React 19 + TypeScript + Vite + Tailwind CSS v4
```

## 已知局限

- 歌词检索和 Shazam 用的都是非官方接口，随时可能变动或限流。所有查询结果都缓存在 `cache.db`。
- 冷门歌的纯器乐演奏（没有歌词，曲库里也没有）认不出来。
- "原唱"一栏用的是网易云标注的原曲；没有标注时，取同名歌里热度最高的版本，偶尔会是翻唱版。
- 目前只支持 Apple Silicon。转写模块有单独的接口，以后可以接入 faster-whisper 来支持其他平台。
