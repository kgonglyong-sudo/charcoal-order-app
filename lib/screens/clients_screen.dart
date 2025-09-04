// lib/screens/clients_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
// ✅ client_edit_screen.dart 파일 임포트
import 'client_edit_screen.dart';

/// 컬렉션 구조:
/// branches/{branchId}/clients/{clientCode}
/// 필드:
/// - clientCode, name, priceTier(A/B/C), memo?, createdAt, updatedAt, active
/// - bizNo, address, managerPhone, orderPhone, email
/// - priceOverrides:   { productId: int }          // 구버전(변형 없음)
/// - priceOverridesV2: { 'pid|vid': int }          // 신규(변형 단위)
/// - deliveryDays: [1..7]  // 1=월 ... 7=일
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
                    final isPaymentRequired = (m['isPaymentRequired'] as bool?) ?? true;

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

  // ✅ _openClientEditor 함수를 Dialog로 변경
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
  
  void _openPriceOverrides(
    BuildContext context,
    String branchId,
    String clientCode,
    String tier,
  ) async {
    // 이전에 있던 개별단가 편집 로직을 여기에 구현하세요.
    // 현재는 ClientEditScreen으로 이동하는 로직만 포함되어 있습니다.
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('기능 구현 필요'),
        content: const Text('개별 단가 편집 기능은 아직 구현되지 않았습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기')),
        ],
      ),
    );
  }
}