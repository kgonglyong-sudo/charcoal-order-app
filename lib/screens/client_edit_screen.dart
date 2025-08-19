import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

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
  String tier = 'B';
  bool isActive = true;
  String memo = '';

  @override
  void initState() {
    super.initState();
    final d = widget.initData;
    if (widget.code != null) codeCtrl.text = widget.code!;
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
    codeCtrl.dispose(); nameCtrl.dispose(); phoneCtrl.dispose(); addrCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;

    final branchId = context.read<AuthService>().branchId;
    if (branchId == null || branchId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('지점 정보가 없습니다.')));
      return;
    }

    final code = codeCtrl.text.trim().toUpperCase();
    final ref = FirebaseFirestore.instance
        .collection('branches').doc(branchId)
        .collection('clients').doc(code);

    final data = {
      'code': code,
      'name': nameCtrl.text.trim(),
      'nameLower': nameCtrl.text.trim().toLowerCase(), // 검색용
      'phone': phoneCtrl.text.trim(),
      'address': addrCtrl.text.trim(),
      'priceTier': tier,
      'isActive': isActive,
      'memo': memo,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': widget.code == null ? FieldValue.serverTimestamp() : null,
    }..removeWhere((k, v) => v == null);

    await ref.set(data, SetOptions(merge: true));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장되었습니다.')));
      Navigator.pop(context);
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
              readOnly: isEdit, // 코드 변경 금지
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
