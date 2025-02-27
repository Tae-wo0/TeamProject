# base_manager.py
from openai import OpenAI
from pinecone import Pinecone
from typing import List, Dict
import logging
from datetime import datetime
from config import *
import re
from media.utils.text_utils import create_text_chunks
from config import PINECONE_NAMESPACE
import hashlib
import os

class BaseManager:
    def __init__(self, openai_api_key: str):
        # OpenAI 클라이언트 초기화
        self.client = OpenAI(api_key=openai_api_key)
        
        # Pinecone 초기화
        try:
            self.pc = Pinecone(api_key=PINECONE_API_KEY)
            existing_indexes = self.pc.list_indexes().names()
            
            if PINECONE_INDEX_NAME not in existing_indexes:
                print(f"인덱스 '{PINECONE_INDEX_NAME}' 생성 중...")
                self.pc.create_index(
                    name=PINECONE_INDEX_NAME,
                    dimension=1536,
                    metric='cosine',
                    spec={"serverless": {"cloud": "aws", "region": "us-west-2"}}
                )
                print("인덱스 생성 완료")
            
            self.index = self.pc.Index(PINECONE_INDEX_NAME)
            print("Pinecone 연결 성공")
            
        except Exception as e:
            print(f"Pinecone 초기화 실패: {str(e)}")
            print("상세 오류:")
            print(f"- API 키: {'설정됨' if PINECONE_API_KEY else '설정되지 않음'}")
            print(f"- 인덱스 이름: {PINECONE_INDEX_NAME}")
            self.pc = None
            self.index = None



    def create_embedding(self, text: str) -> List[float]:
        """단일 텍스트의 임베딩 생성"""
        try:
            # 임베딩 전 텍스트 출력
            print("\n=== 임베딩 입력 텍스트 ===")
            print(text)
            print("="*50)
            
            response = self.client.embeddings.create(
                model="text-embedding-3-small",  # 모델 변경 가능
                input=text
            )
            
            embedding = response.data[0].embedding
            print(f"임베딩 벡터 크기: {len(embedding)}")
            return embedding
            
        except Exception as e:
            print(f"임베딩 생성 실패: {str(e)}")
            return None

    def batch_create_embeddings(self, chunks: List[str]) -> List[Dict]:
        """여러 청크의 임베딩 일괄 생성"""
        try:
            response = self.client.embeddings.create(
                model="text-embedding-3-small",
                input=chunks
            )
            
            return [{
                'chunk_id': i,
                'embedding': data.embedding,
                'text': chunks[i]
            } for i, data in enumerate(response.data)]
            
        except Exception as e:
            print(f"임베딩 생성 중 오류: {str(e)}")
            return []

    def create_safe_id(self, file_path: str, content_type: str) -> str:
        """안전한 벡터 ID 생성"""
        # 파일명만 추출 (경로 제외)
        file_name = os.path.basename(file_path)
        
        # 파일 경로를 해시로 변환
        path_hash = hashlib.md5(file_path.encode()).hexdigest()[:10]
        
        # 안전한 ID 생성: hash_contenttype
        safe_id = f"{path_hash}_{content_type}"
        return safe_id
    

    def create_image_embedding(self, file_path: str, data: Dict):
        """이미지 임베딩 생성 및 저장"""
        try:
            # 메타데이터 구성
            metadata = {
                'file_path': data.get('file_url', file_path),
                'type': 'image',
                'timestamp': datetime.now().isoformat(),
                'caption': data.get('caption', ''),
                'tags': data.get('tags', []),
                'ocr': data.get('ocr_text', '')  # null이면 빈 문자열로
            }

            # OCR이 None인 경우 빈 문자열로 변경
            if metadata['ocr'] is None:
                metadata['ocr'] = ''

            vectors = []
            vector_id = self.create_safe_id(file_path, 'image')

            # 캡션 임베딩
            caption_embedding = self.create_embedding(metadata['caption'])
            if caption_embedding:
                vectors.append({
                    'id': vector_id + "_caption",
                    'values': caption_embedding,
                    'metadata': metadata
                })

            # OCR 텍스트가 있는 경우 OCR 임베딩도 추가
            if metadata['ocr']:
                ocr_embedding = self.create_embedding(metadata['ocr'])
                if ocr_embedding:
                    vectors.append({
                        'id': vector_id + "_ocr",
                        'values': ocr_embedding,
                        'metadata': metadata
                    })

            if vectors:
                self.index.upsert(
                    vectors=vectors,
                    namespace=PINECONE_NAMESPACE
                )
                return True

            return False

        except Exception as e:
            logging.error(f"이미지 임베딩 저장 실패: {str(e)}")
            return False

    def create_video_embedding(self, file_url: str, frame_data: Dict):
        """비디오 프레임 임베딩 생성 및 저장"""
        try:
            # 메타데이터 구성
            metadata = {
                'file_path': file_url,  # 원본 URL 저장
                'type': 'video',
                'timestamp': datetime.now().isoformat(),
                'frame_number': frame_data.get('frame', 0),
                'video_timestamp': frame_data.get('timestamp', 0.0),
                'caption': frame_data.get('caption', ''),
                'tags': frame_data.get('tags', [])
            }

            # 캡션만 임베딩
            embedding = self.create_embedding(metadata['caption'])
            if embedding:
                vector_id = f"{self.create_safe_id(file_url, 'video')}_{metadata['frame_number']}"
                self.index.upsert(
                    vectors=[{
                        'id': vector_id,
                        'values': embedding,
                        'metadata': metadata
                    }],
                    namespace=PINECONE_NAMESPACE
                )
                return True

            return False

        except Exception as e:
            logging.error(f"비디오 임베딩 저장 실패: {str(e)}")
            return False


    def create_audio_embedding(self, text: str, chunk_index: int = None) -> Dict:
        """오디오 임베딩 생성"""
        try:
            print("\n=== 오디오 임베딩 생성 ===")
            print(f"텍스트: {text}")
            if chunk_index is not None:
                print(f"청크 인덱스: {chunk_index}")

            embedding = self.create_embedding(text)
            
            return {
                'embedding': embedding,
                'chunk_index': chunk_index
            }

        except Exception as e:
            print(f"오디오 임베딩 생성 실패: {str(e)}")
            return None

    def create_text_chunks(text: str, chunk_size: int = 500, overlap: int = 100) -> List[Dict]:
        """텍스트를 청크 단위로 분할 (딕셔너리 형태로 반환)"""
        chunks = []
        sentences = re.split(r'(?<=[.!?])\s+', text)  # 문장 단위로 나누기
        current_chunk = ""

        for sentence in sentences:
            sentence = sentence.strip()
            if not sentence:
                continue

            if len(current_chunk) + len(sentence) > chunk_size:
                if current_chunk:
                    chunks.append({"chunk_index": len(chunks), "text": current_chunk})  
                    current_chunk = current_chunk[-overlap:] + " " + sentence
                else:
                    current_chunk = sentence
            else:
                current_chunk = current_chunk + " " + sentence if current_chunk else sentence

        if current_chunk:
            chunks.append({"chunk_index": len(chunks), "text": current_chunk})  

        logging.info(f"생성된 청크 개수: {len(chunks)}")  # 청크 개수 확인
        return chunks





    def create_long_text_embedding(self, text: str, text_type: str = 'document') -> List[Dict]:
        """장문 텍스트(문서/오디오 변환 텍스트 등) 임베딩 생성"""
        try:
            logging.info(f"\n=== {text_type} 임베딩 생성 ===")
            logging.info(f"전체 텍스트 길이: {len(text)} 문자")

            chunk_settings = {
                'document': {'size': 1000, 'overlap': 200},
                'audio': {'size': 500, 'overlap': 100},
                'crawled': {'size': 800, 'overlap': 150}
            }

            settings = chunk_settings.get(text_type, {'size': 500, 'overlap': 100})

            chunk_results = create_text_chunks(
                text=text,
                chunk_size=settings['size'],
                overlap=settings['overlap']
            )

            fixed_chunk_results = []
            for i, chunk in enumerate(chunk_results):
                if isinstance(chunk, str):
                    logging.error(f" 문자열이 청크 리스트에 포함됨! 변환 처리 중...: {chunk}")
                    chunk = {"chunk_index": i, "text": chunk}
                
                if not isinstance(chunk, dict):
                    logging.error(f" 잘못된 데이터 타입 발견: {type(chunk)}")
                    return []

                embedding = self.create_embedding(chunk["text"])
                if embedding:
                    chunk["embedding"] = embedding
                    fixed_chunk_results.append(chunk)
                else:
                    logging.error(f" 임베딩 생성 실패! 해당 청크 스킵: {chunk}")

            logging.info(f"\n 총 {len(fixed_chunk_results)}개 청크 처리 완료")
            return fixed_chunk_results

        except Exception as e:
            logging.error(f"장문 텍스트 임베딩 실패: {str(e)}")
            return []




    def check_stored_data(self):
        try:
            stats = self.index.describe_index_stats()
            print("\n=== 저장된 데이터 통계 ===")
            print(f"전체 벡터 수: {stats.total_vector_count}")
            print(f"차원 수: {stats.dimension}")
            # 메타데이터 필드 분포 확인
            if hasattr(stats, 'metadata_config'):
                print(f"메타데이터 구성: {stats.metadata_config}")
        except Exception as e:
            print(f"데이터 확인 중 오류: {str(e)}")

    def delete_all_vectors(self):
        """Pinecone 인덱스의 모든 벡터 삭제"""
        try:
            # 현재 벡터 수 확인
            stats = self.index.describe_index_stats()
            total_vectors = stats.total_vector_count
            
            if total_vectors > 0:
                # 모든 벡터 삭제
                self.index.delete(
                    delete_all=True,
                   
                )
                print(f"\n[삭제 완료] {total_vectors}개의 벡터가 삭제되었습니다.")
            else:
                print("\n삭제할 벡터가 없습니다.")
            
            return True
            
        except Exception as e:
            print(f"벡터 삭제 중 오류 발생: {str(e)}")
            return False

    def create_url_embedding(self, file_url: str, data: Dict, content_type: str):
        try:
            # 메타데이터 기본 구성
            metadata = {
                'file_path': file_url,
                'type': content_type,
                'timestamp': datetime.now().isoformat()
            }

            # vector_id 미리 생성
            base_vector_id = self.create_safe_id(file_url, content_type)

            # 컨텐츠 타입별 메타데이터 추가
            if content_type == 'image':
                metadata.update({
                    'caption': data.get('caption', ''),
                    'tags': data.get('tags', []),
                    'ocr': data.get('ocr_text', '')
                })
                text_for_embedding = metadata['caption']
                vector_id = base_vector_id
                
            elif content_type == 'video':
                metadata.update({
                    'frame_number': data.get('frame', 0),
                    'video_timestamp': data.get('timestamp', 0.0),
                    'caption': data.get('caption', ''),
                    'tags': data.get('tags', [])
                })
                text_for_embedding = metadata['caption']
                vector_id = f"{base_vector_id}_{metadata['frame_number']}"
                
            elif content_type == 'audio':
                metadata.update({
                    'caption': data.get('caption', ''),
                    'frame': data.get('frame', 0),
                    'timestamp': data.get('timestamp', datetime.now().isoformat())
                })
                text_for_embedding = metadata['caption']
                vector_id = f"{base_vector_id}_{metadata['frame']}"
                
            elif content_type == 'video_with_audio':
                metadata.update({
                    'caption': data.get('caption', ''),
                    'frame': data.get('frame', 0),
                    'timestamp': data.get('timestamp', datetime.now().isoformat()),
                    'video_timestamp': data.get('video_timestamp', 0.0)  # 비디오 관련 정보 추가
                })
                text_for_embedding = metadata['caption']
                vector_id = f"{base_vector_id}_{metadata['frame']}"
                
            elif content_type == 'document':
                metadata.update({
                    'title': data.get('title', ''),
                    'content': data.get('content', '')
                })
                text_for_embedding = metadata['content']
                vector_id = base_vector_id

            # 임베딩 생성
            embedding = self.create_embedding(text_for_embedding)
            if embedding:
                print(f"\n=== 벡터 저장 정보 ===")
                print(f"Vector ID: {vector_id}")
                print(f"Type: {metadata['type']}")
                print(f"File Path: {metadata['file_path']}")
                print(f"Caption: {metadata.get('caption', '')}")  # 캡션 정보 출력
                print(f"Frame: {metadata.get('frame', '')}")      # 프레임 정보 출력
                
                # Pinecone에 저장
                self.index.upsert(
                    vectors=[{
                        'id': vector_id,
                        'values': embedding,
                        'metadata': metadata
                    }],
                    namespace=PINECONE_NAMESPACE
                )
                
                # 저장 후 확인
                print(f"\n=== 저장된 벡터 확인 ===")
                stats = self.index.describe_index_stats()
                print(f"전체 벡터 수: {stats.total_vector_count}")
                
                return True

            return False

        except Exception as e:
            logging.error(f"URL 임베딩 저장 실패: {str(e)}")
            return False

    def create_document_embedding(self, file_url: str, content: Dict):
        """문서 임베딩 생성 및 Pinecone에 저장"""
        try:
            logging.info(f" 문서 임베딩 저장 시작: {file_url}")

            # 메타데이터 구성
            metadata = {
                'file_path': file_url,
                'type': 'document',
                'timestamp': datetime.now().isoformat(),
                'title': content.get('title', ''),
                'content': content.get('content', '')
            }

            if not metadata['content'].strip():
                logging.error(f" 문서 내용이 비어 있음! Pinecone에 저장 안 함. (파일: {file_url})")
                return False

            logging.info(f" 문서 원본 내용 (일부): {metadata['content'][:200]}...")

            text_for_embedding = metadata['content']
            chunk_results = self.create_long_text_embedding(text_for_embedding, text_type='document')

            if not isinstance(chunk_results, list):
                logging.error(" 문서 임베딩 생성 실패: 반환된 값이 리스트가 아님")
                return False

            for i, chunk in enumerate(chunk_results):
                if not isinstance(chunk, dict):
                    logging.error(f"청크 데이터 오류: 예상된 타입이 dict인데 {type(chunk)}가 반환됨. 데이터: {chunk}")
                    return False

                if 'chunk_index' not in chunk or 'embedding' not in chunk:
                    logging.error(f"청크 데이터 오류: 필수 키가 없음. 데이터: {chunk}")
                    return False

            for chunk in chunk_results:
                vector_id = f"{file_url}_{chunk['chunk_index']}"
                embedding = chunk['embedding']

                logging.info(f" 저장할 벡터 ID: {vector_id}, 청크 길이: {len(chunk.get('text', ''))}")

                self.index.upsert(
                    vectors=[{
                        'id': vector_id,
                        'values': embedding,
                        'metadata': metadata
                    }],
                    namespace=PINECONE_NAMESPACE
                )

            logging.info(f" 문서 Pinecone 저장 완료: {file_url}")

            return True

        except Exception as e:
            logging.error(f"문서 임베딩 저장 실패: {str(e)}")
            return False