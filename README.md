# ZIM (Zoom In Memory)
K-Digital AI Bootcamp Final Project (2025 오세돌 최종 프로젝트)

## 🖥️ 프로젝트 소개
효율적인 미디어 데이터 검색을 위한 AI 기반 솔루션


## 🕰️ 개발 기간
- 25.1.15일 ~ 25.2.26일


### 🧑‍🤝‍🧑 오세돌 멤버 구성
- 팀장/김태우 - 임베딩, Whisper 사용
- 서기/송동호 - 프론트, Firebase와 연동
- 자료수집/지원배 - Pinecone(벡터DB)
- 타임키퍼/양유진 - Firebase, Flutter와 연동, Pinecone과 연동
- 발표/이수진 - 크롤링


### ⚙️ 개발 환경
- [`JDK 17`](https://nazzang19.tistory.com/127)
- [`Flutter`](https://freeinformation.tistory.com/entry/Flutter-%ED%94%8C%EB%9F%AC%ED%84%B0-%EB%8B%A4%EC%9A%B4%EB%A1%9C%EB%93%9C-%EC%84%A4%EC%B9%98)
- [`Android Studio(에뮬레이터까지 생성)`](https://freeinformation.tistory.com/entry/Flutter-%ED%94%8C%EB%9F%AC%ED%84%B0-%EB%8B%A4%EC%9A%B4%EB%A1%9C%EB%93%9C-%EC%84%A4%EC%B9%98)
- [`Python 3.12`](https://github.com/conda-forge, "conda-forge")
- [`ram`](https://github.com/xinyu1205/recognize-anything.git)
- **DB** : 벡터db, Firebase
- **패키지 매니저** : pip


## 📌 주요 기능
검색
- 으아아ㅏ아앙아아


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

2. ram 설치
   ```
   git+https://github.com/xinyu1205/recognize-anything.git
   ```


   2-1. 2번이 안될 시
      ```
      git clone https://github.com/xinyu1205/recognize-anything.git

      cd recognize-anything

      pip install -e .
      ```
   
4. dependencies 설치

   requirements.txt 파일 가지고 있는 상태에서
   ```
   pip install -r requirements.txt
   ```

5. api key 삽입

   api key 넣는 부분에 넣어주기 (그냥 올릴거면 삭제하기)


6. 실행
   
   에뮬레이터 실행 후
   ```
   flutter clean
   
   flutter run
   ```
