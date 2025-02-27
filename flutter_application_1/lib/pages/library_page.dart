import 'package:flutter/material.dart';
import '../widgets/custom_drawer.dart';
import '../services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/storage_service.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'dart:math' show log, pow;

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String _selectedType = '전체';
  final List<String> _filterTypes = ['전체', '이미지', '음성', '동영상', '문서', 'URL'];
  bool _isSelectionMode = false;
  final Set<String> _selectedItems = {};
  final FirestoreService _firestoreService = FirestoreService();
  final StorageService _storageService = StorageService();
  late AudioPlayer _audioPlayer;
  VideoPlayerController? _videoController;
  int _totalStorageSize = 0;
  bool _isLoading = false;
  final int _storageLimit = 5120 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _loadStorageSize();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Widget _buildFilterChips() {
    return Container(
      height: 48, // 60에서 48로 줄임
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 4), // vertical 패딩 추가
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
            default:
              icon = Icons.file_present;
          }

          final isSelected = _selectedType == type;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedType = type;
                });
              },
              borderRadius: BorderRadius.circular(20), // 25에서 20으로 줄임
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6), // 패딩 값 줄임
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).primaryColor
                      : Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20), // 25에서 20으로 줄임
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
                      size: 18, // 20에서 18로 줄임
                      color: isSelected ? Colors.white : Colors.grey[600],
                    ),
                    const SizedBox(width: 6), // 8에서 6으로 줄임
                    Text(
                      type,
                      style: TextStyle(
                        fontSize: 13, // 글자 크기 추가
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

  String _getFileIcon(String fileType) {
    switch (fileType) {
      case 'images':
        return '🖼️';
      case 'videos':
        return '🎥';
      case 'audios':
        return '🎵';
      case 'documents':
        return '📄';
      case 'text':
        return '📝';
      case 'url':
        return '🔗';
      default:
        return '📁';
    }
  }

  Future<void> _loadStorageSize() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final size = await _firestoreService.getTotalStorageSize();
      if (mounted) {
        setState(() {
          _totalStorageSize = size;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('저장 용량 로드 실패: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  Widget _buildStorageInfo() {
    final double usagePercentage = _totalStorageSize / _storageLimit;
    final Color progressColor = usagePercentage > 0.9
        ? Colors.red
        : usagePercentage > 0.7
            ? Colors.orange
            : Theme.of(context).primaryColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '저장 용량',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              if (_isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: usagePercentage,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(progressColor),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatSize(_totalStorageSize),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                _formatSize(_storageLimit),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (usagePercentage > 0.9)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '저장 공간이 거의 찼습니다!',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedItems.clear();
      }
    });
  }

  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes}분 전';
      }
      return '${difference.inHours}시간 전';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}일 전';
    } else {
      return '${date.year}.${date.month}.${date.day}';
    }
  }

  String _getSimpleFileName(String fullFileName) {
    try {
      String fileName = fullFileName.split('/').last.split('?').first;
      fileName = Uri.decodeFull(fileName);
      return fileName;
    } catch (e) {
      return fullFileName;
    }
  }

  Future<void> _deleteFile(String fileId, String fileUrl) async {
    try {
      bool? confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('파일 삭제'),
          content: const Text('이 파일을 삭제하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                '취소',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: ButtonStyle(
                backgroundColor: MaterialStateProperty.all(
                  Theme.of(context).colorScheme.error,
                ),
              ),
              child: const Text('삭제'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        if (fileUrl.startsWith('gs://') ||
            fileUrl.contains('firebase') ||
            fileUrl.contains('appspot')) {
          await _storageService.deleteFile(fileUrl);
        }
        await _firestoreService.deleteFile(fileId);
        await _loadStorageSize();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('파일이 삭제되었습니다'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('파일 삭제 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteSelectedFiles() async {
    try {
      bool? confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            '파일 삭제',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            '선택한 ${_selectedItems.length}개의 파일을 삭제하시겠습니까?',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                '취소',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: ButtonStyle(
                backgroundColor: MaterialStateProperty.all(
                  Theme.of(context).colorScheme.error,
                ),
              ),
              child: const Text('삭제'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        for (String fileId in _selectedItems) {
          try {
            final docSnapshot = await _firestoreService.getFileById(fileId);
            if (docSnapshot.exists) {
              final data = docSnapshot.data() as Map<String, dynamic>;
              final fileUrl = data['fileUrl'] as String;

              if (fileUrl.startsWith('gs://') ||
                  fileUrl.contains('firebase') ||
                  fileUrl.contains('appspot')) {
                await _storageService.deleteFile(fileUrl);
              }

              await _firestoreService.deleteFile(fileId);
            }
            await _loadStorageSize();
          } catch (e) {
            print('파일 삭제 중 오류 발생: $e');
            continue;
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('선택한 파일들이 삭제되었습니다'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {
            _selectedItems.clear();
            _isSelectionMode = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('파일 삭제 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showFileDetails(BuildContext context, Map<String, dynamic> file) {
    final String fileUrl = file['fileUrl'] as String;
    String fileType = file['fileType'] as String;

    switch (fileType) {
      case 'url':
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              file['fileName'] ?? 'URL',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'URL: $fileUrl',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '저장일: ${_formatDate(file['uploadDate'] as Timestamp)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (file['summary'] != null) ...[
                  const Divider(height: 24),
                  Text(
                    '요약',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    file['summary'] as String,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  '닫기',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  // URL 열기 로직
                },
                child: const Text('열기'),
              ),
            ],
          ),
        );
        break;

      case 'images':
        showDialog(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: Stack(
              fit: StackFit.loose,
              alignment: Alignment.center,
              children: [
                InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Hero(
                    tag: fileUrl,
                    child: CachedNetworkImage(
                      imageUrl: fileUrl,
                      placeholder: (context, url) => Container(
                        color: Colors.black45,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.black45,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.white, size: 48),
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
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        break;

      case 'audios':
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              file['fileName'] ?? '오디오',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.audio_file,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 24),
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
                    const SizedBox(width: 8),
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
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          );
                        } else if (playing != true) {
                          return FloatingActionButton(
                            onPressed: _audioPlayer.play,
                            child: const Icon(Icons.play_arrow),
                          );
                        } else {
                          return FloatingActionButton(
                            onPressed: _audioPlayer.pause,
                            child: const Icon(Icons.pause),
                          );
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.forward_10),
                      onPressed: () {
                        _audioPlayer.seek(Duration(
                            seconds: _audioPlayer.position.inSeconds + 10));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                StreamBuilder<Duration?>(
                  stream: _audioPlayer.positionStream,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    return Text(
                      '${position.inMinutes}:${(position.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    );
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _audioPlayer.stop();
                  Navigator.pop(context);
                },
                child: Text(
                  '닫기',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        );
        break;

      case 'videos':
        try {
          _videoController?.dispose();
          _videoController = VideoPlayerController.network(fileUrl);

          showDialog(
            context: context,
            builder: (context) => FutureBuilder(
              future: _videoController!.initialize(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  _videoController!.play();
                  return Dialog(
                    backgroundColor: Colors.black,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: VideoPlayer(_videoController!),
                        ),
                        StatefulBuilder(
                          builder: (context, setState) {
                            return IconButton(
                              icon: Icon(
                                _videoController!.value.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                color: Colors.white,
                                size: 50,
                              ),
                              onPressed: () {
                                setState(() {
                                  if (_videoController!.value.isPlaying) {
                                    _videoController!.pause();
                                  } else {
                                    _videoController!.play();
                                  }
                                });
                              },
                            );
                          },
                        ),
                        Positioned(
                          top: 20,
                          right: 20,
                          child: IconButton(
                            icon: const Icon(Icons.close,
                                color: Colors.white, size: 30),
                            onPressed: () {
                              _videoController?.pause();
                              _videoController?.dispose();
                              _videoController = null;
                              Navigator.pop(context);
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  return const Dialog(
                    backgroundColor: Colors.black,
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  );
                }
              },
            ),
          );
        } catch (e) {
          print('비디오 컨트롤러 에러: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('비디오를 재생할 수 없습니다: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        break;

      default:
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              file['fileName'] ?? '문서',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '파일 종류: $fileType',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '저장일: ${_formatDate(file['uploadDate'] as Timestamp)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (file['content'] != null) ...[
                  const Divider(height: 24),
                  Text(
                    '내용',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    file['content'] as String,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  '닫기',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  try {
                    _storageService.downloadFile(
                      fileUrl,
                      file['fileName'],
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('다운로드가 시작되었습니다'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('다운로드 실패: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: const Text('다운로드'),
              ),
            ],
          ),
        );
    }
  }

  void _showFileMenu(
      BuildContext context, Map<String, dynamic> file, String fileId) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (file['fileType'] == 'url')
              ListTile(
                leading: Icon(
                  Icons.open_in_new,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('URL 열기'),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
            ListTile(
              leading: Icon(
                Icons.share,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('공유'),
              onTap: () {
                Navigator.pop(context);
                Share.share(file['fileUrl']);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.info_outline,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('상세 정보'),
              onTap: () {
                Navigator.pop(context);
                _showFileDetails(context, file);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '삭제',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _deleteFile(fileId, file['fileUrl']);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('보관함'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        actions: [
          if (_isSelectionMode) ...[
            Text(
              '${_selectedItems.length}개 선택됨',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _selectedItems.isEmpty ? null : _deleteSelectedFiles,
              color: Theme.of(context).colorScheme.error,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _toggleSelectionMode,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _toggleSelectionMode,
              tooltip: '삭제하기',
            ),
          ],
        ],
      ),
      drawer: const CustomDrawer(),
      body: Column(
        children: [
          _buildFilterChips(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildStorageInfo(),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestoreService.getFilesByType(_selectedType),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('오류가 발생했습니다: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '저장된 항목이 없습니다',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final fileId = doc.id;

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _isSelectionMode
                            ? () {
                                setState(() {
                                  if (_selectedItems.contains(fileId)) {
                                    _selectedItems.remove(fileId);
                                  } else {
                                    _selectedItems.add(fileId);
                                  }
                                });
                              }
                            : () => _showFileDetails(context, data),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: data['thumbnailUrl'] != null
                                      ? CachedNetworkImage(
                                          imageUrl: data['thumbnailUrl'],
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) =>
                                              Container(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceVariant,
                                            child: const Center(
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          ),
                                          errorWidget: (context, url, error) =>
                                              Container(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceVariant,
                                            child:
                                                const Icon(Icons.error_outline),
                                          ),
                                        )
                                      : Container(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceVariant,
                                          child: Center(
                                            child: Text(
                                              _getFileIcon(data['fileType']),
                                              style:
                                                  const TextStyle(fontSize: 24),
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      data['fileName'] ?? '제목 없음',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatDate(
                                          data['uploadDate'] as Timestamp),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_isSelectionMode)
                                Checkbox(
                                  value: _selectedItems.contains(fileId),
                                  onChanged: (bool? value) {
                                    setState(() {
                                      if (value == true) {
                                        _selectedItems.add(fileId);
                                      } else {
                                        _selectedItems.remove(fileId);
                                      }
                                    });
                                  },
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                )
                              else
                                IconButton(
                                  icon: const Icon(Icons.more_vert),
                                  onPressed: () =>
                                      _showFileMenu(context, data, fileId),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<Uint8List?> _downloadFile(String url) async {
  try {
    final storage = firebase_storage.FirebaseStorage.instance;
    final ref = storage.refFromURL(url);
    final maxSize = 10 * 1024 * 1024;
    final data = await ref.getData(maxSize);

    if (data != null) {
      return data;
    }

    print('데이터를 가져올 수 없습니다');
    return null;
  } catch (e) {
    print('다운로드 에러: $e');
    return null;
  }
}
