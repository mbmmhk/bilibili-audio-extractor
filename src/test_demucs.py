import os
from video_processor import VideoProcessor
from demucs_processor import DemucsProcessor
import logging
import sys

# 强制输出到控制台
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)

logger = logging.getLogger(__name__)

def test_demucs():
    url = "https://www.bilibili.com/video/BV1u84y1P7fv"  # 测试视频
    
    try:
        print("="*50)
        print("开始处理视频")
        print("="*50)
        
        # 下载视频并提取音频
        video_processor = VideoProcessor()
        audio_file = video_processor.download_and_extract_audio(url, None)
        
        print("\n" + "="*50)
        print("开始分离人声")
        print("="*50)
        
        # 分离人声
        processor = DemucsProcessor()
        vocals_file = processor.process_audio(audio_file)
        
        print("\n" + "="*50)
        print("处理完成")
        print(f"原始音频文件: {audio_file}")
        print(f"人声文件: {vocals_file}")
        print("="*50)
            
    except Exception as e:
        print(f"\n错误: {str(e)}")

if __name__ == "__main__":
    test_demucs() 