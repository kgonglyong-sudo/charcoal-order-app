import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/auth_service.dart';
import '../models/order.dart' as my_order;

class OrderHistoryScreen extends StatelessWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final client = auth.currentClient;

    if (client == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('주문 내역')),
        body: const Center(child: Text('로그인이 필요합니다.')),
      );
    }

    final branchId = client.branchId;
    final clientCode = client.code;

    final q = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('orders')
        .where('clientCode', isEqualTo: clientCode)
        .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('주문 내역'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? const [];

          if (docs.isEmpty) {
            return const Center(child: Text('주문 내역이 없습니다.'));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (_, i) {
              final d = docs[i];
              final m = d.data();

              // 모델로 변환(필요 시 간소화)
              final order = my_order.Order.fromMap({
                'id': d.id,
                'clientCode': m['clientCode'] ?? '',
                'date': (m['createdAt'] as Timestamp?)?.toDate().toIso8601String() ??
                    DateTime.now().toIso8601String(),
                'items': (m['items'] as List?) ?? const [],
                'total': (m['total'] as num?)?.toInt() ?? 0,
                'status': m['status'] ?? '주문완료',
              });

              String _comma(int n) => n
                  .toString()
                  .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

              return ListTile(
                title: Text('주문번호: ${order.id}'),
                subtitle: Text(
                  '상태: ${order.status}\n합계: ${_comma(order.total)}원\n일자: ${order.date.toLocal()}',
                ),
                isThreeLine: true,
                onTap: () {},
              );
            },
          );
        },
      ),
    );
  }
}
