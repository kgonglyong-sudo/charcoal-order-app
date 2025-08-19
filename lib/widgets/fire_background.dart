// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import '../widgets/fire_background.dart';
// 기존 import들 유지

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FireBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('숯 회사 로그인',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 16),
                    // TODO: 기존 로그인 폼 위젯들 배치
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
