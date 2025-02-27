import logging

def translate_text(client, text: str, is_caption: bool = True) -> str:
    """번역 유틸리티"""
    try:
        system_content = "You are a translator that converts English {} to Korean.".format(
            "image descriptions" if is_caption else "tags"
        )
        response = client.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[
                {"role": "system", "content": system_content},
                {"role": "user", "content": f"Translate this to Korean: {text}"}
            ],
            temperature=0.3
        )
        return response.choices[0].message.content
    except Exception as e:
        logging.error(f"번역 실패: {str(e)}")
        return text 