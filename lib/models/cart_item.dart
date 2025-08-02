class CartItem {
  final String productId;
  final String productName;
  final int price;
  int quantity;
  final String emoji;

  CartItem({
    required this.productId,
    required this.productName,
    required this.price,
    this.quantity = 1,
    this.emoji = '🪵',
  });

  int get totalPrice => price * quantity;

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'price': price,
      'quantity': quantity,
      'emoji': emoji,
    };
  }

  factory CartItem.fromMap(Map<String, dynamic> map) {
    return CartItem(
      productId: map['productId'] ?? '',
      productName: map['productName'] ?? '',
      price: map['price'] ?? 0,
      quantity: map['quantity'] ?? 1,
      emoji: map['emoji'] ?? '🪵',
    );
  }
}