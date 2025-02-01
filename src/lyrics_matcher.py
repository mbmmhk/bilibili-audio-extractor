from aip import AipSpeech
import json
import os
import time
from typing import List, Dict
import logging
import difflib

logger = logging.getLogger(__name__)

class LyricsMatcher:
    def __init__(self):
        # 百度语音识别配置
        self.APP_ID = '你的APP_ID'
        self.API_KEY = '你的API_KEY'
        self.SECRET_KEY = '你的SECRET_KEY'
        self.client = AipSpeech(self.APP_ID, self.API_KEY, self.SECRET_KEY)
        
        # 加载歌词库
        self.lyrics_db = self._load_lyrics_db()
    
    def _load_lyrics_db(self) -> Dict:
        """加载歌词数据库"""
        lyrics_db = {
            "东京不太热": [
                "东京很热 东京很热",
                "东京不太热 东京不太热",
                "东京很热 东京很热",
                "东京不太热 东京不太热"
            ],
            # 可以添加更多歌曲
        }
        return lyrics_db
    
    def match_song(self, audio_file: str, progress_callback=None) -> List[Dict]:
        """识别音频中的歌词并匹配歌曲"""
        try:
            logger.info(f"开始处理音频文件: {audio_file}")
            
            # 将音频转换为 PCM 格式
            if progress_callback:
                progress_callback({
                    'status': 'converting',
                    'message': '正在转换音频格式...',
                    'percent': 10
                })
            
            # 读取音频文件
            with open(audio_file, 'rb') as fp:
                audio_data = fp.read()
            
            # 调用百度语音识别
            if progress_callback:
                progress_callback({
                    'status': 'recognizing',
                    'message': '正在识别语音...',
                    'percent': 30
                })
            
            result = self.client.asr(audio_data, 'pcm', 16000, {
                'dev_pid': 1537,  # 普通话(支持简单的英文识别)
            })
            
            if result['err_no'] == 0:
                text = result['result'][0]
                logger.info(f"识别到的文字: {text}")
                
                # 匹配歌词
                if progress_callback:
                    progress_callback({
                        'status': 'matching',
                        'message': '正在匹配歌词...',
                        'percent': 60
                    })
                
                matches = self._match_lyrics(text)
                return matches
            else:
                logger.error(f"语音识别失败: {result}")
                return []
                
        except Exception as e:
            logger.error(f"识别过程出错: {str(e)}")
            return []
    
    def _match_lyrics(self, text: str) -> List[Dict]:
        """匹配歌词找到对应歌曲"""
        matches = []
        
        for song_name, lyrics in self.lyrics_db.items():
            # 将歌词合并成一个字符串
            lyrics_text = ' '.join(lyrics)
            
            # 计算相似度
            similarity = difflib.SequenceMatcher(None, text, lyrics_text).ratio()
            
            if similarity > 0.6:  # 相似度阈值
                match = {
                    'title': song_name,
                    'confidence': int(similarity * 100),
                    'lyrics_matched': text,
                    'play_offset_ms': 0
                }
                matches.append(match)
                logger.info(f"找到匹配歌曲: {song_name} (相似度: {similarity:.2f})")
        
        return matches 