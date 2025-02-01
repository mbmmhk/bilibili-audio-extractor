# 将现有的 whisper_matcher.py 重命名为 demucs_processor.py
# 并将类名从 WhisperMatcher 改为 DemucsProcessor 

import logging
from typing import List, Dict
from pydub import AudioSegment
import os
import tempfile
import torchaudio
from demucs.pretrained import get_model
from demucs.apply import apply_model
import torch
import uuid

logger = logging.getLogger(__name__)

class DemucsProcessor:
    def __init__(self):
        print("正在加载模型...")
        # 初始化 demucs
        self.separator = get_model('htdemucs')
        self.separator.cpu()  # 使用CPU运行
        print("模型加载完成！")
    
    def _separate_vocals(self, audio_file: str) -> str:
        """分离人声"""
        try:
            print("正在分离人声，请稍候...")
            # 加载音频
            audio, sr = torchaudio.load(audio_file)
            
            # 确保音频是双声道的
            if audio.shape[0] == 1:
                audio = audio.repeat(2, 1)
            
            # 分离音轨
            with torch.no_grad():
                audio = audio.unsqueeze(0)  # 添加批次维度
                sources = apply_model(self.separator, audio, device='cpu')
                
                # 打印所有音轨的形状
                print("\n音轨信息:")
                print(f"Sources shape: {sources.shape}")
                for i, name in enumerate(['vocals', 'drums', 'bass', 'other']):
                    print(f"{name} shape: {sources[0, i].shape}")
                
                # 获取人声音轨 (other)
                vocals = sources[0, 3]  # 第四个音轨是人声
                
                # 增加音量以突出人声
                vocals = vocals * 1.5  # 可以调整这个倍数
                
                # 生成随机文件名
                vocals_filename = f"vocals_{uuid.uuid4().hex[:8]}.wav"
                vocals_file = os.path.join("downloads", vocals_filename)
                
                # 确保downloads目录存在
                os.makedirs("downloads", exist_ok=True)
                
                # 保存人声文件
                torchaudio.save(vocals_file, vocals, sr)
                
                print(f"人声分离完成！保存为: {vocals_file}")
                return vocals_file
                
        except Exception as e:
            logger.error(f"人声分离失败: {str(e)}")
            import traceback
            logger.error(traceback.format_exc())
            return audio_file
    
    def process_audio(self, audio_file: str) -> str:
        """处理音频文件"""
        try:
            # 加载音频
            audio = AudioSegment.from_wav(audio_file)
            
            # 转换为单声道
            audio = audio.set_channels(1)
            
            print(f"音频长度: {len(audio)/1000:.1f}秒")
            
            # 生成随机文件名保存处理后的音频
            processed_filename = f"processed_{uuid.uuid4().hex[:8]}.wav"
            processed_file = os.path.join("downloads", processed_filename)
            
            # 确保downloads目录存在
            os.makedirs("downloads", exist_ok=True)
            
            # 保存处理后的音频
            audio.export(processed_file, format='wav')
            print(f"音频处理完成！保存为: {processed_file}")
            
            # 分离人声
            vocals_file = self._separate_vocals(processed_file)
            
            return vocals_file
            
        except Exception as e:
            logger.error(f"音频处理失败: {str(e)}")
            return audio_file 