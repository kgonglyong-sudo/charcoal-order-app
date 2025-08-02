import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../services/database_service.dart';
import '../models/order.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  final DatabaseService _databaseService = DatabaseService();
  List<Order> _orders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final orders = await _databaseService.getOrders(authService.currentClient!.code);
      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('주문 내역을 불러오는데 실패했습니다: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('주문 내역'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 80,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16),
                      Text(
                        '주문 내역이 없습니다',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _orders.length,
                  itemBuilder: (context, index) {
                    final order = _orders[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.orange.shade100,
                          child: const Icon(
                            Icons.receipt,
                            color: Colors.orange,
                          ),
                        ),
                        title: Text(
                          '주문 #${order.id.substring(order.id.length - 6)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('yyyy-MM-dd HH:mm').format(order.date),
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                            Text(
                              '총 ${order.total.toString().replaceAllMapped(
                                RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                                (Match m) => '${m[1]},',
                              )}원',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                order.status,
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const Icon(Icons.expand_more),
                          ],
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '주문 상품',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...order.items.map((item) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Row(
                                        children: [
                                          Text(item.emoji),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(item.productName),
                                          ),
                                          Text('${item.quantity}개'),
                                          const SizedBox(width: 16),
                                          Text(
                                            '${item.totalPrice.toString().replaceAllMapped(
                                              RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                                              (Match m) => '${m[1]},',
                                            )}원',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                                const Divider(),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => _reorder(order),
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('다시 주문'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  void _reorder(Order order) {
    final cartService = Provider.of<CartService>(context, listen: false);
    
    // 장바구니 비우기
    cartService.clear();
    
    // 이전 주문 상품들을 장바구니에 추가
    for (final item in order.items) {
      // 기존 CartItem을 그대로 추가하기 위해 직접 추가
      cartService.items.add(item);
    }
    
    // 상태 업데이트
    cartService.notifyListeners();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('이전 주문이 장바구니에 추가되었습니다'),
        duration: Duration(seconds: 2),
      ),
    );
    
    // 장바구니 화면으로 이동
    Navigator.of(context).pushNamed('/cart');
  }
}
