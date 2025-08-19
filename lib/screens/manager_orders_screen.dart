// lib/screens/manager_orders_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class ManagerOrdersScreen extends StatefulWidget {
  const ManagerOrdersScreen({super.key});
  @override
  State<ManagerOrdersScreen> createState() => _ManagerOrdersScreenState();
}

class _ManagerOrdersScreenState extends State<ManagerOrdersScreen> {
  String _statusFilter = '전체'; // 전체/입금대기/주문완료

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final branchId = auth.branchId ?? '';

    if (branchId.isEmpty) {
      return const Scaffold(body: Center(child: Text('지점 정보가 없습니다. /user/{uid}.branchId 확인')));
    }

    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('orders')
        .orderBy('createdAt', descending: true);

    // 상태 필터: Firestore 쿼리로 거름 (복합 인덱스 필요할 수 있음)
    if (_statusFilter != '전체') {
      q = q.where('status', isEqualTo: _statusFilter);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('주문 관리 · $branchId'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            initialValue: _statusFilter,
            onSelected: (v) => setState(() => _statusFilter = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: '전체', child: Text('전체')),
              PopupMenuItem(value: '입금대기', child: Text('입금대기')),
              PopupMenuItem(value: '주문완료', child: Text('주문완료')),
            ],
            icon: const Icon(Icons.filter_list),
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('불러오기 실패: ${snap.error}'));
          }
          final docs = snap.data?.docs ?? const [];

          if (docs.isEmpty) return const Center(child: Text('주문이 없습니다.'));

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final ref = docs[i].reference;
              final d = docs[i].data();
              final orderId = docs[i].id;
              final client = (d['clientCode'] as String?) ?? '';
              final created = (d['createdAt'] as Timestamp?)?.toDate().toLocal();
              final items = (d['items'] as List?)?.cast<Map>() ?? const [];
              final total = (d['total'] as num?)?.toInt() ?? 0;
              final status = (d['status'] as String?) ?? '-';
              final payment = (d['payment'] as Map?) ?? {};
              final method = (payment['method'] ?? '-').toString();

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('#$orderId', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        if (client.isNotEmpty) Text('• $client'),
                        const Spacer(),
                        if (created != null)
                          Text('${created.year}-${_2(created.month)}-${_2(created.day)} ${_2(created.hour)}:${_2(created.minute)}',
                              style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        items.map((e) {
                          final name = (e['productName'] as String?) ?? '';
                          final qty = (e['quantity'] as num?)?.toInt() ?? 0;
                          return '$name x$qty';
                        }).join(', '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _StatusChip(status: status),
                          const Spacer(),
                          Text('결제수단: $method', style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 12),
                          Text('${_comma(total)}원', style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: status == '입금대기'
                                ? () => _updateStatus(ref, '주문완료')
                                : null,
                            icon: const Icon(Icons.check),
                            label: const Text('입금확인 → 주문완료'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: status != '입금대기'
                                ? () => _updateStatus(ref, '입금대기')
                                : null,
                            icon: const Icon(Icons.undo),
                            label: const Text('입금대기 전환'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _updateStatus(DocumentReference<Map<String, dynamic>> ref, String next) async {
    await ref.update({
      'status': next,
      'payment.status': next == '입금대기' ? '입금대기' : '결제완료(확인)',
      'payment.updatedAt': FieldValue.serverTimestamp(),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('상태가 "$next"(으)로 변경되었습니다.')));
  }

  static String _2(int v) => v.toString().padLeft(2, '0');
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});
  @override
  Widget build(BuildContext context) {
    Color c = Colors.grey;
    if (status == '입금대기') c = Colors.amber;
    if (status == '주문완료') c = Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withOpacity(.3)),
      ),
      child: Text(status, style: TextStyle(color: c, fontSize: 12)),
    );
  }
}

String _comma(int n) =>
    n.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
