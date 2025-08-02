class Product {
  final String id;
  final String name;
  final Map<String, int> prices; // {A: 15000, B: 14000, C: 13000}
  final String? imageUrl;
  final String emoji; // 임시 이미지용

  Product({
    required this.id,
    required this.name,
    required this.prices,
    this.imageUrl,
    this.emoji = '🪵',
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      prices: Map<String, int>.from(map['prices'] ?? {}),
      imageUrl: map['imageUrl'],
      emoji: map['emoji'] ?? '🪵',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'prices': prices,
      'imageUrl': imageUrl,
      'emoji': emoji,
    };
  }

  int getPriceForTier(String tier) {
    return prices[tier] ?? prices['C'] ?? 0;
  }
}