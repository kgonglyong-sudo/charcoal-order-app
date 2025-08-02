import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../services/database_service.dart';
import '../models/product.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final DatabaseService _databaseService = DatabaseService();
  List<Product> _products = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await _databaseService.getProducts();
      setState(() {
        _products = products;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('상품을 불러오는데 실패했습니다: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('상품 목록'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          // 장바구니 아이콘
          Consumer<CartService>(
            builder: (context, cartService, child) {
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.shopping_cart),
                    onPressed: () {
                      Navigator.of(context).pushNamed('/cart');
                    },
                  ),
                  if (cartService.itemCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '${cartService.itemCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          // 주문내역 버튼
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.of(context).pushNamed('/orders');
            },
          ),
          // 로그아웃 버튼
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Provider.of<AuthService>(context, listen: false).logout();
              Navigator.of(context).pushReplacementNamed('/login');
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Consumer<AuthService>(
              builder: (context, authService, child) {
                final client = authService.currentClient!;
                return Column(
                  children: [
                    // 거래처 정보 헤더
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: Colors.orange.shade50,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${client.name} (${client.code})',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '등급: ${client.priceTier}급 - 특별 할인가 적용',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 상품 목록
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _products.length,
                        itemBuilder: (context, index) {
                          final product = _products[index];
                          final price = product.getPriceForTier(client.priceTier);
                          
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.orange.shade100,
                                child: Text(
                                  product.emoji,
                                  style: const TextStyle(fontSize: 24),
                                ),
                              ),
                              title: Text(
                                product.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                '${price.toString().replaceAllMapped(
                                  RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                                  (Match m) => '${m[1]},',
                                )}원',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              trailing: ElevatedButton(
                                onPressed: () {
                                  Provider.of<CartService>(context, listen: false)
                                      .addItem(product, client.priceTier);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('${product.name}이(가) 장바구니에 추가되었습니다'),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('담기'),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
