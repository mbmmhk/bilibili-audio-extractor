from flask import Flask, render_template, request, jsonify
from video_processor import VideoProcessor
from qq_music_matcher import QQMusicMatcher
import threading
import time
import logging
import sys
import os
from logger_config import setup_logger

setup_logger()

logger = logging.getLogger(__name__)

app = Flask(__name__)

# 全局变量
progress = {
    'status': 'idle',
    'percent': 0,
    'message': '',
    'results': None
}

# 当前处理线程
current_task = {
    'thread': None,
    'should_stop': False
}

def process_video(url):
    global progress, current_task
    
    def progress_callback(data):
        if not current_task['should_stop']:
            progress.update(data)
    
    try:
        video_processor = VideoProcessor()
        audio_file = None
        
        try:
            # 下载和提取音频
            audio_file = video_processor.download_and_extract_audio(url, progress_callback)
            
            if current_task['should_stop']:
                raise Exception("任务已取消")
            
            # 使用 QQ 音乐匹配
            matcher = QQMusicMatcher()
            results = matcher.match_song(audio_file, progress_callback)
            
            if current_task['should_stop']:
                raise Exception("任务已取消")
            
            # 完成
            progress.update({
                'status': 'done',
                'message': '识别完成！',
                'percent': 100,
                'results': results
            })
            
        finally:
            # 清理临时文件
            if audio_file and os.path.exists(audio_file):
                try:
                    os.remove(audio_file)
                except:
                    pass
            
    except Exception as e:
        logger.error(f"处理过程出错: {str(e)}", exc_info=True)
        progress.update({
            'status': 'error',
            'message': str(e),
            'percent': 0
        })
    finally:
        current_task['thread'] = None
        current_task['should_stop'] = False

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/submit', methods=['POST'])
def submit_url():
    global current_task
    
    # 如果有正在进行的任务，返回错误
    if current_task['thread'] and current_task['thread'].is_alive():
        return jsonify({'error': '已有任务正在进行中'}), 400
    
    url = request.json.get('url')
    if not url:
        return jsonify({'error': '请输入视频URL'}), 400
    
    # 重置进度
    progress.update({
        'status': 'idle',
        'percent': 0,
        'message': '',
        'results': None
    })
    
    # 启动新线程
    current_task['should_stop'] = False
    current_task['thread'] = threading.Thread(target=process_video, args=(url,))
    current_task['thread'].start()
    
    return jsonify({'message': '开始处理'})

@app.route('/cancel', methods=['POST'])
def cancel_task():
    global current_task, progress
    if current_task['thread'] and current_task['thread'].is_alive():
        current_task['should_stop'] = True
        progress.update({
            'status': 'canceling',
            'message': '正在取消任务...',
            'percent': 0
        })
        return jsonify({'message': '正在取消任务'})
    return jsonify({'message': '没有正在进行的任务'})

@app.route('/progress')
def get_progress():
    return jsonify(progress)

if __name__ == '__main__':
    # 确保下载目录存在
    os.makedirs('downloads', exist_ok=True)
    
    # 启动服务器
    logger.info("启动服务器...")
    app.run(host='127.0.0.1', port=5000, debug=False) 