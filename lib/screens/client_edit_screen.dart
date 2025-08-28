import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

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
  
  // 기본 정보 컨트롤러
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _contactPersonController = TextEditingController();
  final _emailController = TextEditingController();
  final _notesController = TextEditingController();
  
  // 비밀번호 컨트롤러
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  // 상태 변수
  bool _isActive = true;
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _changePassword = false;
  
  // 거래 조건
  String _paymentMethod = 'cash';
  double _creditLimit = 0.0;
  int _paymentTerms = 0;
  
  // 할인 정보
  double _discountRate = 0.0;
  bool _allowDiscount = false;

  @override
  void initState() {
    super.initState();
    _loadClientData();
    // 🔥 branchId 디버그 출력
    print('🔥 현재 branchId: ${widget.branchId}');
    
    if (_isNewClient()) {
      // 🔥 바로 GP001로 설정
      _codeController.text = 'GP001';
      _generateClientCode();
    }
  }

  // 🔥 간단하게 수정된 코드 생성 함수
  Future<void> _generateClientCode() async {
    // 🔥 간단하게 GP001로 고정
    setState(() {
      _codeController.text = 'GP001';
    });
    print('🔥 코드 설정 완료: GP001');
  }

  // 🔥 지사별 접두사 반환 함수
  String _getBranchPrefix(String branchId) {
    // 영어 branchId와 한글 branchId 모두 대응
    switch (branchId.toLowerCase()) {
      case 'gimpo':
      case '김포지사':
      case 'gimpo_branch':
        return 'GP';
      case 'chungcheong':
      case '충청지사':
      case 'chungcheong_branch':
        return 'CLIENT';
      case 'seoul':
      case '서울지사':
      case 'seoul_branch':
        return 'SEL';
      case 'busan':
      case '부산지사':
      case 'busan_branch':
        return 'BS';
      default:
        print('🚨 알 수 없는 branchId: $branchId, 기본값 CLI 사용');
        return 'CLI';
    }
  }

  void _loadClientData() {
    if (widget.initData != null) {
      final data = widget.initData!;
      _codeController.text = data['code'] ?? '';
      _nameController.text = data['name'] ?? '';
      _phoneController.text = data['phone'] ?? '';
      _addressController.text = data['address'] ?? '';
      _contactPersonController.text = data['contactPerson'] ?? '';
      _emailController.text = data['email'] ?? '';
      _notesController.text = data['notes'] ?? '';
      _isActive = data['isActive'] ?? true;
      _paymentMethod = data['paymentMethod'] ?? 'cash';
      _creditLimit = (data['creditLimit'] ?? 0.0).toDouble();
      _paymentTerms = data['paymentTerms'] ?? 0;
      _discountRate = (data['discountRate'] ?? 0.0).toDouble();
      _allowDiscount = data['allowDiscount'] ?? false;
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
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _saveClient() async {
    if (!_formKey.currentState!.validate()) return;

    // 비밀번호 확인
    if (_isNewClient() || _changePassword) {
      if (_passwordController.text.trim().isEmpty) {
        _showErrorDialog('비밀번호를 입력하세요');
        return;
      }
      if (_passwordController.text != _confirmPasswordController.text) {
        _showErrorDialog('비밀번호가 일치하지 않습니다');
        return;
      }
      if (_passwordController.text.length < 4) {
        _showErrorDialog('비밀번호는 최소 4자 이상이어야 합니다');
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      print('🔥 저장 시작 - branchId: ${widget.branchId}');
      
      final clientData = {
        'code': _codeController.text.trim().toUpperCase(),
        'name': _nameController.text.trim(),
        'nameLower': _nameController.text.trim().toLowerCase(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'contactPerson': _contactPersonController.text.trim(),
        'email': _emailController.text.trim(),
        'notes': _notesController.text.trim(),
        'isActive': _isActive,
        'paymentMethod': _paymentMethod,
        'creditLimit': _creditLimit,
        'paymentTerms': _paymentTerms,
        'discountRate': _discountRate,
        'allowDiscount': _allowDiscount,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // 비밀번호 처리
      if (_isNewClient() || _changePassword) {
        clientData['passwordHash'] = _hashPassword(_passwordController.text.trim());
      }

      final clientsRef = FirebaseFirestore.instance
          .collection('branches')
          .doc(widget.branchId)
          .collection('clients');

      if (_isNewClient()) {
        // 거래처 코드 중복 확인
        final existingClient = await clientsRef
            .where('code', isEqualTo: _codeController.text.trim().toUpperCase())
            .limit(1)
            .get();

        if (existingClient.docs.isNotEmpty) {
          _showErrorDialog('이미 존재하는 거래처 코드입니다');
          return;
        }

        clientData['createdAt'] = FieldValue.serverTimestamp();
        await clientsRef.doc(_codeController.text.trim().toUpperCase()).set(clientData);
        
        print('🔥 거래처 저장 완료: ${_codeController.text}');
        _showSuccessDialog('거래처가 성공적으로 등록되었습니다');
      } else {
        await clientsRef.doc(widget.code).update(clientData);
        _showSuccessDialog('거래처 정보가 성공적으로 수정되었습니다');
      }

    } catch (e) {
      print('🚨 저장 에러: $e');
      _showErrorDialog('저장 중 오류가 발생했습니다: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  bool _isNewClient() => widget.code == null;

  void _showErrorDialog(String message) {
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
        title: Text(_isNewClient() ? '거래처 등록' : '거래처 수정'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            )
          else
            IconButton(
              onPressed: _saveClient,
              icon: const Icon(Icons.save),
              tooltip: '저장',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔥 branchId 디버그 정보 표시
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue.shade600, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '현재 지사: ${widget.branchId} | 접두사: ${_getBranchPrefix(widget.branchId)}',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              _buildSectionTitle('기본 정보', Icons.business),
              _buildBasicInfoSection(),
              
              const SizedBox(height: 24),
              
              _buildSectionTitle('로그인 정보', Icons.lock),
              _buildPasswordSection(),
              
              const SizedBox(height: 24),
              
              _buildSectionTitle('거래 조건', Icons.payment),
              _buildTradingConditionsSection(),
              
              const SizedBox(height: 24),
              
              _buildSectionTitle('할인 정보', Icons.discount),
              _buildDiscountSection(),
              
              const SizedBox(height: 32),
              
              _buildSaveButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.orange, size: 24),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfoSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _codeController,
                    decoration: InputDecoration(
                      labelText: '거래처 코드 *',
                      hintText: 'CLIENT013, GP001',
                      prefixIcon: const Icon(Icons.qr_code),
                      border: const OutlineInputBorder(),
                      helperText: _isNewClient() ? '자동으로 생성됩니다' : null,
                      helperStyle: const TextStyle(color: Colors.green),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '거래처 코드를 입력하세요';
                      }
                      if (value.trim().length < 2) {
                        return '거래처 코드는 2자 이상이어야 합니다';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: '거래처명 *',
                      hintText: '서울마트',
                      prefixIcon: Icon(Icons.store),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '거래처명을 입력하세요';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: '전화번호',
                      hintText: '02-1234-5678',
                      prefixIcon: Icon(Icons.phone),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _contactPersonController,
                    decoration: const InputDecoration(
                      labelText: '담당자',
                      hintText: '홍길동',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: '이메일',
                hintText: 'example@company.com',
                prefixIcon: Icon(Icons.email),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: '주소',
                hintText: '서울시 강남구...',
                prefixIcon: Icon(Icons.location_on),
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: '메모',
                hintText: '특이사항이나 메모를 입력하세요',
                prefixIcon: Icon(Icons.note),
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            
            SwitchListTile(
              title: const Text('활성 상태'),
              subtitle: Text(_isActive ? '활성화됨' : '비활성화됨'),
              value: _isActive,
              onChanged: (value) {
                setState(() {
                  _isActive = value;
                });
              },
              activeColor: Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_isNewClient()) ...[
              SwitchListTile(
                title: const Text('비밀번호 변경'),
                subtitle: const Text('체크하면 비밀번호를 변경할 수 있습니다'),
                value: _changePassword,
                onChanged: (value) {
                  setState(() {
                    _changePassword = value;
                    if (!value) {
                      _passwordController.clear();
                      _confirmPasswordController.clear();
                    }
                  });
                },
                activeColor: Colors.orange,
              ),
              const SizedBox(height: 16),
            ],
            
            if (_isNewClient() || _changePassword) ...[
              TextFormField(
                controller: _passwordController,
                obscureText: !_isPasswordVisible,
                decoration: InputDecoration(
                  labelText: '비밀번호 *',
                  hintText: '최소 4자 이상',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                  ),
                  border: const OutlineInputBorder(),
                ),
                validator: (_isNewClient() || _changePassword) ? (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '비밀번호를 입력하세요';
                  }
                  if (value.length < 4) {
                    return '비밀번호는 최소 4자 이상이어야 합니다';
                  }
                  return null;
                } : null,
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: !_isConfirmPasswordVisible,
                decoration: InputDecoration(
                  labelText: '비밀번호 확인 *',
                  hintText: '비밀번호를 다시 입력하세요',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isConfirmPasswordVisible ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                      });
                    },
                  ),
                  border: const OutlineInputBorder(),
                ),
                validator: (_isNewClient() || _changePassword) ? (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '비밀번호 확인을 입력하세요';
                  }
                  if (value != _passwordController.text) {
                    return '비밀번호가 일치하지 않습니다';
                  }
                  return null;
                } : null,
              ),
              
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue.shade600, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '이 비밀번호는 고객이 주문 앱에서 로그인할 때 사용됩니다.',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock, color: Colors.grey.shade600),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '비밀번호가 설정되어 있습니다. 변경하려면 위의 스위치를 켜주세요.',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTradingConditionsSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: _paymentMethod,
              decoration: const InputDecoration(
                labelText: '결제 방법',
                prefixIcon: Icon(Icons.payment),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('현금')),
                DropdownMenuItem(value: 'credit', child: Text('외상')),
                DropdownMenuItem(value: 'card', child: Text('카드')),
                DropdownMenuItem(value: 'transfer', child: Text('계좌이체')),
              ],
              onChanged: (value) {
                setState(() {
                  _paymentMethod = value!;
                });
              },
            ),
            const SizedBox(height: 16),
            
            if (_paymentMethod == 'credit') ...[
              TextFormField(
                initialValue: _creditLimit.toString(),
                decoration: const InputDecoration(
                  labelText: '외상 한도 (원)',
                  prefixIcon: Icon(Icons.account_balance_wallet),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  _creditLimit = double.tryParse(value) ?? 0.0;
                },
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                initialValue: _paymentTerms.toString(),
                decoration: const InputDecoration(
                  labelText: '결제 조건 (일)',
                  prefixIcon: Icon(Icons.calendar_today),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  _paymentTerms = int.tryParse(value) ?? 0;
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiscountSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('할인 허용'),
              subtitle: const Text('이 거래처에 할인을 적용할 수 있습니다'),
              value: _allowDiscount,
              onChanged: (value) {
                setState(() {
                  _allowDiscount = value;
                  if (!value) {
                    _discountRate = 0.0;
                  }
                });
              },
              activeColor: Colors.orange,
            ),
            
            if (_allowDiscount) ...[
              const SizedBox(height: 16),
              TextFormField(
                initialValue: _discountRate.toString(),
                decoration: const InputDecoration(
                  labelText: '기본 할인율 (%)',
                  prefixIcon: Icon(Icons.percent),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  _discountRate = double.tryParse(value) ?? 0.0;
                },
                validator: _allowDiscount ? (value) {
                  final rate = double.tryParse(value ?? '');
                  if (rate != null && (rate < 0 || rate > 100)) {
                    return '할인율은 0~100% 사이여야 합니다';
                  }
                  return null;
                } : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _saveClient,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: _isLoading
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text('저장 중...'),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.save),
                  const SizedBox(width: 8),
                  Text(_isNewClient() ? '거래처 등록' : '수정 완료'),
                ],
              ),
      ),
    );
  }
}
