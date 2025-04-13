import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

class GoogleDriveService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      drive.DriveApi.driveReadonlyScope,
      drive.DriveApi.driveFileScope,
      drive.DriveApi.driveMetadataReadonlyScope,
    ],
  );

  Future<drive.DriveApi?> getDriveApi() async {
    try {
      final account = await _googleSignIn.signInSilently() ?? await _googleSignIn.signIn();
      if (account == null) return null;

      final auth = await account.authentication;
      if (auth.accessToken == null) throw Exception("アクセストークンの取得に失敗しました");

      final authClient = authenticatedClient(
        http.Client(),
        AccessCredentials(
          AccessToken(
            "Bearer",
            auth.accessToken!,
            DateTime.now().toUtc().add(const Duration(hours: 1)),
          ),
          null,
          [
            drive.DriveApi.driveReadonlyScope,
            drive.DriveApi.driveFileScope,
            drive.DriveApi.driveMetadataReadonlyScope,
          ],
        ),
      );

      return drive.DriveApi(authClient);
    } catch (e) {
      print("🔐 Drive API認証エラー: $e");
      rethrow;
    }
  }

  Future<List<drive.File>> listMyDriveFiles() async {
    try {
      final driveApi = await getDriveApi();
      if (driveApi == null) throw Exception("Drive APIクライアント取得失敗");

      print("🔍 Drive API呼び出し開始");

      final folderId = '1ommatmolQ3thyVqmsaWHLuC7iYXPi5q6';

      final fileList = await driveApi.files.list(
        q: "'$folderId' in parents and mimeType != 'application/vnd.google-apps.folder' and trashed = false",
        $fields: "files(id, name, mimeType, modifiedTime, size, thumbnailLink)",
        pageSize: 100,
        orderBy: "modifiedTime desc",
      );

      print("📝 Drive APIレスポンス: ${fileList.files?.length} 件");

      fileList.files?.forEach((file) {
        print("  - ${file.name} (${file.mimeType})");
        print("    Size: ${file.size}, Thumbnail: ${file.thumbnailLink}");
      });

      return fileList.files ?? [];
    } catch (e) {
      print("❌ Drive一覧取得エラー: $e");
      rethrow;
    }
  }

  // ✅ アップロード追加！
  Future<void> uploadFileToFolder(File file, String fileName, String folderId) async {
    final driveApi = await getDriveApi();
    if (driveApi == null) throw Exception("Drive APIクライアント取得失敗");

    final media = drive.Media(file.openRead(), await file.length());
    final driveFile = drive.File()
      ..name = fileName
      ..parents = [folderId];

    await driveApi.files.create(driveFile, uploadMedia: media);
    print("✅ アップロード成功: $fileName");
  }
}
