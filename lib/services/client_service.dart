import 'package:cloud_firestore/cloud_firestore.dart';

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

  Future<BranchPolicy> fetchBranchPolicy(String branchId) async {
    final doc = await db.collection('branches').doc(branchId).get();
    final m = (doc.data() ?? {});
    return BranchPolicy(
      scheme: (m['codeScheme'] ?? 'legacy') as String,
      codePrefix: (m['codePrefix'] ?? '') as String,
      clientSeq: (m['clientSeq'] ?? 1) as int,
    );
  }

  /// 지점 정책에 맞춰 거래처 생성 (문서ID 자동)
  Future<void> createClient({
    required String branchId,
    required Map<String, dynamic> data,
  }) async {
    await db.runTransaction((txn) async {
      final branchRef = db.collection('branches').doc(branchId);
      final bSnap = await txn.get(branchRef);
      if (!bSnap.exists) throw Exception('Branch not found');

      final m = bSnap.data() as Map<String, dynamic>;
      final scheme = (m['codeScheme'] ?? 'legacy') as String;

      late String docId;

      if (scheme == 'legacy') {
        // ✅ 충청지사 등 레거시 방식: 기존 로직을 그대로 사용
        // 예: 자동 증가 “CLIENT001 …” 혹은 지금 쓰는 방식 호출
        // 여기선 임시로 자동 ID를 쓰되, 네가 기존 함수가 있으면 그걸 호출해.
        docId = db.collection('dummy').doc().id; // <- 기존 로직으로 교체
      } else if (scheme == 'prefix-seq') {
        final prefix = (m['codePrefix'] ?? '') as String;
        final next = (m['clientSeq'] ?? 1) as int;
        if (prefix.isEmpty) throw Exception('Missing codePrefix');
        docId = '$prefix${_pad(next)}'; // GP001
        txn.update(branchRef, {'clientSeq': next + 1});
      } else {
        throw Exception('Unknown code scheme: $scheme');
      }

      final clientRef = branchRef.collection('clients').doc(docId);
      final exists = await txn.get(clientRef);
      if (exists.exists) throw Exception('Duplicated client code: $docId');

      txn.set(clientRef, {
        ...data,
        'code': docId,
        'branchId': branchId,
        'createdAt': FieldValue.serverTimestamp(),
        'active': data['active'] ?? true,
      });
    });
  }
}
