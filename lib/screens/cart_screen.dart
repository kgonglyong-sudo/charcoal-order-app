import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/cart_service.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/order.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('장바구니'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: Consumer<CartService>(
        builder: (context, cartService, child) {
          if (cartService.items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 80,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    '장바구니가 비어있습니다',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: cartService.items.length,
                  itemBuilder: (context, index) {
                    final item = cartService.items[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            // 상품 정보
                            CircleAvatar(
                              backgroundColor: Colors.orange.shade100,
                              child: Text(
                                item.emoji,
                                style: const TextStyle(fontSize: 20),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    '${item.price.toString().replaceAllMapped(
                                      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                                      (Match m) => '${m[1]},',
                                    )}원',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 수량 조절
                            Row(
                              children: [
                                IconButton(
                                  onPressed: () {
                                    cartService.updateQuantity(
                                      item.productId,
                                      item.quantity - 1,
                                    );
                                  },
                                  icon: const Icon(Icons.remove_circle_outline),
                                  color: Colors.orange,
                                ),
                                Text(
                                  '${item.quantity}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    cartService.updateQuantity(
                                      item.productId,
                                      item.quantity + 1,
                                    );
                                  },
                                  icon: const Icon(Icons.add_circle_outline),
                                  color: Colors.orange,
                                ),
                              ],
                            ),
                            // 삭제 버튼
                            IconButton(
                              onPressed: () {
                                cartService.removeItem(item.productId);
                              },
                              icon: const Icon(Icons.delete_outline),
                              color: Colors.red,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // 하단 주문 정보
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.3),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '총 금액',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${cartService.totalAmount.toString().replaceAllMapped(
                            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                            (Match m) => '${m[1]},',
                          )}원',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _placeOrder(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '주문하기',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _placeOrder(BuildContext context) async {
    final cartService = Provider.of<CartService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final databaseService = DatabaseService();

    if (cartService.items.isEmpty) return;

    // 로딩 다이얼로그 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('주문 처리 중...'),
          ],
        ),
      ),
    );

    try {
      final order = Order(
        id: 'O${DateTime.now().millisecondsSinceEpoch}',
        clientCode: authService.currentClient!.code,
        date: DateTime.now(),
        items: List.from(cartService.items),
        total: cartService.totalAmount,
      );

      await databaseService.createOrder(order);

      if (context.mounted) {
        Navigator.of(context).pop(); // 로딩 다이얼로그 닫기
        
        // 성공 다이얼로그
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('주문 완료'),
            content: const Text('주문이 성공적으로 접수되었습니다.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // 다이얼로그 닫기
                  cartService.clear(); // 장바구니 비우기
                  Navigator.of(context).pop(); // 장바구니 화면 닫기
                },
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // 로딩 다이얼로그 닫기
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('주문 처리 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }
}
