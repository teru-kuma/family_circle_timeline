import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/google_drive_service.dart';
import 'file_viewer_screen.dart';
import 'auth_screen.dart';

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

  // サブフォルダに移動するメソッド
  void navigateToFolder(String folderId, String folderName) {
    // 現在のフォルダをパス履歴に追加（すでに履歴にある場合は追加しない）
    if (_folderPathHistory.last['id'] != folderId) {
      _folderPathHistory.add({
        'id': folderId,
        'name': folderName,
      });
    }
    
    setState(() {
      _currentFolderId = folderId;
    });
    
    loadFiles(); // フォルダの内容を読み込む
  }

  // 親フォルダに戻るメソッド
  void navigateBack() {
    if (_folderPathHistory.length > 1) {
      // 最後の要素（現在のフォルダ）を削除
      _folderPathHistory.removeLast();
      // 新しい現在のフォルダを設定
      final parentFolder = _folderPathHistory.last;
      setState(() {
        _currentFolderId = parentFolder['id']!;
      });
      loadFiles();
    }
  }

  // メディア選択ダイアログを表示
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

  // 選択されたメディアファイルをアップロード
  Future<void> _uploadMediaFile(XFile mediaFile) async {
    // ファイルサイズの取得
    final int fileSize = await mediaFile.length();
    
    setState(() {
      _isUploading = true;
      _currentFileName = mediaFile.name;
      _fileSize = fileSize.toDouble();
    });

    try {
      final File file = File(mediaFile.path);
      final String fileName = mediaFile.name;
      
      print("📤 アップロード開始: $fileName (${_formatFileSize(fileSize)})");

      // 現在のフォルダにアップロード
      await _driveService.uploadFileToFolder(file, fileName, _currentFolderId);
      
      // 成功メッセージ
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("「$fileName」のアップロード完了！"),
          backgroundColor: Colors.green,
        ),
      );
      
      // ファイル一覧を更新
      await loadFiles();
    } catch (e) {
      print("❌ アップロードエラー: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("「${_currentFileName}」のアップロードに失敗しました"),
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

  // ファイルをタップした時の処理
  void _handleFileTap(Map<String, dynamic> file) {
    if (file['isFolder'] == true) {
      // フォルダの場合はそのフォルダに移動
      navigateToFolder(file['fileId'], file['name']);
    } else {
      // ファイルの場合はビューアを表示
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

  // リストビューを構築
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
              : '${file['modifiedTime']}\n${file['size']}'),
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

  // グリッドビューを構築
  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, // 横に2つのアイテム
        childAspectRatio: 0.75, // 縦長のカード
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
            clipBehavior: Clip.antiAlias, // 角丸のカードに合わせて内容を切り取る
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // フォルダかファイルか
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
                      
                      // 動画の場合は再生アイコンを重ねる
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

  // パンくずリストを表示するウィジェット
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
                    // パスの途中のフォルダをクリックした場合、そこまで戻る
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
          return false; // 画面を閉じずに、親フォルダに戻す
        }
        return true; // ルートなら通常の戻る動作
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