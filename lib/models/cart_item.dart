class CartItem {
  final String productId;
  final String productName;
  final int price;   // 단가
  int quantity;      // 수량 (변경 가능)
  final String emoji;

  CartItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    required this.emoji,
  });

  /// 합계 (단가 × 수량)
  int get totalPrice => price * quantity;

  /// Firestore → CartItem
  factory CartItem.fromMap(Map<String, dynamic> map) {
    return CartItem(
      productId: map['productId'] ?? '',
      productName: map['productName'] ?? '',
      price: (map['price'] ?? 0) is int
          ? map['price'] ?? 0
          : int.tryParse(map['price'].toString()) ?? 0,
      quantity: (map['quantity'] ?? 0) is int
          ? map['quantity'] ?? 0
          : int.tryParse(map['quantity'].toString()) ?? 0,
      emoji: map['emoji'] ?? '📦',
    );
  }

  /// CartItem → Firestore
  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'price': price,
      'quantity': quantity,
      'emoji': emoji,
    };
  }
}
