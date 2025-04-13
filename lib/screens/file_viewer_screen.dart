import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:video_player/video_player.dart';
import '../services/google_drive_service.dart';
import 'package:url_launcher/url_launcher.dart';

class FileViewerScreen extends StatefulWidget {
  final String fileId;
  final String fileName;
  final String mimeType;

  const FileViewerScreen({
    super.key,
    required this.fileId,
    required this.fileName,
    required this.mimeType,
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
    if (widget.mimeType.startsWith('image/')) {
      _loadFile();
    } else {
      _isLoading = false; // 動画などはすぐ表示用メッセージに切り替える
    }
  }

  Future<void> _loadFile() async {
    try {
      final driveApi = await _driveService.getDriveApi();
      if (driveApi == null) throw Exception("Drive APIクライアント取得失敗");

      setState(() {
        _isLoading = true;
        _error = null;
      });

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
    } catch (e) {
      setState(() {
        _error = 'ファイルの読み込みに失敗しました: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _launchDriveVideo(String fileId) async {
    final url = 'https://drive.google.com/file/d/$fileId/view';
    final uri = Uri.parse(url);

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw '起動に失敗しました';
      }
    } catch (e) {
      print("❌ URL起動に失敗しました: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('動画を開けませんでした。Google Driveアプリがインストールされていますか？')),
      );
    }
  }

  Future<void> _cleanUp() async {
    if (_tempFile != null && await _tempFile!.exists()) {
      await _tempFile!.delete();
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _videoController = null;
    _cleanUp();
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
            icon: const Icon(Icons.open_in_browser),
            onPressed: () => _launchDriveVideo(widget.fileId),
            tooltip: 'Google Driveで開く',
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
              onPressed: _loadFile,
              child: const Text("再試行"),
            ),
          ],
        ),
      );
    } else if (widget.mimeType.startsWith('image/') && _fileBytes != null) {
      return Image.memory(_fileBytes!);
    } else {
      return const Center(child: Text("動画はGoogle Driveアプリで再生できます"));
    }
  }
}
