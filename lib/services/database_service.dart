import '../models/product.dart';
import '../models/order.dart';
import '../models/cart_item.dart';

class DatabaseService {
  // 임시 데이터 (나중에 Firebase로 대체)
  static final List<Product> _sampleProducts = [
    Product(
      id: 'P001',
      name: '참숯 1급',
      prices: {'A': 15000, 'B': 14000, 'C': 13000},
      emoji: '🪵',
    ),
    Product(
      id: 'P002',
      name: '참숯 2급',
      prices: {'A': 12000, 'B': 11000, 'C': 10000},
      emoji: '🪵',
    ),
    Product(
      id: 'P003',
      name: '백탄',
      prices: {'A': 18000, 'B': 17000, 'C': 16000},
      emoji: '⚫',
    ),
    Product(
      id: 'P004',
      name: '흑탄',
      prices: {'A': 10000, 'B': 9500, 'C': 9000},
      emoji: '⚫',
    ),
    Product(
      id: 'P005',
      name: '대나무숯',
      prices: {'A': 13000, 'B': 12500, 'C': 12000},
      emoji: '🎋',
    ),
  ];

  static List<Order> _sampleOrders = [
    Order(
      id: 'O001',
      clientCode: 'CLIENT001',
      date: DateTime.now().subtract(const Duration(days: 7)),
      items: [
        CartItem(
          productId: 'P001',
          productName: '참숯 1급',
          price: 15000,
          quantity: 5,
          emoji: '🪵',
        ),
        CartItem(
          productId: 'P003',
          productName: '백탄',
          price: 18000,
          quantity: 2,
          emoji: '⚫',
        ),
      ],
      total: 111000,
      status: '완료',
    ),
  ];

  // 상품 목록 가져오기
  Future<List<Product>> getProducts() async {
    await Future.delayed(const Duration(milliseconds: 500)); // 로딩 시뮬레이션
    return _sampleProducts;
  }

  // 주문 내역 가져오기
  Future<List<Order>> getOrders(String clientCode) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return _sampleOrders.where((order) => order.clientCode == clientCode).toList();
  }

  // 주문 생성
  Future<String> createOrder(Order order) async {
    await Future.delayed(const Duration(seconds: 1)); // 저장 시뮬레이션
    _sampleOrders.add(order);
    return order.id;
  }
}