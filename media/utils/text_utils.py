import re
import logging
from typing import List, Dict

def create_text_chunks(text: str, chunk_size: int = 500, overlap: int = 100) -> List[Dict]:
    """텍스트를 청크로 분할"""
    try:
        chunks = []
        sentences = re.split('[.!?。]+', text)
        current_chunk = ""
        
        for sentence in sentences:
            sentence = sentence.strip()
            if not sentence:
                continue
                
            if len(current_chunk) + len(sentence) > chunk_size:
                if current_chunk:
                    chunks.append(current_chunk)
                    current_chunk = current_chunk[-overlap:] + " " + sentence
                else:
                    current_chunk = sentence
            else:
                current_chunk = current_chunk + " " + sentence if current_chunk else sentence
        
        if current_chunk:
            chunks.append(current_chunk)
            
        return chunks
            
    except Exception as e:
        logging.error(f"텍스트 청킹 실패: {str(e)}")
        return [] 