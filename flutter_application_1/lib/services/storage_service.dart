import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../services/firestore_service.dart'; // FirestoreService import 추가

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirestoreService _firestoreService =
      FirestoreService(); // FirestoreService 인스턴스 추가

  String _getMimeType(String fileName) {
    String extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/msword';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  // 파일 업로드 함수 수정 (파일 크기 체크 추가)
  Future<String> uploadFile(
      dynamic file, String folderName, String fileName) async {
    try {
      final ref = _storage.ref().child(folderName).child(fileName);
      UploadTask uploadTask;

      if (file is File) {
        // 모바일 환경에서의 파일 업로드
        uploadTask = ref.putFile(file);
      } else if (file is Uint8List) {
        // 웹 환경에서의 파일 업로드
        uploadTask = ref.putData(file);
      } else {
        throw Exception('지원하지 않는 파일 형식입니다');
      }

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print('파일 업로드 실패: $e');
      throw Exception('파일 업로드에 실패했습니다: $e');
    }
  }

  Future<void> deleteFile(String fileUrl) async {
    try {
      if (fileUrl.startsWith('http')) {
        // http:// 또는 https:// URL을 Firebase Storage 참조로 변환
        final uri = Uri.parse(fileUrl);
        final path = uri.path;
        // URL에서 파일 경로 추출
        final storagePath = path.split('/o/').last;
        // URL 디코딩
        final decodedPath = Uri.decodeComponent(storagePath.split('?').first);

        final ref = _storage.ref().child(decodedPath);
        await ref.delete();
      } else {
        // 직접 Storage 참조 URL이 주어진 경우
        final ref = _storage.refFromURL(fileUrl);
        await ref.delete();
      }
      print('Storage 파일 삭제 성공: $fileUrl');
    } catch (e) {
      print('Storage 파일 삭제 실패: $e');
      // 파일이 이미 없는 경우는 성공으로 처리
      if (e.toString().contains('object-not-found')) {
        print('파일이 이미 삭제되었거나 존재하지 않습니다.');
        return;
      }
      throw Exception('파일 삭제에 실패했습니다: $e');
    }
  }

  Future<void> downloadFile(String fileUrl, String fileName) async {
    try {
      if (kIsWeb) {
        html.AnchorElement(href: fileUrl)
          ..setAttribute('download', fileName)
          ..click();
      } else {
        final response = await http.get(Uri.parse(fileUrl));
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(response.bodyBytes);
      }
    } catch (e) {
      print('파일 다운로드 실패: $e');
      rethrow;
    }
  }

  Future<void> shareFiles(List<Map<String, String>> files) async {
    try {
      if (kIsWeb) {
        String shareText = '공유된 파일:\n\n';
        for (var file in files) {
          shareText += '${file['name']}\n${file['url']}\n\n';
        }
        Share.share(shareText.trim());
      } else {
        if (files.length == 1) {
          Share.share(
            '${files[0]['name']}\n${files[0]['url']}',
            subject: '파일 공유',
          );
        } else {
          String shareText = '공유된 파일:\n\n';
          for (var file in files) {
            shareText += '${file['name']}\n${file['url']}\n\n';
          }
          Share.share(shareText.trim(), subject: '여러 파일 공유');
        }
      }
    } catch (e) {
      print('파일 공유 실패: $e');
      rethrow;
    }
  }

  // 폴더 생성
  Future<void> createFolder(String userId, String folderName) async {
    try {
      final bytes = Uint8List(0);
      final folderRef = _storage.ref().child('$userId/$folderName/.folder');
      await folderRef.putData(bytes);
      print('Storage 폴더 생성 성공');
    } catch (e) {
      print('Storage 폴더 생성 실패: $e');
      rethrow;
    }
  }

  // 파일 크기 가져오기
  Future<int> getFileSize(String fileUrl) async {
    try {
      if (fileUrl.startsWith('gs://') ||
          fileUrl.contains('firebase') ||
          fileUrl.contains('appspot')) {
        final ref = _storage.refFromURL(fileUrl);
        final metadata = await ref.getMetadata();
        return metadata.size ?? 0;
      }
      return 0;
    } catch (e) {
      print('파일 크기 가져오기 실패: $e');
      return 0;
    }
  }
}
