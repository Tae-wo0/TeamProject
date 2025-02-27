import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../widgets/custom_drawer.dart';
import '../services/firestore_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

class SearchResult {
  final String id;
  final double score;
  final String type;
  final String fileName;
  final String? fileUrl;
  final String? summary;
  final String? caption;
  final DateTime timestamp;
  final double similarity;
  final Map<String, dynamic>? metadata;

  SearchResult({
    required this.id,
    required this.score,
    required this.type,
    required this.fileName,
    this.fileUrl,
    this.summary,
    this.caption,
    required this.timestamp,
    required this.similarity,
    this.metadata,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    try {
      final metadata = json['metadata'] as Map<String, dynamic>;

      String? fileUrl = metadata['file_path'] ?? metadata['url'];
      print("fileUrl 값: $fileUrl");

      String fileName = 'Unknown File';
      if (fileUrl != null) {
        try {
          final uri = Uri.parse(fileUrl);
          if (uri.hasScheme && uri.hasAuthority) {
            // Firebase Storage URL에서 파일명 추출
            if (fileUrl.contains('firebasestorage.googleapis.com')) {
              // 'o/' 다음부터 '?' 이전까지의 문자열 추출
              final startIndex = fileUrl.indexOf('/o/') + 3;
              final endIndex = fileUrl.indexOf('?');
              if (startIndex > 2 && endIndex > startIndex) {
                String encodedPath = fileUrl.substring(startIndex, endIndex);
                // URL 디코딩
                String decodedPath = Uri.decodeComponent(encodedPath);
                // 경로에서 파일명만 추출 (마지막 '/' 이후의 문자열)
                fileName = decodedPath.split('/').last;
                print("추출된 파일 경로: $decodedPath");
                print("추출된 파일명: $fileName");
              }
            }
          } else {
            print(' 잘못된 URL 형식: $fileUrl');
            fileUrl = null;
          }
        } catch (e) {
          print(' URL 파싱 에러: $e');
          fileUrl = null;
        }
      }
      String type = metadata['type']?.toLowerCase() ?? 'unknown';
      final Map<String, String> typeMapping = {
        'image': 'image',
        'video': 'video',
        'video_with_audio': 'video',
        'audio': 'audio',
        'web': 'url',
        'document': 'document',
        'pdf': 'pdf',
        'word': 'word',
        'pptx': 'pptx',
        'xlsx': 'xlsx',
        'hwp': 'hwp',
        'url': 'url',
      };

      type = typeMapping[type] ?? 'document';

      // URL 타입인 경우에만 title 사용
      if (type == 'url') {
        fileName = metadata['title'] ?? 'Unknown URL';
      }

      print("최종 선택된 파일명: $fileName");

      return SearchResult(
        id: json['id'] as String,
        score: (json['score'] as num).toDouble(),
        type: type,
        fileName: fileName,
        fileUrl: fileUrl,
        summary: metadata['summary'] ?? "요약 정보 없음",
        timestamp: DateTime.parse(
            metadata['timestamp'] ?? DateTime.now().toIso8601String()),
        similarity: (json['score'] as num?)?.toDouble() ?? 0.0,
        metadata: metadata,
      );
    } catch (e) {
      print("변환 오류: $e");
      return SearchResult(
        id: 'error',
        score: 0.0,
        type: 'unknown',
        fileName: 'Unknown',
        fileUrl: null,
        timestamp: DateTime.now(),
        similarity: 0.0,
        metadata: {},
      );
    }
  }
  static DateTime _parseTimestamp(dynamic timestamp) {
    try {
      if (timestamp == null) return DateTime.now();

      if (timestamp is String) {
        if (timestamp.contains('T')) {
          return DateTime.parse(timestamp);
        }
      }

      double seconds = double.tryParse(timestamp.toString()) ?? 0.0;
      return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
    } catch (e) {
      print('Timestamp parsing error: $timestamp');
      return DateTime.now();
    }
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isLoading = false;
  bool _showScrollToTop = false;
  Set<String> _selectedTypes = {'전체'};
  final AudioPlayer _audioPlayer = AudioPlayer();
  VideoPlayerController? _videoController;
  bool _showAllTypes = false;
  bool _isGridView = true;
  Widget _buildFilterChips() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _filterTypes.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final type = _filterTypes[index];
          IconData icon;
          switch (type) {
            case '전체':
              icon = Icons.apps;
              break;
            case '이미지':
              icon = Icons.image;
              break;
            case '음성':
              icon = Icons.audio_file;
              break;
            case '동영상':
              icon = Icons.video_library;
              break;
            case '문서':
              icon = Icons.description;
              break;
            case 'URL':
              icon = Icons.link;
              break;
            case 'PDF':
              icon = Icons.picture_as_pdf;
              break;
            case '워드':
              icon = Icons.description;
              break;
            case '엑셀':
              icon = Icons.table_chart;
              break;
            case '한글':
              icon = Icons.text_fields;
              break;
            default:
              icon = Icons.file_present;
          }

          final isSelected = _selectedTypes.contains(type);
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  if (type == '전체') {
                    _selectedTypes = {'전체'};
                  } else {
                    _selectedTypes.remove('전체');
                    if (isSelected) {
                      _selectedTypes.remove(type);
                      if (_selectedTypes.isEmpty) {
                        _selectedTypes.add('전체');
                      }
                    } else {
                      _selectedTypes.add(type);
                    }
                  }
                });
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).primaryColor
                      : Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).primaryColor
                        : Colors.grey[300]!,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color:
                                Theme.of(context).primaryColor.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: isSelected ? Colors.white : Colors.grey[600],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      type,
                      style: TextStyle(
                        fontSize: 13,
                        color: isSelected ? Colors.white : Colors.grey[600],
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _shareResult(SearchResult result) {
    String shareText = '${result.fileName}';

    if (result.fileUrl != null) {
      shareText += '\n\n파일 링크: ${result.fileUrl}';
    }

    if (result.summary != null && result.summary!.isNotEmpty) {
      shareText += '\n\n요약:\n${result.summary}';
    }

    Share.share(shareText, subject: result.fileName);
  }

  Future<void>? _videoFuture;

  final List<String> _filterTypes = ['전체', '이미지', '음성', '동영상', '문서', 'URL'];

  final _firestoreService = FirestoreService();
  List<SearchResult> _searchResults = [];

  final String apiUrl = 'http://172.30.48.214:8000';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      setState(() {
        _showScrollToTop = _scrollController.offset > 200;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _handleSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      print('검색 요청 시작: $query');

      final response = await http.post(
        Uri.parse('$apiUrl/search'), // /search로 통일
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json; charset=utf-8',
        },
        body: jsonEncode({
          'query': query,
          'top_k': 10,
          'threshold': 0.0,
        }),
      );

      // UTF-8 디코딩 추가
      final decodedBody = utf8.decode(response.bodyBytes);
      print('서버 응답 전체: $decodedBody');

      if (response.statusCode == 200) {
        final result = jsonDecode(decodedBody);
        print('응답 파싱 결과: $result');

        if (result['success'] == true && result['data'] != null) {
          final List<dynamic> results = result['data']['results'] ?? [];
          print('검색 결과 개수: ${results.length}');
          print('검색 결과 목록: $results');

          final searchResults = results.map((item) {
            print('변환 전 아이템: $item');
            final converted = SearchResult.fromJson(item);
            print('변환 후 아이템: ${converted.type}, ${converted.fileUrl}');
            return converted;
          }).toList();

          setState(() {
            _searchResults = searchResults;
          });
        } else {
          print('검색 결과 없음: ${result['message'] ?? "알 수 없는 오류"}');
          setState(() {
            _searchResults = [];
          });
        }
      } else {
        final errorBody = jsonDecode(decodedBody);
        print('서버 오류 상세: $errorBody');
        throw Exception(
            '검색 요청 실패 (${response.statusCode}): ${errorBody['detail']}');
      }
    } catch (error) {
      print('검색 처리 중 오류 발생: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('검색 중 오류가 발생했습니다\n$error'),
          duration: const Duration(seconds: 3),
        ),
      );
      setState(() {
        _searchResults = [];
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  IconData getTypeIcon(String type) {
    switch (type) {
      case 'image':
        return Icons.image;
      case 'audio':
        return Icons.audio_file;
      case 'video':
        return Icons.video_file;
      case 'document':
        return Icons.description;
      case 'text':
        return Icons.text_snippet;
      case 'url':
        return Icons.link;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'word':
        return Icons.description;
      case 'pptx':
        return Icons.slideshow;
      case 'xlsx':
        return Icons.table_chart;
      case 'hwp':
        return Icons.text_fields;
      default:
        return Icons.file_present;
    }
  }

  Future<void> _playAudio(String url) async {
    if (url.isEmpty) {
      print("오디오 URL 없음");
      return;
    }
    try {
      await _audioPlayer.setUrl(url);
      await _audioPlayer.play();
    } catch (e) {
      print('오디오 재생 에러: $e');
    }
  }

  Future<void> _playVideo(String url) async {
    if (url.isEmpty) {
      print("비디오 URL 없음");
      return;
    }
    _videoController = VideoPlayerController.network(url);
    try {
      await _videoController!.initialize();
      _videoController!.play();
    } catch (e) {
      print('비디오 재생 에러: $e');
    }
  }

  Future<void> _launchURL(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        throw '해당 URL을 열 수 없습니다: $url';
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('URL을 열 수 없습니다: $e')),
      );
    }
  }

  void _showVideoPlayer(String url) {
    _videoFuture = _playVideo(url);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: FutureBuilder(
          future: _videoFuture,
          builder: (context, snapshot) {
            if (_videoController == null ||
                !_videoController!.value.isInitialized) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }

            return Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: VideoPlayer(_videoController!),
                ),
                // 닫기 버튼
                Positioned(
                  top: 16,
                  right: 16,
                  child: IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () {
                      _videoController?.pause();
                      Navigator.pop(context);
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showFileDetails(SearchResult result) {
    switch (result.type) {
      case 'image':
        showDialog(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: EdgeInsets.zero,
            child: Stack(
              fit: StackFit.loose,
              alignment: Alignment.center,
              children: [
                InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: CachedNetworkImage(
                    imageUrl: result.fileUrl ?? '',
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: (context, url, error) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.white, size: 50),
                          const SizedBox(height: 16),
                          Text(
                            '이미지를 불러올 수 없습니다\n$error',
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    fit: BoxFit.contain,
                  ),
                ),
                Positioned(
                  top: 40,
                  right: 20,
                  child: IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
        );
        break;

      case 'audio':
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(result.fileName),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.audio_file, size: 50),
                const SizedBox(height: 10),
                Text(
                  result.fileName, // ✅ 파일명 추가
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                StreamBuilder<Duration>(
                  stream: _audioPlayer.positionStream,
                  builder: (context, snapshot) {
                    final duration = snapshot.data ?? Duration.zero;
                    return Column(
                      children: [
                        Slider(
                          min: 0,
                          max: _audioPlayer.duration?.inSeconds.toDouble() ?? 1,
                          value: duration.inSeconds.toDouble(),
                          onChanged: (value) {
                            _audioPlayer.seek(Duration(seconds: value.toInt()));
                          },
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                                "${duration.inMinutes}:${duration.inSeconds.remainder(60)}"),
                            Text(
                              "${_audioPlayer.duration?.inMinutes ?? 0}:${_audioPlayer.duration?.inSeconds.remainder(60) ?? 0}",
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.replay_10),
                      onPressed: () {
                        _audioPlayer.seek(Duration(
                            seconds: _audioPlayer.position.inSeconds - 10));
                      },
                    ),
                    StreamBuilder<PlayerState>(
                      stream: _audioPlayer.playerStateStream,
                      builder: (context, snapshot) {
                        final playerState = snapshot.data;
                        final processingState = playerState?.processingState;
                        final playing = playerState?.playing;

                        if (processingState == ProcessingState.loading ||
                            processingState == ProcessingState.buffering) {
                          return Container(
                            margin: const EdgeInsets.all(8.0),
                            width: 32.0,
                            height: 32.0,
                            child: const CircularProgressIndicator(),
                          );
                        } else if (playing != true) {
                          return IconButton(
                            icon: const Icon(Icons.play_arrow),
                            onPressed: () => _playAudio(result.fileUrl ?? ''),
                          );
                        } else {
                          return IconButton(
                            icon: const Icon(Icons.pause),
                            onPressed: _audioPlayer.pause,
                          );
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.forward_10),
                      onPressed: () {
                        _audioPlayer.seek(Duration(
                            seconds: _audioPlayer.position.inSeconds + 10));
                      },
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _audioPlayer.stop();
                  Navigator.pop(context);
                },
                child: const Text('닫기'),
              ),
            ],
          ),
        );
        break;

      case 'video':
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(result.fileName),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.video_library, size: 50),
                const SizedBox(height: 10),
                Text(
                  result.fileName, // ✅ 파일명 추가
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text("비디오 재생"),
                  onPressed: () {
                    Navigator.pop(context);
                    _showVideoPlayer(result.fileUrl ?? '');
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ],
          ),
        );
        break;

      case 'url':
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(result.fileName),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.summary != null && result.summary!.isNotEmpty) ...[
                  const Text(
                    '요약 정보:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(result.summary!),
                  const Divider(),
                ],
                const SizedBox(height: 8),
                Text('저장일: ${result.timestamp.toString().split('.')[0]}'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
              if (result.fileUrl != null)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _launchURL(result.fileUrl!);
                  },
                  child: const Text('열기'),
                ),
            ],
          ),
        );
        break;

      case 'document':
      case 'pdf':
      case 'word':
      case 'pptx':
      case 'xlsx':
      case 'hwp':
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(result.fileName),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📄 원본 문서 내용:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: SingleChildScrollView(
                    child: Text(
                        result.metadata?['content'] ?? '문서 내용을 불러올 수 없습니다.'),
                  ),
                ),
                const SizedBox(height: 16),
                Text('📅 업로드 날짜: ${result.timestamp.toString().split('.')[0]}'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ],
          ),
        );
        break;

      default:
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(result.fileName),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('파일 유형: ${result.type}'),
                const SizedBox(height: 8),
                if (result.caption != null) ...[
                  const Divider(),
                  Text('내용: ${result.caption}'),
                ],
                const SizedBox(height: 8),
                Text('업로드: ${result.timestamp.toString().split('.')[0]}'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ],
          ),
        );
    }
  }

