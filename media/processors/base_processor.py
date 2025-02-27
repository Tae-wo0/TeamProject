from ..utils.translation_utils import translate_text
import logging
from config import PINECONE_NAMESPACE  # 설정에서 namespace 임포트

class BaseProcessor:
    def __init__(self, base_manager):
        self.base_manager = base_manager

    def translate_caption(self, caption):
        return translate_text(self.base_manager.client, caption, is_caption=True)

    def translate_tags(self, tags):
        tags_text = ', '.join(tags)
        translated = translate_text(self.base_manager.client, tags_text, is_caption=False)
        return [tag.strip() for tag in translated.split(',')]

    def process_media(self, file_path: str):
        """미디어 파일 처리"""
        try:
            media_type = self.get_media_type(file_path)
            
            if media_type == 'image':
                return self.image_processor.process_image(file_path)
            elif media_type == 'video':
                return self.video_processor.process_video(file_path)
            elif media_type == 'audio':
                return self.audio_processor.process_audio(file_path)
            else:
                print(f"지원하지 않는 미디어 타입: {media_type}")
                return False
            
        except Exception as e:
            print(f"미디어 처리 중 오류 발생: {str(e)}")
            return False 