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
      total: map['total'] ?? 0,
      status: map['status'] ?? '주문완료',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'clientCode': clientCode,
      // Firestore에서 Timestamp로 저장되도록 변환
      'date': Timestamp.fromDate(date),
      'items': items.map((item) => item.toMap()).toList(),
      'total': total,
      'status': status,
    };
  }

  /// date 필드 안전하게 파싱 (Timestamp or String or DateTime)
  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}
