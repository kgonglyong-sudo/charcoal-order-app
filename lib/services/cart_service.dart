import 'package:flutter/foundation.dart';
import '../models/cart_item.dart';
import '../models/product.dart';

class CartService with ChangeNotifier {
  List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);
  
  int get itemCount => _items.length;
  
  int get totalAmount => _items.fold(0, (sum, item) => sum + item.totalPrice);

  void addItem(Product product, String priceTier) {
    final price = product.getPriceForTier(priceTier);
    final existingIndex = _items.indexWhere(
      (item) => item.productId == product.id,
    );

    if (existingIndex >= 0) {
      _items[existingIndex].quantity++;
    } else {
      _items.add(CartItem(
        productId: product.id,
        productName: product.name,
        price: price,
        quantity: 1,
        emoji: product.emoji,
      ));
    }
    notifyListeners();
  }

  void updateQuantity(String productId, int newQuantity) {
    if (newQuantity <= 0) {
      removeItem(productId);
      return;
    }

    final index = _items.indexWhere((item) => item.productId == productId);
    if (index >= 0) {
      _items[index].quantity = newQuantity;
      notifyListeners();
    }
  }

  void removeItem(String productId) {
    _items.removeWhere((item) => item.productId == productId);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}