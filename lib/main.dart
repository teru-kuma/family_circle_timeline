import 'package:flutter/material.dart';
import 'screens/auth_screen.dart'; // ← これがあなたの作ったログイン画面

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family Drive App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const AuthScreen(), // ← アプリ起動時に最初に表示する画面！
    );
  }
}
