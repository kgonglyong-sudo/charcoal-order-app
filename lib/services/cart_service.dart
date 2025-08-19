// lib/services/cart_service.dart
import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../models/cart_item.dart';
import '../models/product.dart';

class CartService with ChangeNotifier {
  final List<CartItem> _items = [];

  /// 외부에서 수정 불가한 읽기 전용 리스트
  UnmodifiableListView<CartItem> get items => UnmodifiableListView(_items);

  /// 라인 수(품목 종류 수)
  int get itemCount => _items.length;

  /// 총 수량(품목 수량의 합)
  int get totalQuantity => _items.fold(0, (sum, it) => sum + it.quantity);

  /// 총 금액
  int get totalAmount => _items.fold(0, (sum, it) => sum + it.totalPrice);

  /// 기존: 등급 기반 단가 계산하여 담기
  void addItem(Product product, String priceTier) {
    final price = product.getPriceForTier(priceTier);
    _addOrInc(product: product, unitPrice: price);
  }

  /// 신규: 화면에서 계산된 단가를 그대로 담기
  void addItemWithPrice(Product product, int unitPrice) {
    _addOrInc(product: product, unitPrice: unitPrice);
  }

  /// 공통 내부 함수: 동일 productId 존재 시 수량 +1, 없으면 새로 추가
  void _addOrInc({required Product product, required int unitPrice}) {
    final idx = _items.indexWhere((it) => it.productId == product.id);
    if (idx >= 0) {
      // 이미 있는 경우: 최초 담을 때의 단가 유지, 수량만 증가
      _items[idx].quantity++;
    } else {
      _items.add(CartItem(
        productId: product.id,
        productName: product.name,
        price: unitPrice < 0 ? 0 : unitPrice,
        quantity: 1,
        emoji: product.emoji,
      ));
    }
    notifyListeners();
  }

  /// 수량 설정 (0 이하면 해당 품목 제거)
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

  /// 수량 +1
  void incrementQuantity(String productId) {
    final index = _items.indexWhere((item) => item.productId == productId);
    if (index >= 0) {
      _items[index].quantity++;
      notifyListeners();
    }
  }

  /// 수량 -1 (0 이하가 되면 자동 제거)
  void decrementQuantity(String productId) {
    final index = _items.indexWhere((item) => item.productId == productId);
    if (index >= 0) {
      final q = _items[index].quantity - 1;
      if (q <= 0) {
        _items.removeAt(index);
      } else {
        _items[index].quantity = q;
      }
      notifyListeners();
    }
  }

  /// 라인 단가 수정 (price가 final 이므로 새 CartItem으로 교체)
  void setItemPrice(String productId, int newUnitPrice) {
    final index = _items.indexWhere((item) => item.productId == productId);
    if (index < 0) return;

    final it = _items[index];
    final sanitized = newUnitPrice < 0 ? 0 : newUnitPrice;

    _items[index] = CartItem(
      productId: it.productId,
      productName: it.productName,
      price: sanitized,
      quantity: it.quantity,
      emoji: it.emoji,
    );

    notifyListeners();
  }

  /// 품목 제거
  void removeItem(String productId) {
    _items.removeWhere((item) => item.productId == productId);
    notifyListeners();
  }

  /// 장바구니 비우기
  void clear() {
    _items.clear();
    notifyListeners();
  }

  /// 헬퍼: 품목 존재 여부
  bool hasItem(String productId) =>
      _items.any((it) => it.productId == productId);
}
