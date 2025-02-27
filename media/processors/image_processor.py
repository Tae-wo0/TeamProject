import torch
import logging
from PIL import Image
from google.cloud import vision
from .base_processor import BaseProcessor
from ..utils.translation_utils import translate_text
import requests
from io import BytesIO
import tempfile
import os

class ImageProcessor(BaseProcessor):
    def __init__(self, base_manager, ram_model, transform, blip_model, blip_processor, vision_client=None):
        super().__init__(base_manager)
        self.ram_model = ram_model
        self.transform = transform
        self.blip_model = blip_model
        self.blip_processor = blip_processor
        self.vision_client = vision_client
        self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')

    def process_image(self, file_path: str, file_url: str = None):
        try:
            print("\n" + "="*50)
            print(f"이미지 처리 시작: {file_path}")
            print("="*50)
            
            original_file_url = file_url if file_url else file_path

            # 이미지 한 번만 로드
            image = Image.open(file_path).convert('RGB')

            # OCR 처리
            print("\n[OCR 처리 중...]")
            ocr_text = self.detect_text(file_path)
            if ocr_text:
                print(f"감지된 텍스트: {ocr_text}")
            else:
                print("텍스트가 감지되지 않았습니다.")
                ocr_text = ''

            # BLIP과 RAM 동시 처리
            print("\n[BLIP 캡션 생성 중...]")
            try:
                inputs = self.blip_processor(image, return_tensors="pt").to(self.device, torch.float16)
                with torch.no_grad():
                    outputs = self.blip_model.generate(**inputs, max_new_tokens=100)
                    caption = self.blip_processor.decode(outputs[0], skip_special_tokens=True)
            except Exception as e:
                print(f"캡션 생성 중 오류: {str(e)}")
                return None

            print("\n[RAM 태그 생성 중...]")
            try:
                ram_input = self.transform(image).unsqueeze(0).to(self.device)
                with torch.no_grad():
                    result = self.ram_model.generate_tag(ram_input)
                    if isinstance(result, tuple):
                        tags = result[0][0].split(' | ')
                    else:
                        tags = result[0].split(' | ')

                    print(f"[디버그] 분리된 태그들: {tags}")

                    # 캡션과 태그 따로 번역
                    translated_caption = self.translate_caption(caption)
                    translated_tags = self.translate_tags(tags)

                    print(f"\n생성된 캡션: {translated_caption}")
                    print(f"생성된 태그: {' | '.join(translated_tags)}")

                    caption = translated_caption
                    tags = translated_tags

            except Exception as e:
                print(f"RAM 태그 생성 중 오류: {str(e)}")
                return None

            embedding_data = {
                'type': 'image',
                'file_url': original_file_url, 
                'caption': caption,
                'tags': tags,
                'ocr_text': ocr_text
            }

            success = self.base_manager.create_image_embedding(original_file_url, embedding_data)
            if not success:
                print("임베딩 저장 실패")
                return None

            print("\n=== 이미지 처리 완료 ===")
            return {'file_url': original_file_url, 'metadata': embedding_data}  

        except Exception as e:
            logging.error(f"이미지 처리 중 오류 ({file_path}): {str(e)}")
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
            return None


    def generate_caption(self, file_url: str):
        """BLIP-2 캡셔닝"""
        if not self.blip_processor:
            return None
        try:
            image = Image.open(file_url).convert('RGB')
            inputs = self.blip_processor(image, return_tensors="pt").to(self.device, torch.float16)
            output = self.blip_processor.generate(**inputs, max_new_tokens=100)
            caption = self.blip_processor.decode(output[0], skip_special_tokens=True)
            return self.translate_caption(caption)
        except Exception as e:
            logging.error(f"캡션 생성 오류: {str(e)}")
            return None

    def generate_tags(self, file_url: str):
        """RAM 태깅"""
        if not self.ram_model:
            return None
        try:
            image = Image.open(file_url).convert('RGB')
            image_tensor = self.transform(image).unsqueeze(0).to(self.device)
            with torch.no_grad():
                tags = self.ram_model.generate_tag(image_tensor)
                return self.translate_tags(tags)
        except Exception as e:
            logging.error(f"태그 생성 오류: {str(e)}")
            return None

    def detect_text(self, file_url: str):
        """OCR 처리"""
        if not self.vision_client:
            return None
        try:
            with open(file_url, 'rb') as image_file:
                content = image_file.read()
            image = vision.Image(content=content)
            response = self.vision_client.text_detection(image=image)
            texts = response.text_annotations
            return texts[0].description if texts else None
        except Exception as e:
            logging.error(f"OCR 처리 오류: {str(e)}")
            return None

    def translate_caption(self, caption):
        return translate_text(self.base_manager.client, caption, is_caption=True)

    def translate_tags(self, tags):
        tags_text = ', '.join(tags)
        translated = translate_text(self.base_manager.client, tags_text, is_caption=False)
        return [tag.strip() for tag in translated.split(',')]
    
    def process_image_url(self, file_url: str, file_name: str):
        """URL 이미지 처리 메서드"""
        try:
            print(f"\n=== URL 이미지 처리 시작 ===")
            print(f"URL: {file_url}")
            print(f"파일명: {file_name}")

            # URL에서 이미지 다운로드
            response = requests.get(file_url)
            if response.status_code != 200:
                raise ValueError(f"이미지 다운로드 실패: {response.status_code}")

            # 임시 파일로 저장
            with tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(file_name)[1]) as temp_file:
                temp_file.write(response.content)
                temp_path = temp_file.name

            try:
                result = self.process_image(temp_path, file_url=file_url)

                if result:
                    print(f"\n=== URL 이미지 처리 완료 ===")
                    return result
                else:
                    print(f"\n=== URL 이미지 처리 실패 ===")
                    return None

            finally:
                # 임시 파일 삭제
                if os.path.exists(temp_path):
                    os.remove(temp_path)

        except Exception as e:
            logging.error(f"URL 이미지 처리 중 오류 발생: {str(e)}")
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
            return None
