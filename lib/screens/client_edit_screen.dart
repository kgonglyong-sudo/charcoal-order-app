// lib/screens/client_edit_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class ClientEditScreen extends StatefulWidget {
  final String branchId;
  final String? code;
  final Map<String, dynamic>? initData;

  const ClientEditScreen({
    super.key,
    required this.branchId,
    this.code,
    this.initData,
  });

  @override
  State<ClientEditScreen> createState() => _ClientEditScreenState();
}

class _ClientEditScreenState extends State<ClientEditScreen> {
  final _formKey = GlobalKey<FormState>();

  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _contactPersonController = TextEditingController();
  final _emailController = TextEditingController();
  final _notesController = TextEditingController();
  
  String _priceTier = 'C';
  List<int> _deliveryDays = [];
  bool _isActive = true;
  bool _isLoading = false;
  bool _isPaymentRequired = true;

  @override
  void initState() {
    super.initState();
    _loadClientData();
    if (_isNewClient()) {
      _loadAutoCodePreview();
    }
  }

  void _loadClientData() {
    if (_isNewClient()) {
      _codeController.text = '불러오는 중...';
    } else {
      final data = widget.initData!;
      _codeController.text = widget.code ?? '';
      _nameController.text = data['name'] ?? '';
      _phoneController.text = data['phone'] ?? '';
      _addressController.text = data['address'] ?? '';
      _contactPersonController.text = data['contactPerson'] ?? '';
      _emailController.text = data['email'] ?? '';
      _notesController.text = data['notes'] ?? '';
      _isActive = data['isActive'] ?? true;
      _priceTier = data['priceTier'] ?? 'C';
      _deliveryDays = List<int>.from(data['deliveryDays'] ?? []);
      _isPaymentRequired = data['isPaymentRequired'] ?? true;
    }
  }

  Future<void> _loadAutoCodePreview() async {
    try {
      final authService = context.read<AuthService>();
      final previewCode = await authService.previewNextClientCodeByPolicy(widget.branchId);
      if (mounted) {
        setState(() {
          _codeController.text = previewCode;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _codeController.text = '오류: 코드 생성 실패';
        });
      }
      print('❌ 코드 미리보기 로드 중 오류 발생: $e');
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _contactPersonController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveClient() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isNewClient() && _passwordController.text.isEmpty) {
      _showErrorDialog('새 거래처 등록 시 비밀번호는 필수입니다.');
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      final authService = context.read<AuthService>();

      if (!authService.isSignedIn || !(['manager', 'admin'].contains(authService.role))) {
        throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
            message: '매니저 권한이 필요합니다.');
      }
      
      if (_isNewClient()) {
        final newCode = await authService.createClientAuto(
          branchId: widget.branchId,
          name: _nameController.text.trim(),
          password: _passwordController.text,
          isPaymentRequired: _isPaymentRequired,
          priceTier: _priceTier,
          deliveryDays: _deliveryDays,
        );
        print('✅ AuthService를 통해 거래처 생성 성공: $newCode');
        _showSuccessDialog('거래처가 성공적으로 등록되었습니다: $newCode');
      } else {
        final clientsRef = FirebaseFirestore.instance
            .collection('branches')
            .doc(widget.branchId)
            .collection('clients');
            
        await clientsRef.doc(widget.code).update({
          'name': _nameController.text.trim(),
          'nameLower': _nameController.text.trim().toLowerCase(),
          'phone': _phoneController.text.trim(),
          'address': _addressController.text.trim(),
          'contactPerson': _contactPersonController.text.trim(),
          'email': _emailController.text.trim(),
          'notes': _notesController.text.trim(),
          'isActive': _isActive,
          'priceTier': _priceTier,
          'deliveryDays': _deliveryDays,
          'isPaymentRequired': _isPaymentRequired,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _showSuccessDialog('거래처 정보가 성공적으로 수정되었습니다');
      }
    } catch (e, stackTrace) {
      print('🔥🔥🔥 거래처 저장 최종 에러 🔥🔥🔥');
      print('에러 타입: ${e.runtimeType}');
      print('에러 메시지: $e');
      print('--- 스택 트레이스 ---');
      print(stackTrace);
      _showErrorDialog('저장 중 오류가 발생했습니다. 디버그 콘솔을 확인하세요.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool _isNewClient() => widget.code == null;

  void _toggleDeliveryDay(int day) {
    setState(() {
      if (_deliveryDays.contains(day)) {
        _deliveryDays.remove(day);
      } else {
        _deliveryDays.add(day);
        _deliveryDays.sort();
      }
    });
  }
  
  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('오류'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('성공'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context, true);
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNewClient() ? '새 거래처 등록' : '거래처 정보 수정'),
        actions: [
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))))
          else
            IconButton(onPressed: _saveClient, icon: const Icon(Icons.save), tooltip: '저장'),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: '거래처 코드',
                  border: OutlineInputBorder(),
                ),
                readOnly: true,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              if (_isNewClient())
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: '비밀번호 *',
                    hintText: '새 거래처의 비밀번호를 설정해주세요',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  validator: (value) => (value?.trim().isEmpty ?? true) ? '비밀번호를 입력해주세요.' : null,
                ),
              if (_isNewClient()) const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '거래처명 *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value?.trim().isEmpty ?? true) ? '거래처명을 입력해주세요.' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _priceTier,
                decoration: const InputDecoration(labelText: '가격 등급', border: OutlineInputBorder()),
                items: ['A', 'B', 'C'].map((tier) => DropdownMenuItem(value: tier, child: Text('등급 $tier'))).toList(),
                onChanged: (value) => setState(() => _priceTier = value!),
              ),
              const SizedBox(height: 24),
              const Text('지정 배송요일', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Wrap(
                spacing: 8,
                children: List.generate(7, (index) {
                  final day = index + 1;
                  final dayLabels = ['월', '화', '수', '목', '금', '토', '일'];
                  final isSelected = _deliveryDays.contains(day);
                  return ChoiceChip(
                    label: Text(dayLabels[index]),
                    selected: isSelected,
                    onSelected: (_) => _toggleDeliveryDay(day),
                  );
                }),
              ),
              const SizedBox(height: 24),
              SwitchListTile(
                title: const Text('주문 시 결제 필수'),
                value: _isPaymentRequired,
                onChanged: (value) => setState(() => _isPaymentRequired = value),
              ),
              const SizedBox(height: 16),
              TextFormField(controller: _phoneController, decoration: const InputDecoration(labelText: '연락처', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              TextFormField(controller: _addressController, decoration: const InputDecoration(labelText: '주소', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              TextFormField(controller: _contactPersonController, decoration: const InputDecoration(labelText: '담당자', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              TextFormField(controller: _emailController, decoration: const InputDecoration(labelText: '이메일', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              TextFormField(controller: _notesController, decoration: const InputDecoration(labelText: '메모', border: OutlineInputBorder()), maxLines: 3),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('활성 상태'),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
              ),
            ],
          ),
        ),
      ),
    );
  }
}