// lib/services/auth_service.dart
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
  String? _managerBranchId; // ✅ 매니저/관리자용 지점 ID 보관

  // getters
  bool get isLoading => _isLoading;
  bool get isSignedIn => _isSignedIn;
  Client? get currentClient => _currentClient;
  String? get role => _role;
  String? get uid => _auth.currentUser?.uid;

  // 편의 접근자 (역할에 따라 분기)
  String? get branchId {
    if (_role == 'client') return _currentClient?.branchId;
    return _managerBranchId; // ✅ 매니저/관리자일 때 사용
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
    final snap = await _db.collection('user').doc(uid).get(); // 규칙에 맞춰 'user'(단수)
    final data = snap.data() ?? {};

    _role = data['role'] as String?;

    if (_role == 'client') {
      // ✅ 클라이언트 프로필 로딩
      _managerBranchId = null; // 혹시 이전 상태가 남아있지 않도록 초기화

      final branchId = (data['branchId'] ?? '') as String;
      final code     = (data['clientCode'] ?? '') as String;

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
      // ✅ 매니저/관리자 프로필 로딩
      _currentClient = null;
      _managerBranchId = (data['branchId'] ?? '') as String?;
      // (관리자는 브랜치가 없을 수도 있음. 매니저 화면에서 branchId가 필수라면 user 문서에 채워주세요)
    }

    notifyListeners();
  }

  // ------------------------------
  // 거래처 코드 로그인
  // 1) 익명 로그인 보장
  // 2) collectionGroup('clients')에서 clientCode로 문서 찾기
  // 3) 찾은 문서의 상위 브랜치ID와 정보로 /user/{uid} '최초 1회' 생성
  // ------------------------------
  Future<bool> login(String codeRaw) async {
    final code = codeRaw.trim().toUpperCase();
    if (code.isEmpty) return false;

    _setLoading(true);
    await Future.delayed(const Duration(milliseconds: 200));

    try {
      // 1) 익명 로그인 보장 (Firebase 콘솔 → Authentication → Anonymous 활성화)
      User? u = _auth.currentUser;
      u ??= (await _auth.signInAnonymously()).user;
      if (u == null) throw Exception('익명 로그인 실패');

      // 2) clients 컬렉션그룹에서 코드 검색 (규칙에서 clients read 허용 필요)
      final qs = await _db
          .collectionGroup('clients')
          .where('clientCode', isEqualTo: code)
          .limit(1)
          .get();

      if (qs.docs.isEmpty) {
        hasError = true;
        errorMessage = '해당 코드의 거래처를 찾을 수 없습니다.';
        _isSignedIn = false;
        notifyListeners();
        return false;
      }

      final clientDoc = qs.docs.first;
      final data = clientDoc.data();
      final branchId  = clientDoc.reference.parent.parent!.id; // 상위 브랜치 문서 ID
      final name      = (data['name'] ?? '') as String;
      final priceTier = ((data['priceTier'] ?? 'C') as String).toUpperCase();

      // 안전한 deliveryDays 파싱
      final parsedDays = ((data['deliveryDays'] as List?)?.whereType<int>() ?? const <int>[])
          .where((e) => e >= 1 && e <= 7)
          .toList();

      // 3) /user/{uid} 문서 "최초 1회 생성" (규칙: create만 허용, update는 admin 전용)
      final userRef = _db.collection('user').doc(u.uid);
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
      // 이미 존재하면 규칙상 업데이트가 막혀 있으므로 건드리지 않음

      // 메모리 상태 갱신
      _currentClient = Client(
        code: code,
        name: name,
        branchId: branchId,
        priceTier: priceTier,
        deliveryDays: parsedDays,
      );
      _managerBranchId = null; // ✅ 클라이언트 로그인 시 매니저 필드는 비움
      _role = 'client';
      _isSignedIn = true;
      hasError = false;
      errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      hasError = true;
      errorMessage = e.toString();
      _isSignedIn = false;
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
      _managerBranchId = null; // ✅ 정리
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