// 📌 '상세보기' 버튼 클릭 시 원본 문서 내용을 보여주는 팝업
  void _showFullDocumentDetails(SearchResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${result.fileName} - 상세 정보'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📄 원본 문서 내용:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child:
                    Text(result.metadata?['content'] ?? '원본 내용을 불러올 수 없습니다.'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '검색 결과가 없습니다',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    final filteredResults = _selectedTypes.contains('전체')
        ? _searchResults
        : _searchResults.where((result) {
            final koreanType = result.type == 'image'
                ? '이미지'
                : result.type == 'audio'
                    ? '음성'
                    : result.type == 'video'
                        ? '동영상'
                        : result.type == 'url'
                            ? 'URL'
                            : '문서';
            return _selectedTypes.contains(koreanType);
          }).toList();

    return _isGridView
        ? _buildGridView(filteredResults)
        : _buildListView(filteredResults);
  }

  Widget _buildGridView(List<SearchResult> results) {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        return _buildGridItem(result);
      },
    );
  }

  Widget _buildListView(List<SearchResult> results) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                getTypeIcon(result.type),
                color: Theme.of(context).primaryColor,
              ),
            ),
            title: Text(
              result.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              result.timestamp.toString().split('.')[0],
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            onTap: () => _showFileDetails(result),
          ),
        );
      },
    );
  }

  Widget _buildPreviewArea(SearchResult result) {
    switch (result.type) {
      case 'image':
        print('이미지 URL: ${result.fileUrl}');
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: CachedNetworkImage(
            imageUrl: result.fileUrl ?? '',
            fit: BoxFit.cover,
            placeholder: (context, url) => const Center(
              child: CircularProgressIndicator(),
            ),
            errorWidget: (context, url, error) {
              print('이미지 로드 에러: $error for URL: $url');
              return const Center(
                child: Icon(Icons.image_not_supported, size: 40),
              );
            },
          ),
        );

      case 'video':
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: Stack(
            alignment: Alignment.center,
            children: [
              CachedNetworkImage(
                imageUrl: '${result.fileUrl}?thumbnail', // ✅ 썸네일 표시 (가능한 경우)
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.black.withOpacity(0.05),
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) {
                  return Container(
                    color: Colors.black.withOpacity(0.05),
                    child: const Center(
                      child: Icon(Icons.play_circle_outline, size: 40),
                    ),
                  );
                },
              ),
              const Icon(Icons.play_circle_fill, color: Colors.white, size: 50),
            ],
          ),
        );

      case 'audio':
        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.05),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.audio_file, size: 40),
              const SizedBox(height: 8),
              Text(
                result.fileName,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );

      case 'url':
        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.05),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: const Center(
            child: Icon(Icons.link, size: 40),
          ),
        );

      default:
        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.05),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: const Center(
            child: Icon(Icons.description, size: 40),
          ),
        );
    }
  }

  Widget _buildGridItem(SearchResult result) {
    return GestureDetector(
      onTap: () {
        if (result.type == 'video' && result.fileUrl != null) {
          _showVideoPlayer(result.fileUrl!);
        } else {
          _showFileDetails(result);
        }
      },
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: _buildPreviewArea(result),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.fileName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          result.timestamp.toString().split('.')[0],
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share, size: 20),
                    onPressed: () => _shareResult(result),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('데이터 검색'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            onPressed: () {
              setState(() {
                _isGridView = !_isGridView;
              });
            },
          ),
        ],
      ),
      drawer: const CustomDrawer(),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 3,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '검색어를 입력하세요',
                    hintStyle: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 16,
                    ),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchResults = [];
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      _handleSearch(value);
                    }
                  },
                ),
              ),
              _buildFilterChips(),
              Expanded(
                child: _buildSearchResults(),
              ),
            ],
          ),
          if (_showScrollToTop)
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                mini: true,
                onPressed: _scrollToTop,
                child: const Icon(Icons.arrow_upward),
              ),
            ),
        ],
      ),
    );
  }
}
