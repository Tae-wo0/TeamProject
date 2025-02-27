import os
import time
import json
import re
from typing import Dict, Any, List
from urllib.parse import urlparse
import requests
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from webdriver_manager.chrome import ChromeDriverManager
import trafilatura
import logging
from datetime import datetime
from config import *


logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler()
    ]
)
class CrawlingProcessor:
    def __init__(self, base_manager, github_token: str = None):
        # base_manager에서 필요한 클라이언트들 가져오기
        self.client = base_manager.client
        self.index = base_manager.index
        self.github_token = github_token
        
        # Selenium 설정
        options = webdriver.ChromeOptions()
        options.add_argument('--headless=new')
        options.add_argument('--no-sandbox')
        options.add_argument('--disable-dev-shm-usage')
        options.add_argument('--disable-gpu')
        options.add_argument('--log-level=3')
        options.add_argument('--silent')
        
        # 로깅 설정
        options.add_experimental_option('excludeSwitches', ['enable-logging'])
        logging.getLogger('selenium').setLevel(logging.ERROR)
        os.environ['WDM_LOG_LEVEL'] = '0'

        service = Service(ChromeDriverManager().install())
        self.driver = webdriver.Chrome(service=service, options=options)
        self.driver.implicitly_wait(5)
        print("Selenium 초기화 성공")

    def extract_content(self, url):
        """웹 페이지 내용 추출"""
        try:
            print(f"\n크롤링 시작: {url}")
            url = url.strip()
            if not url.startswith(('http://', 'https://')):
                url = 'https://' + url
                
            domain = urlparse(url).netloc

            # 1. trafilatura로 먼저 시도
            try:
                response = requests.get(url, timeout=10)
                downloaded = response.text
                if downloaded:
                    result = trafilatura.extract(
                        downloaded,
                        include_comments=False,
                        include_tables=True,
                        no_fallback=False,
                        target_language='ko'
                    )
                    
                    if result and len(result.strip()) > 100:
                        metadata = trafilatura.extract_metadata(downloaded)
                        title = metadata.get('title', '')
                        print("trafilatura로 추출 성공")
                        
                        return {
                            'title': title,
                            'content': result,
                            'domain': domain,
                            'url': url
                        }
            except Exception as e:
                print(f"trafilatura 추출 실패: {str(e)}")

            # 2. Selenium으로 시도
            print("Selenium으로 추출 시도 중...")
            self.driver.set_page_load_timeout(15)
            self.driver.get(url)

            # JavaScript로 내용 추출
            script = """
                function getContent() {
                    let title = '';
                    let content = '';
                    
                    // 제목 찾기
                    const titleSelectors = ['h1', '.title', '#title', '.article-title', 
                        '.post-title', '.entry-title', '[class*="title"]'];
                    for (let selector of titleSelectors) {
                        const element = document.querySelector(selector);
                        if (element) {
                            title = element.textContent.trim();
                            if (title) break;
                        }
                    }
                    
                    // 내용 찾기
                    const contentSelectors = ['article', 'main', '.content', '#content',
                        '.article', '.post', '.entry-content'];
                    for (let selector of contentSelectors) {
                        const element = document.querySelector(selector);
                        if (element) {
                            content = element.textContent.trim();
                            if (content.length > 100) break;
                        }
                    }
                    
                    return {title, content};
                }
                return getContent();
            """
            
            result = self.driver.execute_script(script)
            
            if result['content'] and len(result['content']) > 100:
                print("Selenium으로 추출 성공")
                
                return {
                    'title': result['title'] or self.driver.title,
                    'content': result['content'],
                    'domain': domain,
                    'url': url
                }

            print("내용 추출 실패")
            return None

        except Exception as e:
            print(f"내용 추출 실패: {str(e)}")
            return None

    def create_chunks(self, text: str, run_type: int = 1, chunk_size: int = 500) -> List[str]:
        """
        텍스트를 동적 크기의 청크로 분할하는 개선된 메소드
        
        Args:
            text (str): 분할할 텍스트
            run_type (int): 실행 타입 (기존 호환성 유지)
            chunk_size (int): 기본 청크 크기 (기존 호환성 유지)
        
        Returns:
            List[str]: 청크 리스트
        """
        try:
            # 입력 텍스트 전처리
            text = text.strip()
            if not text:
                logging.warning("빈 텍스트가 입력되었습니다.")
                return []

            words = text.split()
            total_length = len(words)
            chunks = []

            # 텍스트 길이에 따른 동적 청크 크기 및 오버랩 설정
            if total_length < 300:
                actual_chunk_size = total_length
                overlap_size = 0
                logging.info(f"짧은 텍스트 감지: 단일 청크로 처리 (길이: {total_length})")
            elif total_length < 1000:
                actual_chunk_size = 500
                overlap_size = 100  # 20% 오버랩
                logging.info("중간 길이 텍스트: 500자 청크, 100자 오버랩")
            else:
                actual_chunk_size = 800
                overlap_size = 200  # 25% 오버랩
                logging.info("긴 텍스트: 800자 청크, 200자 오버랩")

            # 문단 구분자로 자연스러운 분할 시도
            paragraphs = text.split('\n\n')
            current_chunk = []
            current_length = 0

            for paragraph in paragraphs:
                paragraph_words = paragraph.split()
                paragraph_length = len(paragraph_words)

                # 현재 청크에 문단을 추가할 수 있는 경우
                if current_length + paragraph_length <= actual_chunk_size:
                    current_chunk.extend(paragraph_words)
                    current_length += paragraph_length
                else:
                    # 현재 청크가 있으면 저장
                    if current_chunk:
                        chunks.append(' '.join(current_chunk))

                    # 새 문단이 청크 크기보다 큰 경우
                    if paragraph_length > actual_chunk_size:
                        # 청크 크기로 분할하되 오버랩 적용
                        for i in range(0, paragraph_length, actual_chunk_size - overlap_size):
                            end_idx = min(i + actual_chunk_size, paragraph_length)
                            if end_idx - i >= actual_chunk_size * 0.3:  # 최소 크기 체크
                                chunk = ' '.join(paragraph_words[i:end_idx])
                                chunks.append(chunk)
                        current_chunk = []
                        current_length = 0
                    else:
                        # 새 청크 시작
                        current_chunk = paragraph_words
                        current_length = paragraph_length

            # 마지막 청크 처리
            if current_chunk:
                chunks.append(' '.join(current_chunk))

            # 청크 품질 개선
            improved_chunks = []
            for i, chunk in enumerate(chunks):
                chunk_length = len(chunk.split())
                
                # 너무 작은 청크 처리 (이전 청크와 병합)
                if i > 0 and chunk_length < actual_chunk_size * 0.3:
                    previous_chunk = improved_chunks[-1]
                    merged_chunk = previous_chunk + " " + chunk
                    improved_chunks[-1] = merged_chunk
                    logging.debug(f"작은 청크 병합: 청크 {i}를 이전 청크와 병합")
                else:
                    improved_chunks.append(chunk)

            # 결과 로깅
            logging.info(f"총 텍스트 길이: {total_length} 단어")
            logging.info(f"생성된 청크 수: {len(improved_chunks)}")
            logging.info(f"청크 크기: {actual_chunk_size}, 오버랩: {overlap_size}")

            return improved_chunks

        except Exception as e:
            logging.error(f"청크 생성 중 오류 발생: {str(e)}")
            return []
        
    def create_comprehensive_summary(self, content: str) -> str:
        """문서를 순차적으로 읽고 전체 내용을 요약"""
        try:
            # 1. 문서를 적절한 크기로 분할 (약 1500토큰 단위)
            chunks = []
            current_chunk = []
            current_length = 0
            
            for para in content.split('\n\n'):
                para_length = len(para) // 4
                if current_length + para_length > 1500:
                    chunks.append('\n\n'.join(current_chunk))
                    current_chunk = [para]
                    current_length = para_length
                else:
                    current_chunk.append(para)
                    current_length += para_length
            
            if current_chunk:
                chunks.append('\n\n'.join(current_chunk))
            
            print(f"문서를 {len(chunks)}개의 청크로 분할")
            
            # 2. GPT와의 대화 시작 - 문서 읽기
            messages = [
                {"role": "system", "content": "당신은 긴 문서를 순차적으로 읽고 이해하는 assistant입니다. 각 부분을 주의 깊게 읽고 전체 내용을 파악해주세요."}
            ]
            
            # 각 청크를 순차적으로 전달
            for i, chunk in enumerate(chunks):
                messages.append({
                    "role": "user", 
                    "content": f"다음은 문서의 {i+1}/{len(chunks)} 부분입니다:\n\n{chunk}"
                })
                
                response = self.client.chat.completions.create(
                    model="gpt-3.5-turbo",
                    messages=messages + [{"role": "user", "content": "이 부분을 읽었다는 것을 확인해주세요."}],
                    temperature=0.3,
                    max_tokens=50
                )
                
                messages.append({
                    "role": "assistant",
                    "content": response.choices[0].message.content
                })
                print(f"청크 {i+1}/{len(chunks)} 읽기 완료")
            
            # 3. 전체 내용 요약 요청
            messages.append({
                "role": "user",
                "content": "지금까지 읽은 전체 문서의 내용을 5줄로 요약해주세요. 각 줄은 50자 이내로 작성해주세요."
            })
            
            final_response = self.client.chat.completions.create(
                model="gpt-3.5-turbo",
                messages=messages,
                temperature=0.3,
                max_tokens=300
            )
            
            return final_response.choices[0].message.content.strip()
            
        except Exception as e:
            print(f"요약 프로세스 실패: {str(e)}")
            return "요약 프로세스 실패"        


    def save_to_pinecone(self, url: str, web_data: Dict[str, Any]) -> bool:
        """웹 콘텐츠 요약본만 Pinecone에 저장"""
        try:
            print(f"\n=== 웹 페이지 처리 시작: {url} ===")
            
            # GPT-3.5로 전체 내용 이해 후 요약
            try:
                summary = self.create_comprehensive_summary(web_data['content'])
                print(f"\n페이지 요약본:\n{summary}")
                
                # 요약본 임베딩 생성
                summary_embedding = self.client.embeddings.create(
                    model="text-embedding-3-small",
                    input=summary
                ).data[0].embedding

                # 요약본만 Pinecone에 저장
                self.index.upsert(
                    vectors=[{
                        'id': f"{url}_summary",
                        'values': summary_embedding,
                        'metadata': {
                            'url': url,
                            'title': web_data['title'],
                            'domain': web_data['domain'],
                            'summary': summary,
                            'type': 'url',  
                            'timestamp': datetime.now().isoformat()
                        }
                    }],
                    namespace=PINECONE_NAMESPACE
                )
                print(f"페이지 요약본 임베딩 저장 완료: {url}")
                return True
                
            except Exception as e:
                print(f"요약본 생성 및 임베딩 저장 실패: {str(e)}")
                return False
                
        except Exception as e:
            print(f"Pinecone 저장 실패: {str(e)}")
            return False        

   