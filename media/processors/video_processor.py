import cv2
import torch
import requests
from PIL import Image
import logging
from .base_processor import BaseProcessor
import os
from ..utils.translation_utils import translate_text
import numpy as np
from transformers import Blip2Processor, Blip2ForConditionalGeneration
from ram import models
from torchvision import transforms
from google.cloud import vision
from .audio_processor import AudioProcessor  # AudioProcessor 임포트 추가
from pydub import AudioSegment
import subprocess
from datetime import datetime  # datetime 모듈 추가
class VideoProcessor(BaseProcessor):
    def __init__(self, base_manager, ram_model, transform, blip_model, blip_processor, vision_client=None):
        super().__init__(base_manager)
        self.ram_model = ram_model
        self.transform = transform
        self.blip_model = blip_model
        self.blip_processor = blip_processor
        self.vision_client = vision_client
        self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')

    def process_video(self, video_path: str, file_url: str = None):
        """비디오 처리: 프레임 추출, 캡셔닝, 메타데이터용 태깅"""
        try:
            print("\n" + "="*50)
            print(f"비디오 처리 시작: {video_path}")
            print("="*50)
            
            cap = cv2.VideoCapture(video_path)
            if not cap.isOpened():
                raise Exception("비디오 파일을 열 수 없습니다.")

            fps = cap.get(cv2.CAP_PROP_FPS)
            total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            duration = total_frames / fps
            
            if duration < 60:  # 1분 미만
                interval = 15  # 15초마다
            elif duration < 300:  # 5분 미만
                interval = 30
            else:  # 5분 이상
                interval = 45
            
            frame_interval = int(fps * interval)
            frames_data = []
            frame_count = 0
            
            while cap.isOpened():
                ret, frame = cap.read()
                if not ret:
                    break
                    
                if frame_count % frame_interval == 0:
                    print(f"\n[프레임 {frame_count} 처리 중...]")
                    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                    frame_pil = Image.fromarray(frame_rgb)
                    
                    try:
                        # BLIP 캡셔닝 & 번역
                        print("\n[BLIP 캡션 생성 중...]")
                        inputs = self.blip_processor(frame_pil, return_tensors="pt").to(self.device, torch.float16)
                        with torch.no_grad():
                            outputs = self.blip_model.generate(**inputs, max_new_tokens=100)
                            caption = self.blip_processor.decode(outputs[0], skip_special_tokens=True)
                            translated_caption = translate_text(self.base_manager.client, caption, is_caption=True)
                        
                        # RAM 태깅 & 번역
                        print("\n[RAM 태그 생성 중...]")
                        ram_input = self.transform(frame_pil).unsqueeze(0).to(self.device)
                        with torch.no_grad():
                            tags = self.ram_model.generate_tag(ram_input)
                            if isinstance(tags, tuple):
                                tags = tags[0]
                            if isinstance(tags, str):
                                tags = tags.split(' | ')
                            # 태그 번역 추가
                            translated_tags = translate_text(self.base_manager.client, ' | '.join(tags), is_caption=False)
                            translated_tags = [tag.strip() for tag in translated_tags.split('|')]
                        
                        # 임베딩 데이터 저장
                        embedding_data = {
                            'caption': translated_caption,
                            'frame': frame_count,
                            'timestamp': frame_count / fps,
                            'tags': translated_tags  # 번역된 태그
                        }
                        
                        # file_url을 우선적으로 사용
                        success = self.base_manager.create_video_embedding(
                            file_url or video_path,  # file_url이 있으면 사용, 없으면 video_path
                            embedding_data
                        )
                        
                        if success:
                            frames_data.append(embedding_data)
                            
                    except Exception as e:
                        print(f"프레임 처리 중 오류: {str(e)}")
                        frame_count += 1
                        continue
                    
                    frame_count += 1
                else:
                    frame_count += 1
            
            cap.release()
            
            if frames_data:
                return {
                    'file_path': file_url or video_path,  # file_url 우선 사용
                    'frames': frames_data,
                    'type': 'video'
                }
            return None

        except Exception as e:
            logging.error(f"비디오 처리 중 오류: {str(e)}")
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
            return None

    def generate_caption(self, image):
        """BLIP-2 캡셔닝"""
        if not self.blip_processor:
            return None
        try:
            inputs = self.blip_processor(image, return_tensors="pt").to(self.device, torch.float16)
            output = self.blip_processor.generate(**inputs, max_new_tokens=100)
            caption = self.blip_processor.decode(output[0], skip_special_tokens=True)
            return self.translate_caption(caption)
        except Exception as e:
            logging.error(f"캡션 생성 오류: {str(e)}")
            return None

    def generate_tags(self, image):
        """RAM 태깅"""
        if not self.ram_model:
            return None
        try:
            image_tensor = self.transform(image).unsqueeze(0).to(self.device)
            with torch.no_grad():
                tags = self.ram_model.generate_tag(image_tensor)
                if isinstance(tags, tuple):
                    tags = tags[0]
                return self.translate_tags(tags)
        except Exception as e:
            logging.error(f"태그 생성 오류: {str(e)}")
            return None

    def _process_frame_batch(self, frames, frame_infos, video_path):
        try:
            # 1. 모든 프레임 한번에 입력 준비
            blip_inputs = self.blip_processor(frames, return_tensors="pt").to(self.device, torch.float16)
            ram_inputs = torch.stack([self.transform(frame) for frame in frames]).to(self.device)
            
            # 2. 모든 모델 추론 한번에 실행
            with torch.no_grad():
                # BLIP 캡션 생성
                outputs = self.blip_processor.generate(**blip_inputs, max_new_tokens=100)
                captions = [self.blip_processor.decode(output, skip_special_tokens=True) for output in outputs]
                
                # RAM 태그 생성 - 수정된 부분
                batch_tags = self.ram_model.generate_tag(ram_inputs)
                if isinstance(batch_tags, tuple):
                    batch_tags = batch_tags[0]
            
            # 3. 모든 텍스트 한번에 번역
            combined_texts = []
            for caption, tags in zip(captions, batch_tags):
                combined_texts.append(f"{caption} ||| {', '.join(tags)}")
            
            all_text = " <<< >>> ".join(combined_texts)
            translated_text = translate_text(self.base_manager.client, all_text, is_caption=True)
            
            # 4. 번역된 텍스트 분리 및 결과 저장
            batch_results = []
            unique_frames = []
            unique_frame_infos = []
            prev_frame = None

            for frame_info, translated_pair in zip(frame_infos, translated_text.split(" <<< >>> ")):
                caption, tags_text = translated_pair.split(" ||| ")
                tags = [tag.strip() for tag in tags_text.split(',')]
                
                frame_array = np.array(frame_info['frame'])
                if prev_frame is None:
                    unique_frames.append(frame_info['frame'])
                    unique_frame_infos.append(frame_info)
                    prev_frame = frame_array
                else:
                    diff = np.mean((frame_array - prev_frame) ** 2)
                    if diff > 3000:  # 더 큰 차이가 있을 때만 처리
                        unique_frames.append(frame_info['frame'])
                        unique_frame_infos.append(frame_info)
                        prev_frame = frame_array

                embedding_data = {
                    'type': 'video',
                    'caption': caption,
                    'tags': tags,
                    'frame': frame_info['frame'],
                    'timestamp': frame_info['timestamp']
                }
                
                success = self.base_manager.create_video_embedding(video_path, embedding_data)
                if success:
                    batch_results.append(embedding_data)
            
            return batch_results

        except Exception as e:
            logging.error(f"배치 처리 중 오류: {str(e)}")
            return [] 

    def check_audio_volume(self, video_path: str) -> float:
        """비디오의 평균 오디오 볼륨 확인"""
        try:
            # 비디오에서 오디오 추출 (AAC 포맷 사용)
            audio_path = "temp_audio.m4a"  # .mp3 대신 .m4a 사용
            command = f'ffmpeg -i "{video_path}" -vn -c:a aac "{audio_path}"'
            subprocess.call(command, shell=True)
            
            # 오디오 로드 및 볼륨 체크
            audio = AudioSegment.from_file(audio_path, format="m4a")  # format 지정
            volume_rms = audio.rms
            
            # 임시 파일 삭제
            if os.path.exists(audio_path):
                os.remove(audio_path)
                
            return volume_rms
            
        except Exception as e:
            logging.error(f"오디오 볼륨 체크 중 오류: {str(e)}")
            return 0.0


    def process_video_url(self, file_url: str, filename: str) -> dict:
        try:
            logging.info("\n=== 비디오 URL 처리 시작 ===")
            logging.info(f"URL: {file_url}")
            logging.info(f"파일 이름: {filename}")
            
            # 비디오 다운로드
            response = requests.get(file_url, stream=True)
            if response.status_code != 200:
                raise Exception(f"비디오 다운로드 실패 (상태 코드: {response.status_code})")
            
            # 임시 파일로 저장
            temp_path = f"temp_{filename}"
            with open(temp_path, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
            
            if not os.path.exists(temp_path):
                raise Exception("임시 파일 생성 실패")
                
            try:
                # 오디오 볼륨 체크
                volume = self.check_audio_volume(temp_path)
                logging.info(f"오디오 볼륨 레벨: {volume}")
                
                result = None
                
                if volume > 30:  # 볼륨이 30 이상이면 오디오 처리
                    logging.info("유의미한 오디오 감지됨 - 오디오 처리 시작")
                    
                    # ffmpeg로 오디오 추출
                    audio_path = "temp_audio.m4a"
                    command = f'ffmpeg -i "{temp_path}" -vn -c:a aac "{audio_path}"'
                    subprocess.run(command, shell=True, check=True)
                    
                    if not os.path.exists(audio_path):
                        raise Exception("오디오 추출 실패")
                    
                    # AudioProcessor로 오디오 처리
                    audio_processor = AudioProcessor(self.base_manager)
                    audio_result = audio_processor.process_audio(
                        audio_path,
                        file_url=file_url,
                        source_type='video_with_audio'
                    )
                    
                    if audio_result:
                        result = {
                            'file_path': file_url,
                            'type': 'video_with_audio',
                            'audio_segments': audio_result.get('segments', []),
                            'timestamp': datetime.now().isoformat()
                        }
                    
                else:  # 볼륨이 30 미만이면 시각적 처리
                    logging.info("무음 비디오 감지됨 - 시각적 처리 시작")
                    result = self.process_video(temp_path, file_url=file_url)
                
                if result is None:
                    raise Exception("비디오 처리 결과가 없습니다")
                    
                return result
                
            finally:
                # 임시 파일들 정리
                for temp_file in [temp_path, "temp_audio.m4a"]:
                    if os.path.exists(temp_file):
                        os.remove(temp_file)
                        logging.info(f"임시 파일 삭제: {temp_file}")
                
                if torch.cuda.is_available():
                    torch.cuda.empty_cache()
                    logging.info("CUDA 캐시 정리 완료")
                    
        except subprocess.CalledProcessError as e:
            logging.error(f"FFmpeg 처리 실패: {str(e)}")
            raise Exception("오디오 추출 실패")
        except Exception as e:
            logging.error(f"비디오 URL 처리 중 오류: {str(e)}", exc_info=True)
            raise Exception(f"비디오 처리 실패: {str(e)}")