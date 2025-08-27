import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/client_service.dart';  // ClientService import

class ClientEditScreen extends StatefulWidget {
  const ClientEditScreen({super.key, this.code, this.initData});
  final String? code; // 수정 시 문서ID
  final Map<String, dynamic>? initData;

  @override
  State<ClientEditScreen> createState() => _ClientEditScreenState();
}

class _ClientEditScreenState extends State<ClientEditScreen> {
  final _form = GlobalKey<FormState>();
  final codeCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final addrCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();  // 비밀번호 입력란 추가
  String tier = 'B';
  bool isActive = true;
  String memo = '';

  @override
  void initState() {
    super.initState();
    final d = widget.initData;
    if (widget.code != null) codeCtrl.text = widget.code!;  // 수정 시 코드 입력
    if (d != null) {
      nameCtrl.text = d['name'] ?? '';
      phoneCtrl.text = d['phone'] ?? '';
      addrCtrl.text = d['address'] ?? '';
      tier = (d['priceTier'] ?? 'B');
      isActive = (d['isActive'] ?? true);
      memo = (d['memo'] ?? '');
    }
  }

  @override
  void dispose() {
    codeCtrl.dispose();
    nameCtrl.dispose();
    phoneCtrl.dispose();
    addrCtrl.dispose();
    passwordCtrl.dispose();  // 비밀번호 입력란 해제
    super.dispose();
  }

  // 수정된 _save() 함수
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;

    final branchId = context.read<AuthService>().branchId;
    if (branchId == null || branchId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('지점 정보가 없습니다.')));
      return;
    }

    final rawPassword = passwordCtrl.text.trim();  // 비밀번호 값을 사용자 입력으로 처리

    // code가 null일 경우 새로운 거래처를 등록
    final code = codeCtrl.text.trim().toUpperCase();

    try {
      // ClientService를 사용해 거래처 생성
      final clientService = ClientService(FirebaseFirestore.instance);
      final clientCode = await clientService.createClient(
        branchId: branchId,
        data: {
          'name': nameCtrl.text.trim(),
          'phone': phoneCtrl.text.trim(),
          'address': addrCtrl.text.trim(),
          'priceTier': tier,
          'isActive': isActive,
          'memo': memo,
        },
        rawPassword: rawPassword,  // 비밀번호는 이제 사용자가 입력한 값으로 처리
      );

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('거래처 저장 완료')));
      Navigator.pop(context);  // 저장 후 이전 화면으로 돌아가기
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.code != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? '거래처 수정' : '거래처 등록')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: codeCtrl,
              readOnly: isEdit,  // 수정 시 코드 변경 불가
              decoration: const InputDecoration(labelText: '거래처 코드'),
              validator: (v) => (v == null || v.trim().isEmpty) ? '코드를 입력하세요' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: '거래처명'),
              validator: (v) => (v == null || v.trim().isEmpty) ? '이름을 입력하세요' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(controller: phoneCtrl, decoration: const InputDecoration(labelText: '전화번호')),
            const SizedBox(height: 8),
            TextFormField(controller: addrCtrl, decoration: const InputDecoration(labelText: '주소')),
            const SizedBox(height: 8),
            TextFormField(
              controller: passwordCtrl,  // 비밀번호 입력란 추가
              obscureText: true,  // 비밀번호는 숨김 처리
              decoration: const InputDecoration(labelText: '비밀번호'),
              validator: (v) => (v == null || v.trim().isEmpty) ? '비밀번호를 입력하세요' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('등급:'),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: tier,
                  items: const [
                    DropdownMenuItem(value: 'A', child: Text('A')),
                    DropdownMenuItem(value: 'B', child: Text('B')),
                    DropdownMenuItem(value: 'C', child: Text('C')),
                  ],
                  onChanged: (v) => setState(() => tier = v ?? 'B'),
                ),
                const Spacer(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('활성'),
                  value: isActive,
                  onChanged: (v) => setState(() => isActive = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: memo,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '메모'),
              onChanged: (v) => memo = v,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('저장'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
