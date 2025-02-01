# B站视频音频分离工具

一个简单易用的工具，可以从B站视频中提取音频并分离人声。

## 功能特点

- 支持B站视频链接解析
- 自动下载视频并提取音频
- 使用 Demucs 模型分离人声
- 简洁美观的Web界面
- 支持进度显示和状态提示
- 支持下载原始视频、音频和分离后的人声

## 安装说明

1. 克隆仓库
```bash
git clone https://github.com/mbmmhk/bilibili-audio-extractor.git
cd bilibili-audio-extractor
```

2. 安装依赖
```bash
pip install -r requirements.txt
```

3. 下载 ffmpeg
- Windows: 下载 [ffmpeg](https://www.gyan.dev/ffmpeg/builds/)
- 解压并将 ffmpeg.exe、ffprobe.exe 放入项目的 ffmpeg 目录

4. 下载 Demucs 模型（首次运行时会自动下载）

## 使用方法

1. 运行应用
```bash
python app.py
```

2. 打开浏览器访问 http://127.0.0.1:5000

3. 输入B站视频链接，例如：
```
https://www.bilibili.com/video/BVxxxxxx
```

4. 点击"开始处理"，等待处理完成

5. 下载处理后的文件：
- 原始视频（mp4）
- 原始音频（wav）
- 分离后的人声（wav）

## 目录结构

```
bilibili-audio-extractor/
├── app.py                 # Flask应用主文件
├── src/
│   ├── video_processor.py # 视频处理模块
│   └── demucs_processor.py# 音频分离模块
├── templates/
│   └── index.html        # Web界面模板
├── downloads/            # 下载文件存储目录
├── ffmpeg/              # ffmpeg工具目录
└── requirements.txt     # 项目依赖
```

## 技术栈

- Python 3.8+
- Flask (Web框架)
- yt-dlp (视频下载)
- Demucs (音频分离)
- FFmpeg (音频处理)

## 注意事项

1. 确保有足够的磁盘空间
2. 需要稳定的网络连接
3. 首次运行会下载模型文件
4. 处理时间取决于视频长度和电脑性能

## License

MIT License

## 环境要求

- Python 3.8+
- FFmpeg

### FFmpeg 安装说明

#### Windows 安装方法
1. 方法一（推荐）：
   - 下载 [FFmpeg](https://www.gyan.dev/ffmpeg/builds/) 预编译包
   - 解压下载的文件
   - 将解压后的 ffmpeg.exe、ffprobe.exe、ffplay.exe 放入项目的 ffmpeg 目录中

2. 方法二：
   - 使用 [Chocolatey](https://chocolatey.org/) 包管理器安装：
   ```bash
   choco install ffmpeg
   ```

#### macOS 安装方法
使用 Homebrew 包管理器安装：
```bash
brew install ffmpeg
```

#### Linux 安装方法
Ubuntu/Debian:
```bash
sudo apt update
sudo apt install ffmpeg
```

CentOS/RHEL:
```bash
sudo yum install epel-release
sudo yum install ffmpeg
```

验证安装：
```bash
ffmpeg -version
```
