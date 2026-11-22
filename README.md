# Songline · B 站歌单时间轴

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

## 运行

需要 macOS + Apple Silicon（Whisper 用的是 MLX）。ffmpeg 已经随 Python 依赖一起安装，不需要另外装。

```bash
# 后端（Python 3.12，用 uv 管理）
cd backend
uv sync
uv run songline serve          # 打开 http://127.0.0.1:8765

# 命令行直接识别
uv run songline run "https://www.bilibili.com/video/BV1zgWq6eEQT"
uv run songline run BV1zgWq6eEQT --json --no-shazam
```

前端开发：

```bash
cd frontend
npm install
npm run dev      # http://localhost:5173 ，/api 会代理到 8765 端口
npm run build    # 生成 dist/，由后端在 / 路径直接提供
```

首次运行会自动下载 Whisper 模型（约 1.6 GB）。

### 配置（环境变量）

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
