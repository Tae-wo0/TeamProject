from pydub import AudioSegment
import logging
import requests
import os
from .base_processor import BaseProcessor
from datetime import datetime

class AudioProcessor(BaseProcessor):
    def __init__(self, base_manager):
        super().__init__(base_manager)
        
    def process_audio_url(self, file_url: str, file_name: str = None) -> dict:
        """URL로부터 오디오를 처리"""
        try:
            print("\n=== 오디오 URL 처리 시작 ===")
            print(f"URL: {file_url}")
            print(f"파일명: {file_name}")
            
            # 오디오 다운로드
            response = requests.get(file_url, stream=True)
            if response.status_code != 200:
                raise Exception("오디오 다운로드 실패")
            
            # 임시 파일로 저장
            temp_path = "temp_audio.mp3"
            with open(temp_path, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
    
            try:
                # 공통 처리 로직 호출
                result = self._process_audio_file(temp_path, file_url=file_url, file_name=file_name)
                return result
                
            finally:
                # 임시 파일 삭제
                if os.path.exists(temp_path):
                    os.remove(temp_path)
                    
        except Exception as e:
            logging.error(f"오디오 URL 처리 중 오류: {str(e)}")
            return None

    def process_audio(self, file_path: str, file_url: str = None, source_type: str = 'audio') -> dict:
        """로컬 오디오 파일 처리"""
        try:
            print("\n" + "="*50)
            print(f"오디오 처리 시작: {file_path}")
            if file_url:
                print(f"원본 URL: {file_url}")
            print("="*50)
            
            return self._process_audio_file(file_path, file_url=file_url, source_type=source_type)
            
        except Exception as e:
            logging.error(f"오디오 처리 중 오류: {str(e)}")
            return None

    def _process_audio_file(self, file_path: str, file_url: str = None, file_name: str = None, source_type: str = 'audio') -> dict:
        """오디오 파일 처리 공통 로직"""
        try:
            # 전체 오디오를 한 번에 Whisper로 변환
            print("\n[전체 오디오 텍스트 변환 중...]")
            full_text = self.transcribe_audio(file_path)
            print(f"\n전체 텍스트 추출 완료: {len(full_text)}자")
            
            # 전체 텍스트를 문장 단위로 분할
            sentences = full_text.split('. ')
            segments = []
            current_chunk = []
            current_length = 0
            chunk_index = 0
            chunk_size = 300
            overlap_size = 75
            
            # 저장할 경로 결정
            target_path = file_url if file_url else file_path
            
            for sentence in sentences:
                sentence = sentence.strip() + '. '
                sentence_length = len(sentence)
                
                if current_length + sentence_length > chunk_size:
                    chunk_text = ''.join(current_chunk)
                    
                    chunk_data = {
                        'type': source_type,
                        'caption': chunk_text,
                        'frame': chunk_index,
                        'timestamp': datetime.now().isoformat()
                    }
                    
                    success = self.base_manager.create_url_embedding(
                        target_path,
                        chunk_data,
                        source_type
                    )
                    
                    if success:
                        segments.append(chunk_data)
                    
                    overlap_text = chunk_text[-overlap_size:] if overlap_size > 0 else ""
                    current_chunk = [overlap_text, sentence] if overlap_text else [sentence]
                    current_length = len(overlap_text) + sentence_length
                    chunk_index += 1
                else:
                    current_chunk.append(sentence)
                    current_length += sentence_length
            
            # 마지막 청크 처리
            if current_chunk:
                chunk_text = ''.join(current_chunk)
                chunk_data = {
                    'type': source_type,
                    'caption': chunk_text,
                    'frame': chunk_index,
                    'timestamp': datetime.now().isoformat()
                }
                
                success = self.base_manager.create_url_embedding(
                    target_path,
                    chunk_data,
                    source_type
                )
                
                if success:
                    segments.append(chunk_data)
            
            result = {
                'file_path': target_path,
                'file_name': file_name,
                'segments': segments,
                'type': source_type,
                'total_text_length': len(full_text),
                'total_chunks': len(segments)
            }
            
            return result
            
        except Exception as e:
            logging.error(f"오디오 파일 처리 중 오류: {str(e)}")
            return None

    def transcribe_audio(self, audio_path: str) -> str:
        """OpenAI Whisper API를 사용하여 오디오를 텍스트로 변환"""
        try:
            with open(audio_path, "rb") as audio_file:
                transcript = self.base_manager.client.audio.transcriptions.create(
                    model="whisper-1",
                    file=audio_file,
                    response_format="text"
                )
                return transcript
        except Exception as e:
            logging.error(f"OpenAI Whisper API 오류: {str(e)}")
            return ""