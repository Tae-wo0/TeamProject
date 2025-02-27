import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/storage_service.dart';
import '../services/firestore_service.dart';
import '../widgets/custom_drawer.dart';
import 'home_page.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class DataImportPage extends StatefulWidget {
  const DataImportPage({super.key});

  @override
  State<DataImportPage> createState() => _DataImportPageState();
}

class _DataImportPageState extends State<DataImportPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  List<Map<String, dynamic>> _selectedFiles = [];
  final StorageService _storageService = StorageService();
  final FirestoreService _firestoreService = FirestoreService();
  final _urlController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode();
  bool _isUrlFocused = false;
  bool _isUrlLoading = false;

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  static const String apiUrl = 'http://172.30.48.214:8000';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );

    _urlFocusNode.addListener(() {
      setState(() {
        _isUrlFocused = _urlFocusNode.hasFocus;
      });
    });

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _urlFocusNode.dispose();
    _urlController.dispose();
    super.dispose();
  }

  String _getFileType(String fileName) {
    String ext = fileName.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'tiff', 'webp'].contains(ext)) {
      return 'image';
    } else if (['mp4', 'avi', 'mov', 'wmv', 'flv', 'mkv'].contains(ext)) {
      return 'video';
    } else if (['mp3', 'wav', 'aac', 'flac', 'ogg', 'm4a'].contains(ext)) {
      return 'audio';
    } else if (['pdf', 'docx', 'pptx', 'xlsx', 'txt', 'hwp'].contains(ext)) {
      return 'document';
    }
    return 'unknown';
  }

  IconData _getFileIcon(String type) {
    switch (type) {
      case 'images':
        return Icons.image_outlined;
      case 'videos':
        return Icons.video_file_outlined;
      case 'audios':
        return Icons.audio_file_outlined;
      case 'documents':
        return Icons.description_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Widget _buildSelectedFilesList() {
    if (_selectedFiles.isEmpty) return const SizedBox.shrink();

    return Scrollbar(
      thickness: 6,
      radius: const Radius.circular(8),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
            ),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _selectedFiles.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final file = _selectedFiles[index];
              final IconData iconData = _getFileIcon(file['type']);

              return ListTile(
                dense: true,
                leading: Icon(iconData,
                    color: Theme.of(context).colorScheme.primary),
                title: Text(
                  file['name'],
                  style: const TextStyle(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '타입: ${file['type']}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    setState(() {
                      _selectedFiles.removeAt(index);
                    });
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _processWebUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL을 입력해주세요'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isUrlLoading = true;
    });

    try {
      print('API 요청 시작: $apiUrl/process/media');
      print('요청 데이터: ${jsonEncode({
            'file_url': url,
            'file_type': 'url',
            'file_name': url,
            'metadata': {
              'type': 'url',
              'timestamp': DateTime.now().toIso8601String(),
              'source': 'web_import'
            }
          })}');

      final response = await http
          .post(
        Uri.parse('$apiUrl/process/media'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'file_url': url,
          'file_type': 'url',
          'file_name': url,
          'metadata': {
            'type': 'url',
            'timestamp': DateTime.now().toIso8601String(),
            'source': 'web_import'
          }
        }),
      )
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('서버 연결 시간이 초과되었습니다');
        },
      );

      print('응답 상태 코드: ${response.statusCode}');
      print('응답 데이터: ${response.body}');

      final result = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final userId = _firestoreService.currentUserId;
        if (userId != null) {
          await _firestoreService.saveFileUrlToFirestore(
            userId,
            url,
            'urls',
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('URL이 성공적으로 처리되었습니다'),
              backgroundColor: Colors.green,
              action: SnackBarAction(
                label: '보관함에서 보기',
                textColor: Colors.white,
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const HomePage(initialIndex: 2),
                    ),
                  );
                },
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } else {
        throw Exception(
            '서버 응답 오류: ${result['message'] ?? '처리 실패'} (상태 코드: ${response.statusCode})');
      }
    } catch (e) {
      print('URL 처리 실패 상세 정보:');
      print('에러 타입: ${e.runtimeType}');
      print('에러 메시지: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('URL 처리 실패: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUrlLoading = false;
          _urlController.clear();
        });
      }
    }
  }

  Future<void> _handleFileSelection() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'txt',
          'pdf',
          'docx',
          'jpg',
          'png',
          'mp4',
          'mp3',
          'wav'
        ],
        allowMultiple: true,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _selectedFiles = result.files.map((file) {
            dynamic fileData;
            if (kIsWeb) {
              fileData = file.bytes;
            } else {
              fileData = File(file.path!);
            }

            return {
              'file': fileData,
              'name': file.name,
              'type': _getFolderName(file.extension ?? ''),
            };
          }).toList();
        });
        print('선택된 파일 수: ${_selectedFiles.length}');
      }
    } catch (e) {
      print('파일 선택 실패: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('파일 선택 실패: $e')),
      );
    }
  }

  String _getFolderName(String extension) {
    if (['jpg', 'png'].contains(extension)) return 'images';
    if (['mp4'].contains(extension)) return 'videos';
    if (['mp3', 'wav'].contains(extension)) return 'audios';
    return 'documents';
  }

  Future<void> _handleUpload() async {
    if (_selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('먼저 파일을 선택해주세요'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final userId = _firestoreService.currentUserId;
      if (userId == null) throw Exception('로그인이 필요합니다');

      // 현재 저장 용량 확인
      final currentStorageSize = await _firestoreService.getTotalStorageSize();
      final storageLimit = 5120 * 1024 * 1024; // 100MB 제한

      // 선택한 파일들의 총 크기 계산
      int totalNewFilesSize = 0;
      for (var fileData in _selectedFiles) {
        int fileSize = fileData['file'] is File
            ? await (fileData['file'] as File).length()
            : (fileData['file'] as Uint8List).length;
        totalNewFilesSize += fileSize;
      }

      // 용량 초과 체크
      if (currentStorageSize + totalNewFilesSize > storageLimit) {
        throw Exception('저장 용량이 초과되었습니다. 일부 파일을 삭제한 후 다시 시도해주세요.');
      }

      int successCount = 0;
      List<String> failedFiles = [];
      List<Map<String, dynamic>> processedResults = [];

      for (var fileData in _selectedFiles) {
        try {
          String downloadUrl = await _storageService.uploadFile(
            fileData['file'],
            fileData['type'],
            fileData['name'],
          );

          if (downloadUrl.isNotEmpty) {
            int fileSize = fileData['file'] is File
                ? await (fileData['file'] as File).length()
                : (fileData['file'] as Uint8List).length;

            await _firestoreService.saveFileUrlToFirestore(
              userId,
              downloadUrl,
              fileData['type'],
              fileSize: fileSize,
              fileName: fileData['name'],
            );

            String fileName = fileData['name'] ?? 'unknown_file.txt';
            String fileType = _getFileType(fileName);
            String apiEndpoint = '$apiUrl/process/media';

            final response = await http
                .post(
              Uri.parse(apiEndpoint),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'file_url': downloadUrl,
                'file_type': fileType,
                'file_name': fileData['name'],
                'save_frames': true,
                'metadata': {
                  'original_source': {
                    'type': fileData['type'],
                    'file_name': fileData['name'],
                    'upload_time': DateTime.now().toIso8601String(),
                  }
                }
              }),
            )
                .timeout(
              const Duration(minutes: 5),
              onTimeout: () {
                throw TimeoutException('파일 처리 시간이 초과되었습니다');
              },
            );

            final responseBody = utf8.decode(response.bodyBytes);
            final result = jsonDecode(responseBody);

            if (response.statusCode == 200 && result['success']) {
              successCount++;
              processedResults.add({
                'name': fileData['name'],
                'result': result,
              });
            } else {
              throw Exception(result['message'] ?? '파일 처리 실패');
            }
          }
        } catch (e) {
          failedFiles.add(fileData['name']);
          print('개별 파일 업로드 실패: ${fileData['name']} - $e');
        }
      }

      if (mounted) {
        // 모든 파일 처리가 완료된 후 결과 다이얼로그 표시
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('파일 처리 완료 ($successCount/${_selectedFiles.length})'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var result in processedResults) ...[
                    Text(
                      '✓ ${result['name']}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (failedFiles.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      '실패한 파일:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (var fileName in failedFiles) ...[
                      Text(
                        '✗ $fileName',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const HomePage(initialIndex: 2),
                    ),
                  );
                },
                child: const Text('보관함으로 이동'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print('전체 업로드 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('업로드 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _selectedFiles = [];
        });
      }
    }
  }

  void _showProcessingResult(Map<String, dynamic> result, String fileName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('파일 처리 완료: $fileName'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('처리 유형: ${result['data']?['type'] ?? '알 수 없음'}'),
              const SizedBox(height: 8),
              Text('저장 위치: ${result['data']?['file_url'] ?? '알 수 없음'}'),
              if (result['data']?['metadata']?['content'] != null) ...[
                const SizedBox(height: 8),
                Text('추출된 내용: ${result['data']['metadata']['content']}'),
              ],
              if (result['data']?['metadata']?['caption'] != null) ...[
                const SizedBox(height: 8),
                Text('설명: ${result['data']['metadata']['caption']}'),
              ],
              if (result['data']?['metadata']?['tags'] != null) ...[
                const SizedBox(height: 8),
                Text('태그: ${result['data']['metadata']['tags'].join(', ')}'),
              ],
              if (result['data']?['metadata']?['transcript'] != null) ...[
                const SizedBox(height: 8),
                Text('텍스트 변환: ${result['data']['metadata']['transcript']}'),
              ],
              const SizedBox(height: 16),
              Text(
                  '벡터 데이터베이스 저장 상태: ${result['data']?['vector_status'] ?? '처리 중'}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const HomePage(initialIndex: 2),
                ),
              );
            },
            child: const Text('보관함으로 이동'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('데이터 가져오기'),
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const HomePage(initialIndex: 2),
                ),
              );
            },
          ),
        ],
      ),
      drawer: const CustomDrawer(),
      body: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
        ),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16.0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // URL 입력 섹션
                  Card(
                    elevation: 4,
                    shadowColor: Colors.black26,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: colorScheme.outline.withOpacity(0.2),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.link,
                            color: colorScheme.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _urlController,
                              focusNode: _urlFocusNode,
                              decoration: InputDecoration(
                                hintText: 'URL을 입력하세요',
                                border: InputBorder.none,
                                hintStyle: TextStyle(
                                  color: colorScheme.onSurface.withOpacity(0.5),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            onPressed: _isUrlLoading ? null : _processWebUrl,
                            style: FilledButton.styleFrom(
                              backgroundColor: colorScheme.primaryContainer,
                              foregroundColor: colorScheme.onPrimaryContainer,
                              minimumSize: const Size(80, 40),
                            ),
                            child: Text(
                              _isUrlLoading ? '저장 중...' : '저장',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 파일 업로드 영역
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _scaleAnimation.value,
                        child: Opacity(
                          opacity: _fadeAnimation.value,
                          child: Card(
                            elevation: 4,
                            shadowColor: Colors.black26,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                              side: BorderSide(
                                color: _selectedFiles.isEmpty
                                    ? colorScheme.outline.withOpacity(0.2)
                                    : colorScheme.primary.withOpacity(0.5),
                                width: _selectedFiles.isEmpty ? 1 : 2,
                              ),
                            ),
                            child: InkWell(
                              onTap: _isLoading ? null : _handleFileSelection,
                              borderRadius: BorderRadius.circular(24),
                              child: Container(
                                height:
                                    MediaQuery.of(context).size.height - 420,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 20,
                                  horizontal: 24,
                                ),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            _selectedFiles.isEmpty
                                                ? MainAxisAlignment.center
                                                : MainAxisAlignment.start,
                                        children: [
                                          if (_selectedFiles.isEmpty) ...[
                                            Container(
                                              padding: const EdgeInsets.all(20),
                                              decoration: BoxDecoration(
                                                color: colorScheme
                                                    .primaryContainer,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.cloud_upload_outlined,
                                                size: 48,
                                                color: colorScheme
                                                    .onPrimaryContainer,
                                              ),
                                            ),
                                            const SizedBox(height: 20),
                                            Text(
                                              '파일 선택하기',
                                              style: TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.onSurface,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 20,
                                                vertical: 10,
                                              ),
                                              decoration: BoxDecoration(
                                                color: colorScheme
                                                    .secondaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.description_outlined,
                                                    size: 18,
                                                    color: colorScheme
                                                        .onSecondaryContainer,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    '문서 / 이미지 / 음성 / 동영상',
                                                    style: TextStyle(
                                                      color: colorScheme
                                                          .onSecondaryContainer,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ] else ...[
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 16),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    '선택된 파일 (${_selectedFiles.length})',
                                                    style: TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color:
                                                          colorScheme.primary,
                                                    ),
                                                  ),
                                                  TextButton.icon(
                                                    onPressed:
                                                        _handleFileSelection,
                                                    icon: const Icon(Icons.add),
                                                    label: const Text('파일 추가'),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Expanded(
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: colorScheme.surface,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child:
                                                    _buildSelectedFilesList(),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (_isLoading)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 20),
                                        child: CircularProgressIndicator(
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // 업로드 버튼
                  FilledButton(
                    onPressed: _isLoading ? null : _handleUpload,
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                    ),
                    child: Text(
                      _isLoading ? '업로드 중...' : '업로드',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
