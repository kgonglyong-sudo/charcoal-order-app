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
      date: DateTime.parse(map['date']),
      items: (map['items'] as List<dynamic>? ?? [])
          .map((item) => CartItem.fromMap(item))
          .toList(),
      total: map['total'] ?? 0,
      status: map['status'] ?? '주문완료',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'clientCode': clientCode,
      'date': date.toIso8601String(),
      'items': items.map((item) => item.toMap()).toList(),
      'total': total,
      'status': status,
    };
  }
}