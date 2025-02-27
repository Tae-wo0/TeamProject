import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rxdart/rxdart.dart';
import './pinecone_service.dart';

// 검색 결과 아이템을 위한 클래스 추가
class SearchResult {
  final String id;
  final String fileName;
  final String? content;
  final String type;
  final String? fileUrl;
  final double similarity;
  final Timestamp timestamp;

  SearchResult({
    required this.id,
    required this.fileName,
    this.content,
    required this.type,
    this.fileUrl,
    required this.similarity,
    required this.timestamp,
  });
}

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PineconeService _pineconeService = PineconeService();

  // 현재 로그인한 사용자 ID 가져오기
  String? get currentUserId => _auth.currentUser?.uid;

  // 현재 로그인한 사용자 이메일 가져오기
  String? get currentUserEmail => _auth.currentUser?.email;

  // 총 저장 용량 가져오기
  Future<int> getTotalStorageSize() async {
    try {
      final userId = currentUserId;
      if (userId == null) return 0;

      final querySnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('files')
          .get();

      int totalSize = 0;
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        if (data.containsKey('fileSize')) {
          totalSize += (data['fileSize'] as num).toInt();
        }
      }

      return totalSize;
    } catch (e) {
      print('저장 용량 계산 실패: $e');
      return 0;
    }
  }

  // 사용량 제한 확인
  Future<bool> checkStorageLimit(int newFileSize) async {
    try {
      final currentSize = await getTotalStorageSize();
      const storageLimit = 5120 * 1024 * 1024; // 5GB

      return (currentSize + newFileSize) <= storageLimit;
    } catch (e) {
      print('저장 용량 확인 실패: $e');
      return false;
    }
  }

  // 텍스트 문서 관련 기능
  Future<void> saveTextContent(String content, String fileName,
      {String? folderId}) async {
    try {
      final userId = currentUserId;
      if (userId == null) throw Exception('로그인이 필요합니다');

      await _firestore.collection('documents').add({
        'userId': userId,
        'content': content,
        'fileName': fileName,
        'folderId': folderId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'type': 'text', // 검색 필터용
      });
    } catch (e) {
      print('텍스트 저장 실패: $e');
      rethrow;
    }
  }

  // 파일 메타데이터 저장
  Future<void> saveFileMetadata(
    String fileUrl,
    String fileType,
    String fileName, {
    String? folderId,
    required int fileSize, // fileSize 매개변수 추가
  }) async {
    try {
      final userId = currentUserId;
      if (userId == null) throw Exception('로그인이 필요합니다');

      final docRef = await _firestore.collection('files').add({
        'userId': userId,
        'fileUrl': fileUrl,
        'fileName': fileName,
        'fileType': fileType,
        'folderId': folderId,
        'fileSize': fileSize, // 파일 크기 저장
        'uploadDate': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('파일 저장 실패: $e');
      rethrow;
    }
  }

  // 통합 검색 (텍스트 내용 + 파일명)
  Stream<List<QuerySnapshot>> searchAll(String searchTerm) {
    final userId = currentUserId;
    if (userId == null) throw Exception('로그인이 필요합니다');

    // 텍스트 문서 검색
    final documentsQuery = _firestore
        .collection('documents')
        .where('userId', isEqualTo: userId)
        .where('content', isGreaterThanOrEqualTo: searchTerm)
        .where('content', isLessThan: '${searchTerm}z');

    // 파일명으로 검색
    final filesQuery = _firestore
        .collection('files')
        .where('userId', isEqualTo: userId)
        .where('fileName', isGreaterThanOrEqualTo: searchTerm)
        .where('fileName', isLessThan: '${searchTerm}z');

    // 두 결과를 합쳐서 반환
    return Rx.combineLatest2(
      documentsQuery.snapshots(),
      filesQuery.snapshots(),
      (QuerySnapshot docs, QuerySnapshot files) => [docs, files],
    );
  }

  // 폴더 내 항목 검색
  Stream<List<QuerySnapshot>> searchInFolder(
      String folderId, String searchTerm) {
    final userId = currentUserId;
    if (userId == null) throw Exception('로그인이 필요합니다');

    final documentsQuery = _firestore
        .collection('documents')
        .where('userId', isEqualTo: userId)
        .where('folderId', isEqualTo: folderId)
        .where('content', isGreaterThanOrEqualTo: searchTerm)
        .where('content', isLessThan: '${searchTerm}z');

    final filesQuery = _firestore
        .collection('files')
        .where('userId', isEqualTo: userId)
        .where('folderId', isEqualTo: folderId)
        .where('fileName', isGreaterThanOrEqualTo: searchTerm)
        .where('fileName', isLessThan: '${searchTerm}z');

    return Rx.combineLatest2(
      documentsQuery.snapshots(),
      filesQuery.snapshots(),
      (QuerySnapshot docs, QuerySnapshot files) => [docs, files],
    );
  }

  // 폴더 내 모든 항목 가져오기
  Stream<List<QuerySnapshot>> getFolderContents(String folderId) {
    final userId = currentUserId;
    if (userId == null) throw Exception('로그인이 필요합니다');

    final documentsQuery = _firestore
        .collection('documents')
        .where('userId', isEqualTo: userId)
        .where('folderId', isEqualTo: folderId)
        .orderBy('updatedAt', descending: true);

    final filesQuery = _firestore
        .collection('files')
        .where('userId', isEqualTo: userId)
        .where('folderId', isEqualTo: folderId)
        .orderBy('uploadDate', descending: true);

    return Rx.combineLatest2(
      documentsQuery.snapshots(),
      filesQuery.snapshots(),
      (QuerySnapshot docs, QuerySnapshot files) => [docs, files],
    );
  }

  // 사용자의 텍스트/메모 목록 가져오기
  Stream<QuerySnapshot> getTextDocuments() {
    final userId = currentUserId;
    if (userId == null) throw Exception('로그인이 필요합니다');

    return _firestore
        .collection('documents')
        .where('userId', isEqualTo: userId)
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }

  // 텍스트/메모 삭제
  Future<void> deleteDocument(String documentId) async {
    try {
      final userId = currentUserId;
      if (userId == null) throw Exception('로그인이 필요합니다');

      await _firestore.collection('documents').doc(documentId).delete();
      print('문서 삭제 성공');
    } catch (e) {
      print('문서 삭제 실패: $e');
      rethrow;
    }
  }

  // 텍스트/메모 수정
  Future<void> updateDocument(String documentId, String content) async {
    try {
      final userId = currentUserId;
      if (userId == null) throw Exception('로그인이 필요합니다');

      await _firestore.collection('documents').doc(documentId).update({
        'content': content,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('문서 수정 성공');
    } catch (e) {
      print('문서 수정 실패: $e');
      rethrow;
    }
  }

  // 텍스트/메모 검색
  Stream<QuerySnapshot> searchDocuments(String searchTerm) {
    final userId = currentUserId;
    if (userId == null) throw Exception('로그인이 필요합니다');

    return _firestore
        .collection('documents')
        .where('userId', isEqualTo: userId)
        .where('content', isGreaterThanOrEqualTo: searchTerm)
        .where('content', isLessThan: '${searchTerm}z')
        .orderBy('content')
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }

  // Firestore에 파일 URL 저장 수정
  Future<void> saveFileUrlToFirestore(
    String userId,
    String fileUrl,
    String fileType, {
    int? fileSize, // 새로운 매개변수
    String? fileName, // 기존 매개변수들
    String? thumbnailUrl,
    String? summary,
    String? content,
  }) async {
    try {
      String defaultFileName = fileType == 'url' ? 'URL' : '파일';

      await _firestore.collection('users').doc(userId).collection('files').add({
        'fileUrl': fileUrl,
        'fileType': fileType,
        'fileName': fileName ?? defaultFileName, // 파일 이름이 없을 경우 기본값 사용
        'uploadDate': Timestamp.now(),
        'fileSize': fileSize ?? 0,
        if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
        if (summary != null) 'summary': summary,
        if (content != null) 'content': content,
      });
    } catch (e) {
      throw Exception('파일 정보 저장 실패: $e');
    }
  }

  Future<DocumentSnapshot> getFileById(String fileId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('사용자 ID를 찾을 수 없습니다');

    return await _firestore
        .collection('users')
        .doc(userId)
        .collection('files')
        .doc(fileId)
        .get();
  }

  // 파일 목록 가져오기
  Stream<QuerySnapshot> getFiles(String userId) {
    return _firestore
        .collection('files')
        .where('userId', isEqualTo: userId)
        .snapshots();
  }

  // 파일 타입별로 가져오기
  Stream<QuerySnapshot> getFilesByType(String type) {
    final userId = currentUserId;
    if (userId == null) {
      return Stream.empty();
    }

    final filesRef =
        _firestore.collection('users').doc(userId).collection('files');

    if (type == '전체') {
      return filesRef.orderBy('uploadDate', descending: true).snapshots();
    }

    // 타입 매핑
    String fileType;
    switch (type) {
      case '이미지':
        fileType = 'images';
        break;
      case '음성':
        fileType = 'audios';
        break;
      case '동영상':
        fileType = 'videos';
        break;
      case '문서':
        fileType = 'documents';
        break;
      case 'URL':
        fileType = 'urls';
        break;
      default:
        fileType = type.toLowerCase();
    }

    // orderBy를 제거하고 where 조건만 사용
    return filesRef.where('fileType', isEqualTo: fileType).snapshots();
  }

  Future<void> deleteFile(String fileId) async {
    try {
      final userId = currentUserId;
      if (userId == null) throw Exception('사용자 ID를 찾을 수 없습니다');

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('files')
          .doc(fileId)
          .delete();
    } catch (e) {
      print('Firestore 파일 삭제 실패: $e');
      throw Exception('파일 정보 삭제에 실패했습니다: $e');
    }
  }

  // 폴더 생성 함수 수정
  Future<String> createFolder(String userId, String folderName,
      {String? parentFolderId}) async {
    try {
      // 폴더 문서 생성
      final folderRef = await _firestore.collection('folders').add({
        'userId': userId,
        'name': folderName,
        'parentFolderId': parentFolderId, // 상위 폴더 ID
        'createdAt': FieldValue.serverTimestamp(),
        'files': [], // 폴더 내 파일 목록
      });

      // 상위 폴더가 있는 경우, 해당 폴더의 subFolders에 추가
      if (parentFolderId != null) {
        await _firestore.collection('folders').doc(parentFolderId).update({
          'subFolders': FieldValue.arrayUnion([folderRef.id])
        });
      }

      print('Firestore 폴더 생성 성공');
      return folderRef.id; // 생성된 폴더의 ID 반환
    } catch (e) {
      print('Firestore 폴더 생성 실패: $e');
      rethrow;
    }
  }

  // 특정 폴더 내의 파일 목록 가져오기
  Stream<QuerySnapshot> getFolderFiles(String folderId) {
    return _firestore
        .collection('folders')
        .doc(folderId)
        .collection('files')
        .orderBy('uploadDate', descending: true)
        .snapshots();
  }

  // 루트 레벨의 파일과 폴더 목록 가져오기
  Stream<QuerySnapshot> getRootItems(String userId) {
    return _firestore
        .collection('files')
        .where('userId', isEqualTo: userId)
        .where('folderId', isNull: true) // 폴더에 속하지 않은 파일만
        .orderBy('uploadDate', descending: true)
        .snapshots();
  }

  // 폴더 목록 가져오기 수정
  Stream<QuerySnapshot> getFolders(String userId, {String? parentFolderId}) {
    Query query =
        _firestore.collection('folders').where('userId', isEqualTo: userId);

    if (parentFolderId != null) {
      query = query.where('parentFolderId', isEqualTo: parentFolderId);
    } else {
      query = query.where('parentFolderId', isNull: true); // 루트 레벨 폴더만
    }

    return query.orderBy('createdAt', descending: true).snapshots();
  }

  // 향상된 검색 기능 수정
  Stream<List<SearchResult>> enhancedSearch(String searchTerm) {
    final userId = currentUserId;
    if (userId == null) throw Exception('로그인이 필요합니다');

    final term = searchTerm.toLowerCase();

    // 현재 사용자의 파일만 검색
    return _firestore
        .collection('files')
        .where('userId', isEqualTo: userId) // 현재 로그인한 사용자의 파일만 검색
        .snapshots()
        .map((snapshot) {
      final results = snapshot.docs
          .map((doc) {
            final data = doc.data();
            final fileName = (data['fileName'] as String).toLowerCase();
            final similarity = _calculateSimilarity(term, fileName);

            if (similarity > 0.1) {
              return SearchResult(
                id: doc.id,
                fileName: data['fileName'],
                type: data['fileType'] ?? 'unknown',
                fileUrl: data['fileUrl'],
                similarity: similarity,
                timestamp: data['uploadDate'] is Timestamp
                    ? data['uploadDate'] as Timestamp
                    : Timestamp.now(),
              );
            }
            return null;
          })
          .where((result) => result != null)
          .cast<SearchResult>()
          .toList();

      // 유사도 순으로 정렬
      results.sort((a, b) => b.similarity.compareTo(a.similarity));
      return results;
    });
  }

  // 유사도 계산 함수 (파일명 검색에 최적화)
  double _calculateSimilarity(String term, String fileName) {
    if (term.isEmpty) return 0.0;

    // 정확한 일치
    if (fileName == term) return 1.0;

    // 부분 문자열 포함
    if (fileName.contains(term)) return 0.8;

    // 단어 단위로 분리하여 검사
    final searchWords = term.split(RegExp(r'[_\s-]'));
    final fileNameWords = fileName.split(RegExp(r'[_\s-]'));

    double maxSimilarity = 0.0;
    for (var searchWord in searchWords) {
      for (var fileWord in fileNameWords) {
        // 단어 단위 부분 일치
        if (fileWord.contains(searchWord)) {
          maxSimilarity = maxSimilarity < 0.6 ? 0.6 : maxSimilarity;
          continue;
        }

        // 레벤슈타인 거리 기반 유사도
        int distance = _levenshteinDistance(
            searchWord.toLowerCase(), fileWord.toLowerCase());
        double wordSimilarity =
            1 - (distance / (searchWord.length + fileWord.length));
        maxSimilarity =
            maxSimilarity < wordSimilarity ? wordSimilarity : maxSimilarity;
      }
    }

    return maxSimilarity;
  }

  // 레벤슈타인 거리 계산
  int _levenshteinDistance(String s1, String s2) {
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<List<int>> d = List.generate(
      s1.length + 1,
      (i) => List.generate(s2.length + 1, (j) => 0),
    );

    for (int i = 0; i <= s1.length; i++) {
      d[i][0] = i;
    }
    for (int j = 0; j <= s2.length; j++) {
      d[0][j] = j;
    }

    for (int i = 1; i <= s1.length; i++) {
      for (int j = 1; j <= s2.length; j++) {
        int cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        d[i][j] = [
          d[i - 1][j] + 1, // 삭제
          d[i][j - 1] + 1, // 삽입
          d[i - 1][j - 1] + cost, // 대체
        ].reduce((curr, next) => curr < next ? curr : next);
      }
    }

    return d[s1.length][s2.length];
  }

  // 모든 파일 목록 가져오기
  Stream<List<SearchResult>> getAllFiles() {
    final userId = currentUserId;
    if (userId == null) throw Exception('로그인이 필요합니다');

    // 파일 메타데이터 가져오기 (현재 사용자의 파일만)
    final filesStream = _firestore
        .collection('files')
        .where('userId', isEqualTo: userId)
        .orderBy('uploadDate', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        // null 체크 강화
        Timestamp timestamp;
        try {
          timestamp = data['uploadDate'] as Timestamp? ?? Timestamp.now();
        } catch (e) {
          timestamp = Timestamp.now();
        }

        return SearchResult(
          id: doc.id,
          fileName: data['fileName'] ?? '제목 없음',
          type: data['fileType'] ?? 'unknown',
          fileUrl: data['fileUrl'],
          similarity: 1.0,
          timestamp: timestamp,
        );
      }).toList();
    });

    // 텍스트 문서 가져오기 (현재 사용자의 문서만)
    final documentsStream = _firestore
        .collection('documents')
        .where('userId', isEqualTo: userId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        // null 체크 강화
        Timestamp timestamp;
        try {
          timestamp = (data['updatedAt'] ?? data['createdAt']) as Timestamp? ??
              Timestamp.now();
        } catch (e) {
          timestamp = Timestamp.now();
        }

        return SearchResult(
          id: doc.id,
          fileName: data['fileName'] ?? '제목 없음',
          content: data['content'],
          type: 'document',
          similarity: 1.0,
          timestamp: timestamp,
        );
      }).toList();
    });

    return Rx.combineLatest2(
      documentsStream,
      filesStream,
      (List<SearchResult> docs, List<SearchResult> files) {
        final allResults = [...docs, ...files];
        allResults.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return allResults;
      },
    );
  }

  // 로그인 상태 확인 및 테스트 데이터 생성
  Future<void> initializeTestData() async {
    final userId = currentUserId;
    print('로그인 상태 확인 - userId: $userId');

    if (userId == null) {
      print('로그인이 필요합니다');
      return;
    }

    try {
      // 현재 데이터 확인
      final docsSnapshot = await _firestore
          .collection('documents')
          .where('userId', isEqualTo: userId)
          .get();

      final filesSnapshot = await _firestore
          .collection('files')
          .where('userId', isEqualTo: userId)
          .get();

      print('현재 documents 수: ${docsSnapshot.docs.length}');
      print('현재 files 수: ${filesSnapshot.docs.length}');

      // 데이터가 없으면 테스트 데이터 생성
      if (docsSnapshot.docs.isEmpty && filesSnapshot.docs.isEmpty) {
        print('테스트 데이터 생성 시작');

        // 텍스트 문서 추가
        await saveTextContent(
          '이것은 테스트 문서입니다.',
          '테스트문서1.txt',
        );

        await saveTextContent(
          '두 번째 테스트 문서입니다.',
          '중요문서.txt',
        );

        // 파일 메타데이터 추가
        await saveFileMetadata(
          'https://example.com/test.mp4',
          'videos',
          '테스트비디오.mp4',
          fileSize: 1024 * 1024, // 1MB
        );

        await saveFileMetadata(
          'https://example.com/test.mp3',
          'audios',
          '테스트오디오.mp3',
          fileSize: 512 * 1024, // 512KB
        );

        print('테스트 데이터 생성 완료');
      }
    } catch (e) {
      print('테스트 데이터 생성 중 오류: $e');
    }
  }

  // Pinecone 통합 메서드 수정
  Future<void> integratePinecone() async {
    try {
      await _pineconeService.testConnection();
      print('Pinecone 통합 성공');
    } catch (e) {
      print('Pinecone 통합 실패: $e');
      rethrow;
    }
  }
}
