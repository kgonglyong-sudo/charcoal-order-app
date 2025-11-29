// lib/models/order.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'cart_item.dart';

class Order {
  final String id;
  final String clientCode;
  final DateTime date;
  final List<CartItem> items;
  final int total;
  final String status;

  Order({
    required this.id,
    required this.clientCode,
    required this.date,
    required this.items,
    required this.total,
    this.status = '주문완료',
  });

  factory Order.fromMap(Map<String, dynamic> map) {
    return Order(
      id: map['id'] ?? '',
      clientCode: map['clientCode'] ?? '',
      date: _parseDate(map['date']),
      items: (map['items'] as List<dynamic>? ?? [])
          .map((item) => CartItem.fromMap(item as Map<String, dynamic>))
          .toList(),
      total: (map['total'] as num?)?.toInt() ?? 0,
      status: map['status'] ?? '주문완료',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      // id는 문서 ID로 쓰고, 필드엔 안 넣어도 됨 (넣고 싶으면 아래 줄 주석 해제)
      // 'id': id,
      'clientCode': clientCode,
      // createdAt/date 둘 중 하나만 쓰면 되지만,
      // 지금 주문내역 쿼리는 createdAt으로 정렬하니까 둘 다 넣어주는 것도 괜찮음
      'date': Timestamp.fromDate(date),
      'createdAt': Timestamp.fromDate(date),
      'items': items.map((item) => item.toMap()).toList(),
      'total': total,
      'status': status,
    };
  }

  /// date 필드 안전하게 파싱
  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}
