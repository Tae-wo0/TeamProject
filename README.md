# ZIM (Zoom In Memory)
K-Digital AI Bootcamp Final Project (2025 오세돌 최종 프로젝트)

## 🖥️ 프로젝트 소개
효율적인 미디어 데이터 검색을 위한 AI 기반 솔루션


## 🕰️ 개발 기간
- 25.1.15일 ~ 25.2.26일


### 🧑‍🤝‍🧑 오세돌 멤버 구성
- 팀장/김태우 - 임베딩, Fast API, 백엔드 프론트엔드 연결
- 서기/송동호 - Flutter, Firebase와 연동, OCR(Google-cloud-vision 사용)
- 자료수집/지원배 - Pinecone(벡터DB), 임베딩 및 처리속도개선, 벡터 서치, 리팩터링
- 타임키퍼/양유진 - Firebase, Flutter와 연동, Pinecone과 연동
- 발표/이수진 - 크롤링, 서류작업 처리 및 영상 편집, UI 카드 디자인


### ⚙️ 개발 환경
- [`JDK 17`](https://nazzang19.tistory.com/127)
- [`Flutter`](https://freeinformation.tistory.com/entry/Flutter-%ED%94%8C%EB%9F%AC%ED%84%B0-%EB%8B%A4%EC%9A%B4%EB%A1%9C%EB%93%9C-%EC%84%A4%EC%B9%98)
- [`Android Studio(에뮬레이터까지 생성)`](https://freeinformation.tistory.com/entry/Flutter-%ED%94%8C%EB%9F%AC%ED%84%B0-%EB%8B%A4%EC%9A%B4%EB%A1%9C%EB%93%9C-%EC%84%A4%EC%B9%98)
- [`Python 3.10`](https://github.com/conda-forge/miniforge "miniforge")
- [`RAM`](https://github.com/xinyu1205/recognize-anything.git)
- **DB** : 벡터db, Firebase
- **패키지 매니저** : pip


## 📌 주요 기능 (추후 수정)
벡터 임베딩
- 미디어 통합 검색
- 유연한 질의 해석
- 의미 기반 검색


## 🪄 사용한 API
- pinecone api

- open ai api

- cloud vision api


## ✔️ 사용법
1. cmd로 가상환경 만들기
   ```
   conda create --name zim python==3.10
   
   conda activate zim
   ```

2. xinyu1205/recognize_anything_model 다운로드
   
- https://huggingface.co/xinyu1205/recognize_anything_model/tree/main 접속
- ram_swin_large_14m.pth 모델 다운로드
- pretrained 폴더 생성 후 모델 넣기

3. dependencies 설치

   requirements.txt 파일 가지고 있는 상태에서
   ```
   pip install -r requirements.txt
   ```
   실행 시 필요한거 싹 다 설치됨


   3-1. ram 설치(requirements.txt 안에 포함되어있긴 함)
      ```
      git+https://github.com/xinyu1205/recognize-anything.git
      ```


   3-2. 3-1번이 안될 시
      ```
      git clone https://github.com/xinyu1205/recognize-anything.git

      cd recognize-anything

      pip install -e .
      ```
   
4. api key 삽입

   api key 넣는 부분에 넣어주기 (그냥 올릴거면 삭제하기)


5. 실행
   서버 실행 후
   ```
   python main.py
   ```
   
   에뮬레이터 실행 후
   ```
   flutter clean
   
   flutter run
   ```
