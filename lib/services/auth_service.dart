import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/client.dart';

class AuthService with ChangeNotifier {
  // Firebase
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 상태
  bool _isLoading = false;
  bool _isSignedIn = false;

  // 에러 상태
  bool hasError = false;
  String? errorMessage;

  // 프로필
  Client? _currentClient;   // client 전용 프로필 (branchId, priceTier, deliveryDays 등)
  String? _role;            // 'manager' | 'client' | 'admin'
  String? _managerBranchId; // 매니저/관리자용 지점 ID 보관

  // getters
  bool get isLoading => _isLoading;
  bool get isSignedIn => _isSignedIn;
  Client? get currentClient => _currentClient;
  String? get role => _role;
  String? get uid => _auth.currentUser?.uid;

  // 편의 접근자 (역할에 따라 분기)
  String? get branchId {
    if (_role == 'client') return _currentClient?.branchId;
    return _managerBranchId; // 매니저/관리자일 때 사용
  }

  String? get clientCode => _currentClient?.code;
  String get priceTier => _currentClient?.priceTier ?? 'C';
  List<int> get deliveryDays => _currentClient?.deliveryDays ?? const [];

  // ------------------------------
  // 앱 시작 시 현재 유저 자동 로드(선택)
  // ------------------------------
  Future<void> init() async {
    final user = _auth.currentUser;
    if (user == null) {
      _isSignedIn = false;
      notifyListeners();
      return;
    }
    await _safe(() async {
      await _loadUserProfile(user.uid);
      _isSignedIn = true;
    });
  }

  // ------------------------------
  // 이메일/비밀번호 로그인 (관리자/매니저용)
  // ------------------------------
  Future<void> signInWithEmail(String email, String password) async {
    await _safe(() async {
      final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
      await _loadUserProfile(cred.user!.uid); // Firestore /user/{uid} 로드
      _isSignedIn = true;
    });
  }

  // /user/{uid} 로드
  Future<void> _loadUserProfile(String uid) async {
    final snap = await _db.collection('user').doc(uid).get();
    final data = snap.data() ?? {};

    _role = data['role'] as String?;

    if (_role == 'client') {
      // 클라이언트 프로필 로딩
      _managerBranchId = null;

      final branchId = (data['branchId'] ?? '') as String;
      final code = (data['clientCode'] ?? '') as String;

      // deliveryDays는 user 문서에 없으므로 실제 clients 문서에서 보강해서 로드
      Map<String, dynamic> clientDocData = {};
      if (branchId.isNotEmpty && code.isNotEmpty) {
        final cs = await _db
            .collection('branches').doc(branchId)
            .collection('clients').doc(code)
            .get();
        clientDocData = cs.data() ?? {};
      }

      final loadedTier = ((data['priceTier'] ?? clientDocData['priceTier'] ?? 'C') as String).toUpperCase();

      // 안전한 deliveryDays 파싱
      final safeDays = ((clientDocData['deliveryDays'] as List?)?.whereType<int>() ?? const <int>[])
          .where((e) => e >= 1 && e <= 7)
          .toList();

      _currentClient = Client(
        code: code,
        name: (data['name'] ?? clientDocData['name'] ?? '') as String,
        branchId: branchId,
        priceTier: loadedTier,
        deliveryDays: safeDays,
      );
    } else {
      // 매니저/관리자 프로필 로딩
      _currentClient = null;
      _managerBranchId = (data['branchId'] ?? '') as String?;
    }

    notifyListeners();
  }

