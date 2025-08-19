// lib/services/database_service.dart
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import '../models/product.dart';
import '../models/order.dart';
import '../models/cart_item.dart';

class DatabaseService {
  final _db = fs.FirebaseFirestore.instance;

  // ===== 임시 상품/주문 데이터 (데모/폴백용) =====
  static final List<Product> _sampleProducts = [
    Product(id: 'P001', name: '라오스비장탄', prices: {'A': 21000, 'B': 22000, 'C': 21500}, emoji: '🪵'),
    Product(id: 'P002', name: '리치 비장탄', prices: {'A': 19000, 'B': 20000, 'C': 19500}, emoji: '🪵'),
    Product(id: 'P003', name: '두번구운 라오스', prices: {'A': 21000, 'B': 20000, 'C': 19000}, emoji: '⚫'),
    Product(id: 'P004', name: '열탄',       prices: {'A': 12000, 'B': 11500, 'C': 12000}, emoji: '⚫'),
    Product(id: 'P005', name: '대나무숯',   prices: {'A': 13500, 'B': 14500, 'C': 15000}, emoji: '🎋'),
  ];

  static List<Order> _sampleOrders = [
    Order(
      id: 'O001',
      clientCode: 'CLIENT001',
      date: DateTime.now().subtract(const Duration(days: 7)),
      items: [
        CartItem(productId: 'P001', productName: '참숯 1급', price: 15000, quantity: 5, emoji: '🪵'),
        CartItem(productId: 'P003', productName: '백탄',     price: 18000, quantity: 2, emoji: '⚫'),
      ],
      total: 111000,
      status: '완료',
    ),
  ];

  // ===== 상품: 전사 공용 products 컬렉션 사용 =====
  Future<List<Product>> getProducts() async {
    try {
      // 정렬은 sortOrder 기준, 이름 보조정렬은 메모리에서 처리
      final snap = await _db.collection('products').orderBy('sortOrder').get();

      int _asInt(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);

      final docs = snap.docs.toList()
        ..sort((a, b) {
          final am = a.data();
          final bm = b.data();
          final ao = _asInt(am['sortOrder']);
          final bo = _asInt(bm['sortOrder']);
          if (ao != bo) return ao.compareTo(bo);
          final an = (am['nameKo'] ?? am['name'] ?? a.id).toString();
          final bn = (bm['nameKo'] ?? bm['name'] ?? b.id).toString();
          return an.compareTo(bn);
        });

      final out = <Product>[];
      for (final d in docs) {
        final m = d.data();

        // 삭제/비활성 제외(클라이언트 필터)
        if (m['deletedAt'] != null) continue;
        if ((m['active'] ?? true) == false) continue;

        final id = d.id;
        final nameKo = (m['nameKo'] as String?)?.trim();
        final nameEn = (m['name'] as String?)?.trim();
        final name = (nameKo?.isNotEmpty == true)
            ? nameKo!
            : (nameEn?.isNotEmpty == true ? nameEn! : id);

        final emoji = (m['emoji'] as String?)?.trim() ?? '🧱';

        // 표준단가 맵 변환 (prices.{A,B,C} 우선, 없으면 priceA/B/C 폴백)
        final pricesMap = <String, int>{'A': 0, 'B': 0, 'C': 0};
        final pricesRaw = (m['prices'] as Map?) ?? const {};
        int _pick(Map src, String key, dynamic legacy) {
          final v = src[key] ?? src[key.toUpperCase()];
          if (v is num) return v.toInt();
          if (legacy is num) return (legacy as num).toInt();
          return 0;
        }

        pricesMap['A'] = _pick(pricesRaw, 'A', m['priceA']);
        pricesMap['B'] = _pick(pricesRaw, 'B', m['priceB']);
        pricesMap['C'] = _pick(pricesRaw, 'C', m['priceC']);

        out.add(Product(
          id: id,
          name: name,
          emoji: emoji,
          prices: pricesMap,
        ));
      }

      // 비어있으면 샘플로 폴백(초기 세팅 단계 대비)
      if (out.isEmpty) return _sampleProducts;

      return out;
    } catch (_) {
      // 에러시 샘플 폴백
      return _sampleProducts;
    }
  }

