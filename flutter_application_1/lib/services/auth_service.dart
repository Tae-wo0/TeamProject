import 'package:firebase_auth/firebase_auth.dart';
import './pinecone_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PineconeService _pineconeService = PineconeService();

  // 현재 유저 상태 스트림
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // 이메일/비밀번호로 회원가입
  Future<UserCredential?> signUpWithEmail(String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // 회원가입 성공 시 Pinecone 네임스페이스 생성 시도
      try {
        await _pineconeService.createNamespaceWithUID();
        print('Pinecone 네임스페이스 생성 성공: ${credential.user?.uid}');
      } catch (e) {
        print('Pinecone 네임스페이스 생성 실패: $e');
        // 네임스페이스 생성 실패 시 계정 삭제
        await credential.user?.delete();
        throw Exception('Pinecone 네임스페이스 생성 실패: $e');
      }
      
      return credential;
    } catch (e) {
      print('회원가입 실패: $e');
      rethrow;
    }
  }

  // 이메일/비밀번호로 로그인
  Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // 로그인 성공 시 Pinecone 네임스페이스 연결 확인
      try {
        await _pineconeService.testConnection();
        print('Pinecone 연결 성공: ${credential.user?.uid}');
      } catch (e) {
        print('Pinecone 연결 실패: $e');
        throw Exception('Pinecone 연결 실패: $e');
      }
      
      return credential;
    } catch (e) {
      print('로그인 실패: $e');
      rethrow;
    }
  }

  // 로그아웃
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // 현재 로그인된 사용자 가져오기
  User? get currentUser => _auth.currentUser;
}