  // ------------------------------
  // 거래처 코드 로그인 (🔥 완전히 새로운 로직)
  // ------------------------------
  Future<bool> login(String codeRaw, String branchKeyRaw) async {
    final code = codeRaw.trim().toUpperCase();
    final branchKey = branchKeyRaw.trim().toUpperCase();

    if (code.isEmpty || branchKey.isEmpty) {
      hasError = true;
      errorMessage = '거래처 코드와 지점 코드를 모두 입력해주세요.';
      notifyListeners();
      return false;
    }

    _setLoading(true);
    hasError = false;
    errorMessage = null;
    
    try {
      print('🔍 로그인 시도: branchKey=$branchKey, code=$code');

      // 1. 익명 로그인 보장
      User? user = _auth.currentUser;
      if (user == null) {
        user = (await _auth.signInAnonymously()).user;
        if (user == null) throw Exception('익명 로그인 실패');
      }

      // 2. branchKey로 지점 문서 찾기
      final branchQuery = await _db
          .collection('branches')
          .where('branchKey', isEqualTo: branchKey)
          .limit(1)
          .get();

      if (branchQuery.docs.isEmpty) {
        hasError = true;
        errorMessage = '존재하지 않는 지점 코드입니다: $branchKey\n(사용 가능: GP, CC)';
        _isSignedIn = false;
        notifyListeners();
        return false;
      }

      final branchDoc = branchQuery.docs.first;
      final branchId = branchDoc.id;
      final branchData = branchDoc.data() as Map<String, dynamic>;
      
      print('✅ 지점 찾음: $branchId');
      print('📋 지점 데이터: $branchData');

      // 3. 해당 지점의 clients 하위 컬렉션에서 거래처 코드 검색
      final clientDoc = await _db
          .collection('branches')
          .doc(branchId)
          .collection('clients')
          .doc(code)
          .get();

      if (!clientDoc.exists) {
        hasError = true;
        errorMessage = '존재하지 않는 거래처 코드입니다: $code\n지점: ${branchData['name']}';
        _isSignedIn = false;
        notifyListeners();
        return false;
      }

      // 4. 클라이언트 데이터 파싱
      final clientData = clientDoc.data() as Map<String, dynamic>;
      final name = (clientData['name'] ?? '') as String;
      final priceTier = ((clientData['priceTier'] ?? 'C') as String).toUpperCase();

      // 안전한 deliveryDays 파싱
      final parsedDays = ((clientData['deliveryDays'] as List?)?.whereType<int>() ?? const <int>[])
          .where((e) => e >= 1 && e <= 7)
          .toList();

      // 5. /user/{uid} 문서 "최초 1회 생성"
      final userRef = _db.collection('user').doc(user.uid);
      final userSnap = await userRef.get();
      if (!userSnap.exists) {
        await userRef.set({
          'role': 'client',
          'branchId': branchId,
          'clientCode': code,
          'priceTier': priceTier,
          'name': name,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // 6. 메모리 상태 갱신
      _currentClient = Client(
        code: code,
        name: name,
        branchId: branchId,
        priceTier: priceTier,
        deliveryDays: parsedDays,
      );
      _managerBranchId = null;
      _role = 'client';
      _isSignedIn = true;
      hasError = false;
      errorMessage = null;
      
      print('🎉 로그인 성공!');
      print('👤 사용자 정보: ${_currentClient?.toString()}');
      
      notifyListeners();
      return true;

    } catch (e) {
      hasError = true;
      errorMessage = '로그인 중 오류가 발생했습니다: $e';
      _isSignedIn = false;
      
      print('❌ 로그인 오류: $e');
      
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ------------------------------
  // 로그아웃
  // ------------------------------
  Future<void> signOut() async {
    _setLoading(true);
    try {
      await _auth.signOut();
    } finally {
      _currentClient = null;
      _managerBranchId = null;
      _role = null;
      _isSignedIn = false;
      hasError = false;
      errorMessage = null;
      _setLoading(false);
    }
  }

  // ------------------------------
  // util
  // ------------------------------
  Future<void> _safe(Future<void> Function() run) async {
    _setLoading(true);
    try {
      await run();
      hasError = false;
      errorMessage = null;
    } catch (e) {
      hasError = true;
      errorMessage = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }
}
