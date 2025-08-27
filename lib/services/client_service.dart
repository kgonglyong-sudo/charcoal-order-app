import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bcrypt/bcrypt.dart';  // 비밀번호 해시화 라이브러리

class BranchPolicy {
  final String scheme;     // 'legacy' | 'prefix-seq'
  final String codePrefix; // 'GP' 등
  final int clientSeq;     // 다음 번호
  BranchPolicy({required this.scheme, required this.codePrefix, required this.clientSeq});
}

String _pad(int n, {int w = 3}) => n.toString().padLeft(w, '0');

class ClientService {
  final FirebaseFirestore db;
  ClientService(this.db);

  // 지점 정책 가져오기
  Future<BranchPolicy> fetchBranchPolicy(String branchId) async {
    final doc = await db.collection('branches').doc(branchId).get();
    final m = (doc.data() ?? {});
    return BranchPolicy(
      scheme: (m['codeScheme'] ?? 'legacy') as String,
      codePrefix: (m['codePrefix'] ?? '') as String,
      clientSeq: (m['nextClientSeq'] ?? 1) as int,  // nextClientSeq로 관리
    );
  }

  /// 지점 정책에 맞춰 거래처 생성 (문서ID 자동)
  /// 반환: 최종 생성된 clientCode (예: CLIENT007, GP003)
  Future<String> createClient({
    required String branchId,
    required Map<String, dynamic> data,
    required String rawPassword,  // 비밀번호 처리
  }) async {
    try {
      return await db.runTransaction<String>((txn) async {
        final branchRef = db.collection('branches').doc(branchId);
        final bSnap = await txn.get(branchRef);
        if (!bSnap.exists) {
          throw Exception('Branch not found: $branchId');
        }

        final m = bSnap.data() as Map<String, dynamic>;
        final scheme = (m['codeScheme'] ?? 'legacy') as String;
        final nextClientSeq = (m['nextClientSeq'] ?? 1) as int;  // nextClientSeq 사용

        late String docId;

        // 지점 정책에 따른 코드 생성
        if (scheme == 'prefix-seq') {
          // GP### 방식
          final prefix = (m['codePrefix'] ?? '') as String;
          if (prefix.isEmpty) {
            throw Exception('Missing codePrefix in branch "$branchId"');
          }
          docId = '$prefix${_pad(nextClientSeq)}';  // 예: GP001
          txn.update(branchRef, {'nextClientSeq': nextClientSeq + 1});  // 다음 번호 올리기
        } else if (scheme == 'legacy') {
          // CLIENT### 방식
          final last = await db
              .collection('branches').doc(branchId)
              .collection('clients')
              .orderBy('clientCode', descending: true)
              .limit(1)
              .get();
          int lastNum = 0;
          if (last.docs.isNotEmpty) {
            final lastCode = last.docs.first.data()['clientCode'] as String? ?? '';
            final match = RegExp(r'(\d+)').firstMatch(lastCode);
            lastNum = int.tryParse(match?.group(1) ?? '0') ?? 0;
          }
          docId = 'CLIENT${_pad(lastNum + 1)}';  // 예: CLIENT007
        } else {
          throw Exception('Unknown code scheme: $scheme');
        }

        // 중복 방지
        final clientRef = branchRef.collection('clients').doc(docId);
        final exists = await txn.get(clientRef);
        if (exists.exists) {
          throw Exception('Duplicated client code: $docId');
        }

        // 비밀번호 해시화 처리
        final hash = BCrypt.hashpw(rawPassword, BCrypt.gensalt());  // 비밀번호 해시화
        final authRef = db.collection('client_auth').doc(docId);
        txn.set(authRef, {
          'passwordHash': hash,  // 비밀번호 해시 저장
          'createdAt': FieldValue.serverTimestamp(),
        });

        // 거래처 데이터 저장
        txn.set(clientRef, {
          ...data,
          'clientCode': docId,                    // 필드명 통일
          'branchId': branchId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'active': data['active'] ?? true,
        });

        return docId;
      });
    } on FirebaseException catch (e) {
      // 파이어스토어 에러코드 노출 (permission-denied 등)
      throw Exception('FirebaseException: ${e.code} ${e.message}');
    } catch (e) {
      // 커스텀 에러 그대로 전달
      throw Exception(e.toString());
    }
  }
}
