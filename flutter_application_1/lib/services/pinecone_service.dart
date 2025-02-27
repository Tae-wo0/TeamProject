import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';

class PineconeService {
  // FirestoreService 대신 직접 Firebase Auth 사용
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  final String _apiKey = 'pcsk_3pRZ8M_21ZBG3L69LX9f7tajk2yKG8ksPB8ociPCMG5BVtLwVb2QYwyNtiTrd463M4piQL';
  final String _environment = 'aped-4627-b74a';
  final String _indexName = '1536-n89llnk';
  
  String get _baseUrl => 'https://$_indexName.svc.$_environment.pinecone.io';

  Map<String, String> get _headers => {
    'Api-Key': _apiKey,
    'Content-Type': 'application/json',
  };

  static Future<void> initialize() async {
    final instance = PineconeService();
    try {
      await instance.testConnection();
      print('Pinecone 초기화 성공');
    } catch (e) {
      print('Pinecone 초기화 실패: $e');
      rethrow;
    }
  }

  // Firebase UID로 Pinecone 네임스페이스 생성
  Future<void> createNamespaceWithUID() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw Exception('로그인이 필요합니다');

    try {
      // Pinecone에 네임스페이스 생성 요청
      final response = await http.post(
        Uri.parse('$_baseUrl/vectors/upsert'),
        headers: _headers,
        body: jsonEncode({
          'namespace': userId,
          'vectors': [{
            'id': 'init_$userId',
            'values': List.generate(1536, (i) => i == 0 ? 1.0 : 0.0),  // 첫 번째 값만 1.0으로 설정
          }],
        }),
      );

      if (response.statusCode == 200) {
        print('Pinecone 네임스페이스 생성 성공: $userId');
      } else {
        print('Pinecone 네임스페이스 생성 실패! 상태 코드: ${response.statusCode}, 응답: ${response.body}');
        throw Exception('Pinecone 네임스페이스 생성 실패');
      }
    } catch (e) {
      print('Pinecone 오류: $e');
      rethrow;
    }
  }

  // Pinecone 연결 테스트
  Future<void> testConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/query'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        print('Pinecone 연결 성공! 응답: ${response.body}');
      } else {
        print('Pinecone 연결 실패! 상태 코드: ${response.statusCode}, 응답: ${response.body}');
        throw Exception('Pinecone 연결 실패: 상태 코드 ${response.statusCode}');
      }
    } catch (e) {
      print('Pinecone 연결 오류: $e');
      throw Exception('Pinecone 서버 연결 실패: $e');
    }
  }

  // 유사 벡터 검색 (UID 네임스페이스 내에서)
  Future<List<String>> findSimilarFiles({
    String? userId,  // 선택적 매개변수로 변경
    required List<double> queryEmbedding,
    int topK = 10,
  }) async {
    final namespace = userId ?? _auth.currentUser?.uid;
    if (namespace == null) throw Exception('로그인이 필요합니다');

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/query'),
        headers: _headers,
        body: jsonEncode({
          'vector': queryEmbedding,
          'topK': topK,
          'namespace': namespace,  // Firebase UID 네임스페이스에서 검색
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Pinecone 검색 실패: ${response.body}');
      }

      final data = jsonDecode(response.body);
      // 유사한 파일들의 ID만 반환
      return List<String>.from(
        data['matches'].map((match) => match['metadata']['fileId'] as String)
      );
    } catch (e) {
      print('Pinecone 검색 오류: $e');
      rethrow;
    }
  }

  // 벡터 임베딩 삭제
  Future<void> deleteEmbedding(String fileId, {String? userId}) async {
    final namespace = userId ?? _auth.currentUser?.uid;
    if (namespace == null) throw Exception('로그인이 필요합니다');

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/vectors/delete'),
        headers: _headers,
        body: jsonEncode({
          'ids': [fileId],
          'namespace': namespace,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Pinecone 벡터 삭제 실패: ${response.body}');
      }

      print('Pinecone 벡터 삭제 성공');
    } catch (e) {
      print('Pinecone 벡터 삭제 오류: $e');
      rethrow;
    }
  }
} 