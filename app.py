from flask import Flask, request, jsonify, render_template, send_from_directory
from src.video_processor import VideoProcessor
from src.demucs_processor import DemucsProcessor
import os

app = Flask(__name__)

# 配置下载目录
DOWNLOAD_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "downloads")
os.makedirs(DOWNLOAD_DIR, exist_ok=True)

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/process', methods=['POST'])
def process_video():
    try:
        data = request.get_json()
        url = data.get('url')
        
        if not url:
            return jsonify({'success': False, 'error': '请提供视频URL'})
            
        # 下载视频并提取音频
        video_processor = VideoProcessor()
        audio_file = video_processor.download_and_extract_audio(url)
        
        # 获取视频文件路径
        video_file = audio_file.replace('audio_', 'video_').replace('.wav', '.mp4')
        
        # 分离人声
        demucs_processor = DemucsProcessor()
        vocals_file = demucs_processor.process_audio(audio_file)
        
        return jsonify({
            'success': True,
            'video_file': f'/download/{os.path.basename(video_file)}',
            'original_audio': f'/download/{os.path.basename(audio_file)}',
            'vocals_audio': f'/download/{os.path.basename(vocals_file)}'
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@app.route('/download/<filename>')
def download_file(filename):
    return send_from_directory(DOWNLOAD_DIR, filename)

if __name__ == '__main__':
    app.run(debug=True) 