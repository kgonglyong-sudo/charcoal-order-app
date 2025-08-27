// lib/screens/clients_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

/// 컬렉션 구조:
/// branches/{branchId}/clients/{clientCode}
/// 필드:
/// - clientCode, name, priceTier(A/B/C), memo?, createdAt, updatedAt, active
/// - bizNo, address, managerPhone, orderPhone, email
/// - priceOverrides:   { productId: int }          // 구버전(변형 없음)
/// - priceOverridesV2: { 'pid|vid': int }          // 신규(변형 단위)
/// - deliveryDays: [1..7]  // 1=월 ... 7=일
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});
  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final branchId = auth.branchId;

    if (branchId == null || branchId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('거래처')),
        body: const Center(
          child: Text('지점 정보가 없습니다. /users/{uid}.branchId 를 확인하세요.'),
        ),
      );
    }

    final q = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('clients');

    return Scaffold(
      appBar: AppBar(
        title: const Text('거래처'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: Column(
        children: [
          // 검색 + 총 개수
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: '거래처명/코드 검색',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _search = v.trim()),
                  ),
                ),
                const SizedBox(width: 10),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: q.snapshots(),
                  builder: (context, snap) {
                    final total = snap.data?.docs.length ?? 0;
                    return Text('총 $total개',
                        style: const TextStyle(fontWeight: FontWeight.w600));
                  },
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: q.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? const [];

                // 검색
                final filtered = docs.where((d) {
                  final m = d.data();
                  final code = (m['clientCode'] as String? ?? '').toLowerCase();
                  final name = (m['name'] as String? ?? '').toLowerCase();
                  final s = _search.toLowerCase();
                  return s.isEmpty || code.contains(s) || name.contains(s);
                }).toList();

                // 정렬: clientCode 내 숫자 기준 오름차순
                int extractNum(QueryDocumentSnapshot<Map<String, dynamic>> d) {
                  final code = (d['clientCode'] as String? ?? d.id);
                  final n = RegExp(r'\d+').firstMatch(code)?.group(0);
                  return int.tryParse(n ?? '0') ?? 0;
                }
                filtered.sort((a, b) => extractNum(a).compareTo(extractNum(b)));

                if (filtered.isEmpty) {
                  return const Center(child: Text('등록된 거래처가 없습니다.'));
                }

                final now = DateTime.now();
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (_, i) {
                    final d = filtered[i];
                    final m = d.data();
                    final code = m['clientCode'] as String? ?? d.id;
                    final name = m['name'] as String? ?? '(이름없음)';
                    final tier = (m['priceTier'] as String? ?? '').toUpperCase();
                    final memo = m['memo'] as String? ?? '';
                    final bizNo = m['bizNo'] as String? ?? '';
                    final address = m['address'] as String? ?? '';
                    final managerPhone = m['managerPhone'] as String? ?? '';
                    final orderPhone = m['orderPhone'] as String? ?? '';
                    final email = m['email'] as String? ?? '';
                    final created = (m['createdAt'] as Timestamp?)?.toDate();

                    final days = (m['deliveryDays'] as List?)
                            ?.whereType<int>()
                            .where((e) => e >= 1 && e <= 7)
                            .toList() ??
                        const <int>[];
                    final dayText =
                        days.isEmpty ? '미지정' : days.map(_weekdayLabel).join(', ');
                    final next = _nextDeliveryDate(now, days);
                    final nextText = next == null
                        ? ''
                        : ' • 이번주: ${_fmt(next)}(${_weekdayLabel(next.weekday)})';

                    final subLines = <String>[
                      code + (tier.isEmpty ? '' : ' • 등급: $tier'),
                      if (bizNo.isNotEmpty) '사업자번호: $bizNo',
                      if (address.isNotEmpty) '주소: $address',
                      if (managerPhone.isNotEmpty) '담당: $managerPhone',
                      if (orderPhone.isNotEmpty) '발주: $orderPhone',
                      if (email.isNotEmpty) '이메일: $email',
                      '배송 요일: $dayText$nextText',
                      if (created != null) '생성: ${_fmt(created)}',
                      if (memo.isNotEmpty) '메모: $memo',
                    ].join('\n');

                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.storefront)),
                      title: Text(name),
                      subtitle: Text(subLines),
                      isThreeLine: true,
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.sell, size: 18),
                            label: const Text('개별 단가'),
                            onPressed: () =>
                                _openPriceOverrides(context, branchId, code, tier),
                          ),
                          IconButton(
                            tooltip: '수정',
                            icon: const Icon(Icons.edit),
                            onPressed: () =>
                                _openClientEditor(context, branchId, initial: m),
                          ),
                          IconButton(
                            tooltip: '삭제',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () =>
                                _confirmDelete(context, branchId, code),
                          ),
                        ],
                      ),
                      onTap: () => _openClientEditor(context, branchId, initial: m),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addClient',
        onPressed: () => _openClientEditor(context, branchId),
        icon: const Icon(Icons.add),
        label: const Text('거래처 추가'),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, String branchId, String clientCode) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제 확인'),
        content: Text('거래처 "$clientCode" 를 삭제할까요?\n(주의: 주문 데이터는 그대로 남습니다)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseFirestore.instance
          .collection('branches').doc(branchId)
          .collection('clients').doc(clientCode)
          .delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제되었습니다.')));
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 지점정책 분기 & 생성 로직
  // ───────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _fetchBranchPolicy(String branchId) async {
    final b = await FirebaseFirestore.instance.collection('branches').doc(branchId).get();
    return b.data() ?? <String, dynamic>{};
  }

  String _pad(int n, {int w = 3}) => n.toString().padLeft(w, '0');

  Future<String> _previewNextClientCodeByPolicy(String branchId) async {
    final m = await _fetchBranchPolicy(branchId);
    final scheme = (m['codeScheme'] ?? 'legacy') as String;
    if (scheme == 'prefix-seq') {
      final prefix = (m['codePrefix'] ?? '') as String;
      final next = (m['clientSeq'] ?? 1) as int;
      if (prefix.isEmpty) return '자동(지점코드 없음)';
      return '$prefix${_pad(next)}';
    }
    return _nextClientCode(branchId); // legacy
  }

  /// 정책에 맞춰 안전 생성(트랜잭션) + 낙관적 재시도
  Future<String> _createClientByPolicy({
    required String branchId,
    required Map<String, dynamic> data,
  }) async {
    final db = FirebaseFirestore.instance;

    Future<String> _tx() {
      return db.runTransaction<String>((txn) async {
        final branchRef = db.collection('branches').doc(branchId);
        final bSnap = await txn.get(branchRef);
        if (!bSnap.exists) {
          throw Exception('Branch not found: $branchId');
        }

        final m = bSnap.data() as Map<String, dynamic>;
        final scheme = (m['codeScheme'] ?? 'legacy') as String;

        late String docId;

        if (scheme == 'prefix-seq') {
          final prefix = (m['codePrefix'] ?? '') as String;
          final next = (m['clientSeq'] ?? 1) as int;
          if (prefix.isEmpty) throw Exception('Missing codePrefix in branch');
          docId = '$prefix${_pad(next)}';
          txn.update(branchRef, {'clientSeq': next + 1});
        } else {
          // legacy: CLIENT###
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
          docId = 'CLIENT${_pad(lastNum + 1)}';
        }

        // 중복 방지
        final clientRef = branchRef.collection('clients').doc(docId);
        final exists = await txn.get(clientRef);
        if (exists.exists) {
          throw Exception('Duplicated client code: $docId');
        }

        // 저장
        txn.set(clientRef, {
          ...data,
          'clientCode': docId,
          'branchId': branchId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'active': data['active'] ?? true,
        });

        return docId;
      });
    }

    const maxRetries = 3;
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        return await _tx();
      } on FirebaseException catch (e) {
        // 권한/네트워크 에러는 바로 노출
        throw Exception('FirebaseException: ${e.code} ${e.message}');
      } catch (e) {
        // 동시성/중복 같은 경우 재시도
        if (attempt <= maxRetries &&
            ('$e'.contains('duplicated') || '$e'.contains('already exists'))) {
          await Future.delayed(Duration(milliseconds: 120 * attempt));
          continue;
        }
        rethrow;
      }
    }
  }

  /// 등록/수정 다이얼로그
  Future<void> _openClientEditor(
    BuildContext context,
    String branchId, {
    Map<String, dynamic>? initial,
  }) async {
    final isEdit = initial != null;
    final nameCtrl = TextEditingController(text: initial?['name'] ?? '');
    final memoCtrl = TextEditingController(text: initial?['memo'] ?? '');
    final bizCtrl = TextEditingController(text: initial?['bizNo'] ?? '');
    final addrCtrl = TextEditingController(text: initial?['address'] ?? '');
    final mPhoneCtrl = TextEditingController(text: initial?['managerPhone'] ?? '');
    final oPhoneCtrl = TextEditingController(text: initial?['orderPhone'] ?? '');
    final emailCtrl = TextEditingController(text: initial?['email'] ?? '');
    String tier = (initial?['priceTier'] as String? ?? 'B').toUpperCase();

    final Set<int> days = {
      ...(initial?['deliveryDays'] as List? ?? const []),
    }.whereType<int>().where((e) => e >= 1 && e <= 7).toSet();

    String autoCodePreview = initial?['clientCode'] ?? '';
    if (!isEdit) {
      autoCodePreview = await _previewNextClientCodeByPolicy(branchId);
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(isEdit ? '거래처 수정' : '거래처 추가'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: TextEditingController(text: autoCodePreview),
                    readOnly: true,
                    decoration: const InputDecoration(labelText: '거래처 코드(문서 ID) * 자동'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: '거래처명 *'),
                  ),
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '가격 등급',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: tier,
                        items: const [
                          DropdownMenuItem(value: 'A', child: Text('A')),
                          DropdownMenuItem(value: 'B', child: Text('B')),
                          DropdownMenuItem(value: 'C', child: Text('C')),
                        ],
                        onChanged: (v) => setD(() => tier = v ?? 'B'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('지정 배송요일', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: List.generate(7, (i) {
                            final w = i + 1;
                            return FilterChip(
                              label: Text(_weekdayLabel(w)),
                              selected: days.contains(w),
                              onSelected: (_) {
                                setD(() {
                                  if (days.contains(w)) {
                                    days.remove(w);
                                  } else {
                                    days.add(w);
                                  }
                                });
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: bizCtrl, decoration: const InputDecoration(labelText: '사업자등록번호')),
                  const SizedBox(height: 8),
                  TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: '사업장 주소')),
                  const SizedBox(height: 8),
                  TextField(controller: mPhoneCtrl, decoration: const InputDecoration(labelText: '담당(채권) 전화')),
                  const SizedBox(height: 8),
                  TextField(controller: oPhoneCtrl, decoration: const InputDecoration(labelText: '발주 전화')),
                  const SizedBox(height: 8),
                  TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: '이메일')),
                  const SizedBox(height: 8),
                  TextField(controller: memoCtrl, maxLines: 2, decoration: const InputDecoration(labelText: '메모')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;

                final data = {
                  'name': name,
                  'priceTier': tier,
                  'memo': memoCtrl.text.trim(),
                  'bizNo': bizCtrl.text.trim(),
                  'address': addrCtrl.text.trim(),
                  'managerPhone': mPhoneCtrl.text.trim(),
                  'orderPhone': oPhoneCtrl.text.trim(),
                  'email': emailCtrl.text.trim(),
                  'deliveryDays': (days.toList()..sort()),
                };

                try {
                  if (isEdit) {
                    final code = initial!['clientCode'] as String? ?? '';
                    final ref = FirebaseFirestore.instance
                        .collection('branches').doc(branchId)
                        .collection('clients').doc(code);
                    await ref.set({
                      ...data,
                      'updatedAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));

                    if (!mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('수정되었습니다.')),
                    );
                  } else {
                    final createdCode = await _createClientByPolicy(
                      branchId: branchId,
                      data: data,
                    );

                    final ref = FirebaseFirestore.instance
                        .collection('branches').doc(branchId)
                        .collection('clients').doc(createdCode);
                    final preset = await _defaultPricesForTier(tier);
                    if (preset.isNotEmpty) {
                      await ref.set({'priceOverrides': preset}, SetOptions(merge: true));
                    }

                    if (!mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('등록되었습니다. ($createdCode)')),
                    );
                  }
                } on FirebaseException catch (e, st) {
                  debugPrint('FirebaseException: ${e.code} ${e.message}\n$st');
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('거래처 등록 실패: ${e.code} ${e.message}')),
                  );
                } catch (e, st) {
                  Object inner = e;
                  if (e is AsyncError) inner = e.error ?? e;
                  debugPrint('Error on create client (unboxed): $inner\n$st');
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('거래처 등록 실패: $inner')),
                  );
                }
              },
              child: Text(isEdit ? '수정' : '등록'),
            ),
          ],
        ),
      ),
    );
  }

  /// (레거시용) 다음 코드 생성: CLIENT001 → …
  Future<String> _nextClientCode(String branchId) async {
    final snap = await FirebaseFirestore.instance
        .collection('branches').doc(branchId)
        .collection('clients')
        .orderBy('clientCode', descending: true)
        .limit(1)
        .get();

    int lastNum = 0;
    if (snap.docs.isNotEmpty) {
      final last = snap.docs.first.data()['clientCode'] as String? ?? '';
      final m = RegExp(r'(\d+)').firstMatch(last);
      lastNum = int.tryParse(m?.group(1) ?? '0') ?? 0;
    }
    final next = lastNum + 1;
    final padded = next.toString().padLeft(3, '0');
    return 'CLIENT$padded';
  }

  /// 등급(A/B/C) 기준 기본가 맵 (변형 없는 상품용 구버전 호환)
  Future<Map<String, int>> _defaultPricesForTier(String tier) async {
    final res = await FirebaseFirestore.instance.collection('products').get();
    final map = <String, int>{};
    for (final d in res.docs) {
      final m = d.data();
      final pid = d.id;
      int price = 0;
      if (m['prices'] is Map) {
        final mm = Map<String, dynamic>.from(m['prices']);
        final p = mm[tier] ?? mm[tier.toUpperCase()];
        if (p is num) price = p.toInt();
      }
      if (price == 0) {
        final p2 = m['price$tier']; // priceA, priceB, priceC
        if (p2 is num) price = p2.toInt();
      }
      map[pid] = price;
    }
    return map;
  }

  /// ✅ 개별 단가 편집 (변형 단위, 표준단가와 동일 소스/정렬/한글명)
  Future<void> _openPriceOverrides(
    BuildContext context,
    String branchId,
    String clientCode,
    String tier,
  ) async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('branches').doc(branchId)
          .collection('clients').doc(clientCode);

      final clientSnap = await docRef.get();
      final overridesV2 = Map<String, dynamic>.from(
        (clientSnap.data()?['priceOverridesV2'] as Map?) ?? const {},
      );
      final overridesLegacy = Map<String, dynamic>.from(
        (clientSnap.data()?['priceOverrides'] as Map?) ?? const {},
      );

      final ps = await FirebaseFirestore.instance.collection('products').get();

      final rows = <_ProdBlock>[];
      int _asInt(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);

      // product 정렬/필터
      final pdocs = ps.docs
          .where((d) => d.data()['deletedAt'] == null)
          .toList()
        ..sort((a, b) {
          final am = a.data();
          final bm = b.data();
          final ao = _asInt(am['sortOrder']);
          final bo = _asInt(bm['sortOrder']);
          if (ao != bo) return ao.compareTo(bo);
          final an = (am['nameKo'] ?? am['name'] ?? a.id).toString();
          final bn = (bm['nameKo'] ?? bm['name'] ?? b.id).toString();
          return an.compareTo(bn);
        });

      for (final p in pdocs) {
        final pm = p.data();
        final pid = p.id;
        final pnameKo = (pm['nameKo'] as String?)?.trim();
        final pnameEn = (pm['name'] as String?)?.trim();
        final pname =
            (pnameKo?.isNotEmpty == true) ? pnameKo! : (pnameEn?.isNotEmpty == true ? pnameEn! : pid);

        final vs = await p.reference.collection('variants').get();
        final vdocs = vs.docs.toList()
          ..sort((a, b) {
            final ao = _asInt(a.data()['sortOrder']);
            final bo = _asInt(b.data()['sortOrder']);
            return ao.compareTo(bo);
          });

        // 변형이 없는 상품: 구버전 호환
        if (vdocs.isEmpty) {
          final prices = Map<String, dynamic>.from(pm['prices'] ?? const {});
          final base = _asInt(prices[tier.toUpperCase()]);
          final legacy = _asInt(overridesLegacy[pid]);
          final controller = TextEditingController(
            text: (legacy != 0 ? legacy : base).toString(),
          );
          rows.add(_ProdBlock(
            pid: pid,
            productName: pname,
            variants: [
              _VarRow(
                vid: '',
                label: '(기본)',
                active: (pm['active'] ?? true) == true,
                basePrice: base,
                controller: controller,
                keyForSave: pid, // 구버전 키
                isLegacy: true,
              ),
            ],
          ));
          continue;
        }

        final varRows = <_VarRow>[];
        for (final v in vdocs) {
          final vm = v.data();
          final vid = v.id;
          final labelKo = (vm['labelKo'] as String?)?.trim();
          final labelEn = (vm['label'] as String?)?.trim();
          final label = (labelKo?.isNotEmpty == true)
              ? labelKo!
              : (labelEn?.isNotEmpty == true ? labelEn! : vid);
          final active = (vm['active'] ?? true) == true;

          final gp = Map<String, dynamic>.from(vm['gradePrices'] ?? const {});
          final base = _asInt(gp[tier.toUpperCase()]);

          final key = '$pid|$vid';
          final ov2 = _asInt(overridesV2[key]);
          final controller = TextEditingController(
            text: (ov2 != 0 ? ov2 : base).toString(),
          );

          varRows.add(_VarRow(
            vid: vid,
            label: label,
            active: active,
            basePrice: base,
            controller: controller,
            keyForSave: key, // 'pid|vid'
            isLegacy: false,
          ));
        }

        if (varRows.isNotEmpty) {
          rows.add(_ProdBlock(pid: pid, productName: pname, variants: varRows));
        }
      }

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 16,
              right: 16,
              top: 12,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.85,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('개별 단가: $clientCode (등급 $tier)',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(child: Text('표시할 품목이 없습니다.'))
                        : ListView.separated(
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemCount: rows.length,
                            itemBuilder: (_, i) {
                              final p = rows[i];
                              return Card(
                                child: ExpansionTile(
                                  title: Text(p.productName,
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                  children: [
                                    const Divider(height: 0),
                                    ...p.variants.map(
                                      (vr) => Padding(
                                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '• ${vr.label}',
                                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                                  ),
                                                ),
                                                if (!vr.active)
                                                  const Padding(
                                                    padding: EdgeInsets.only(left: 6),
                                                    child: Icon(
                                                      Icons.pause_circle_filled,
                                                      size: 16,
                                                      color: Colors.orange,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '기본가(등급 $tier): ${_comma(vr.basePrice)}원',
                                                    style: const TextStyle(fontSize: 12),
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: 130,
                                                  child: TextField(
                                                    controller: vr.controller,
                                                    keyboardType: TextInputType.number,
                                                    textAlign: TextAlign.end,
                                                    decoration: const InputDecoration(
                                                      isDense: true,
                                                      labelText: '개별단가',
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('닫기'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.save),
                          label: const Text('저장'),
                          onPressed: () async {
                            final v2 = <String, int>{};
                            final legacy = <String, int>{};

                            for (final pb in rows) {
                              for (final vr in pb.variants) {
                                final text = vr.controller.text.trim();
                                final val = int.tryParse(text) ?? vr.basePrice;
                                if (vr.isLegacy) {
                                  legacy[vr.keyForSave] = val; // pid
                                } else {
                                  v2[vr.keyForSave] = val; // 'pid|vid'
                                }
                              }
                            }

                            final data = <String, dynamic>{
                              'priceOverridesV2': v2,
                              'updatedAt': FieldValue.serverTimestamp(),
                            };
                            if (legacy.isNotEmpty) data['priceOverrides'] = legacy;

                            await docRef.set(data, SetOptions(merge: true));
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('개별 단가가 저장되었습니다.')),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('개별단가 편집 열기 실패: $e')),
      );
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  static String _comma(int v) =>
      v.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _weekdayLabel(int weekday) {
    const labels = {1: '월', 2: '화', 3: '수', 4: '목', 5: '금', 6: '토', 7: '일'};
    return labels[weekday] ?? '$weekday';
  }

  /// 지정 요일들 중 "오늘 기준 가장 가까운 이번 주 날짜" (이번 주 내에 없으면 다음 주 첫 선택 요일)
  static DateTime? _nextDeliveryDate(DateTime now, List<int> weekdays) {
    if (weekdays.isEmpty) return null;
    final days = [...weekdays]..sort();
    final base = DateTime(now.year, now.month, now.day);
    final monday = base.subtract(Duration(days: base.weekday - 1));
    for (final w in days) {
      final d = monday.add(Duration(days: w - 1));
      if (!d.isBefore(base)) return d;
    }
    final firstNextWeek = monday.add(const Duration(days: 7));
    return firstNextWeek.add(Duration(days: days.first - 1));
  }
}

// 내부 표시용 모델들
class _ProdBlock {
  _ProdBlock({
    required this.pid,
    required this.productName,
    required this.variants,
  });
  final String pid;
  final String productName;
  final List<_VarRow> variants;
}

class _VarRow {
  _VarRow({
    required this.vid,
    required this.label,
    required this.active,
    required this.basePrice,
    required this.controller,
    required this.keyForSave,
    required this.isLegacy,
  });
  final String vid;
  final String label;
  final bool active;
  final int basePrice;
  final TextEditingController controller;
  final String keyForSave; // 'pid|vid' 또는 'pid'(legacy)
  final bool isLegacy;
}
