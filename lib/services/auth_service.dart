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
  String? _managerBranchId; // 매니저/관리자용 지점 ID 보관(문서 ID)

  // ===== getters =====
  bool get isLoading => _isLoading;
  bool get isSignedIn => _isSignedIn;
  Client? get currentClient => _currentClient;
  String? get role => _role;
  String? get uid => _auth.currentUser?.uid;

  // 편의 접근자 (역할에 따라 분기)
  String? get branchId {
    if (_role == 'client') return _currentClient?.branchId; // 문서ID
    return _managerBranchId;                                 // 문서ID
  }

  // 매니저 전용: 로그인했고 manager/admin이면 문서ID 반환
  String? get managerBranchIdOrNull =>
      (_role == 'manager' || _role == 'admin') ? _managerBranchId : null;

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
      // 매니저/관리자 프로필 로딩 (지점 문서ID 보관)
      _currentClient = null;
      _managerBranchId = (data['branchId'] ?? '') as String?;
    }

    notifyListeners();
  }

  // ------------------------------
  // 거래처 코드 로그인 (보안 우수: 쿼리 없이 단건 get만 사용)
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
      debugPrint('🔍 로그인 시도: branchKey=$branchKey, code=$code');

      // 1) 익명 로그인 보장 (Auth 콘솔에서 Anonymous provider 활성화 필요)
      User? user = _auth.currentUser;
      if (user == null) {
        user = (await _auth.signInAnonymously()).user;
        if (user == null) throw Exception('익명 로그인 실패');
      }

      // 2) branchKey → branchId 해석 (문서 ID 또는 매핑 컬렉션)
      final branchId = await _resolveBranchId(branchKey);
      if (branchId == null) {
        hasError = true;
        errorMessage = '존재하지 않는 지점 코드입니다: $branchKey';
        _isSignedIn = false;
        notifyListeners();
        return false;
      }

      // 3) 지점 문서 단건 get (정보 표시용)
      final branchDoc = await _db.collection('branches').doc(branchId).get();
      final branchData = branchDoc.data() as Map<String, dynamic>? ?? {};

      // 4) 거래처 문서 단건 get
      final clientDoc = await _db
          .collection('branches').doc(branchId)
          .collection('clients').doc(code)
          .get();

      if (!clientDoc.exists) {
        hasError = true;
        errorMessage = '존재하지 않는 거래처 코드입니다: $code\n지점: ${branchData['name'] ?? branchId}';
        _isSignedIn = false;
        notifyListeners();
        return false;
      }

      // 5) 데이터 파싱
      final clientData = clientDoc.data() as Map<String, dynamic>;
      final name = (clientData['name'] ?? '') as String;
      final priceTier = ((clientData['priceTier'] ?? 'C') as String).toUpperCase();
      final parsedDays = ((clientData['deliveryDays'] as List?)?.whereType<int>() ?? const <int>[])
          .where((e) => e >= 1 && e <= 7)
          .toList();

      // 6) /user/{uid} upsert (트랜잭션으로 일관성)
      final userRef = _db.collection('user').doc(user.uid);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(userRef);
        final now = FieldValue.serverTimestamp();
        final payload = <String, dynamic>{
          'role': 'client',
          'branchId': branchId, // 문서 ID
          'clientCode': code,
          'priceTier': priceTier,
          'name': name,
          'updatedAt': now,
        };
        if (!snap.exists) {
          tx.set(userRef, {
            ...payload,
            'createdAt': now,
          });
        } else {
          tx.update(userRef, payload);
        }
      });

      // 7) 메모리 상태 갱신
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
          ? '접근 권한이 없습니다. (Firestore 보안규칙을 확인하세요)'
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

  // ------------------------------
  // (매니저) 거래처 등록: 지점키 기반 자동코드 발급 + 생성 (트랜잭션)
  // ------------------------------
  Future<String> createClientAuto({
    required String branchKey, // 드롭다운 값 'GP' | 'CC'
    required String name,
    String priceTier = 'C',
    Map<String, num>? priceOverrides,
    List<int>? deliveryDays, // 1~7 (월~일)
  }) async {
    // 매니저/관리자 권한 체크(선택)
    if (!(_role == 'manager' || _role == 'admin')) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied', message: '매니저 권한이 필요합니다.');
    }

    final branchId = await _resolveBranchId(branchKey);
    if (branchId == null) {
      throw Exception('지점 매핑 없음: $branchKey (branch_keys 컬렉션 확인)');
    }

    final db = _db;
    final countersRef = db.collection('branches').doc(branchId)
                          .collection('meta').doc('counters');

    return await db.runTransaction<String>((tx) async {
      final now = FieldValue.serverTimestamp();

      // 1) 시퀀스 읽기
      final cSnap = await tx.get(countersRef);
      var nextSeq = (cSnap.data()?['clientSeq'] as int?) ?? 1;

      // 2) 코드 생성 (예: GP001)
      late DocumentReference<Map<String, dynamic>> clientRef;
      late String code;
      while (true) {
        code = '$branchKey${nextSeq.toString().padLeft(3, '0')}';
        clientRef = db.collection('branches').doc(branchId)
                      .collection('clients').doc(code);
        final exist = await tx.get(clientRef);
        if (!exist.exists) break;
        nextSeq++;
      }

      // 3) 생성
      tx.set(clientRef, {
        'code': code,
        'name': name,
        'priceTier': priceTier.toUpperCase(),
        'priceOverrides': priceOverrides ?? <String, num>{},
        if (deliveryDays != null)
          'deliveryDays': deliveryDays.where((e) => e >= 1 && e <= 7).toList(),
        'createdAt': now,
        'updatedAt': now,
      });

      // 4) 시퀀스 증가
      tx.set(countersRef, {'clientSeq': nextSeq + 1}, SetOptions(merge: true));

      debugPrint('✅ CREATED path: branches/$branchId/clients/$code');
      return code;
    });
  }

  /// branchKey를 실제 branches 문서 ID로 해석한다.
  /// 우선 branches/{branchKey} 존재 여부를 보고, 없으면 branch_keys/{branchKey} 매핑을 본다.
  Future<String?> _resolveBranchId(String branchKey) async {
    final direct = await _db.collection('branches').doc(branchKey).get();
    if (direct.exists) return branchKey;

    final mapDoc = await _db.collection('branch_keys').doc(branchKey).get();
    if (mapDoc.exists) {
      final id = (mapDoc.data()?['branchId'] as String?)?.trim();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
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
    } on FirebaseException catch (e) {
      hasError = true;
      errorMessage = e.message ?? e.code;
      rethrow;
    } catch (e) {
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
