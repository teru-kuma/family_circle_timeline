import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../screens/drive_explorer_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // ✅ 必ず drive.readonly スコープを含める
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/drive.readonly',
    ],
  );

  bool _isSigningIn = false;
  String? _error;
  GoogleSignInAccount? _user;

  Future<void> _handleSignIn() async {
    print("🚀 _handleSignIn() 実行開始");

    setState(() {
      _isSigningIn = true;
      _error = null;
    });

    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        print("❌ アカウントが null → ログインキャンセル or 失敗");
        throw Exception("ログインがキャンセルされました");
      }

      print("✅ ログイン成功！");
      print("👤 ユーザー名: ${account.displayName}");
      print("📧 メール: ${account.email}");

      setState(() => _user = account);

      if (!mounted) return;

      // ✅ 成功したら Drive 画面へ遷移
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DriveExplorerScreen()),
      );
    } catch (e, stack) {
      print("❌ ログイン処理でエラー: $e");
      print("🪜 StackTrace:\n$stack");
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isSigningIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ログイン')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Googleでログインしてファイルを見る'),
                  const SizedBox(height: 24),
                  _isSigningIn
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: () async {
                            print("👆 ログインボタンが押されました！");
                            await _handleSignIn();
                          },
                          child: const Text('Googleでログイン'),
                        ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ]
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
// auth_screen.dartのGoogleSignInの初期化部分を修正
final GoogleSignIn _googleSignIn = GoogleSignIn(
  scopes: [
    'email',
    'profile',
    drive.DriveApi.driveReadonlyScope,
    drive.DriveApi.driveFileScope,
    drive.DriveApi.driveMetadataReadonlyScope,
  ],
);