  // ===== (기존) 목데이터 주문 =====
  Future<List<Order>> getOrders(String clientCode) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return _sampleOrders.where((o) => o.clientCode == clientCode).toList();
    // ※ 실제 운영에선 getOrdersByBranchAndClient 사용 권장
  }

  // ===== Firestore: 내 지점 + 내 코드 주문 조회(정렬) =====
  Future<List<Order>> getOrdersByBranchAndClient({
    required String branchId,
    required String clientCode,
  }) async {
    try {
      final snap = await _db
          .collection('branches')
          .doc(branchId)
          .collection('orders')
          .where('clientCode', isEqualTo: clientCode)
          .orderBy('createdAt', descending: true)
          .get();

      return snap.docs.map(_orderFromDoc).toList();
    } on fs.FirebaseException catch (e) {
      // 인덱스 없을 때 임시 우회(메모리 정렬)
      if (e.code == 'failed-precondition') {
        final snap = await _db
            .collection('branches')
            .doc(branchId)
            .collection('orders')
            .where('clientCode', isEqualTo: clientCode)
            .get();
        final list = snap.docs.map(_orderFromDoc).toList();
        list.sort((a, b) => b.date.compareTo(a.date));
        return list;
      }
      rethrow;
    }
  }

  // ===== Firestore: 기간 필터 포함 =====
  Future<List<Order>> getOrdersByBranchAndClientInRange({
    required String branchId,
    required String clientCode,
    required DateTime start, // 포함
    required DateTime end,   // 미포함 [start, end)
  }) async {
    try {
      final snap = await _db
          .collection('branches')
          .doc(branchId)
          .collection('orders')
          .where('clientCode', isEqualTo: clientCode)
          .where('createdAt', isGreaterThanOrEqualTo: fs.Timestamp.fromDate(start.toUtc()))
          .where('createdAt', isLessThan: fs.Timestamp.fromDate(end.toUtc()))
          .orderBy('createdAt', descending: true)
          .get();

      return snap.docs.map(_orderFromDoc).toList();
    } on fs.FirebaseException catch (e) {
      if (e.code == 'failed-precondition') {
        final snap = await _db
            .collection('branches')
            .doc(branchId)
            .collection('orders')
            .where('clientCode', isEqualTo: clientCode)
            .where('createdAt', isGreaterThanOrEqualTo: fs.Timestamp.fromDate(start.toUtc()))
            .where('createdAt', isLessThan: fs.Timestamp.fromDate(end.toUtc()))
            .get();
        final list = snap.docs.map(_orderFromDoc).toList();
        list.sort((a, b) => b.date.compareTo(a.date));
        return list;
      }
      rethrow;
    }
  }

  // ===== 문서 -> 모델 매핑 =====
  Order _orderFromDoc(fs.QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();

    // createdAt -> DateTime
    DateTime date;
    final created = data['createdAt'];
    if (created is fs.Timestamp) {
      date = created.toDate();
    } else if (created is DateTime) {
      date = created;
    } else {
      date = DateTime.now();
    }

    // items -> List<CartItem>
    final rawItems = (data['items'] as List?) ?? const [];
    final items = rawItems.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return CartItem(
        productId: (m['productId'] as String?) ?? '',
        productName: (m['productName'] as String?) ?? '',
        price: (m['price'] as num?)?.toInt() ?? 0,
        quantity: (m['quantity'] as num?)?.toInt() ?? 0,
        emoji: (m['emoji'] as String?) ?? '',
      );
    }).toList();

    // total은 항상 int
    final int total = (data['total'] is num)
        ? (data['total'] as num).toInt()
        : items.fold<int>(0, (s, it) => s + (it.price * it.quantity));

    return Order(
      id: d.id,
      clientCode: (data['clientCode'] as String?) ?? '',
      date: date,
      items: items,
      total: total,
      status: (data['status'] as String?) ?? '주문완료',
    );
  }

  // ===== 주문 생성 (현재는 목데이터에만 추가) =====
  Future<String> createOrder(Order order) async {
    await Future.delayed(const Duration(seconds: 1)); // 저장 시뮬
    _sampleOrders.add(order);
    return order.id;
  }
}
