import logging
import sys

def setup_logger():
    # 创建日志记录器
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)
    
    # 创建控制台处理器
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.INFO)
    
    # 设置日志格式
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    console_handler.setFormatter(formatter)
    
    # 清除现有的处理器
    logger.handlers.clear()
    
    # 添加处理器到日志记录器
    logger.addHandler(console_handler)
    
    return logger 