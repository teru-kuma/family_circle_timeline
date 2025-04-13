import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../services/google_drive_service.dart';

class FileViewerScreen extends StatefulWidget {
  final String fileId;
  final String fileName;
  final String mimeType;
  final int fileSize;

  const FileViewerScreen({
    super.key,
    required this.fileId,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
  });

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  final GoogleDriveService _driveService = GoogleDriveService();
  Uint8List? _fileBytes;
  VideoPlayerController? _videoController;
  bool _isLoading = true;
  String? _error;
  File? _tempFile;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    try {
      final driveApi = await _driveService.getDriveApi();
      if (driveApi == null) throw Exception("Drive APIクライアント取得失敗");

      setState(() {
        _isLoading = true;
        _error = null;
      });

      if (widget.mimeType.startsWith('video/')) {
        // 動画の場合、Google Drive APIを使用してファイルを取得
        final tempDir = await getTemporaryDirectory();
        _tempFile = File('${tempDir.path}/${widget.fileName}');

        // 既存の一時ファイルを削除
        if (await _tempFile!.exists()) {
          await _tempFile!.delete();
        }

        // ファイルのダウンロード
        final file = await driveApi.files.get(
          widget.fileId,
          downloadOptions: drive.DownloadOptions.fullMedia,
        );

        if (file is drive.Media) {
          final bytes = <int>[];
          await for (final chunk in file.stream) {
            bytes.addAll(chunk);
          }
          
          await _tempFile!.writeAsBytes(Uint8List.fromList(bytes), flush: true);

          // 動画プレーヤーの初期化
          _videoController = VideoPlayerController.file(_tempFile!)
            ..initialize().then((_) {
              setState(() {
                _isLoading = false;
              });
              _videoController?.play();
            })
            ..addListener(() {
              if (_videoController!.value.hasError) {
                setState(() {
                  _error = '動画の再生に失敗しました: ${_videoController!.value.errorDescription}';
                  _isLoading = false;
                });
              }
            });
        } else {
          throw Exception('動画ファイルの取得に失敗しました');
        }
      } else {
        // 画像などの静的ファイルの場合
        final file = await driveApi.files.get(
          widget.fileId,
          downloadOptions: drive.DownloadOptions.fullMedia,
        );

        if (file is drive.Media) {
          final bytes = <int>[];
          await for (final chunk in file.stream) {
            bytes.addAll(chunk);
          }

          setState(() {
            _fileBytes = Uint8List.fromList(bytes);
            _isLoading = false;
          });
        } else {
          throw Exception('ファイルの取得に失敗しました');
        }
      }
    } catch (e) {
      setState(() {
        _error = 'ファイルの読み込みに失敗しました: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _cleanUp() async {
    // 一時ファイルの削除
    if (_tempFile != null && await _tempFile!.exists()) {
      await _tempFile!.delete();
    }
  }

  @override
  void dispose() {
    // 動画プレーヤーのクリーンアップ
    _videoController?.dispose();
    _videoController = null;

    // 一時ファイルの削除
    _cleanUp();

    // メモリ解放
    _fileBytes = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _cleanUp();  // 再読み込み前にクリーンアップ
              _loadFile();
            },
          ),
        ],
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadFile(),
              child: const Text("再試行"),
            ),
          ],
        ),
      );
    } else if (widget.mimeType.startsWith('video/') && _videoController != null) {
      return AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: VideoPlayer(_videoController!),
      );
    } else if (widget.mimeType.startsWith('image/') && _fileBytes != null) {
      return Image.memory(_fileBytes!);
    } else {
      return const Center(child: Text("このファイル形式にはまだ対応していません"));
    }
  }
}
