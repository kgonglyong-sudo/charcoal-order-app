// lib/screens/email_login_dialog.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class EmailLoginDialog extends StatefulWidget {
  const EmailLoginDialog({super.key});

  @override
  State<EmailLoginDialog> createState() => _EmailLoginDialogState();
}

class _EmailLoginDialogState extends State<EmailLoginDialog> {
  final _email = TextEditingController();
  final _pw = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    final pw = _pw.text;
    if (email.isEmpty || pw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이메일과 비밀번호를 입력하세요')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await context.read<AuthService>().signInWithEmail(email, pw);
      if (!mounted) return; // 팝업이 이미 닫혔으면 중단
      Navigator.of(context).pop(); // 성공 → 팝업 닫기 (화면 분기는 AuthGate가 처리)
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('이메일로 로그인'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: '이메일'),
              onSubmitted: (_) => _login(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pw,
              obscureText: true,
              decoration: const InputDecoration(labelText: '비밀번호'),
              onSubmitted: (_) => _login(),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '예) manager@demo.com / test1234',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _login,
          child: _loading
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('로그인'),
        ),
      ],
    );
  }
}
