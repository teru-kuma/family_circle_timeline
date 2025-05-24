import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:exif/exif.dart';
import '../services/google_drive_service.dart';
import 'file_viewer_screen.dart';
import 'auth_screen.dart';
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// ★追加：お子様の誕生日を定数として定義 (令和4年12月7日 = 2022年12月7日)
final _childBirthDate = DateTime.utc(2022, 12, 7);

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
      // アップロードも行うため drive.file スコープも必要になる場合があります。
      // 現状 google_drive_service.dart で drive.DriveApi.driveFileScope を要求しているので、
      // ここでも合わせておくとより明確かもしれません。
      // 'https://www.googleapis.com/auth/drive.file',
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
  final String rootFolderId = dotenv.env['GOOGLE_DRIVE_FOLDER_ID'] ?? '';
  String _currentFolderId = ''; // initStateでrootFolderIdを代入
  List<Map<String, String>> _folderPathHistory = []; // フォルダ階層の履歴

  // タイムライン表示用の、日付でグループ化されたファイルを保持する新しい変数
  Map<String, List<Map<String, dynamic>>> _groupedFiles = {};

  @override
  void initState() {
    super.initState();
    _currentFolderId = rootFolderId; // _currentFolderIdを初期化
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
      final filesFromDrive = await _driveService.listFolderContents(_currentFolderId);
      setState(() {
        _files = filesFromDrive
            .map((f) => {
                  'fileId': f.id ?? '',
                  'name': f.name ?? '',
                  'mimeType': f.mimeType ?? '',
                  'modifiedTime': f.modifiedTime?.toLocal().toString() ?? '',
                  'dateTime': f.modifiedTime?.toLocal(), // DateTime型を保持
                  'size': f.size != null ? _formatFileSize(int.parse(f.size!)) : '',
                  'thumbnailLink': f.thumbnailLink,
                  'isFolder': f.mimeType == 'application/vnd.google-apps.folder',
                })
            .toList();

        // 取得したファイルを日付ごとにグループ化 (ルートフォルダ表示の時のみ)
        if (_currentFolderId == rootFolderId) {
          _groupedFiles = _groupFilesByDate(_files);
        } else {
          _groupedFiles = {};
        }

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

  Map<String, List<Map<String, dynamic>>> _groupFilesByDate(
      List<Map<String, dynamic>> files) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var file in files) {
      final DateTime? dateTime = file['dateTime'] as DateTime?;
      if (dateTime != null) {
        final String dateKey = DateFormat('yyyy/MM/dd').format(dateTime);
        if (!grouped.containsKey(dateKey)) {
          grouped[dateKey] = [];
        }
        grouped[dateKey]!.add(file);
      }
    }
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    final Map<String, List<Map<String, dynamic>>> sortedGrouped = {};
    for (var key in sortedKeys) {
      sortedGrouped[key] = grouped[key]!;
      sortedGrouped[key]!.sort((a, b) {
        final DateTime? dateA = a['dateTime'] as DateTime?;
        final DateTime? dateB = b['dateTime'] as DateTime?;
        if (dateA == null || dateB == null) return 0;
        return dateB.compareTo(dateA);
      });
    }
    return sortedGrouped;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  void navigateToFolder(String folderId, String folderName) {
    // 既に現在のフォルダなら何もしない
    if (_currentFolderId == folderId && _folderPathHistory.isNotEmpty && _folderPathHistory.last['id'] == folderId) return;

    // パンくずリストの重複追加を防ぐ
    bool alreadyInHistory = _folderPathHistory.any((folder) => folder['id'] == folderId);
    if (!alreadyInHistory) {
         _folderPathHistory.add({
            'id': folderId,
            'name': folderName,
        });
    } else {
        // 履歴内に既にあるフォルダIDに移動する場合、そのID以降の履歴を削除
        int existingIndex = _folderPathHistory.indexWhere((folder) => folder['id'] == folderId);
        if (existingIndex != -1 && existingIndex < _folderPathHistory.length -1) {
            _folderPathHistory = _folderPathHistory.sublist(0, existingIndex + 1);
        }
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

  Future<void> _pickAndUploadImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      await _uploadMediaFile(image);
    }
  }

  Future<void> _pickAndUploadVideo() async {
    final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video != null) {
      await _uploadMediaFile(video);
    }
  }

  Future<String> getDefaultFileName(XFile mediaFile) async {
    final File file = File(mediaFile.path);
    final isVideo = mediaFile.path.toLowerCase().endsWith('.mp4') ||
                    mediaFile.path.toLowerCase().endsWith('.mov') ||
                    mediaFile.path.toLowerCase().endsWith('.avi') ||
                    mediaFile.path.toLowerCase().endsWith('.mkv') ||
                    mediaFile.path.toLowerCase().endsWith('.wmv');
    final prefix = isVideo ? "VID" : "IMG";

    try {
      final DateTime? date = await _getMediaDate(file.path);
      if (date != null) {
        final dateStr = DateFormat('yyyyMMdd_HHmmss').format(date);
        final ext = mediaFile.path.split('.').last;
        return "${prefix}_$dateStr.$ext";
      }
    } catch (e) {
      print('撮影日時取得エラー: $e');
    }

    try {
      final stat = await file.stat();
      final creationDate = stat.modified;
      final now = DateTime.now();
      final dateStr = DateFormat('yyyyMMdd').format(creationDate);
      final timeStr = DateFormat('HHmmss').format(now);
      final ext = mediaFile.path.split('.').last;
      return "${prefix}_${dateStr}_${timeStr}.$ext";
    } catch (e) {
      print('ファイル情報取得エラー: $e');
      final now = DateTime.now();
      final formatted = DateFormat('yyyyMMdd_HHmmss').format(now);
      final ext = mediaFile.path.split('.').last;
      return "${prefix}_$formatted.$ext";
    }
  }

  Future<DateTime?> _getMediaDate(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final tags = await readExifFromBytes(bytes);

      if (tags != null) {
        final dateTimeOriginal = tags['Image DateTime']?.printable;
        if (dateTimeOriginal != null) {
          final parts = dateTimeOriginal.split(' ');
          if (parts.length == 2) {
            final datePart = parts[0].replaceAll(':', '-');
            final timePartFixed = parts[1].replaceAll('-', ':'); // 時刻のハイフンもコロンに
            return DateTime.tryParse('$datePart $timePartFixed');
          }
        }
      }
      final file = File(imagePath);
      final stat = await file.stat();
      return stat.modified;
    } catch (e) {
      print('撮影日時取得エラー: $e');
      return null;
    }
  }

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

    if (result == null || result.isEmpty) return;
    final fileName = result;

    setState(() {
      _isUploading = true;
      _currentFileName = fileName;
      _fileSize = fileSize.toDouble();
    });

    try {
      final File file = File(mediaFile.path);
      print("📦 アップロード開始: $fileName (${_formatFileSize(fileSize)})");
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
          content: Text("「$_currentFileName」のアップロードに失敗しました"),
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
      return Icon(Icons.folder, color: Colors.orange.shade700);
    } else {
      return const Icon(Icons.insert_drive_file);
    }
  }

  void _handleFileTap(Map<String, dynamic> file) {
    if (file['isFolder'] == true) {
      navigateToFolder(file['fileId']!, file['name']!);
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

  String _calculateAge(DateTime photoDate) {
    int years = photoDate.year - _childBirthDate.year;
    int months = photoDate.month - _childBirthDate.month;
    int days = photoDate.day - _childBirthDate.day;

    if (months < 0 || (months == 0 && days < 0)) {
      years--;
      months += 12;
    }

    if (days < 0) {
      final lastDayOfMonth = DateTime(photoDate.year, photoDate.month, 0).day;
      days = lastDayOfMonth + days;
      months--;
    }

    if (years < 0) return "生まれる前";

    String ageString = "";
    if (years > 0) {
      ageString += "${years}歳";
    }
    if (months > 0 || (years == 0 && months == 0 && days >=0 )) { // 0歳0ヶ月も表示
        if (years > 0 && months == 0 && days == 0) {
            // X歳ちょうど
        } else {
             ageString += "${months}ヶ月";
        }
    }
    if (ageString.isEmpty && days >= 0){ // 生まれて1ヶ月未満
        return "0ヶ月";
    }

    return ageString.trim();
  }

  Widget _buildTimelineView() {
    if (_groupedFiles.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              "この期間に写真や動画はありません\n右上のボタンからアップロードしてください",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _groupedFiles.keys.length,
      itemBuilder: (context, index) {
        final dateKey = _groupedFiles.keys.elementAt(index);
        final filesOnDate = _groupedFiles[dateKey]!;
        final dateParsed = DateFormat('yyyy/MM/dd').parse(dateKey);
        final childAge = _calculateAge(dateParsed);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Text(
                    dateKey.substring(5),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  if (childAge.isNotEmpty)
                    Text(
                      '($childAge)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Container(
                    width: 2,
                    // ★★★ 高さ調整ポイント 2 ★★★
                    height: 130, // 100 から 130 に変更
                    color: Colors.grey,
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  // ★★★ 高さ調整ポイント 1 ★★★
                  height: 130, // 100 から 130 に変更
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: filesOnDate.length,
                    itemBuilder: (context, fileIndex) {
                      final file = filesOnDate[fileIndex];
                      final bool isVideo = file['mimeType']?.toString().startsWith('video/') == true;
                      final bool isFolder = file['isFolder'] == true;

                      return GestureDetector(
                        onTap: () => _handleFileTap(file),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Stack(
                            children: [
                              Container(
                                width: 100,
                                height: 100, // アイテム自体の高さは100のまま（親のSizedBoxで全体の高さを確保）
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey.shade300),
                                  color: isFolder ? Colors.grey.shade100 : null,
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: isFolder
                                    ? Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.folder, size: 40, color: Colors.orange.shade700),
                                          // ★★★ フォルダ内のSizedBoxの高さ調整 ★★★
                                          const SizedBox(height: 4), // 8 から 4 に変更
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                            child: Text(
                                              file['name']!,
                                              style: const TextStyle(fontSize: 12),
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      )
                                    : file['thumbnailLink']?.isNotEmpty == true
                                        ? Image.network(
                                            file['thumbnailLink']!,
                                            fit: BoxFit.cover,
                                            loadingBuilder: (context, child, loadingProgress) {
                                              if (loadingProgress == null) return child;
                                              return Center(
                                                child: CircularProgressIndicator(
                                                  value: loadingProgress.expectedTotalBytes != null
                                                      ? loadingProgress.cumulativeBytesLoaded /
                                                          loadingProgress.expectedTotalBytes!
                                                      : null,
                                                ),
                                              );
                                            },
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
                                          ),
                              ),
                              if (isVideo && !isFolder)
                                Positioned.fill(
                                  child: Center(
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
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8.0,
        mainAxisSpacing: 8.0,
      ),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        final bool isFolder = file['isFolder'] == true;
        final bool isVideo = file['mimeType']?.toString().startsWith('video/') == true;

        return GestureDetector(
          onTap: () => _handleFileTap(file),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: isFolder
                      ? Center(child: Icon(Icons.folder, size: 40, color: Colors.orange.shade700))
                      : file['thumbnailLink'] != null && file['thumbnailLink']!.isNotEmpty
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  file['thumbnailLink']!,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return const Center(child: CircularProgressIndicator());
                                  },
                                  errorBuilder: (context, error, stackTrace) {
                                    return Center(child: _getFileIcon(file['mimeType']!));
                                  },
                                ),
                                if (isVideo)
                                  const Center(
                                    child: Icon(Icons.play_circle_outline, color: Colors.white70, size: 30),
                                  ),
                              ],
                            )
                          : Center(child: _getFileIcon(file['mimeType']!)),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    file['name']!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildListView() {
    return ListView.builder(
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        final bool isFolder = file['isFolder'] == true;

        return ListTile(
          leading: _getFileIcon(file['mimeType']!), // isFolderも考慮される
          title: Text(file['name']!),
          subtitle: Text(isFolder ? 'フォルダ' : (file['size'] ?? '')),
          onTap: () => _handleFileTap(file),
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
                    navigateToFolder(folder['id']!, folder['name']!);
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
        if (_currentFolderId != rootFolderId && _folderPathHistory.length > 1) {
          navigateBack();
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_folderPathHistory.isNotEmpty ? _folderPathHistory.last['name']! : "家族写真・動画共有"),
          leading: _currentFolderId != rootFolderId && _folderPathHistory.length > 1
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: navigateBack,
                  tooltip: "戻る",
                )
              : null,
          actions: [
            if (_currentFolderId != rootFolderId) // サブフォルダ内でのみ表示・非表示切り替えを表示
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
            if (_folderPathHistory.length > 1) _buildBreadcrumbs(),
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
                          : _currentFolderId == rootFolderId
                              ? _buildTimelineView()
                              : _files.isEmpty
                                  ? const Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.folder_open, size: 64, color: Colors.grey),
                                          SizedBox(height: 16),
                                          Text(
                                            "このフォルダには何もありません",
                                            textAlign: TextAlign.center,
                                            style: TextStyle(color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    )
                                  : _isGridView
                                      ? _buildGridView()
                                      : _buildListView(),
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