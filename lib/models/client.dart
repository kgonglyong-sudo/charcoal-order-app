class Client {
  final String code;
  final String name;
  final String branchId;
  final String priceTier; // A, B, C

  Client({
    required this.code,
    required this.name,
    required this.branchId,
    required this.priceTier,
  });

  factory Client.fromMap(Map<String, dynamic> map) {
    return Client(
      code: map['code'] ?? '',
      name: map['name'] ?? '',
      branchId: map['branchId'] ?? '',
      priceTier: map['priceTier'] ?? 'C',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'name': name,
      'branchId': branchId,
      'priceTier': priceTier,
    };
  }
}