import os
import logging
import yt_dlp
import uuid
from pydub import AudioSegment
import re
from typing import Optional, Dict, Any

# 直接配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler()]
)

logger = logging.getLogger(__name__)

class VideoProcessor:
    def __init__(self):
        # 获取项目根目录
        self.root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        logger.info(f"项目根目录: {self.root_dir}")
        
        # 设置下载目录
        self.download_dir = os.path.join(self.root_dir, "downloads")
        logger.info(f"下载目录: {self.download_dir}")
        
        # 确保下载目录存在
        os.makedirs(self.download_dir, exist_ok=True)
        
        # 配置ffmpeg路径
        self.ffmpeg_path = os.path.join(self.root_dir, "ffmpeg", "ffmpeg.exe")
        logger.info(f"尝试使用 ffmpeg 路径: {self.ffmpeg_path}")
        
        if os.path.exists(self.ffmpeg_path):
            logger.info("ffmpeg 配置成功")
            # 设置 pydub 的 ffmpeg 路径
            AudioSegment.converter = self.ffmpeg_path
            # 设置 ffprobe 路径
            ffprobe_path = os.path.join(self.root_dir, "ffmpeg", "ffprobe.exe")
            AudioSegment.ffprobe = ffprobe_path
        else:
            logger.warning("未找到 ffmpeg，将使用系统默认路径")
            self.ffmpeg_path = None

    def _download_progress_hook(self, d):
        """下载进度回调"""
        if d['status'] == 'downloading':
            progress = d.get('downloaded_bytes', 0) / d.get('total_bytes', 100) * 100
            speed = d.get('speed', 0)
            eta = d.get('eta', 0)
            speed_str = f"{speed/1024/1024:.1f}MB/s" if speed else "未知速度"
            eta_str = f"剩余{eta}秒" if eta else ""
            logger.info(f"进度更新: 下载中: {progress:.1f}% - {speed_str} - {eta_str} ({progress}%)")
        elif d['status'] == 'finished':
            logger.info(f"进度更新: 下载完成，准备转换格式... (40%)")

    def _convert_progress_hook(self, d):
        """转换进度回调"""
        if d['status'] == 'started':
            logger.info(f"进度更新: 开始转换音频格式... (40%)")
        elif d['status'] == 'finished':
            logger.info(f"进度更新: 音频转换完成 (50%)")

    def download_and_extract_audio(self, url: str, progress_callback=None) -> str:
        """下载视频并提取音频"""
        try:
            logger.info(f"开始处理视频URL: {url}")
            
            # 从URL中提取视频ID
            video_id = url.split('/')[-1].split('?')[0]  # 移除URL参数
            logger.info(f"提取到视频ID: {video_id}")
            
            logger.info("开始下载视频并提取音频")
            
            # 生成随机文件名（不带扩展名）
            file_id = uuid.uuid4().hex[:8]
            video_filename = f"video_{file_id}"
            
            # yt-dlp配置
            ydl_opts = {
                'format': 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best',  # 更通用的格式选择
                'paths': {'home': self.download_dir, 'temp': self.download_dir},
                'outtmpl': {
                    'default': video_filename + '.%(ext)s',
                },
                'postprocessors': [{
                    'key': 'FFmpegExtractAudio',
                    'preferredcodec': 'wav',
                    'nopostoverwrites': True,
                }],
                'progress_hooks': [self._download_progress_hook],
                'postprocessor_hooks': [self._convert_progress_hook],
                'ffmpeg_location': self.ffmpeg_path,
                'keepvideo': True,
                'verbose': True,
                'merge_output_format': 'mp4',
                'writethumbnail': False,
                'clean_infojson': True,
                'no_remove_tmp_files': True,
                'extract_audio': True,
                'keep_fragments': True,
                'keep_video': True
            }
            
            # 下载视频
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                ydl.download([url])
            
            # 获取输出文件路径
            audio_file = os.path.join(self.download_dir, f"{video_filename}.wav")
            video_file = os.path.join(self.download_dir, f"{video_filename}.mp4")
            
            logger.info(f"视频文件已保存: {video_file}")
            logger.info(f"音频文件已保存: {audio_file}")
            
            # 验证文件是否存在
            if not os.path.exists(audio_file):
                raise FileNotFoundError(f"音频文件未找到: {audio_file}")
            if not os.path.exists(video_file):
                logger.warning(f"视频文件未找到: {video_file}")
            
            return audio_file
            
        except Exception as e:
            logger.error(f"下载或提取音频失败: {str(e)}")
            import traceback
            logger.error(traceback.format_exc())
            raise

    def _extract_bvid(self, url: str) -> Optional[str]:
        """从各种格式的B站链接中提取BV号"""
        try:
            # 匹配BV号的正则表达式
            bv_pattern = r'BV[a-zA-Z0-9]{10}'
            
            # 尝试匹配BV号
            match = re.search(bv_pattern, url)
            if match:
                return match.group()
                
            # 如果是短链接，需要处理重定向
            if 'b23.tv' in url:
                try:
                    import requests
                    response = requests.head(url, allow_redirects=True)
                    final_url = response.url
                    match = re.search(bv_pattern, final_url)
                    if match:
                        return match.group()
                except Exception as e:
                    logger.error(f"处理短链接时出错: {str(e)}", exc_info=True)
                    
            logger.warning(f"未能从URL中提取BV号: {url}")
            return None
            
        except Exception as e:
            logger.error(f"提取BV号时出错: {str(e)}", exc_info=True)
            return None 