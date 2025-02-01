import os
import json
import time
from video_processor import VideoProcessor
from song_matcher import SongMatcher
from pydub import AudioSegment

class CoverSongDetector:
    def __init__(self):
        self.video_processor = VideoProcessor()
        self.song_matcher = SongMatcher()
        
    def detect_songs(self, video_url):
        """检测视频中的翻唱歌曲"""
        try:
            # 下载并提取音频
            audio_file = self.video_processor.download_and_extract_audio(video_url)
            
            # 将音频分段处理
            matches = self._process_audio_segments(audio_file)
            
            # 生成报告
            return self._generate_report(matches)
            
        except Exception as e:
            return {'error': str(e)}
            
    def _process_audio_segments(self, audio_file, segment_length=30000):
        """将音频分段处理，每段30秒"""
        matches = []
        audio = AudioSegment.from_wav(audio_file)
        
        # 每30秒一段
        for start_time in range(0, len(audio), segment_length):
            # 提取片段
            segment = audio[start_time:start_time + segment_length]
            
            # 保存临时文件
            temp_file = f"temp_segment_{start_time}.wav"
            segment.export(temp_file, format="wav")
            
            # 识别片段
            segment_matches = self.song_matcher.match_song(temp_file)
            
            # 添加时间戳信息
            for match in segment_matches:
                match['start_time'] = start_time
                matches.append(match)
                
            # 删除临时文件
            os.remove(temp_file)
            
            # 避免请求过于频繁
            time.sleep(1)
            
        return matches
    
    def _generate_report(self, matches):
        """生成识别报告"""
        # 按时间排序
        sorted_matches = sorted(matches, key=lambda x: x['start_time'])
        
        report = {
            'total_songs': len(matches),
            'matches': []
        }
        
        for match in sorted_matches:
            report['matches'].append({
                '时间戳': f"{match['start_time']/1000:.2f}秒",
                '歌曲名': match['title'],
                '艺术家': match['artist'],
                '专辑': match['album'],
                '置信度': f"{match['confidence']}%"
            })
            
        return report

if __name__ == "__main__":
    detector = CoverSongDetector()
    result = detector.detect_songs("https://www.bilibili.com/video/BVxxxxxx")
    print(json.dumps(result, ensure_ascii=False, indent=2)) 