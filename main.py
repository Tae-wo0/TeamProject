from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from typing import List, Optional
from pydantic import BaseModel, validator
import logging
from datetime import datetime
import os
import aiohttp

# 필요한 모듈들 임포트
from base_manager import BaseManager
from media.media_coordinator import MediaCoordinator
from search import MediaSearcher
from media.utils.constants import *
from config import *

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)

app = FastAPI(title="Media Processing API")

# CORS 설정
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 요청 모델
class FileRequest(BaseModel):
    file_url: str
    file_name: str
    file_type: str
    save_frames: Optional[bool] = False
    metadata: Optional[dict] = {}

    @validator("file_type")
    def validate_file_type(cls, v):
        allowed_types = ["image", "video", "audio", "document", "pdf", "word", "pptx", "xlsx", "hwp", "url"]
        if v.lower() not in allowed_types:
            raise ValueError(f"지원하지 않는 파일 형식입니다. 지원 형식: {allowed_types}")
        return v.lower()

    @validator("file_url")
    def validate_url(cls, v):
        if not v or not v.startswith(("http://", "https://")):
            raise ValueError("유효하지 않은 URL 형식입니다")
        return v

    @validator("file_name")
    def validate_file_name(cls, v):
        if not v or v.isspace():
            raise ValueError("파일 이름은 필수입니다")
        return v


# 검색 요청 모델
class SearchRequest(BaseModel):
    query: str
    top_k: Optional[int] = 10
    threshold: Optional[float] = 0.0

    @validator("query")
    def validate_query(cls, v):
        if not v or v.isspace():
            raise ValueError("검색어는 필수입니다")
        return v

    @validator("top_k")
    def validate_top_k(cls, v):
        if v < 1:
            raise ValueError("top_k는 1 이상이어야 합니다")
        return v

    @validator("threshold")
    def validate_threshold(cls, v):
        if not (0 <= v <= 1):
            raise ValueError("threshold는 0과 1 사이여야 합니다")
        return v


# 전역 변수
base_manager = None
media_coordinator = None
media_searcher = None


@app.on_event("startup")
async def startup_event():
    """서버 시작시 필요한 초기화"""
    global base_manager, media_coordinator, media_searcher

    try:
        base_manager = BaseManager(OPENAI_API_KEY)
        media_coordinator = MediaCoordinator(base_manager)
        media_searcher = MediaSearcher(base_manager)

        logging.info("서버 초기화 완료")

    except Exception as e:
        logging.error(f"서버 초기화 실패: {str(e)}")
        raise e


@app.get("/")
async def root():
    """서버 상태 확인"""
    return {"status": "running", "timestamp": datetime.now().isoformat()}


@app.post("/process/media")
async def process_media(request: FileRequest):
    try:
        logging.info("\n=== 미디어 처리 시작 ===")
        logging.info(f" 파일 타입: {request.file_type}")
        logging.info(f" 파일 이름: {request.file_name}")
        logging.info(f" URL: {request.file_url}")

        if request.file_type != "url":
            try:
                async with aiohttp.ClientSession() as session:
                    async with session.head(request.file_url) as response:
                        if response.status != 200:
                            raise ValueError(f"파일 URL에 접근할 수 없습니다. 상태 코드: {response.status}")
                        logging.info(" URL 접근 확인 완료")
            except Exception as e:
                logging.error(f" URL 접근 확인 실패: {str(e)}")
                raise ValueError("파일 URL에 접근할 수 없습니다")

        logging.info("🚀 MediaCoordinator 처리 시작")

        result = media_coordinator.process_media_url(
            file_url=request.file_url,
            file_type=request.file_type,
            file_name=request.file_name,
            save_frames=request.save_frames
        )

        if not result:
            raise HTTPException(status_code=500, detail="미디어 처리 실패")

        return {
            "success": True,
            "data": {
                "type": "url",
                "file_url": request.file_url,
                "metadata": result,
                "vector_status": "completed"
            }
        }

    except ValueError as e:
        logging.error(f" 입력 데이터 오류: {str(e)}")
        raise HTTPException(status_code=422, detail=str(e))
    except HTTPException as e:
        raise e
    except Exception as e:
        logging.error(f" 파일 처리 중 예상치 못한 오류: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"내부 서버 오류: {str(e)}")

@app.post("/search")
async def search(request: SearchRequest):
    try:
        print(f"\n=== 검색 요청 ===")
        print(f"Query: {request.query}")
        print(f"Top K: {request.top_k}")
        print(f"Threshold: {request.threshold}")
        print(f"Namespace: {PINECONE_NAMESPACE}")
        
        # 쿼리 임베딩 생성
        query_embedding = base_manager.create_embedding(request.query)
        if not query_embedding:
            raise HTTPException(status_code=500, detail="임베딩 생성 실패")

        # Pinecone 검색
        search_results = base_manager.index.query(
            vector=query_embedding,
            top_k=request.top_k,
            namespace=PINECONE_NAMESPACE,
            include_metadata=True
        )
        
        print(f"\n=== 검색 결과 ===")
        print(f"결과 수: {len(search_results.matches)}")
        
        # 결과 필터링 및 변환
        filtered_results = []
        for match in search_results.matches:
            score = match.score
            if score < request.threshold:
                continue
                
            print(f"\n매치 정보:")
            print(f"ID: {match.id}")
            print(f"Score: {score}")
            print(f"Metadata: {match.metadata}")
            
            result = {
                "id": match.id,
                "score": score,
                "metadata": match.metadata
            }
            filtered_results.append(result)

        # 응답 생성
        response_data = {
            "query": request.query,
            "results": filtered_results,
            "timestamp": datetime.now().isoformat()
        }
        
        print(f"\n=== 최종 응답 ===")
        print(f"필터링된 결과 수: {len(filtered_results)}")
        
        return {
            "success": True,
            "data": response_data
        }

    except Exception as e:
        print(f"검색 처리 중 오류 발생: {str(e)}")
        logging.error(f"검색 실패: {str(e)}")
        return {
            "success": False,
            "message": f"검색 처리 중 오류가 발생했습니다: {str(e)}",
            "data": None
        }

@app.delete("/reset")
async def reset_database():
    """데이터베이스 초기화"""
    try:
        success = base_manager.delete_all_vectors()
        if success:
            return {"status": "success", "message": "데이터베이스 초기화 완료"}
        raise HTTPException(status_code=500, detail="데이터베이스 초기화 실패")
    except Exception as e:
        logging.error(f"데이터베이스 초기화 중 오류 발생: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail="데이터베이스 초기화 실패")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)