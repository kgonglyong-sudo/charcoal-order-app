import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _clientCodeController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _clientCodeController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_clientCodeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('거래처 코드를 입력해주세요')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final authService = Provider.of<AuthService>(context, listen: false);
    final success = await authService.login(_clientCodeController.text.trim());

    setState(() {
      _isLoading = false;
    });

    if (success) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/products');
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('잘못된 거래처 코드입니다')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.orange.shade50,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 로고
              Image.asset(
                'assets/images/logo-bg.png',
                width: 200,
                height: 120,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  // 이미지 로드 실패시 기존 아이콘 표시
                  return Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(60),
                    ),
                    child: const Icon(
                      Icons.local_fire_department,
                      size: 60,
                      color: Colors.white,
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              
              // 제목
              const Text(
                '서울에너지 숯 주문관리 충청지사',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '거래처 코드로 로그인하세요',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 48),
              
              // 입력 필드
              Container(
                constraints: const BoxConstraints(maxWidth: 400),
                child: TextField(
                  controller: _clientCodeController,
                  decoration: InputDecoration(
                    labelText: '거래처 코드',
                    hintText: 'CLIENT001, CLIENT002, CLIENT003',
                    prefixIcon: const Icon(Icons.business),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _login(),
                ),
              ),
              const SizedBox(height: 24),
              
              // 로그인 버튼
              Container(
                constraints: const BoxConstraints(maxWidth: 400),
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          '로그인',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 32),
              
              // 테스트 계정 안내
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '테스트 계정',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text('CLIENT001 - 대한숯상회 (A등급)'),
                    Text('CLIENT002 - 중부숯유통 (B등급)'),
                    Text('CLIENT003 - 충남숯도매 (C등급)'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
