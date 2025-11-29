// lib/screens/clients_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'client_edit_screen.dart';

/// 컬렉션 구조:
/// branches/{branchId}/clients/{clientCode}
/// 필드:
/// - clientCode, name, priceTier(A/B/C), memo?, createdAt, updatedAt, active
/// - bizNo, address, managerPhone, orderPhone, email
/// - priceOverrides:   { productId: int }          // 개별단가 (상품ID 기준)
/// - priceOverridesV2: { 'pid|vid': int }          // (향후 변형단위까지 쓸 때)
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
    final branchId = auth.managerBranchIdOrNull;

    if (branchId == null || branchId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('거래처')),
        body: const Center(
          child: Text('지점 정보가 없습니다. 관리자로 로그인했는지 확인하세요.'),
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
                    final isPaymentRequired =
                        (m['isPaymentRequired'] as bool?) ?? true;

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
                      '결제 필수: ${isPaymentRequired ? '예' : '아니오'}',
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
                            onPressed: () => _openPriceOverrides(
                              context,
                              branchId,
                              code,
                              tier,
                              name,
                            ),
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
        content:
            Text('거래처 "$clientCode" 를 삭제할까요?\n(주의: 주문 데이터는 그대로 남습니다)'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseFirestore.instance
          .collection('branches')
          .doc(branchId)
          .collection('clients')
          .doc(clientCode)
          .delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('삭제되었습니다.')));
    }
  }

  Future<void> _openClientEditor(
    BuildContext context,
    String branchId, {
    Map<String, dynamic>? initial,
  }) async {
    await showDialog(
      context: context,
      builder: (_) => ClientEditScreen(
        branchId: branchId,
        code: initial?['clientCode'] as String?,
        initData: initial,
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Helpers
  // ───────────────────────────────────────────────────────────────────────────
  static String _weekdayLabel(int weekday) {
    const labels = {1: '월', 2: '화', 3: '수', 4: '목', 5: '금', 6: '토', 7: '일'};
    return labels[weekday] ?? '$weekday';
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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

  // ───────────────────────────────────────────────────────────────────────────
  // 개별 단가 편집 열기
  // ───────────────────────────────────────────────────────────────────────────
  void _openPriceOverrides(
    BuildContext context,
    String branchId,
    String clientCode,
    String tier,
    String clientName,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ClientPriceOverrideScreen(
          branchId: branchId,
          clientCode: clientCode,
          clientName: clientName,
          priceTier: tier,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 개별 단가 목록용 간단 모델
// ─────────────────────────────────────────────────────────────────────────────
class _OverrideItem {
  final String productId;
  final String name;
  final int basePrice;

  _OverrideItem({
    required this.productId,
    required this.name,
    required this.basePrice,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 개별 단가 편집 화면
//  - products 컬렉션에서 상품 목록 불러오기
//  - 각 상품의 variants/gradePrices에서 표준단가 읽기
//  - branches/{branchId}/clients/{clientCode}.priceOverrides 맵에 저장
// ─────────────────────────────────────────────────────────────────────────────
class _ClientPriceOverrideScreen extends StatefulWidget {
  final String branchId;
  final String clientCode;
  final String clientName;
  final String priceTier;

  const _ClientPriceOverrideScreen({
    required this.branchId,
    required this.clientCode,
    required this.clientName,
    required this.priceTier,
  });

  @override
  State<_ClientPriceOverrideScreen> createState() =>
      _ClientPriceOverrideScreenState();
}

class _ClientPriceOverrideScreenState
    extends State<_ClientPriceOverrideScreen> {
  bool _loading = true;
  bool _saving = false;

  // 상품별 개별단가 (productId -> 단가)
  Map<String, int> _overrides = {};

  // 화면에 보여줄 리스트 (상품 + 대표 변형 기준 표준단가)
  final List<_OverrideItem> _items = [];

  // 각 상품별 입력 컨트롤러
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final db = FirebaseFirestore.instance;

      // 1) 모든 상품 불러오기
      final prodSnap = await db.collection('products').get();

      // 2) 해당 거래처의 기존 개별단가 맵 불러오기
      final clientRef = db
          .collection('branches')
          .doc(widget.branchId)
          .collection('clients')
          .doc(widget.clientCode);
      final clientSnap = await clientRef.get();
      final clientData = clientSnap.data() ?? {};
      final rawOverrides =
          (clientData['priceOverrides'] as Map<String, dynamic>? ?? {});
      _overrides = rawOverrides.map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      );

      // 3) 상품마다 variants에서 gradePrices 읽어서 표준단가 만들기
      final tier = widget.priceTier.toUpperCase();

      for (final p in prodSnap.docs) {
        final pid = p.id;
        final pm = p.data();
        final productName =
            pm['nameKo'] as String? ?? pm['name'] as String? ?? pid;

        // variants 서브컬렉션에서 첫 번째 변형만 사용 (대표 변형)
        final variantSnap =
            await p.reference.collection('variants').limit(1).get();
        if (variantSnap.docs.isEmpty) {
          // 변형이 없으면 이 상품은 스킵
          continue;
        }

        final v = variantSnap.docs.first;
        final vm = v.data();
        final gradePrices =
            vm['gradePrices'] as Map<String, dynamic>? ?? <String, dynamic>{};
        final basePriceNum =
            (gradePrices[tier] ?? gradePrices[tier.toLowerCase()] ?? 0) as num;
        final basePrice = basePriceNum.toInt();

        _items.add(
          _OverrideItem(
            productId: pid,
            name: productName,
            basePrice: basePrice,
          ),
        );
      }

      // 4) 각 상품별 컨트롤러 생성 (기존 개별단가 있으면 기본값으로)
      for (final item in _items) {
        final override = _overrides[item.productId];
        _controllers[item.productId] = TextEditingController(
          text: override?.toString() ?? '',
        );
      }
    } catch (e) {
      debugPrint('❌ 개별단가 로드 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('개별단가를 불러오는 중 오류가 발생했습니다: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final db = FirebaseFirestore.instance;
      final clientRef = db
          .collection('branches')
          .doc(widget.branchId)
          .collection('clients')
          .doc(widget.clientCode);

      // TextField 값 → 새로운 overrides 맵
      final newMap = <String, int>{};
      _controllers.forEach((pid, ctrl) {
        final text = ctrl.text.trim();
        if (text.isEmpty) return;
        final v = int.tryParse(text);
        if (v != null && v > 0) {
          newMap[pid] = v;
        }
      });

      await clientRef.set(
        {
          'priceOverrides': newMap,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('개별 단가가 저장되었습니다.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('❌ 개별단가 저장 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 중 오류가 발생했습니다: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tier = widget.priceTier.toUpperCase();
    return Scaffold(
      appBar: AppBar(
        title: Text('개별 단가 - ${widget.clientName}'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(12.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: '저장',
              onPressed: _save,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('등록된 상품이 없습니다.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (_, i) {
                    final item = _items[i];
                    final ctrl = _controllers[item.productId]!;

                    return ListTile(
                      title: Text(item.name),
                      subtitle:
                          Text('표준단가($tier): ${item.basePrice}원'),
                      trailing: SizedBox(
                        width: 120,
                        child: TextField(
                          controller: ctrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '개별 단가',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
