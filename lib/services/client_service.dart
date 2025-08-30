import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// 지점 정책 클래스
class BranchPolicy {
  final String scheme;
  final String codePrefix;
  final int clientSeq;
  
  BranchPolicy({
    required this.scheme, 
    required this.codePrefix, 
    required this.clientSeq
  });
  
  @override
  String toString() {
    return 'BranchPolicy(scheme: $scheme, codePrefix: $codePrefix, clientSeq: $clientSeq)';
  }
}

/// 클라이언트 작업 결과 클래스
class ClientResult {
  final bool success;
  final String? clientCode;
  final String? error;
  final Map<String, dynamic>? data;
  
  ClientResult.success(this.clientCode, {this.data}) 
      : success = true, error = null;
      
  ClientResult.error(this.error) 
      : success = false, clientCode = null, data = null;
      
  @override
  String toString() {
    return 'ClientResult(success: $success, clientCode: $clientCode, error: $error)';
  }
}

/// 숫자를 지정된 자리수로 패딩하는 헬퍼 함수
String _pad(int n, {int w = 3}) => n.toString().padLeft(w, '0');

/// 거래처 관리 서비스 클래스
class ClientService {
  final FirebaseFirestore db;
  
  ClientService(this.db);

  /// 지점 정책 가져오기 (안전한 버전)
  Future<ClientResult> fetchBranchPolicySafe(String branchId) async {
    try {
      if (kDebugMode) {
        print('🔍 fetchBranchPolicy 시작 - branchId: $branchId');
      }
      
      // 입력 검증
      if (branchId.isEmpty) {
        return ClientResult.error('지점 ID가 비어있습니다');
      }
      
      // 지점 문서 조회
      final doc = await db.collection('branches').doc(branchId).get();
      
      if (!doc.exists) {
        return ClientResult.error('지점을 찾을 수 없습니다: $branchId');
      }
      
      final data = doc.data();
      if (data == null) {
        return ClientResult.error('지점 데이터가 없습니다');
      }
      
      if (kDebugMode) {
        print('📄 지점 데이터: $data');
      }
      
      // nextClientSeq 안전하게 파싱
      final nextSeqValue = data['nextClientSeq'];
      int clientSeq = 1;
      
      if (nextSeqValue != null) {
        if (nextSeqValue is int) {
          clientSeq = nextSeqValue;
        } else if (nextSeqValue is String) {
          clientSeq = int.tryParse(nextSeqValue) ?? 1;
        } else if (nextSeqValue is double) {
          clientSeq = nextSeqValue.toInt();
        }
      }
      
      final policy = BranchPolicy(
        scheme: (data['codeScheme'] ?? 'legacy').toString(),
        codePrefix: (data['codePrefix'] ?? '').toString(),
        clientSeq: clientSeq,
      );
      
      if (kDebugMode) {
        print('✅ 정책 생성됨: $policy');
      }
      
      return ClientResult.success(null, data: {
        'policy': policy,
        'branchData': data,
      });
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ fetchBranchPolicy 에러: $e');
      }
      return ClientResult.error('지점 정책 조회 실패: ${e.toString()}');
    }
  }

  /// 거래처 생성 (완전 안전한 버전)
  Future<ClientResult> createClientSafe({
    required String branchId,
    required Map<String, dynamic> data,
    required String rawPassword,
  }) async {
    if (kDebugMode) {
      print('🚀 createClientSafe 시작 - branchId: $branchId');
    }
    
    // 입력 검증
    if (branchId.trim().isEmpty) {
      return ClientResult.error('지점 ID가 필요합니다');
    }
    
    if (rawPassword.trim().isEmpty) {
      return ClientResult.error('비밀번호가 필요합니다');
    }
    
    if (data.isEmpty) {
      return ClientResult.error('거래처 데이터가 필요합니다');
    }
    
    // 필수 필드 검증
    if (data['name'] == null || data['name'].toString().trim().isEmpty) {
      return ClientResult.error('거래처명이 필요합니다');
    }
    
    try {
      // Step 1: 지점 정보 조회
      if (kDebugMode) {
        print('📋 Step 1: 지점 정보 조회');
      }
      
      final branchResult = await _getBranchData(branchId);
      if (!branchResult.success) {
        return branchResult;
      }
      
      final branchData = branchResult.data!['branchData'] as Map<String, dynamic>;
      final scheme = branchData['codeScheme']?.toString() ?? 'legacy';
      
      if (kDebugMode) {
        print('🔧 코드 스키마: $scheme');
      }

      // Step 2: 거래처 코드 생성
      if (kDebugMode) {
        print('📋 Step 2: 거래처 코드 생성');
      }
      
      final codeResult = await _generateClientCode(branchId, branchData, scheme);
      if (!codeResult.success) {
        return codeResult;
      }
      
      final newClientCode = codeResult.clientCode!;
      
      if (kDebugMode) {
        print('✅ 생성된 코드: $newClientCode');
      }

      // Step 3: 중복 체크
      if (kDebugMode) {
        print('📋 Step 3: 중복 체크');
      }
      
      final duplicateResult = await _checkDuplicate(branchId, newClientCode);
      if (!duplicateResult.success) {
        return duplicateResult;
      }

      // Step 4: 거래처 데이터 저장
      if (kDebugMode) {
        print('📋 Step 4: 거래처 데이터 저장');
      }
      
      final saveResult = await _saveClientData(branchId, newClientCode, data);
      if (!saveResult.success) {
        return saveResult;
      }

      // Step 5: 인증 정보 저장
      if (kDebugMode) {
        print('📋 Step 5: 인증 정보 저장');
      }
      
      final authResult = await _saveAuthData(newClientCode, rawPassword);
      if (!authResult.success) {
        return authResult;
      }

      // Step 6: 시퀀스 업데이트 (prefix-seq인 경우만)
      if (scheme == 'prefix-seq') {
        if (kDebugMode) {
          print('📋 Step 6: nextClientSeq 업데이트');
        }
        
        final updateResult = await _updateSequence(branchId, branchData);
        if (!updateResult.success) {
          // 시퀀스 업데이트 실패는 경고만 출력하고 계속 진행
          if (kDebugMode) {
            print('⚠️ 시퀀스 업데이트 실패: ${updateResult.error}');
          }
        }
      }

      if (kDebugMode) {
        print('🎉 거래처 생성 완료: $newClientCode');
      }
      
      return ClientResult.success(newClientCode, data: {
        'clientCode': newClientCode,
        'branchId': branchId,
        'scheme': scheme,
        'clientData': {
          ...data,
          'clientCode': newClientCode,
          'branchId': branchId,
        }
      });
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ createClientSafe 예상치 못한 에러: $e');
      }
      return ClientResult.error('거래처 생성 중 오류 발생: ${e.toString()}');
    }
  }

  /// 거래처 목록 조회 (안전한 버전)
  Future<ClientResult> getClientListSafe(String branchId, {
    int limit = 50,
    String? lastClientCode,
    String? searchName,
  }) async {
    try {
      if (branchId.trim().isEmpty) {
        return ClientResult.error('지점 ID가 필요합니다');
      }
      
      Query query = db
          .collection('branches')
          .doc(branchId)
          .collection('clients')
          .where('active', isEqualTo: true)
          .orderBy('clientCode');
      
      // 검색 조건 추가
      if (searchName != null && searchName.trim().isNotEmpty) {
        query = query
            .where('name', isGreaterThanOrEqualTo: searchName)
            .where('name', isLessThan: searchName + '\uf8ff');
      }
      
      // 페이지네이션
      if (lastClientCode != null && lastClientCode.isNotEmpty) {
        query = query.startAfter([lastClientCode]);
      }
      
      query = query.limit(limit);
      
      final snapshot = await query.get();
      
      final clients = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();
      
      return ClientResult.success(null, data: {
        'clients': clients,
        'hasMore': snapshot.docs.length == limit,
        'lastClientCode': clients.isNotEmpty ? clients.last['clientCode'] : null,
      });
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ getClientList 에러: $e');
      }
      return ClientResult.error('거래처 목록 조회 실패: ${e.toString()}');
    }
  }

  /// 거래처 정보 조회 (안전한 버전)
  Future<ClientResult> getClientSafe(String branchId, String clientCode) async {
    try {
      if (branchId.trim().isEmpty) {
        return ClientResult.error('지점 ID가 필요합니다');
      }
      
      if (clientCode.trim().isEmpty) {
        return ClientResult.error('거래처 코드가 필요합니다');
      }
      
      final doc = await db
          .collection('branches')
          .doc(branchId)
          .collection('clients')
          .doc(clientCode)
          .get();
      
      if (!doc.exists) {
        return ClientResult.error('거래처를 찾을 수 없습니다: $clientCode');
      }
      
      final data = doc.data();
      if (data == null) {
        return ClientResult.error('거래처 데이터가 없습니다');
      }
      
      return ClientResult.success(clientCode, data: {
        'client': {
          'id': doc.id,
          ...data,
        }
      });
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ getClient 에러: $e');
      }
      return ClientResult.error('거래처 조회 실패: ${e.toString()}');
    }
  }

  /// 거래처 정보 업데이트 (안전한 버전)
  Future<ClientResult> updateClientSafe(
    String branchId, 
    String clientCode, 
    Map<String, dynamic> updateData
  ) async {
    try {
      if (branchId.trim().isEmpty) {
        return ClientResult.error('지점 ID가 필요합니다');
      }
      
      if (clientCode.trim().isEmpty) {
        return ClientResult.error('거래처 코드가 필요합니다');
      }
      
      if (updateData.isEmpty) {
        return ClientResult.error('업데이트할 데이터가 필요합니다');
      }
      
      // 시스템 필드 보호
      final protectedFields = ['clientCode', 'branchId', 'createdAt'];
      for (final field in protectedFields) {
        updateData.remove(field);
      }
      
      // 업데이트 시간 추가
      updateData['updatedAt'] = FieldValue.serverTimestamp();
      
      await db
          .collection('branches')
          .doc(branchId)
          .collection('clients')
          .doc(clientCode)
          .update(updateData);
      
      return ClientResult.success(clientCode, data: {
        'updatedFields': updateData.keys.toList(),
      });
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ updateClient 에러: $e');
      }
      return ClientResult.error('거래처 업데이트 실패: ${e.toString()}');
    }
  }

  /// 거래처 비활성화 (안전한 버전)
  Future<ClientResult> deactivateClientSafe(String branchId, String clientCode) async {
    try {
      if (branchId.trim().isEmpty) {
        return ClientResult.error('지점 ID가 필요합니다');
      }
      
      if (clientCode.trim().isEmpty) {
        return ClientResult.error('거래처 코드가 필요합니다');
      }
      
      await db
          .collection('branches')
          .doc(branchId)
          .collection('clients')
          .doc(clientCode)
          .update({
        'active': false,
        'deactivatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      return ClientResult.success(clientCode, data: {
        'action': 'deactivated',
      });
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ deactivateClient 에러: $e');
      }
      return ClientResult.error('거래처 비활성화 실패: ${e.toString()}');
    }
  }

  // === 내부 헬퍼 메서드들 ===

  /// 지점 데이터 조회
  Future<ClientResult> _getBranchData(String branchId) async {
    try {
      final doc = await db.collection('branches').doc(branchId).get();
      
      if (!doc.exists) {
        return ClientResult.error('지점을 찾을 수 없습니다: $branchId');
      }
      
      final data = doc.data();
      if (data == null) {
        return ClientResult.error('지점 데이터가 비어있습니다');
      }
      
      return ClientResult.success(null, data: {'branchData': data});
      
    } catch (e) {
      return ClientResult.error('지점 정보 조회 실패: ${e.toString()}');
    }
  }

  /// 거래처 코드 생성
  Future<ClientResult> _generateClientCode(
    String branchId, 
    Map<String, dynamic> branchData, 
    String scheme
  ) async {
    try {
      String newClientCode;
      
      if (scheme == 'prefix-seq') {
        final prefix = branchData['codePrefix']?.toString() ?? '';
        if (prefix.isEmpty) {
          return ClientResult.error('codePrefix가 설정되지 않았습니다');
        }
        
        final seqValue = branchData['nextClientSeq'];
        int nextSeq = 1;
        
        if (seqValue != null) {
          if (seqValue is int) {
            nextSeq = seqValue;
          } else if (seqValue is String) {
            nextSeq = int.tryParse(seqValue) ?? 1;
          } else if (seqValue is double) {
            nextSeq = seqValue.toInt();
          }
        }
        
        newClientCode = '$prefix${_pad(nextSeq)}';
        
      } else {
        // legacy 방식
        final lastNumber = await _getLastClientNumber(branchId);
        if (lastNumber < 0) {
          return ClientResult.error('기존 거래처 번호 조회 실패');
        }
        
        newClientCode = 'CLIENT${_pad(lastNumber + 1)}';
      }
      
      return ClientResult.success(newClientCode);
      
    } catch (e) {
      return ClientResult.error('거래처 코드 생성 실패: ${e.toString()}');
    }
  }

  /// 마지막 거래처 번호 조회
  Future<int> _getLastClientNumber(String branchId) async {
    try {
      final query = await db
          .collection('branches')
          .doc(branchId)
          .collection('clients')
          .orderBy('clientCode', descending: true)
          .limit(1)
          .get();
          
      if (query.docs.isEmpty) {
        return 0;
      }
      
      final lastCode = query.docs.first.data()['clientCode']?.toString() ?? '';
      final match = RegExp(r'(\d+)').firstMatch(lastCode);
      return int.tryParse(match?.group(1) ?? '0') ?? 0;
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ 마지막 거래처 번호 조회 실패: $e');
      }
      return -1; // 에러 표시
    }
  }

  /// 중복 체크
  Future<ClientResult> _checkDuplicate(String branchId, String clientCode) async {
    try {
      final existing = await db
          .collection('branches')
          .doc(branchId)
          .collection('clients')
          .doc(clientCode)
          .get();
          
      if (existing.exists) {
        return ClientResult.error('중복된 거래처 코드입니다: $clientCode');
      }
      
      return ClientResult.success(null);
      
    } catch (e) {
      return ClientResult.error('중복 체크 실패: ${e.toString()}');
    }
  }

  /// 거래처 데이터 저장
  Future<ClientResult> _saveClientData(
    String branchId, 
    String clientCode, 
    Map<String, dynamic> data
  ) async {
    try {
      final clientData = <String, dynamic>{
        ...data,
        'clientCode': clientCode,
        'branchId': branchId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'active': data['active'] ?? true,
      };
      
      await db
          .collection('branches')
          .doc(branchId)
          .collection('clients')
          .doc(clientCode)
          .set(clientData);
      
      return ClientResult.success(null);
      
    } catch (e) {
      return ClientResult.error('거래처 데이터 저장 실패: ${e.toString()}');
    }
  }

  /// 인증 정보 저장
  Future<ClientResult> _saveAuthData(String clientCode, String password) async {
    try {
      await db.collection('client_auth').doc(clientCode).set({
        'passwordHash': password, // 실제로는 해시 처리 필요
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': null,
        'loginAttempts': 0,
        'locked': false,
      });
      
      return ClientResult.success(null);
      
    } catch (e) {
      return ClientResult.error('인증 정보 저장 실패: ${e.toString()}');
    }
  }

  /// 시퀀스 업데이트
  Future<ClientResult> _updateSequence(String branchId, Map<String, dynamic> branchData) async {
    try {
      final currentSeqValue = branchData['nextClientSeq'];
      int currentSeq = 1;
      
      if (currentSeqValue != null) {
        if (currentSeqValue is int) {
          currentSeq = currentSeqValue;
        } else if (currentSeqValue is String) {
          currentSeq = int.tryParse(currentSeqValue) ?? 1;
        } else if (currentSeqValue is double) {
          currentSeq = currentSeqValue.toInt();
        }
      }
      
      await db.collection('branches').doc(branchId).update({
        'nextClientSeq': currentSeq + 1,
      });
      
      if (kDebugMode) {
        print('✅ nextClientSeq 업데이트 완료: ${currentSeq + 1}');
      }
      
      return ClientResult.success(null);
      
    } catch (e) {
      return ClientResult.error('시퀀스 업데이트 실패: ${e.toString()}');
    }
  }

  // === 기존 메서드들 (하위 호환성) ===

  /// 지점 정책 가져오기 (기존 API)
  Future<BranchPolicy> fetchBranchPolicy(String branchId) async {
    final result = await fetchBranchPolicySafe(branchId);
    
    if (!result.success) {
      throw Exception(result.error);
    }
    
    return result.data!['policy'] as BranchPolicy;
  }

  /// 거래처 생성 (기존 API)
  Future<String> createClient({
    required String branchId,
    required Map<String, dynamic> data,
    required String rawPassword,
  }) async {
    final result = await createClientSafe(
      branchId: branchId,
      data: data,
      rawPassword: rawPassword,
    );
    
    if (!result.success) {
      throw Exception(result.error);
    }
    
    return result.clientCode!;
  }

  /// 거래처 목록 조회 (기존 API)
  Future<List<Map<String, dynamic>>> getClientList(String branchId, {
    int limit = 50,
    String? lastClientCode,
    String? searchName,
  }) async {
    final result = await getClientListSafe(
      branchId,
      limit: limit,
      lastClientCode: lastClientCode,
      searchName: searchName,
    );
    
    if (!result.success) {
      throw Exception(result.error);
    }
    
    return (result.data!['clients'] as List).cast<Map<String, dynamic>>();
  }

  /// 거래처 정보 조회 (기존 API)
  Future<Map<String, dynamic>> getClient(String branchId, String clientCode) async {
    final result = await getClientSafe(branchId, clientCode);
    
    if (!result.success) {
      throw Exception(result.error);
    }
    
    return result.data!['client'] as Map<String, dynamic>;
  }

  /// 거래처 정보 업데이트 (기존 API)
  Future<void> updateClient(
    String branchId, 
    String clientCode, 
    Map<String, dynamic> updateData
  ) async {
    final result = await updateClientSafe(branchId, clientCode, updateData);
    
    if (!result.success) {
      throw Exception(result.error);
    }
  }

  /// 거래처 비활성화 (기존 API)
  Future<void> deactivateClient(String branchId, String clientCode) async {
    final result = await deactivateClientSafe(branchId, clientCode);
    
    if (!result.success) {
      throw Exception(result.error);
    }
  }
}
