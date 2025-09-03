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

  // 컨트롤러
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _contactPersonController = TextEditingController();
  final _emailController = TextEditingController();
  final _notesController = TextEditingController();
  
  // 상태 변수
  String _priceTier = 'C';
  List<int> _deliveryDays = [];
  bool _isActive = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadClientData();
  }

  void _loadClientData() {
    if (_isNewClient()) {
      _codeController.text = '(자동 생성)';
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
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _contactPersonController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveClient() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    
    // ==================== 👇 여기가 수정된 부분입니다 👇 ====================
    try {
      final authService = context.read<AuthService>(listen: false);
      
      if (_isNewClient()) {
        final branchKey = _getBranchPrefix(widget.branchId);
        
        final newCode = await authService.createClientAuto(
          branchKey: branchKey,
          name: _nameController.text.trim(),
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
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _showSuccessDialog('거래처 정보가 성공적으로 수정되었습니다');
      }
    } catch (e, stackTrace) { // ✨ e와 함께 stackTrace를 잡도록 변경
      // ✨✨✨ 정밀 탐지기 ✨✨✨
      print('🔥🔥🔥 거래처 저장 최종 에러 🔥🔥🔥');
      print('에러 타입: ${e.runtimeType}');
      print('에러 메시지: $e');
      print('--- 스택 트레이스 ---');
      print(stackTrace);
      _showErrorDialog('저장 중 오류가 발생했습니다. 디버그 콘솔을 확인하세요.');
    } finally {
    // ==================== 👆 여기가 수정된 부분입니다 👆 ====================
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool _isNewClient() => widget.code == null;

  String _getBranchPrefix(String branchId) {
    if (branchId.toLowerCase().contains('gimpo')) return 'GP';
    if (branchId.toLowerCase().contains('chungcheong') || branchId.toLowerCase().contains('충청')) return 'CC';
    return 'ETC';
  }

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