// lib/services/order_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class OrderService {
  OrderService._();
  static final instance = OrderService._(); // 싱글턴처럼 편히 쓰기: OrderService.instance

  final _db = FirebaseFirestore.instance;

  /// 주문 생성
  /// - createdAt: serverTimestamp 자동
  /// - branchId: 반드시 전달 (AuthService에서 가져온 사용자 지점)
  /// - clientCode: 거래처 코드(클라이언트 앱이면 로그인 사용자 코드를 넣기)
  /// - items: [{productId, productName, price, quantity}, ...]
  /// - total: null이면 price*qty로 자동 계산
  Future<DocumentReference<Map<String, dynamic>>> createOrder({
    required String branchId,
    required String clientCode,
    required List<Map<String, dynamic>> items,
    int? total,
    String initialStatus = '주문완료',
  }) async {
    final calcTotal = total ?? _calcTotal(items);

    final ref = _db
        .collection('branches')
        .doc(branchId)
        .collection('orders')
        .doc(); // 자동 ID

    await ref.set({
      'branchId': branchId,                      // ✅ 지점
      'clientCode': clientCode,                  // ✅ 거래처
      'items': items,
      'total': calcTotal,
      'status': initialStatus,
      'createdAt': FieldValue.serverTimestamp(), // ✅ 생성 시각
    });

    return ref;
  }

  /// (옵션) 주문 상태 변경 — 매니저/관리자 전용
  Future<void> updateStatus({
    required String branchId,
    required String orderId,
    required String nextStatus,
  }) {
    return _db
        .collection('branches')
        .doc(branchId)
        .collection('orders')
        .doc(orderId)
        .update({'status': nextStatus});
  }

  int _calcTotal(List<Map<String, dynamic>> items) {
    var sum = 0;
    for (final e in items) {
      final p = (e['price'] as num?)?.toInt() ?? 0;
      final q = (e['quantity'] as num?)?.toInt() ?? 0;
      sum += p * q;
    }
    return sum;
  }
}
