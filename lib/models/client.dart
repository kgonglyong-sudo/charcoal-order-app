// lib/models/client.dart
class Client {
  final String code;        // CLIENT001 ...
  final String name;        // 거래처명
  final String branchId;    // branches/{branchId}
  final String priceTier;   // A/B/C
  final List<int> deliveryDays; // 1=월 ... 7=일

  const Client({
    required this.code,
    required this.name,
    required this.branchId,
    required this.priceTier,
    this.deliveryDays = const [],
  });

  factory Client.fromMap(Map<String, dynamic> m) {
    return Client(
      code: (m['clientCode'] ?? '') as String,
      name: (m['name'] ?? '') as String,
      branchId: (m['branchId'] ?? '') as String,
      priceTier: ((m['priceTier'] ?? 'C') as String).toUpperCase(),
      deliveryDays: (m['deliveryDays'] as List?)
              ?.whereType<int>()
              .where((e) => e >= 1 && e <= 7)
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'clientCode': code,
      'name': name,
      'branchId': branchId,
      'priceTier': priceTier,
      'deliveryDays': deliveryDays,
    };
  }

  /// 오늘(now) 기준, 지정 요일들 중 가장 가까운 “이번 주” 날짜
  static DateTime? nextDeliveryDate(DateTime now, List<int> days) {
    if (days.isEmpty) return null;
    final sorted = [...days]..sort();
    final base = DateTime(now.year, now.month, now.day);   // 오늘 00:00
    final monday = base.subtract(Duration(days: base.weekday - 1));
    for (final w in sorted) {
      final d = monday.add(Duration(days: w - 1));
      if (!d.isBefore(base)) return d;
    }
    final nextWeekMonday = monday.add(const Duration(days: 7));
    return nextWeekMonday.add(Duration(days: sorted.first - 1));
  }
}
