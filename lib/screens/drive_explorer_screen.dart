import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/google_drive_service.dart';
import 'file_viewer_screen.dart';

class DriveExplorerScreen extends StatefulWidget {
  const DriveExplorerScreen({super.key});

  @override
  State<DriveExplorerScreen> createState() => _DriveExplorerScreenState();
}

class _DriveExplorerScreenState extends State<DriveExplorerScreen> {
  final GoogleDriveService _driveService = GoogleDriveService();
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> _files = [];
  bool _isLoading = true;
  bool _isUploading = false;
  String? _error;

  final String folderId = '1ommatmolQ3thyVqmsaWHLuC7iYXPi5q6'; // あなたの共有フォルダID

  @override
  void initState() {
    super.initState();
    loadFiles();
  }

  Future<void> loadFiles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final files = await _driveService.listMyDriveFiles();
      setState(() {
        _files = files
            .map((f) => {
                  'fileId': f.id ?? '',
                  'name': f.name ?? '',
                  'mimeType': f.mimeType ?? '',
                  'modifiedTime': f.modifiedTime?.toLocal().toString() ?? '',
                  'size': f.size != null ? _formatFileSize(int.parse(f.size!)) : '',
                  'thumbnailLink': f.thumbnailLink,
                })
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      print("❌ Drive一覧取得エラー: $e");
      setState(() {
        _isLoading = false;
        _error = "Google Driveの内容を取得できませんでした。\n権限の確認をお願いします。";
      });
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _uploadFile() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() => _isUploading = true);

    final file = File(pickedFile.path);
    final fileName = pickedFile.name;

    try {
      await _driveService.uploadFileToFolder(file, fileName, folderId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("アップロード成功！")),
      );
      await loadFiles(); // アップロード後に一覧更新
    } catch (e) {
      print("❌ アップロードエラー: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("アップロードに失敗しました")),
      );
    } finally {
      setState(() => _isUploading = false);
    }
  }

  Widget _getFileIcon(String mimeType) {
    if (mimeType.startsWith('image/')) {
      return const Icon(Icons.image);
    } else if (mimeType.startsWith('video/')) {
      return const Icon(Icons.video_file);
    } else if (mimeType.startsWith('audio/')) {
      return const Icon(Icons.audio_file);
    } else if (mimeType.contains('folder')) {
      return const Icon(Icons.folder);
    } else if (mimeType.contains('pdf')) {
      return const Icon(Icons.picture_as_pdf);
    } else if (mimeType.contains('document') || mimeType.contains('text')) {
      return const Icon(Icons.description);
    } else if (mimeType.contains('spreadsheet')) {
      return const Icon(Icons.table_chart);
    } else if (mimeType.contains('presentation')) {
      return const Icon(Icons.slideshow);
    }
    return const Icon(Icons.insert_drive_file);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Google Driveの中身"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadFiles,
          ),
          IconButton(
            icon: _isUploading
                ? const Icon(Icons.sync, color: Colors.grey)  // ← わかりやすく回ってる感
                : const Icon(Icons.cloud_upload),
            onPressed: _isUploading ? null : _uploadFile,
            tooltip: "アップロード",
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: loadFiles,
                        child: const Text("再試行"),
                      ),
                    ],
                  ),
                )
              : _files.isEmpty
                  ? const Center(child: Text("ファイルが見つかりません"))
                  : ListView.builder(
                      itemCount: _files.length,
                      itemBuilder: (context, index) {
                        final file = _files[index];
                        return ListTile(
                          title: Text(file['name']!),
                          subtitle: Text('${file['modifiedTime']}\n${file['size']}'),
                          leading: file['thumbnailLink']?.isNotEmpty == true
                              ? Image.network(
                                  file['thumbnailLink']!,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    print("🖼️ サムネイル読み込みエラー: $error");
                                    return _getFileIcon(file['mimeType'] as String);
                                  },
                                )
                              : _getFileIcon(file['mimeType'] as String),
                          isThreeLine: true,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FileViewerScreen(
                                  fileId: file['fileId']!,
                                  fileName: file['name']!,
                                  mimeType: file['mimeType']!,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
    );
  }
}
