// lib/utils/csv_loader.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';

/// CSV → Firestore 업로드 유틸
/// - products_v2.csv  : pid, name, nameKo, category, origin, active, sortOrder ...
/// - variants_v2.csv  : pid, vid, label, labelKo, priceA/B/C(or unitPrice), weight*, active, sortOrder ...
class CsvLoader {
  CsvLoader(this.db);
  final FirebaseFirestore db;

  // ----------------------------------------------------------------
  // CSV 파서 (UTF-8, 헤더 1행 기반)
  // ----------------------------------------------------------------
  Future<List<Map<String, dynamic>>> _readCsv(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath); // UTF-8
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      fieldDelimiter: ',',
      textDelimiter: '"',
      eol: '\n',
    ).convert(raw);

    if (rows.isEmpty) return [];

    final headers = rows.first.map((e) => (e ?? '').toString().trim()).toList();
    final out = <Map<String, dynamic>>[];

    for (var r = 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.isEmpty) continue;

      final m = <String, dynamic>{};
      for (var c = 0; c < headers.length; c++) {
        final key = headers[c];
        final value = c < row.length ? row[c] : '';
        m[key] = value;
      }
      out.add(m);
    }
    return out;
  }

  // ----------------------------------------------------------------
  // helpers
  // ----------------------------------------------------------------
  String _pick(Map m, List<String> keys, {String fallback = ''}) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return fallback;
  }

  /// "21,000원" / "21000.0" / " 21000 " → 21000
  int _toInt(dynamic v) {
    var s = (v ?? '').toString().trim();
    s = s.replaceAll(RegExp(r'[,\s원]'), ''); // 콤마/공백/원 제거
    final d = double.tryParse(s);
    return d?.round() ?? int.tryParse(s) ?? 0;
  }

  double _toDouble(dynamic v) {
    final s = (v ?? '').toString().trim().replaceAll(',', '');
    return double.tryParse(s) ?? 0.0;
  }

  bool _toBool(dynamic v, {bool defaultValue = true}) {
    final s = (v ?? '').toString().trim().toLowerCase();
    if (s.isEmpty) return defaultValue;
    if (['1', 'true', 'y', 'yes', '사용', 'on'].contains(s)) return true;
    if (['0', 'false', 'n', 'no', '미사용', 'off'].contains(s)) return false;
    return true;
  }

  /// 파이어스토어 문서 id로 안전하게 정제
  String _sanitizeId(String id) {
    var x = id.trim();
    x = x.replaceAll('/', '_');           // 경로 구분자 제거
    x = x.replaceAll(RegExp(r'\s+'), '_'); // 공백 → _
    return x;
  }

  // =================================================================
  // products 업로드
  //  - 영문/한글 이름 모두 반영: name, nameKo
  // =================================================================
  Future<void> importProducts(String assetPath) async {
    final rows = await _readCsv(assetPath);
    if (rows.isEmpty) return;

    final batch = db.batch();
    int n = 0;
    Future<void> commit() async => batch.commit();

    for (final m in rows) {
      try {
        final rawPid = _pick(m, ['pid', 'productId', 'id', '품목ID', '상품ID', '코드']);
        final pid = _sanitizeId(rawPid);
        if (pid.isEmpty) continue;

        final nameEn = _pick(m, ['name', 'productName', '품명(영문)', '품명EN', '품명', '상품명'], fallback: pid);
        final nameKo = _pick(m, ['nameKo', '품명KO', '한글명', '표시명', '표준명'], fallback: '');

        final data = <String, dynamic>{
          'name': nameEn,                        // 영문(또는 기본) 이름
          if (nameKo.isNotEmpty) 'nameKo': nameKo, // ✅ 한글 이름
          'category': _pick(m, ['category', '카테고리', '분류']),
          'origin': _pick(m, ['origin', '원산지']),
          'active': _toBool(_pick(m, ['active', '사용'], fallback: '1')),
          'sortOrder': _toInt(_pick(m, ['sortOrder', '정렬'], fallback: '0')),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        batch.set(db.collection('products').doc(pid), data, SetOptions(merge: true));

        if (++n % 450 == 0) await commit();
      } catch (_) {
        // 행 오류는 무시하고 계속 진행
      }
    }

    if (n % 450 != 0) await commit();
  }

  // =================================================================
  // variants 업로드
  //  - 영문/한글 라벨 모두 반영: label, labelKo
  //  - 단가 A/B/C 또는 unitPrice 자동 분배
  // =================================================================
  Future<void> importVariants(String assetPath) async {
    final rows = await _readCsv(assetPath);
    if (rows.isEmpty) return;

    final batch = db.batch();
    int n = 0;
    Future<void> commit() async => batch.commit();

    for (final m in rows) {
      try {
        final rawPid = _pick(m, ['pid', 'productId', '품목ID', '상품ID', '코드']);
        final pid = _sanitizeId(rawPid);
        if (pid.isEmpty) continue;

        final rawVid = _pick(m, ['vid', 'variantId', 'size', '사이즈', '규격', '라벨', 'label']);
        final vid = _sanitizeId(rawVid);
        if (vid.isEmpty) continue;

        final labelEn = _pick(m, ['label', '라벨', 'size', '사이즈', '규격'], fallback: vid);
        final labelKo = _pick(m, ['labelKo', '라벨KO', '사이즈KO', '규격KO', '한글라벨'], fallback: '');

        // A/B/C 우선 추출
        int a = _toInt(_pick(m, ['priceA', 'A', 'a', '단가A']));
        int b = _toInt(_pick(m, ['priceB', 'B', 'b', '단가B']));
        int c = _toInt(_pick(m, ['priceC', 'C', 'c', '단가C']));

        // 모두 0이면 단일 단가 후보를 찾아 A=B=C로 채움
        if (a == 0 && b == 0 && c == 0) {
          final single = _toInt(_pick(m, ['unitPrice', 'price', '단가', '판매가', '기준단가']));
          if (single > 0) a = b = c = single;
        }

        // 추가 속성 (있으면 저장)
        final weightCode = _pick(m, ['weightCode', 'weightCo', '중량코드'], fallback: '');
        final weightKg   = _toDouble(_pick(m, ['weightKg', '중량', '중량KG'], fallback: '0'));
        final sortOrder  = _toInt(_pick(m, ['sortOrder', '정렬', 'order'], fallback: '0'));
        final active     = _toBool(_pick(m, ['active', '사용'], fallback: '1'));

        // 부모 products 문서가 없을 수도 있으니 안전하게 최소 필드로 생성(merge)
        final productRef = db.collection('products').doc(pid);
        final parentNameEn = _pick(m, ['productName', 'name', '품명', '상품명'], fallback: pid);
        final parentNameKo = _pick(m, ['nameKo', 'productNameKo', '품명KO', '한글명'], fallback: '');
        batch.set(
          productRef,
          {
            'name': parentNameEn,
            if (parentNameKo.isNotEmpty) 'nameKo': parentNameKo, // ✅ 부모에도 nameKo 채워줌(있을 때)
            'active': true,
            'sortOrder': 0,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        final data = <String, dynamic>{
          'label': labelEn,
          if (labelKo.isNotEmpty) 'labelKo': labelKo,           // ✅ 한글 라벨
          'active': active,
          'sortOrder': sortOrder,
          if (weightCode.isNotEmpty) 'weightCode': weightCode,
          if (weightKg > 0) 'weightKg': weightKg,
          'gradePrices': {'A': a, 'B': b, 'C': c},
          'updatedAt': FieldValue.serverTimestamp(),
        };

        final ref = productRef.collection('variants').doc(vid);
        batch.set(ref, data, SetOptions(merge: true));

        if (++n % 450 == 0) await commit();
      } catch (_) {
        // 행 오류는 무시하고 계속 진행
      }
    }

    if (n % 450 != 0) await commit();
  }
}
