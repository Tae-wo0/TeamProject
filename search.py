from pinecone import Pinecone
from langchain_openai import OpenAIEmbeddings
from config import (
    OPENAI_API_KEY,
    PINECONE_API_KEY,
    PINECONE_ENVIRONMENT,
    PINECONE_INDEX_NAME,
    PINECONE_NAMESPACE
)
import logging
from datetime import datetime

class MediaSearcher:
    def __init__(self, base_manager):
        self.base_manager = base_manager
        self.pc = Pinecone(api_key=PINECONE_API_KEY, environment=PINECONE_ENVIRONMENT)
        self.index = self.pc.Index(PINECONE_INDEX_NAME)
        self.embeddings = OpenAIEmbeddings(api_key=OPENAI_API_KEY, model="text-embedding-3-small")

    def search_media(self, query: str, top_k: int = 10):
        vector = self.embeddings.embed_query(query)
        """미디어 검색"""
        try:
            # 쿼리에서 타입 필터 확인 및 검색어 정제
            media_type = None
            search_query = query
            
            if query.endswith("사진") or query.endswith("이미지"):
                media_type = "image"
                search_query = query.replace("사진", "").replace("이미지", "").replace("그림", "").strip()
            elif query.endswith("영상") or query.endswith("비디오"):
                media_type = "video"
                search_query = query.replace("영상", "").replace("비디오", "").replace("동영상", "").strip()

            # 정제된 쿼리로 벡터 검색
            vector = self.embeddings.embed_query(search_query)
            
            # 타입 필터 적용
            filter_dict = {}  
            if any(keyword in query.lower() for keyword in ["사진", "이미지", "그림"]):
                filter_dict = {"type": "image"}
            elif any(keyword in query.lower() for keyword in ["영상", "비디오", "동영상"]):
                filter_dict = {"type": "video"}
            elif any(keyword in query.lower() for keyword in ["음성", "오디오", "소리"]):
                filter_dict = {"type": "audio"}

            
            results = self.index.query(
                vector=vector,
                top_k=top_k,
                include_metadata=True,
                filter=filter_dict,  
                namespace=PINECONE_NAMESPACE
            )

                # 유사도 임계값 설정
            SIMILARITY_THRESHOLD = 0.0

            if results.matches:
                unique_results = {}
                
                for match in results.matches:
                    file_path = match.metadata.get('file_path')
                    
                    # 유사도가 낮은 경우 태그 매칭 확인
                    if match.score < SIMILARITY_THRESHOLD:
                        tags = match.metadata.get('tags', [])
                        query_words = search_query.lower().split()
                        
                        # 쿼리의 단어가 태그에 있는지 확인
                        if any(any(query_word in tag.lower() for query_word in query_words) for tag in tags):
                            if file_path not in unique_results or match.score > unique_results[file_path].score:
                                unique_results[file_path] = match
                    else:
                        # 유사도가 높은 경우 그대로 저장
                        if file_path not in unique_results or match.score > unique_results[file_path].score:
                            unique_results[file_path] = match

                # 유사도 기준 정렬
                sorted_matches = sorted(unique_results.values(), key=lambda x: x.score, reverse=True)[:3]
                
                # 결과 포맷팅
                formatted_results = []
                for match in results.matches:
                    print(f"검색 결과: {match.metadata}")
                    formatted_results.append({
                        "id": str(hash(match.metadata.get('file_path', ''))),
                        "score": float(match.score),
                        "metadata": {
                            "type": match.metadata.get("type", "unknown"),
                            "file_path": match.metadata.get("file_path"), 
                            "summary": match.metadata.get("summary", ""), 
                            "caption": match.metadata.get("caption"),
                            "tags": match.metadata.get("tags", []),
                            "timestamp": match.metadata.get("timestamp", datetime.now().isoformat()),
                        }
                    })
                return formatted_results
            else:
                print("\n검색 결과가 없습니다.")
                return None

        except Exception as e:
            print(f"검색 중 오류 발생: {str(e)}")
            return None
        