from .processors import (
    ImageProcessor, VideoProcessor, AudioProcessor,
    DocumentProcessor
)
from .processors.crawling_processor import CrawlingProcessor  # 별도로 import
from concurrent.futures import ThreadPoolExecutor, as_completed
import logging
import torch
import os
from torchvision import transforms
from google.cloud import vision
from transformers import Blip2Processor, Blip2ForConditionalGeneration
from ram import models  # RAM 모델만 임포트
from config import *    # 설정값들 임포트
from .utils.constants import (
    IMAGE_EXTENSIONS,
    VIDEO_EXTENSIONS,
    AUDIO_EXTENSIONS,
    DOCUMENT_EXTENSIONS
)

class MediaCoordinator:
    def __init__(self, base_manager):
        self.base_manager = base_manager
        self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        
        # processed_files 속성 추가
        self.processed_files = []
        
        # RAM 모델 초기화
        try:
            ram_model = models.ram_plus(
                pretrained=RAM_MODEL_PATH,
                image_size=384,
                vit='swin_l'
            )
            ram_model = ram_model.to(self.device)
            ram_model.eval()
            
            # Transform 초기화
            transform = transforms.Compose([
                transforms.Resize((384, 384)),
                transforms.ToTensor(),
                transforms.Normalize(
                    mean=[0.485, 0.456, 0.406],
                    std=[0.229, 0.224, 0.225]
                )
            ])
            
            # BLIP 초기화
            blip_processor = Blip2Processor.from_pretrained("Salesforce/blip2-opt-2.7b")
            blip_model = Blip2ForConditionalGeneration.from_pretrained(
                "Salesforce/blip2-opt-2.7b",
                torch_dtype=torch.float16
            ).to(self.device)
            
            # Vision 클라이언트 초기화
            vision_client = vision.ImageAnnotatorClient()
            
        except Exception as e:
            logging.error(f"모델 초기화 실패: {str(e)}")
            raise e
            
        # 초기화된 모델들을 각 프로세서에 전달
        self.image_processor = ImageProcessor(
            base_manager,
            ram_model=ram_model,
            transform=transform,
            blip_model=blip_model,
            blip_processor=blip_processor,
            vision_client=vision_client
        )
        
        self.video_processor = VideoProcessor(
            base_manager,
            ram_model=ram_model,
            transform=transform,
            blip_model=blip_model,
            blip_processor=blip_processor,
            vision_client=vision_client
        )
        
        self.audio_processor = AudioProcessor(base_manager)
        self.document_processor = DocumentProcessor(base_manager)
        self.crawling_processor = CrawlingProcessor(base_manager)

    def process_file(self, file_path: str):
        """
        단일 파일을 처리합니다.
        
        Args:
            file_path (str): 처리할 파일 경로
            
        Returns:
            dict: 처리 결과
            None: 처리 실패 시
        """
        if not file_path or not isinstance(file_path, str):
            logging.error("유효하지 않은 파일 경로입니다.")
            return None
            
        try:
            logging.info(f"파일 처리 시작: {file_path}")
            
            if not os.path.exists(file_path):
                logging.error(f"파일이 존재하지 않습니다: {file_path}")
                return None
                
            ext = os.path.splitext(file_path)[1].lower()
            
            if ext in IMAGE_EXTENSIONS:
                logging.info("이미지 파일 처리 중...")
                return self.image_processor.process_image(file_path)
            elif ext in VIDEO_EXTENSIONS:
                logging.info("비디오 파일 처리 중...")
                return self.video_processor.process_video(file_path)
            elif ext in AUDIO_EXTENSIONS:
                logging.info("오디오 파일 처리 중...")
                return self.audio_processor.process_audio(file_path)
            elif ext in DOCUMENT_EXTENSIONS:
                logging.info("문서 파일 처리 중...")
                return self.document_processor.process_file(file_path)
            else:
                logging.warning(f"지원하지 않는 파일 형식입니다: {ext}")
                return None

        except Exception as e:
            logging.error(f"파일 처리 중 오류 발생: {str(e)}", exc_info=True)
            return None

    def process_directory(self, path: str):
        """
        디렉토리 또는 파일 경로들을 처리합니다.
        
        Args:
            path (str): 처리할 디렉토리 또는 파일 경로들 (쉼표로 구분)
            
        Returns:
            list: 처리된 결과 목록
        """
        if not path or not isinstance(path, str):
            logging.error("유효하지 않은 경로입니다.")
            return []
            
        try:
            logging.info("경로 처리 시작")
            
            if path.isspace():
                logging.error("경로가 비어있습니다.")
                return []
            
            # 파일 리스트 초기화
            image_files = []
            video_files = []
            audio_files = []
            document_files = []
            
            # 경로 전처리 - 따옴표 제거 및 정규화
            paths = []
            for p in path.split(','):
                clean_path = p.strip().strip('"').strip("'").strip()
                if clean_path:
                    try:
                        norm_path = os.path.normpath(clean_path)
                        if os.path.exists(norm_path):
                            paths.append(norm_path)
                        else:
                            print(f"경로를 찾을 수 없습니다: {clean_path}")
                    except:
                        print(f"잘못된 경로 형식: {clean_path}")
            
            if not paths:
                print("처리할 수 있는 경로가 없습니다.")
                return []
            
            # 각 경로 처리
            for single_path in paths:
                if os.path.isfile(single_path):  # 단일 파일
                    ext = os.path.splitext(single_path)[1].lower()
                    if ext in IMAGE_EXTENSIONS:
                        image_files.append(single_path)
                    elif ext in VIDEO_EXTENSIONS:
                        video_files.append(single_path)
                    elif ext in AUDIO_EXTENSIONS:
                        audio_files.append(single_path)
                    elif ext in DOCUMENT_EXTENSIONS:
                        document_files.append(single_path)
                    else:
                        print(f"지원하지 않는 파일 형식: {single_path}")
                
                elif os.path.isdir(single_path):  # 디렉토리
                    for root, _, files in os.walk(single_path):
                        for file in files:
                            file_path = os.path.join(root, file)
                            ext = os.path.splitext(file)[1].lower()
                            if ext in IMAGE_EXTENSIONS:
                                image_files.append(file_path)
                            elif ext in VIDEO_EXTENSIONS:
                                video_files.append(file_path)
                            elif ext in AUDIO_EXTENSIONS:
                                audio_files.append(file_path)
                            elif ext in DOCUMENT_EXTENSIONS:
                                document_files.append(file_path)

            # 중복 제거
            image_files = list(dict.fromkeys(image_files))
            video_files = list(dict.fromkeys(video_files))
            audio_files = list(dict.fromkeys(audio_files))
            document_files = list(dict.fromkeys(document_files))

            # 처리할 파일 개수 출력
            total_files = len(image_files) + len(video_files) + len(audio_files) + len(document_files)
            if total_files == 0:
                print("\n처리할 파일이 없습니다.")
                return []
            
            print(f"\n총 처리할 파일: {total_files}개")
            print(f"- 이미지: {len(image_files)}개")
            print(f"- 비디오: {len(video_files)}개")
            print(f"- 오디오: {len(audio_files)}개")
            print(f"- 문서: {len(document_files)}개\n")

            processed_results = []
            
            # 이미지 배치 처리
            if image_files:
                print("\n=== 이미지 처리 시작 ===")
                batch_size = 4
                for i in range(0, len(image_files), batch_size):
                    batch = image_files[i:i + batch_size]
                    with ThreadPoolExecutor(max_workers=batch_size) as executor:
                        futures = [executor.submit(self.image_processor.process_image, f) for f in batch]
                        for future in as_completed(futures):
                            result = future.result()
                            if result:
                                processed_results.append(result)
                    
                    progress = min((i + batch_size) / len(image_files) * 100, 100)
                    print(f"이미지 처리 진행률: {progress:.1f}%")
                    
                    if torch.cuda.is_available():
                        torch.cuda.empty_cache()

            # 비디오 처리
            if video_files:
                print("\n=== 비디오 처리 시작 ===")
                for i, video_file in enumerate(video_files, 1):
                    result = self.video_processor.process_video(video_file)
                    if result:
                        processed_results.append(result)
                    print(f"비디오 처리 진행률: {(i/len(video_files))*100:.1f}%")

            # 오디오 처리
            if audio_files:
                print("\n=== 오디오 처리 시작 ===")
                for i, audio_file in enumerate(audio_files, 1):
                    result = self.audio_processor.process_audio(audio_file)
                    if result:
                        processed_results.append(result)
                    print(f"오디오 처리 진행률: {(i/len(audio_files))*100:.1f}%")

            # 문서 처리 추가
            if document_files:
                print("\n=== 문서 처리 시작 ===")
                for i, doc_file in enumerate(document_files, 1):
                    result = self.document_processor.process_file(doc_file)
                    if result:
                        processed_results.append(result)
                    print(f"문서 처리 진행률: {(i/len(document_files))*100:.1f}%")

            print("\n=== 처리 완료 ===")
            print(f"성공적으로 처리된 파일: {len(processed_results)}개")
            
            return processed_results

        except Exception as e:
            logging.error(f"디렉토리 처리 중 오류: {str(e)}")
            return []

    def process_url(self, url: str):
        """웹 페이지 처리"""
        try:
            print("\n=== 웹 페이지 처리 시작 ===")
            web_data = self.crawling_processor.extract_content(url)
            if web_data:
                result = self.crawling_processor.save_to_pinecone(url, web_data)
                if result:
                    print("웹 페이지 처리 완료")
                    return {'url': url, 'metadata': web_data}
            return None
        except Exception as e:
            logging.error(f"웹 페이지 처리 중 오류: {str(e)}")
            return None
        
    def process_media_url(self, file_url: str, file_type: str, file_name: str, save_frames: bool = False):
        try:
            logging.info("\n=== URL 미디어 처리 시작 ===")
            logging.info(f" 파일명: {file_name}")
            logging.info(f" 파일 타입: {file_type}")
            logging.info(f" 파일 URL: {file_url}")

            result = None

            if file_type == 'image':
                result = self.image_processor.process_image_url(file_url, file_name)

            elif file_type == 'video':
                result = self.video_processor.process_video_url(file_url, file_name)

            elif file_type == 'audio':
                result = self.audio_processor.process_audio_url(file_url, file_name)

            elif file_type in ['document', 'pdf', 'word', 'pptx', 'xlsx', 'hwp']:  
                logging.info(f" 문서 처리 시작: {file_name}")
                result = self.document_processor.process_document_url(file_url)

                if result and "content" in result:
                    extracted_text = result["content"]
                    logging.info(f" 문서 추출 텍스트 (일부): {extracted_text[:100]}...")  

                self.base_manager.create_document_embedding(file_url, result)

            elif file_type == 'url':
                logging.info(f" 웹 페이지 처리 시작: {file_name}")
                result = self.process_url(file_url)  

            else:
                logging.error(f" 지원하지 않는 파일 형식입니다: {file_type}")
                raise ValueError(f"지원하지 않는 파일 형식: {file_type}")

            if result is None:
                logging.error(f" {file_type} 처리 결과가 없습니다.")
                raise Exception(f"{file_type} 처리 실패")

            logging.info(f"미디어 처리 완료: {file_name}")
            return result

        except ValueError as e:
            logging.error(f"입력값 오류: {str(e)}")
            raise
        except Exception as e:
            logging.error(f"URL 미디어 처리 중 오류: {str(e)}", exc_info=True)
            raise
