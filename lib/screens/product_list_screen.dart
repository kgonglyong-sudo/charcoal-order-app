// lib/screens/product_list_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../services/database_service.dart';
import '../models/product.dart';
import '../models/client.dart';
import '../utils/pricing.dart';
import 'login_screen.dart';

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
      if (!mounted) return;
      setState(() {
        _products = products;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('상품을 불러오는데 실패했습니다: $e')),
      );
    }
  }

  Future<void> _handleSignOut(BuildContext context) async {
    await context.read<AuthService>().signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  String _fmtYmd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final da = d.day.toString().padLeft(2, '0');
    return '$y-$m-$da';
  }

  String _weekdayLabel(int w) =>
      const {1: '월', 2: '화', 3: '수', 4: '목', 5: '금', 6: '토', 7: '일'}[w] ?? '$w';

  String _won(int v) =>
      '${v.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('상품 목록'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          Consumer<CartService>(
            builder: (context, cartService, child) {
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.shopping_cart),
                    onPressed: () => Navigator.of(context).pushNamed('/cart'),
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
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          '${cartService.itemCount}',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).pushNamed('/orders'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _handleSignOut(context),
            tooltip: '로그아웃',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Consumer<AuthService>(
              builder: (context, authService, child) {
                final client = authService.currentClient;
                if (client == null) {
                  return const Center(
                    child: Text('클라이언트 정보가 없습니다. 다시 로그인해주세요.'),
                  );
                }

                final days = client.deliveryDays;
                final next = Client.nextDeliveryDate(DateTime.now(), days);
                final nextText =
                    (next == null) ? '배송 요일 미지정' : '${_fmtYmd(next)} (${_weekdayLabel(next.weekday)})';

                return FutureBuilder<_PricingCtx>(
                  future: _loadPricingCtxForList(
                    branchId: client.branchId,
                    clientCode: client.code,
                    clientTier: client.priceTier,
                    products: _products,
                  ),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snap.hasData) {
                      return const Center(child: Text('가격 정보를 불러오지 못했습니다.'));
                    }
                    final pctx = snap.data!;

                    // 0원 제품은 숨기기 (표준/개별단가 모두 없으면 비표시)
                    final visible = _products.where((p) {
                      final priceOrNull = pctx.displayPriceOrNull(p.id);
                      return priceOrNull != null && priceOrNull > 0;
                    }).toList();

                    return Column(
                      children: [
                        // 상단 고객/소속/다음 배송일 정보
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          color: Colors.orange.shade50,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${client.name} (${client.code.isNotEmpty ? client.code : '로그인 계정'})',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              Text('소속 지점: ${client.branchId}', style: const TextStyle(fontSize: 14)),
                              Text(
                                '다음 배송일: $nextText',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 리스트
                        Expanded(
                          child: visible.isEmpty
                              ? const Center(child: Text('표시할 상품이 없습니다.\n(표준단가/개별단가를 확인하세요)'))
                              : ListView.builder(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: visible.length,
                                  itemBuilder: (context, index) {
                                    final product = visible[index];
                                    final pid = product.id;

                                    final hasVariants = pctx.hasVariants(pid);
                                    final unitPrice =
                                        pctx.displayPriceOrNull(pid) ?? 0; // 변형있으면 첫 활성 변형 기준가
                                    final priceText = _won(unitPrice);

                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      child: ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: Colors.orange.shade100,
                                          child: Text(product.emoji, style: const TextStyle(fontSize: 24)),
                                        ),
                                        title: Text(
                                          product.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        subtitle: Text(
                                          priceText + (hasVariants ? ' • 사이즈별' : ''),
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.orange.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        trailing: ElevatedButton(
                                          onPressed: () async {
                                            if (!hasVariants) {
                                              // 변형 없음: 바로 담기 (표시 가격 사용)
                                              context
                                                  .read<CartService>()
                                                  .addItemWithPrice(product, unitPrice);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('${product.name}이(가) 장바구니에 추가되었습니다'),
                                                  duration: const Duration(seconds: 1),
                                                ),
                                              );
                                            } else {
                                              // 변형 있음: 하단 시트로 사이즈 선택
                                              final choice = await _pickVariant(context, pctx, product);
                                              if (choice == null) return;
                                              final displayName = '${product.name} (${choice.label})';
                                              context.read<CartService>().addItemWithPrice(
                                                    product.copyWith(name: displayName),
                                                    choice.price,
                                                  );
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('$displayName 이(가) 장바구니에 추가되었습니다'),
                                                  duration: const Duration(seconds: 1),
                                                ),
                                              );
                                            }
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
                );
              },
            ),
    );
  }

  /// 변형 선택
  Future<_VariantChoice?> _pickVariant(
      BuildContext context, _PricingCtx pctx, Product product) async {
    final options = pctx.variantPriceList(product.id);
    if (options.isEmpty) return null;

    return showModalBottomSheet<_VariantChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${product.name} • 사이즈 선택',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (_, i) {
                    final o = options[i];
                    return ListTile(
                      title: Text(o.label),
                      trailing: Text(_won(o.price),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: () => Navigator.pop(context, o),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 클라이언트 개별단가 + products(+variants) map 로드
  Future<_PricingCtx> _loadPricingCtxForList({
    required String branchId,
    required String clientCode,
    required String clientTier,
    required List<Product> products,
  }) async {
    // 1) 개별단가(클라이언트 문서) 로드
    final cRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('clients')
        .doc(clientCode);
    final cSnap = await cRef.get();
    final overridesLegacy =
        Map<String, dynamic>.from((cSnap.data()?['priceOverrides'] as Map?) ?? const {});
    final overridesV2 =
        Map<String, dynamic>.from((cSnap.data()?['priceOverridesV2'] as Map?) ?? const {});

    // 2) 상품 + 변형 데이터 로드
    final prodCol = FirebaseFirestore.instance.collection('products');
    final maps = <String, Map<String, dynamic>>{};
    for (final p in products) {
      final ds = await prodCol.doc(p.id).get();
      final pm = Map<String, dynamic>.from(ds.data() ?? const {});
      // variants 로드(정렬)
      final vSnap = await prodCol.doc(p.id).collection('variants').get();
      final vdocs = vSnap.docs.toList()
        ..sort((a, b) {
          int asInt(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
          return asInt(a.data()['sortOrder']).compareTo(asInt(b.data()['sortOrder']));
        });
      final variants = vdocs
          .map((d) => {
                'id': d.id,
                ...Map<String, dynamic>.from(d.data()),
              })
          .toList();
      pm['variants'] = variants;
      maps[p.id] = pm;
    }

    return _PricingCtx(
      clientTier: clientTier.toUpperCase(),
      overridesLegacy: overridesLegacy,
      overridesV2: overridesV2,
      products: maps,
    );
  }
}

/// 변형 선택용 VO
class _VariantChoice {
  _VariantChoice({required this.vid, required this.label, required this.price});
  final String vid;
  final String label;
  final int price;
}

/// 가격 컨텍스트(개별단가/표준단가/상품(+variants))
class _PricingCtx {
  final String clientTier;
  final Map<String, dynamic> overridesLegacy; // pid -> int
  final Map<String, dynamic> overridesV2; // 'pid|vid' -> int
  final Map<String, Map<String, dynamic>> products; // pid -> product map
  _PricingCtx({
    required this.clientTier,
    required this.overridesLegacy,
    required this.overridesV2,
    required this.products,
  });

  bool hasVariants(String pid) {
    final v = products[pid]?['variants'];
    return v is List && v.isNotEmpty;
  }

  /// 카드에 표시할 1개 가격(변형 있으면 첫 활성 변형의 가격)
  int? displayPriceOrNull(String pid) {
    final pm = products[pid] ?? const {};
    final variants = (pm['variants'] as List?)?.cast<Map>() ?? const [];

    if (variants.isEmpty) {
      // 변형 없음 → 기존 로직(구버전 포함)
      return Pricing.effectivePrice(
        pid: pid,
        product: pm,
        clientTier: clientTier,
        overrides: overridesLegacy,
      );
    }

    // 변형 있음 → 첫 활성 변형 기준
    for (final v in variants) {
      final active = (v['active'] ?? true) == true;
      if (!active) continue;
      final vid = (v['id'] as String?) ?? '';
      final gp = Map<String, dynamic>.from(v['gradePrices'] ?? const {});
      final base = _asInt(gp[clientTier]);
      final ov = _asInt(overridesV2['$pid|$vid']);
      final price = (ov != 0 ? ov : base);
      if (price > 0) return price;
    }
    return null;
  }

  /// 변형별 가격 리스트(활성만)
  List<_VariantChoice> variantPriceList(String pid) {
    final pm = products[pid] ?? const {};
    final variants = (pm['variants'] as List?)?.cast<Map>() ?? const [];
    final out = <_VariantChoice>[];
    for (final v in variants) {
      final active = (v['active'] ?? true) == true;
      if (!active) continue;
      final vid = (v['id'] as String?) ?? '';
      final labelKo = (v['labelKo'] as String?)?.trim();
      final labelEn = (v['label'] as String?)?.trim();
      final label = (labelKo?.isNotEmpty == true)
          ? labelKo!
          : (labelEn?.isNotEmpty == true ? labelEn! : vid);

      final gp = Map<String, dynamic>.from(v['gradePrices'] ?? const {});
      final base = _asInt(gp[clientTier]);
      final ov = _asInt(overridesV2['$pid|$vid']);
      final price = (ov != 0 ? ov : base);
      if (price > 0) {
        out.add(_VariantChoice(vid: vid, label: label, price: price));
      }
    }
    return out;
  }

  static int _asInt(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
}

extension on Product {
  Product copyWith({String? name}) {
    return Product(
      id: id,
      name: name ?? this.name,
      prices: prices,
      emoji: emoji,
    );
  }
}
