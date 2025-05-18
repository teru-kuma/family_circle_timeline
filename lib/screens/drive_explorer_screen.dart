import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:exif/exif.dart';
import '../services/google_drive_service.dart';
import 'file_viewer_screen.dart';
import 'auth_screen.dart';
import 'package:intl/intl.dart';
import 'package:intl/intl.dart';

class DriveExplorerScreen extends StatefulWidget {
  const DriveExplorerScreen({super.key});

  @override
  State<DriveExplorerScreen> createState() => _DriveExplorerScreenState();
}

class _DriveExplorerScreenState extends State<DriveExplorerScreen> {
  final GoogleDriveService _driveService = GoogleDriveService();
  final ImagePicker _picker = ImagePicker();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/drive.readonly',
    ],
  );
  List<Map<String, dynamic>> _files = [];
  bool _isLoading = true;
  bool _isUploading = false;
  String? _error;
  String? _currentFileName; // アップロード中のファイル名
  double _fileSize = 0; // ファイルサイズを記録
  bool _isGridView = true; // グリッドビュー/リストビュー切り替え用フラグ

  // フォルダナビゲーション用の変数を追加
  final String rootFolderId = '1ommatmolQ3thyVqmsaWHLuC7iYXPi5q6'; // メインフォルダID
  String _currentFolderId = '1ommatmolQ3thyVqmsaWHLuC7iYXPi5q6'; // 現在表示中のフォルダID
  List<Map<String, String>> _folderPathHistory = []; // フォルダ階層の履歴

  @override
  void initState() {
    super.initState();
    // 初期化時にルートフォルダをパス履歴に追加
    _folderPathHistory.add({
      'id': rootFolderId, 
      'name': 'メインフォルダ' // ルートフォルダの表示名
    });
    loadFiles();
  }

  Future<void> loadFiles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 指定されたフォルダ内のファイルを取得
      final files = await _driveService.listFolderContents(_currentFolderId);
      setState(() {
        _files = files
            .map((f) => {
                  'fileId': f.id ?? '',
                  'name': f.name ?? '',
                  'mimeType': f.mimeType ?? '',
                  'modifiedTime': f.modifiedTime?.toLocal().toString() ?? '',
                  'size': f.size != null ? _formatFileSize(int.parse(f.size!)) : '',
                  'thumbnailLink': f.thumbnailLink,
                  'isFolder': f.mimeType == 'application/vnd.google-apps.folder',
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

  void navigateToFolder(String folderId, String folderName) {
    if (_folderPathHistory.last['id'] != folderId) {
      _folderPathHistory.add({
        'id': folderId,
        'name': folderName,
      });
    }
    setState(() {
      _currentFolderId = folderId;
    });
    loadFiles();
  }

  void navigateBack() {
    if (_folderPathHistory.length > 1) {
      _folderPathHistory.removeLast();
      final parentFolder = _folderPathHistory.last;
      setState(() {
        _currentFolderId = parentFolder['id']!;
      });
      loadFiles();
    }
  }

  Future<void> _showMediaPickerDialog() async {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo),
                title: const Text('写真をアップロード'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text('動画をアップロード'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadVideo();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // 画像選択とアップロード
  Future<void> _pickAndUploadImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      await _uploadMediaFile(image);
    }
  }

  // 動画選択とアップロード
  Future<void> _pickAndUploadVideo() async {
    final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video != null) {
      await _uploadMediaFile(video);
    }
  }

  // ファイル名自動生成ロジック
  Future<String> getDefaultFileName(XFile mediaFile) async {
    final File file = File(mediaFile.path);
    final isVideo = mediaFile.mimeType?.startsWith('video/') ?? false;
    final prefix = isVideo ? "VID" : "IMG";
    
    try {
      // 撮影日時を取得
      final DateTime? date = await _getMediaDate(file.path);
      if (date != null) {
        // 撮影日時が取得できた場合
        final dateStr = DateFormat('yyyyMMdd_HHmmss').format(date);
        final ext = mediaFile.path.split('.').last;
        return "${prefix}_$dateStr.$ext";
      }
    } catch (e) {
      print('撮影日時取得エラー: $e');
    }

    // 撮影日時が取得できなかった場合、ファイル作成日時を使用
    try {
      final stat = await file.stat();
      final creationDate = stat.modified;
      final now = DateTime.now();
      
      // ファイル作成日時と現在時刻を組み合わせ
      final dateStr = DateFormat('yyyyMMdd').format(creationDate);
      final timeStr = DateFormat('HHmmss').format(now);
      final ext = mediaFile.path.split('.').last;
      return "${prefix}_${dateStr}_${timeStr}.$ext";
    } catch (e) {
      print('ファイル情報取得エラー: $e');
      // 最終手段として現在時刻を使用
      final now = DateTime.now();
      final formatted = DateFormat('yyyyMMdd_HHmmss').format(now);
      final ext = mediaFile.path.split('.').last;
      return "${prefix}_$formatted.$ext";
    }
  }

  // メディアファイルの撮影日時を取得
  Future<DateTime?> _getMediaDate(String imagePath) async {
    try {
      // 画像のEXIFデータを取得
      final bytes = await File(imagePath).readAsBytes();
      final tags = await readExifFromBytes(bytes);
      
      // 撮影日時を取得（EXIFデータから）
      if (tags != null) {
        final dateTimeOriginal = tags['Image DateTime']?.printable;
        if (dateTimeOriginal != null) {
          // EXIFの日付フォーマット（YYYY:MM:DD HH:MM:SS）をパース
          // 例: 2025:05:04 12:56:40 -> 2025-05-04 12:56:40
          final parts = dateTimeOriginal.split(' ');
          final datePart = parts[0].replaceAll(':', '-');
          final timePart = parts[1];
          
          // 時刻部分の - を : に戻す
          final timePartFixed = timePart.replaceAll('-', ':');
          
          // DateTime.parse()は空白区切りでもパース可能
          return DateTime.parse('$datePart $timePartFixed');
          // もしくは、ISO 8601形式で
          // return DateTime.parse('$datePartT$timePartFixed');
        }
      }
      
      // EXIFデータが見つからない場合はファイルの作成日時を使用
      final file = File(imagePath);
      final stat = await file.stat();
      return stat.modified;
    } catch (e) {
      print('撮影日時取得エラー: $e');
      return null;
    }
  }
  // 選択されたメディアファイルをアップロード
  Future<void> _uploadMediaFile(XFile mediaFile) async {
    final int fileSize = await mediaFile.length();
    final String defaultFileName = await getDefaultFileName(mediaFile);
    final TextEditingController controller = TextEditingController(text: defaultFileName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ファイル名を入力'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'ファイル名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('アップロード'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return; // キャンセル時は何もしない
    final fileName = result;

    setState(() {
      _isUploading = true;
      _currentFileName = fileName;
      _fileSize = fileSize.toDouble();
    });

    try {
      final File file = File(mediaFile.path);
      print("\uD83D\uDCE4 アップロード開始: $fileName (\${_formatFileSize(fileSize)})");
      await _driveService.uploadFileToFolder(file, fileName, _currentFolderId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("「$fileName」のアップロード完了！"),
          backgroundColor: Colors.green,
        ),
      );
      await loadFiles();
    } catch (e) {
      print("❌ アップロードエラー: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("「\${_currentFileName}」のアップロードに失敗しました"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isUploading = false;
        _currentFileName = null;
      });
    }
  }

  Widget _getFileIcon(String mimeType) {
    if (mimeType.startsWith('image/')) {
      return const Icon(Icons.image);
    } else if (mimeType.startsWith('video/')) {
      return const Icon(Icons.video_library, color: Colors.red);
    } else if (mimeType == 'application/vnd.google-apps.folder') {
      return const Icon(Icons.folder, color: Colors.orange);
    } else {
      return const Icon(Icons.insert_drive_file);
    }
  }

  void _handleFileTap(Map<String, dynamic> file) {
    if (file['isFolder'] == true) {
      navigateToFolder(file['fileId'], file['name']);
    } else {
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
    }
  }

  Widget _buildListView() {
    return ListView.builder(
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        final bool isFolder = file['isFolder'] == true;
        return ListTile(
          title: Text(file['name']!),
          subtitle: Text(isFolder 
              ? 'フォルダ'
              : '${file['modifiedTime'] ?? ''}\n${file['size'] ?? ''}'),
          leading: isFolder
              ? const Icon(Icons.folder, color: Colors.orange, size: 40)
              : (file['thumbnailLink']?.isNotEmpty == true
                  ? Image.network(
                      file['thumbnailLink']!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _getFileIcon(file['mimeType'] as String);
                      },
                    )
                  : _getFileIcon(file['mimeType'] as String)),
          trailing: isFolder
              ? const Icon(Icons.arrow_forward_ios)
              : (file['mimeType']?.toString().startsWith('video/') == true
                  ? const Icon(Icons.play_circle_outline, color: Colors.red)
                  : null),
          isThreeLine: !isFolder,
          onTap: () => _handleFileTap(file),
        );
      },
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        final bool isFolder = file['isFolder'] == true;
        final bool isVideo = !isFolder && file['mimeType']?.toString().startsWith('video/') == true;
        return GestureDetector(
          onTap: () => _handleFileTap(file),
          child: Card(
            elevation: 3,
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      isFolder
                          ? Container(
                              color: Colors.orange.shade100,
                              child: const Center(
                                child: Icon(Icons.folder, color: Colors.orange, size: 64),
                              ),
                            )
                          : (file['thumbnailLink']?.isNotEmpty == true
                              ? Image.network(
                                  file['thumbnailLink']!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.grey.shade200,
                                      child: Center(
                                        child: _getFileIcon(file['mimeType'] as String),
                                      ),
                                    );
                                  },
                                )
                              : Container(
                                  color: Colors.grey.shade200,
                                  child: Center(
                                    child: _getFileIcon(file['mimeType'] as String),
                                  ),
                                )),
                      if (isVideo)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file['name']!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isFolder ? 'フォルダ' : file['size']!,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBreadcrumbs() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.grey.shade100,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _folderPathHistory.asMap().entries.map((entry) {
            final index = entry.key;
            final folder = entry.value;
            final isLast = index == _folderPathHistory.length - 1;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: isLast ? null : () {
                    while (_folderPathHistory.length > index + 1) {
                      _folderPathHistory.removeLast();
                    }
                    setState(() {
                      _currentFolderId = folder['id']!;
                    });
                    loadFiles();
                  },
                  child: Text(
                    folder['name']!,
                    style: TextStyle(
                      color: isLast ? Colors.black : Colors.blue,
                      fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                if (!isLast) 
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.chevron_right, size: 16),
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_folderPathHistory.length > 1) {
          navigateBack();
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("家族写真・動画共有"),
          leading: _folderPathHistory.length > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: navigateBack,
                tooltip: "戻る",
              )
            : null,
          actions: [
            IconButton(
              icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
              onPressed: () {
                setState(() {
                  _isGridView = !_isGridView;
                });
              },
              tooltip: _isGridView ? "リスト表示" : "グリッド表示",
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isUploading ? null : loadFiles,
              tooltip: "更新",
            ),
            IconButton(
              icon: const Icon(Icons.cloud_upload),
              onPressed: _isUploading ? null : _showMediaPickerDialog,
              tooltip: "写真・動画アップロード",
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'ログアウト',
              onPressed: () async {
                await _googleSignIn.signOut();
                if (!mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                  (Route<dynamic> route) => false,
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            // パンくずリスト
            _buildBreadcrumbs(),
            // コンテンツ
            Expanded(
              child: Stack(
                children: [
                  _isLoading
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
                              ? const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.folder_open, size: 64, color: Colors.grey),
                                      SizedBox(height: 16),
                                      Text(
                                        "このフォルダには何もありません\n右上のボタンから写真や動画をアップロードしてください",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                )
                              : _isGridView ? _buildGridView() : _buildListView(),

                  // アップロード中のオーバーレイ
                  if (_isUploading)
                    Container(
                      color: Colors.black.withOpacity(0.7),
                      child: Center(
                        child: Card(
                          elevation: 8,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 20),
                                Text(
                                  "「${_currentFileName ?? ''}」をアップロード中",
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  "ファイルサイズ: ${_formatFileSize(_fileSize.toInt())}",
                                  style: const TextStyle(fontSize: 14),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  "大きなファイルの場合は時間がかかります\n電源を切らずにそのままお待ちください",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}