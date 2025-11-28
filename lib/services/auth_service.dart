// lib/services/auth_service.dart
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/client.dart';

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _isLoading = false;
  bool _isSignedIn = false;
  bool hasError = false;
  String? errorMessage;

  Client? _currentClient;
  String? _role;
  String? _managerBranchId;

  bool get isLoading => _isLoading;
  bool get isSignedIn => _isSignedIn;
  Client? get currentClient => _currentClient;
  String? get role => _role;
  String? get uid => _auth.currentUser?.uid;

  String? get branchId {
    if (_role == 'client') return _currentClient?.branchId;
    return _managerBranchId;
  }

  String? get managerBranchIdOrNull =>
      (_role == 'manager' || _role == 'admin') ? _managerBranchId : null;

  String? get clientCode => _currentClient?.code;
  String get priceTier => _currentClient?.priceTier ?? 'C';
  List<int> get deliveryDays => _currentClient?.deliveryDays ?? const [];

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

  Future<void> signInWithEmail(String email, String password) async {
    await _safe(() async {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _loadUserProfile(cred.user!.uid);
      _isSignedIn = true;
    });
  }

  Future<void> _loadUserProfile(String uid) async {
    final snap = await _db.collection('user').doc(uid).get();
    final data = snap.data() ?? {};
    _role = data['role'] as String?;
    if (_role == 'client') {
      _managerBranchId = null;
      final branchId = (data['branchId'] as String?) ?? '';
      final code = (data['clientCode'] as String?) ?? '';
      Map<String, dynamic> clientDocData = {};
      if (branchId.isNotEmpty && code.isNotEmpty) {
        final cs = await _db
            .collection('branches')
            .doc(branchId)
            .collection('clients')
            .doc(code)
            .get();
        clientDocData = cs.data() ?? {};
      }
      final loadedTier = ((data['priceTier'] as String?) ??
              (clientDocData['priceTier'] as String?) ??
              'C')
          .toUpperCase();
      final safeDays =
          ((clientDocData['deliveryDays'] as List?)?.whereType<int>() ??
                  const <int>[])
              .where((e) => e >= 1 && e <= 7)
              .toList();
      _currentClient = Client(
        code: code,
        name: (data['name'] as String?) ??
            (clientDocData['name'] as String?) ??
            '',
        branchId: branchId,
        priceTier: loadedTier,
        deliveryDays: safeDays,
      );
    } else {
      _currentClient = null;
      _managerBranchId = (data['branchId'] ?? '') as String?;
    }
    notifyListeners();
  }

  Future<bool> login(String clientCode, String password) async {
    final code = clientCode.trim().toUpperCase();
    if (code.isEmpty || password.isEmpty) {
      hasError = true;
      errorMessage = '거래처 코드와 비밀번호를 입력해주세요.';
      notifyListeners();
      return false;
    }
    _setLoading(true);
    hasError = false;
    errorMessage = null;

    try {
      debugPrint('🔍 로그인 시도: clientCode=$clientCode');
      final clientQuery = _db
          .collectionGroup('clients')
          .where('clientCode', isEqualTo: code)
          .limit(1);
      final clientSnap = await clientQuery.get();

      if (clientSnap.docs.isEmpty) {
        hasError = true;
        errorMessage = '존재하지 않는 거래처 코드입니다.';
        _isSignedIn = false;
        notifyListeners();
        return false;
      }

      final clientDoc = clientSnap.docs.first;
      final clientData = clientDoc.data();
      final storedPassword = clientData['password'] as String?;
      if (storedPassword != password) {
        hasError = true;
        errorMessage = '비밀번호가 올바르지 않습니다.';
        _isSignedIn = false;
        notifyListeners();
        return false;
      }

      final branchId = (clientData['branchId'] as String?) ?? '';
      final name = (clientData['name'] as String?) ?? '';
      final priceTier =
          ((clientData['priceTier'] as String?) ?? 'C').toUpperCase();
      final parsedDays =
          ((clientData['deliveryDays'] as List?)?.whereType<int>() ??
                  const <int>[])
              .where((e) => e >= 1 && e <= 7)
              .toList();

      User? user = _auth.currentUser;
      if (user == null) {
        user = (await _auth.signInAnonymously()).user;
        if (user == null) throw Exception('익명 로그인 실패');
      }

      final userRef = _db.collection('user').doc(user.uid);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(userRef);
        final now = FieldValue.serverTimestamp();
        final payload = <String, dynamic>{
          'role': 'client',
          'branchId': branchId,
          'clientCode': code,
          'priceTier': priceTier,
          'name': name,
          'updatedAt': now,
        };
        if (!snap.exists) {
          tx.set(userRef, {...payload, 'createdAt': now});
        } else {
          tx.update(userRef, payload);
        }
      });

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

      debugPrint('🎉 로그인 성공! 👤 $_currentClient');
      notifyListeners();
      return true;
    } on FirebaseException catch (e) {
      hasError = true;
      errorMessage = (e.code == 'permission-denied')
          ? '접근 권한이 없습니다. (Firestore 보안규칙 또는 인덱스 문제)'
          : (e.message ?? 'Firebase 오류가 발생했습니다');
      _isSignedIn = false;
      debugPrint('❌ Firebase 로그인 오류: ${e.code} ${e.message}');
      notifyListeners();
      return false;
    } catch (e) {
      hasError = true;
      errorMessage = '로그인 중 오류가 발생했습니다: $e';
      _isSignedIn = false;
      debugPrint('❌ 로그인 오류: $e');
      notifyListeners();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // --- 자동 거래처 코드 생성 + 거래처 등록 ---
  Future<String> createClientAuto({
    required String branchId,
    required String name,
    required String password,
    required bool isPaymentRequired,
    String priceTier = 'C',
    Map<String, num>? priceOverrides,
    List<int>? deliveryDays,
  }) async {
    if (!(_role == 'manager' || _role == 'admin')) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: '매니저 권한이 필요합니다.',
      );
    }

    final db = _db;
    final countersRef = db
        .collection('branches')
        .doc(branchId)
        .collection('meta')
        .doc('counters');

    return await db.runTransaction<String>((tx) async {
      debugPrint('💡 [createClientAuto] 트랜잭션 시작');
      final now = FieldValue.serverTimestamp();

      // 1) 마지막 번호 읽기 (없으면 0)
      final cSnap = await tx.get(countersRef);
      int lastSeq = (cSnap.data()?['clientSeq'] as int?) ?? 0;
      int nextSeq = lastSeq + 1;

      // 2) 혹시 같은 코드가 이미 있으면 한 칸씩 더 올리기 (이중 안전장치)
      late String code;
      while (true) {
        code = 'CLIENT${nextSeq.toString().padLeft(3, '0')}';
        final existingClientRef = db
            .collection('branches')
            .doc(branchId)
            .collection('clients')
            .doc(code);
        final exist = await tx.get(existingClientRef);
        if (!exist.exists) break;
        nextSeq++;
      }
      debugPrint('💡 새 거래처 코드 확정: $code (seq=$nextSeq)');

      // 3) 인증 정보 저장
      final authDocRef = db.collection('client_auth').doc(code);
      tx.set(authDocRef, {
        'branchId': branchId,
        'password': password,
        'createdAt': now,
      });

      // 4) 거래처 문서 저장
      final clientRef = db
          .collection('branches')
          .doc(branchId)
          .collection('clients')
          .doc(code);

      tx.set(clientRef, {
        'branchId': branchId,
        'clientCode': code,
        'isPaymentRequired': isPaymentRequired,
        'name': name,
        'priceTier': priceTier.toUpperCase(),
        'priceOverrides': priceOverrides ?? <String, num>{},
        'password': password, // ✅ 로그인 비교용 비밀번호 저장
        if (deliveryDays != null)
          'deliveryDays':
              deliveryDays.where((e) => e >= 1 && e <= 7).toList(),
        'createdAt': now,
        'updatedAt': now,
      });

      // 5) 카운터에 "마지막 번호" 저장
      tx.set(
        countersRef,
        {'clientSeq': nextSeq},
        SetOptions(merge: true),
      );

      debugPrint(
          '✅ CREATED path: branches/$branchId/clients/$code (clientSeq=$nextSeq)');
      return code;
    });
  }

  // --- 화면에서 보여줄 "다음 거래처 코드" 미리보기 ---
  Future<String> previewNextClientCodeByPolicy(String branchId) async {
    final countersRef = _db
        .collection('branches')
        .doc(branchId)
        .collection('meta')
        .doc('counters');

    final snap = await countersRef.get();
    int lastSeq = (snap.data()?['clientSeq'] as int?) ?? 0;
    final nextSeq = lastSeq + 1;

    final code = 'CLIENT${nextSeq.toString().padLeft(3, '0')}';
    return code;
  }

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

  Future<void> _safe(Future<void> Function() run) async {
    _setLoading(true);
    try {
      await run();
      hasError = false;
      errorMessage = null;
    } on FirebaseException catch (e) {
      debugPrint(
          '❌ auth_service에서 Firebase 에러 발생! -> ${e.code}: ${e.message}');
      hasError = true;
      errorMessage = e.message ?? e.code;
      rethrow;
    } catch (e) {
      debugPrint('❌ auth_service에서 일반 에러 발생! -> $e');
      hasError = true;
      errorMessage = e.toString();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }
}
