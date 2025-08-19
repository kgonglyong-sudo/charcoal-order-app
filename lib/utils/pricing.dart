// lib/utils/pricing.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// 개별단가(variants 포함) > 표준단가(variants.gradePrices) > 0
///
/// Firestore 규격:
/// - products/{pid}/variants/{vid}.gradePrices: {'A': int, 'B': int, 'C': int}
/// - (선택) products/{pid}.prices: {'A': int, 'B': int, 'C': int}  // 구버전 호환
/// - clients/{clientCode}.priceOverridesV2: {'pid|vid': int, ...}
/// - clients/{clientCode}.priceOverrides: {'pid': int, ...}        // 구버전 호환
class Pricing {
  /// product(=products/{pid} map), overridesV2(=pid|vid -> int), overrides(=pid->int)
  /// vid가 주어지면 pid|vid 키를 우선 확인.
  static int effectivePrice({
    required String pid,
    required Map<String, dynamic> product,
    required String clientTier,        // 'A' | 'B' | 'C'
    Map<String, dynamic>? overridesV2, // {'pid|vid': int}
    Map<String, dynamic>? overrides,   // {'pid': int} (구버전)
    String? vid,                       // 변형 id
  }) {
    final o2 = overridesV2 ?? const {};
    final o1 = overrides ?? const {};
    final tier = clientTier.toUpperCase();

    // 1) 개별단가 (variants 우선)
    if (vid != null && vid.isNotEmpty) {
      final key = '$pid|$vid';
      final v = o2[key];
      if (v is num) return v.toInt();
      if (v is String) {
        final iv = int.tryParse(v);
        if (iv != null) return iv;
      }
    }
    // 1-2) 구버전 pid 단위 개별단가
    final ov = o1[pid];
    if (ov is num) return ov.toInt();
    if (ov is String) {
      final iv = int.tryParse(ov);
      if (iv != null) return iv;
    }

    // 2) 표준단가(variants.gradePrices.{tier} 우선)
    // product에 variants 컬렉션을 직접 넣어두진 않으므로, 화면에서 전달하길 권장.
    // 다만 product map에 현재 선택된 variant 정보가 붙어오는 경우를 고려한 fallback:
    if (vid != null &&
        product.containsKey('variants') &&
        product['variants'] is Map &&
        (product['variants'] as Map).containsKey(vid)) {
      final vm = Map<String, dynamic>.from(product['variants'][vid]);
      final gp = Map<String, dynamic>.from(vm['gradePrices'] ?? const {});
      final p = gp[tier];
      if (p is num) return p.toInt();
      if (p is String) {
        final iv = int.tryParse(p);
        if (iv != null) return iv;
      }
    }

    // 2-2) 구버전 products/{pid}.prices.{tier}
    final prices = Map<String, dynamic>.from(product['prices'] ?? const {});
    final pv = prices[tier];
    if (pv is num) return pv.toInt();
    if (pv is String) {
      final iv = int.tryParse(pv);
      if (iv != null) return iv;
    }

    return 0;
  }
}
