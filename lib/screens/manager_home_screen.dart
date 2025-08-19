// lib/screens/manager_home_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xls;
import 'dart:typed_data';

import '../services/auth_service.dart';

// ✅ 조건부 임포트: 플랫폼별 저장/공유 구현
import '../utils/xlsx_saver_stub.dart'
  if (dart.library.io) '../utils/xlsx_saver_io.dart'
  if (dart.library.html) '../utils/xlsx_saver_web.dart';

/// ------------------------------
/// (기존) 지점 products.prices 리포지토리 - 다른 화면 호환용으로 유지
/// ------------------------------
class ProductWithPrices {
  ProductWithPrices({
    required this.pid,
    required this.name,
    required this.active,
    required this.priceA,
    required this.priceB,
    required this.priceC,
    required this.sortOrder,
  });

  final String pid;
  final String name;
  final bool active;
  final int priceA;
  final int priceB;
  final int priceC;
  final int sortOrder;
}

class ProductRepository {
  ProductRepository(this._db);
  final FirebaseFirestore _db;

  Query<Map<String, dynamic>> baseProductsQuery({
    required String branchId,
  }) {
    return _db
        .collection('branches')
        .doc(branchId)
        .collection('products')
        .where('deletedAt', isNull: true)
        .orderBy('sortOrder')
        .orderBy('name');
  }

  Stream<List<ProductWithPrices>> watchStandardPrices({
    required String branchId,
  }) {
    return baseProductsQuery(branchId: branchId).snapshots().map((snap) {
      int _numToInt(dynamic v) =>
          v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
      return snap.docs.map((d) {
        final m = d.data();
        final prices = Map<String, dynamic>.from(m['prices'] ?? const {});
        return ProductWithPrices(
          pid: d.id,
          // ✅ 한글 우선
          name: (m['nameKo'] ?? m['name'] ?? '') as String,
          active: (m['active'] ?? true) as bool,
          priceA: _numToInt(prices['A']),
          priceB: _numToInt(prices['B']),
          priceC: _numToInt(prices['C']),
          sortOrder: _numToInt(m['sortOrder']),
        );
      }).toList();
    });
  }

  Future<void> saveStandardPrices({
    required String branchId,
    required Map<String, Map<String, int>> changes, // pid -> {'A':..,'B':..,'C':..}
  }) async {
    final batch = _db.batch();
    final base =
        _db.collection('branches').doc(branchId).collection('products');
    changes.forEach((pid, v) {
      batch.update(base.doc(pid), {
        'prices': {'A': v['A'] ?? 0, 'B': v['B'] ?? 0, 'C': v['C'] ?? 0},
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    await batch.commit();
  }
}

/// ===============================
/// 🔶 variants(사이즈) 단가 편집용 모델/리포지토리
/// ===============================
class VariantRow {
  VariantRow({
    required this.pid,
    required this.productName,
    required this.vid,
    required this.label,
    required this.active,
    required this.sortOrder,
    required this.priceA,
    required this.priceB,
    required this.priceC,
  });

  final String pid;
  final String productName;
  final String vid;
  final String label;
  final bool active;
  final int sortOrder;
  final int priceA;
  final int priceB;
  final int priceC;
}

class ProductWithVariantRows {
  ProductWithVariantRows({
    required this.pid,
    required this.productName,
    required this.variants,
  });

  final String pid;
  final String productName;
  final List<VariantRow> variants;
}

class VariantsRepository {
  VariantsRepository(this._db);
  final FirebaseFirestore _db;

  /// products/{pid}/variants 전체를 불러와 정렬
  Future<List<ProductWithVariantRows>> loadProductsWithVariants() async {
    final ps = await _db.collection('products').get();

    final results = <ProductWithVariantRows>[];
    for (final p in ps.docs) {
      final pm = p.data();
      // ✅ 상품명 한글 우선
      final pname = (pm['nameKo'] ?? pm['name'] ?? p.id).toString();

      final vs = await p.reference
          .collection('variants')
          .orderBy('sortOrder')
          .get();

      final rows = <VariantRow>[];
      for (final v in vs.docs) {
        final vm = v.data();
        final gp = (vm['gradePrices'] as Map?) ?? {};
        int _toInt(dynamic x) =>
            x is num ? x.toInt() : int.tryParse('${x ?? ''}') ?? 0;

        rows.add(VariantRow(
          pid: p.id,
          productName: pname,
          vid: v.id,
          // ✅ 라벨 한글 우선
          label: (vm['labelKo'] ?? vm['label'] ?? v.id).toString(),
          active: (vm['active'] ?? true) == true,
          sortOrder: _toInt(vm['sortOrder']),
          priceA: _toInt(gp['A']),
          priceB: _toInt(gp['B']),
          priceC: _toInt(gp['C']),
        ));
      }

      if (rows.isNotEmpty) {
        results.add(ProductWithVariantRows(
          pid: p.id,
          productName: pname,
          variants: rows,
        ));
      }
    }

    results.sort((a, b) => a.productName.compareTo(b.productName));
    return results;
  }

  /// 변경된 변형만 일괄 저장
  /// key="$pid|$vid" -> {'A':..,'B':..,'C':..}
  Future<void> saveVariantGradePrices(
    Map<String, Map<String, int>> changes,
  ) async {
    WriteBatch batch = _db.batch();
    int n = 0;

    Future<void> commitAndRenew() async {
      await batch.commit();
      n = 0;
      batch = _db.batch();
    }

    for (final entry in changes.entries) {
      final parts = entry.key.split('|');
      if (parts.length != 2) continue;
      final pid = parts[0];
      final vid = parts[1];
      final prices = entry.value;

      final ref =
          _db.collection('products').doc(pid).collection('variants').doc(vid);

      batch.update(ref, {
        'gradePrices': {
          'A': prices['A'] ?? 0,
          'B': prices['B'] ?? 0,
          'C': prices['C'] ?? 0,
        },
      });

      n++;
      if (n % 450 == 0) {
        await commitAndRenew();
      }
    }

    if (n % 450 != 0) {
      await commitAndRenew();
    }
  }
}

/// ------------------------------
/// 매니저 메인
/// ------------------------------
class ManagerHomeScreen extends StatefulWidget {
  const ManagerHomeScreen({super.key});
  @override
  State<ManagerHomeScreen> createState() => _ManagerHomeScreenState();
}

class _ManagerHomeScreenState extends State<ManagerHomeScreen> {
  int _tabIndex = 0;

  String? _selectedBranchId;
  late DateTimeRange _rangeKst;
  Set<int> _selectedWeekdays = {1, 2, 3, 4, 5, 6, 7};

  // 공통 리포지토리 (기존)
  final ProductRepository _repo = ProductRepository(FirebaseFirestore.instance);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final end =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final start = end.subtract(const Duration(days: 7));
    _rangeKst = DateTimeRange(start: start, end: end);
  }

  Future<void> _pickRange() async {
    final res = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(
        start: DateTime(
            _rangeKst.start.year, _rangeKst.start.month, _rangeKst.start.day),
        end: _rangeKst.end.subtract(const Duration(days: 1)),
      ),
      helpText: '기간 선택',
      saveText: '적용',
      cancelText: '취소',
    );
    if (res != null) {
      setState(() {
        _rangeKst = DateTimeRange(
          start: DateTime(res.start.year, res.start.month, res.start.day),
          end: DateTime(res.end.year, res.end.month, res.end.day)
              .add(const Duration(days: 1)),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final managerBranchId = auth.branchId;
    final effectiveBranchId = _selectedBranchId ?? managerBranchId;

    // ✅ 단가관리 탭 제거 → 2개 탭(주문, 리포트)
    final pages = <Widget>[
      OrdersByDateView(
          branchId: effectiveBranchId,
          rangeKst: _rangeKst,
          weekdays: _selectedWeekdays),
      ItemReportView(
        branchId: effectiveBranchId,
        rangeKst: _rangeKst,
        weekdays: _selectedWeekdays,
        onExportTap: () => _openExportSheet(context, effectiveBranchId),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: () => Navigator.pushNamed(context, '/dev/migration'),
          child: Text(['주문', '리포트'][_tabIndex],
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        actions: [
          IconButton(
            tooltip: 'Migration',
            icon: const Icon(Icons.build),
            onPressed: () => Navigator.pushNamed(context, '/dev/migration'),
          ),
          // ✅ 표준단가 관리 버튼 (전사 공용 products/{pid}/variants/{vid})
          IconButton(
            tooltip: '표준단가 관리',
            icon: const Icon(Icons.sell),
            onPressed: () {
              final bid = effectiveBranchId;
              if (bid == null || bid.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content:
                          Text('지점 정보가 없습니다. /user/{uid}.branchId 확인')),
                );
                return;
              }
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) =>
                    StandardPriceSheet(branchId: bid, repo: _repo),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          ManagerTopBar(
            branchId: managerBranchId,
            rangeKst: _rangeKst,
            weekdays: _selectedWeekdays,
            onToggleWeekday: (w) => setState(() {
              if (_selectedWeekdays.contains(w)) {
                _selectedWeekdays.remove(w);
                if (_selectedWeekdays.isEmpty) _selectedWeekdays = {w};
              } else {
                _selectedWeekdays.add(w);
              }
            }),
            onQuickWeekday: (type) => setState(() {
              switch (type) {
                case _QuickWeekday.all:
                  _selectedWeekdays = {1, 2, 3, 4, 5, 6, 7};
                  break;
                case _QuickWeekday.weekday:
                  _selectedWeekdays = {1, 2, 3, 4, 5};
                  break;
                case _QuickWeekday.weekend:
                  _selectedWeekdays = {6, 7};
                  break;
              }
            }),
            onPickRange: _pickRange,
            onClear: () {
              final now = DateTime.now();
              final end = DateTime(now.year, now.month, now.day)
                  .add(const Duration(days: 1));
              final start = end.subtract(const Duration(days: 7));
              setState(() {
                _selectedBranchId = null;
                _rangeKst = DateTimeRange(start: start, end: end);
                _selectedWeekdays = {1, 2, 3, 4, 5, 6, 7};
              });
            },
            onPaymentTap: () => _openPaymentPanel(context, effectiveBranchId),
            onExportTap: () => _openExportSheet(context, effectiveBranchId),
            onOpenClients: () => Navigator.pushNamed(context, '/clients'),
            onLogout: () async {
              await context.read<AuthService>().signOut();
              if (mounted) {
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/login', (_) => false);
              }
            },

            // ✨ 관리자 전용 지점 선택
            isAdmin: (auth.role == 'admin'),
            selectedBranchId: effectiveBranchId,
            onBranchChanged: (newId) => setState(() => _selectedBranchId = newId),
          ),
          const Divider(height: 0),
          Expanded(child: pages[_tabIndex]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (v) => setState(() => _tabIndex = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list_alt), label: '주문'),
          NavigationDestination(icon: Icon(Icons.query_stats), label: '리포트'),
        ],
      ),
    );
  }

  Future<void> _openPaymentPanel(
      BuildContext context, String? branchId) async {
    if (branchId == null || branchId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지점 정보가 없습니다. /user/{uid}.branchId 확인')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => PaymentConfirmSheet(
        branchId: branchId,
        rangeKst: _rangeKst,
        weekdays: _selectedWeekdays,
      ),
    );
  }

  // ====================== 엑셀 내보내기 ======================
  Future<void> _openExportSheet(
      BuildContext context, String? branchId) async {
    if (branchId == null || branchId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지점 정보가 없습니다. /user/{uid}.branchId 확인')),
      );
      return;
    }

    bool byDate = true;
    bool byClient = true;
    bool byItem = true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              final labelRange =
                  '${_fmtDate(_rangeKst.start)} ~ ${_fmtDate(_rangeKst.end.subtract(const Duration(days: 1)))}';
              final weekdayText = (_selectedWeekdays.toList()..sort())
                  .map(_weekdayLabel)
                  .join(', ');
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Text('내보내기',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 8),
                  Text('기간: $labelRange'),
                  if (weekdayText.isNotEmpty) Text('요일: $weekdayText'),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: byDate,
                    onChanged: (v) => setModalState(() => byDate = v ?? false),
                    title: const Text('① 일자별(주문별 상세)'),
                  ),
                  CheckboxListTile(
                    value: byClient,
                    onChanged: (v) => setModalState(() => byClient = v ?? false),
                    title: const Text('② 거래처별 합계'),
                  ),
                  CheckboxListTile(
                    value: byItem,
                    onChanged: (v) => setModalState(() => byItem = v ?? false),
                    title: const Text('③ 품목별 합계'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('닫기'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.ios_share),
                          label: const Text('내보내기'),
                          onPressed: () async {
                            if (!byDate && !byClient && !byItem) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('최소 1개 이상 선택하세요.')),
                              );
                              return;
                            }
                            Navigator.pop(context);

                            final q = FirebaseFirestore.instance
                                .collection('branches')
                                .doc(branchId)
                                .collection('orders')
                                .where(
                                  'createdAt',
                                  isGreaterThanOrEqualTo:
                                      Timestamp.fromDate(
                                          _rangeKst.start.toUtc()),
                                )
                                .where(
                                  'createdAt',
                                  isLessThan: Timestamp.fromDate(
                                      _rangeKst.end.toUtc()),
                                )
                                .orderBy('createdAt', descending: false);

                            final snap = await q.get();
                            final docs = snap.docs.where((d) {
                              final ts = (d['createdAt'] as Timestamp?)
                                  ?.toDate()
                                  .toLocal();
                              if (ts == null) return false;
                              return _selectedWeekdays.contains(ts.weekday);
                            }).toList();

                            if (docs.isEmpty) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('내보낼 데이터가 없습니다.')),
                              );
                              return;
                            }

                            await _exportToExcel(
                              docs: docs,
                              byDate: byDate,
                              byClient: byClient,
                              byItem: byItem,
                              filePrefix:
                                  'orders_${branchId}_${_yyyymmdd(_rangeKst.start)}-${_yyyymmdd(_rangeKst.end.subtract(const Duration(days: 1)))}',
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _exportToExcel({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required bool byDate,
    required bool byClient,
    required bool byItem,
    required String filePrefix,
  }) async {
    final book = xls.Workbook();

    // ① 일자별(주문별 상세)
    if (byDate) {
      final sheet = book.worksheets[0];
      sheet.name = '일자별';
      final headers = ['날짜', '시간', '거래처', '상태', '합계', '품목(이름 x수량 @단가)'];
      for (var i = 0; i < headers.length; i++) {
        sheet.getRangeByIndex(1, i + 1).setText(headers[i]);
      }

      var r = 2;
      for (final d in docs) {
        final m = d.data();
        final ts = (m['createdAt'] as Timestamp?)?.toDate().toLocal();
        final date = ts != null ? _fmtDate(ts) : '';
        final time = ts != null
            ? '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}'
            : '';
        final client = (m['clientCode'] as String?) ?? '';
        final status = (m['status'] as String?) ?? '';
        final total = (m['total'] as num?)?.toInt() ?? 0;
        final items = (m['items'] as List?)?.cast<Map>() ?? const [];
        final itemsStr = items.map((e) {
          final name = (e['productName'] as String?) ?? '';
          final qty = (e['quantity'] as num?)?.toInt() ?? 0;
          final price = (e['price'] as num?)?.toInt() ?? 0;
          return '$name x$qty@$price';
        }).join(', ');

        sheet.getRangeByIndex(r, 1).setText(date);
        sheet.getRangeByIndex(r, 2).setText(time);
        sheet.getRangeByIndex(r, 3).setText(client);
        sheet.getRangeByIndex(r, 4).setText(status);
        sheet.getRangeByIndex(r, 5).setNumber(total.toDouble());
        sheet.getRangeByIndex(r, 6).setText(itemsStr);
        r++;
      }
      sheet.autoFitColumn(1);
      sheet.autoFitColumn(3);
      sheet.autoFitColumn(4);
      sheet.autoFitColumn(6);
    }

    // ② 거래처별 합계
    if (byClient) {
      final sheet = byDate
          ? book.worksheets.addWithName('거래처별')
          : book.worksheets[0]..name = '거래처별';
      final headers = ['거래처', '주문수', '합계'];
      for (var i = 0; i < headers.length; i++) {
        sheet.getRangeByIndex(1, i + 1).setText(headers[i]);
      }

      final agg = <String, _ClientAgg>{};
      for (final d in docs) {
        final m = d.data();
        final client = (m['clientCode'] as String?) ?? '';
        final total = (m['total'] as num?)?.toInt() ?? 0;
        agg.putIfAbsent(client, () => _ClientAgg());
        agg[client]!
          ..count += 1
          ..total += total;
      }

      var r = 2;
      final entries = agg.entries.toList()
        ..sort((a, b) => b.value.total.compareTo(a.value.total));
      for (final e in entries) {
        sheet.getRangeByIndex(r, 1).setText(e.key);
        sheet.getRangeByIndex(r, 2).setNumber(e.value.count.toDouble());
        sheet.getRangeByIndex(r, 3).setNumber(e.value.total.toDouble());
        r++;
      }
      sheet.autoFitColumn(1);
    }

    // ③ 품목별 합계
    if (byItem) {
      final sheet = (byDate || byClient)
          ? book.worksheets.addWithName('품목별')
          : book.worksheets[0]
        ..name = '품목별';
      final headers = ['productId', 'productName', '수량', '매출'];
      for (var i = 0; i < headers.length; i++) {
        sheet.getRangeByIndex(1, i + 1).setText(headers[i]);
      }

      final agg = <String, _ItemAgg>{};
      for (final d in docs) {
        final m = d.data();
        final items = (m['items'] as List?)?.cast<Map>() ?? const [];
        for (final it in items) {
          final pid = (it['productId'] as String?) ?? '(id없음)';
          final name = (it['productName'] as String?) ?? '(이름없음)';
          final price = (it['price'] as num?)?.toInt() ?? 0;
          final qty = (it['quantity'] as num?)?.toInt() ?? 0;
          agg.putIfAbsent(pid, () => _ItemAgg(name: name));
          final a = agg[pid]!;
          a.qty += qty;
          a.revenue += price * qty;
        }
      }

      var r = 2;
      final entries = agg.entries.toList()
        ..sort((a, b) => b.value.revenue.compareTo(a.value.revenue));
      for (final e in entries) {
        sheet.getRangeByIndex(r, 1).setText(e.key);
        sheet.getRangeByIndex(r, 2).setText(e.value.name);
        sheet.getRangeByIndex(r, 3).setNumber(e.value.qty.toDouble());
        sheet.getRangeByIndex(r, 4).setNumber(e.value.revenue.toDouble());
        r++;
      }
      sheet.autoFitColumn(1);
      sheet.autoFitColumn(2);
    }

    // ✅ 저장/공유
    final bytes = Uint8List.fromList(book.saveAsStream());
    book.dispose();
    await saveXlsx(bytes, '$filePrefix.xlsx');
  }

  static String _weekdayLabel(int weekday) {
    const labels = {1: '월', 2: '화', 3: '수', 4: '목', 5: '금', 6: '토', 7: '일'};
    return labels[weekday] ?? '$weekday';
  }

  static String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final da = d.day.toString().padLeft(2, '0');
    return '$y-$m-$da';
  }

  static String _yyyymmdd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
}

enum _QuickWeekday { all, weekday, weekend }

class ManagerTopBar extends StatelessWidget {
  const ManagerTopBar({
    super.key,
    required this.branchId,
    required this.rangeKst,
    required this.weekdays,
    required this.onToggleWeekday,
    required this.onQuickWeekday,
    required this.onPickRange,
    required this.onClear,
    required this.onPaymentTap,
    required this.onExportTap,
    required this.onOpenClients,
    required this.onLogout,

    // ✨ 추가: 관리자 전용 지점 선택
    required this.isAdmin,
    required this.selectedBranchId,
    required this.onBranchChanged,
  });

  final String? branchId;
  final DateTimeRange rangeKst;
  final Set<int> weekdays;
  final ValueChanged<int> onToggleWeekday;
  final ValueChanged<_QuickWeekday> onQuickWeekday;
  final VoidCallback onPickRange;
  final VoidCallback onClear;
  final VoidCallback onPaymentTap;
  final VoidCallback onExportTap;
  final VoidCallback onOpenClients;
  final VoidCallback onLogout;

  // ✨ admin 전용
  final bool isAdmin;
  final String? selectedBranchId;
  final ValueChanged<String?> onBranchChanged;

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        '${_fmtDate(rangeKst.start)} ~ ${_fmtDate(rangeKst.end.subtract(const Duration(days: 1)))}';

    Widget branchSelector;
    if (isAdmin) {
      final q = FirebaseFirestore.instance
          .collection('branches')
          .orderBy('name', descending: false);

      branchSelector = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          final items = (snap.data?.docs ?? const [])
              .map((d) {
                final id = d.id;
                final name = (d['name'] as String?) ?? id;
                return DropdownMenuItem<String>(
                  value: id,
                  child: Text('$name ($id)'),
                );
              })
              .toList();

          final value = (selectedBranchId?.isNotEmpty ?? false)
              ? selectedBranchId
              : branchId;

          return InputDecorator(
            decoration: const InputDecoration(
              labelText: '지점(관리자)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: (items.any((e) => e.value == value)) ? value : null,
                hint: const Text('지점 선택'),
                items: items,
                onChanged: onBranchChanged,
              ),
            ),
          );
        },
      );
    } else {
      branchSelector = InputDecorator(
        decoration: const InputDecoration(
          labelText: '지점',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: Text(branchId ?? '지점 정보 없음'),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: branchSelector),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onPickRange,
                icon: const Icon(Icons.date_range),
                label: Text(dateLabel),
              ),
              const SizedBox(width: 8),
              IconButton(onPressed: onClear, tooltip: '초기화', icon: const Icon(Icons.refresh)),
              IconButton(onPressed: onLogout, tooltip: '로그아웃', icon: const Icon(Icons.logout)),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: -6,
              children: List.generate(7, (i) {
                final weekday = i + 1;
                final selected = weekdays.contains(weekday);
                const labels = ['월', '화', '수', '목', '금', '토', '일'];
                return FilterChip(
                  label: Text(labels[i]),
                  selected: selected,
                  onSelected: (_) => onToggleWeekday(weekday),
                );
              }),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => onQuickWeekday(_QuickWeekday.all),
                  child: const Text('전체'),
                ),
                TextButton(
                  onPressed: () => onQuickWeekday(_QuickWeekday.weekday),
                  child: const Text('주중(월~금)'),
                ),
                TextButton(
                  onPressed: () => onQuickWeekday(_QuickWeekday.weekend),
                  child: const Text('주말(토/일)'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onPaymentTap,
                  icon: const Icon(Icons.payment),
                  label: const Text('결제 확인'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onExportTap,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('내보내기'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onOpenClients,
                  icon: const Icon(Icons.groups),
                  label: const Text('거래처'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final da = d.day.toString().padLeft(2, '0');
    return '$y-$m-$da';
  }
}

class PaymentConfirmSheet extends StatelessWidget {
  const PaymentConfirmSheet({
    super.key,
    required this.branchId,
    required this.rangeKst,
    required this.weekdays,
  });

  final String branchId;
  final DateTimeRange rangeKst;
  final Set<int> weekdays;

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('orders')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(rangeKst.start.toUtc()))
        .where('createdAt',
            isLessThan: Timestamp.fromDate(rangeKst.end.toUtc()))
        .orderBy('createdAt', descending: true);

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.4,
        builder: (_, controller) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            const Text('결제 확인',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: q.snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final all = snap.data?.docs ?? const [];
                  final docs = all.where((doc) {
                    final ts =
                        (doc['createdAt'] as Timestamp?)?.toDate().toLocal();
                    if (ts == null) return false;
                    return weekdays.contains(ts.weekday);
                  }).toList();

                  if (docs.isEmpty) {
                    return const Center(
                        child: Text('해당 기간/요일에 결제 확인할 주문이 없습니다.'));
                  }

                  return ListView.builder(
                    controller: controller,
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final d = docs[i].data();
                      final status = (d['status'] as String?) ?? '';
                      final total = (d['total'] as num?)?.toInt() ?? 0;
                      final client = (d['clientCode'] as String?) ?? '';
                      final payment = (d['payment'] as Map?) ?? {};
                      final method = (payment['method'] ?? '-').toString();

                      return ListTile(
                        title: Text('$client • ${_won(total)}'),
                        subtitle: Text(
                          '상태: ${status.isEmpty ? '상태없음' : status} • 결제수단: ${_labelMethod(method)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FilledButton(
                              onPressed: status == '입금대기'
                                  ? () async {
                                      await docs[i].reference.update({
                                        'status': '주문완료',
                                        'payment.status': '결제완료(확인)',
                                        'payment.updatedAt':
                                            FieldValue.serverTimestamp(),
                                      });
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text('결제확인 처리되었습니다.')),
                                        );
                                      }
                                    }
                                  : null,
                              child: const Text('입금확인'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: status != '입금대기'
                                  ? () async {
                                      await docs[i].reference.update({
                                        'status': '입금대기',
                                        'payment.status': '입금대기',
                                        'payment.updatedAt':
                                            FieldValue.serverTimestamp(),
                                      });
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text('입금대기로 전환되었습니다.')),
                                        );
                                      }
                                    }
                                  : null,
                              child: const Text('입금대기'),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static String _labelMethod(String m) {
    switch (m) {
      case 'bank':
        return '무통장입금';
      case 'card':
        return '카드';
      case 'toss':
        return '토스페이';
      case 'kakao':
        return '카카오페이';
      default:
        return m;
    }
  }

  // ✅ 쉼표 포맷 정규식
  static String _won(int v) =>
      '${v.toString().replaceAllMapped(RegExp(r'(\\d{1,3})(?=(\\d{3})+(?!\\d))'), (m) => '${m[1]},')}원';
}

class OrdersByDateView extends StatelessWidget {
  const OrdersByDateView({
    super.key,
    required this.branchId,
    required this.rangeKst,
    required this.weekdays,
  });

  final String? branchId;
  final DateTimeRange rangeKst;
  final Set<int> weekdays;

  @override
  Widget build(BuildContext context) {
    final bid = branchId;
    if (bid == null || bid.isEmpty) {
      return const Center(
          child: Text('지점 프로필이 없습니다. /user/{uid}.branchId 를 확인하세요.'));
    }

    final q = FirebaseFirestore.instance
        .collection('branches')
        .doc(bid)
        .collection('orders')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(rangeKst.start.toUtc()))
        .where('createdAt',
            isLessThan: Timestamp.fromDate(rangeKst.end.toUtc()))
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const Center(child: Text('해당 조건의 주문이 없습니다.'));
        }

        final filtered = snap.data!.docs.where((d) {
          final ts =
              (d['createdAt'] as Timestamp?)?.toDate().toLocal();
          if (ts == null) return false;
          return weekdays.contains(ts.weekday);
        }).toList();

        if (filtered.isEmpty) {
          return const Center(child: Text('선택한 요일에 해당하는 주문이 없습니다.'));
        }

        final grouped =
            <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
        for (final d in filtered) {
          final ts =
              (d['createdAt'] as Timestamp?)?.toDate().toLocal();
          final key = _fmtYmd(ts);
          grouped.putIfAbsent(key, () => []).add(d);
        }

        final keys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

        return ListView.builder(
          itemCount: keys.length,
          itemBuilder: (context, i) {
            final k = keys[i];
            final docs = grouped[k]!;
            final dayTotal = docs.fold<int>(
                0, (sum, d) => sum + _toInt(d['total']));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 18, 16, 8),
                  child: Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                    children: [
                      Text(k,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      Text('합계 ${_won(dayTotal)}'),
                    ],
                  ),
                ),
                ...docs.map((d) => _OrderTile(doc: d)),
                const Divider(height: 0),
              ],
            );
          },
        );
      },
    );
  }

  static String _fmtYmd(DateTime? dt) {
    if (dt == null) return '날짜없음';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static int _toInt(dynamic v) => v is num ? v.toInt() : 0;

  static String _won(int v) => '${_formatInt(v)}원';

  static String _formatInt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      buf.write(s[i]);
      count++;
      if (count == 3 && i != 0) {
        buf.write(',');
        count = 0;
      }
    }
    return String.fromCharCodes(buf.toString().runes.toList().reversed);
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.doc});
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final created =
        (data['createdAt'] as Timestamp?)?.toDate().toLocal();
    final items =
        (data['items'] as List?)?.cast<Map>() ?? const [];
    final title =
        items.map((e) => e['productName']).whereType<String>().join(', ');
    final total = OrdersByDateView._toInt(data['total']);
    final status = (data['status'] as String?) ?? '';
    final client = (data['clientCode'] as String?) ?? '';
    final branch = (data['branchId'] as String?) ?? '';
    final payment = (data['payment'] as Map?) ?? {};
    final method = (payment['method'] ?? '-').toString();

    return ListTile(
      title: Text(
        title.isEmpty ? '(품목 없음)' : title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
          '$branch • $client • ${_fmtHm(created)} • ${_labelMethod(method)}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(OrdersByDateView._won(total),
              style:
                  const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          _StatusChip(status: status),
          const SizedBox(width: 4),
          _StatusMenu(
            current: status,
            onChange: (next) async {
              final updates = <String, dynamic>{'status': next};
              if (next == '입금대기') {
                updates['payment.status'] = '입금대기';
              } else if (next == '주문완료') {
                updates['payment.status'] = '결제완료(확인)';
              }
              updates['payment.updatedAt'] =
                  FieldValue.serverTimestamp();

              await doc.reference.update(updates);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('상태가 "$next"(으)로 변경되었습니다.')),
                );
              }
            },
          ),
        ],
      ),
      onTap: () => _showOrderDetail(context, doc),
    );
  }

  static String _labelMethod(String m) {
    switch (m) {
      case 'bank':
        return '무통장입금';
      case 'card':
        return '카드';
      case 'toss':
        return '토스페이';
      case 'kakao':
        return '카카오페이';
      default:
        return m;
    }
  }

  static String _fmtHm(DateTime? dt) {
    if (dt == null) return '--:--';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static void _showOrderDetail(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final items =
        (data['items'] as List?)?.cast<Map>() ?? const [];
    final created =
        (data['createdAt'] as Timestamp?)?.toDate().toLocal();
    final client = (data['clientCode'] as String?) ?? '';
    final branch = (data['branchId'] as String?) ?? '';
    final status = (data['status'] as String?) ?? '';
    final total = OrdersByDateView._toInt(data['total']);
    final payment = (data['payment'] as Map?) ?? {};
    final method = (payment['method'] ?? '-').toString();
    final payStatus = (payment['status'] ?? '-').toString();

    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('주문 상세',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('지점: $branch'),
                Text('거래처: $client'),
                Text('주문상태: $status'),
                Text('결제수단: ${_labelMethod(method)}'),
                Text('결제상태: $payStatus'),
                Text('시간: ${created ?? '-'}'),
                const SizedBox(height: 12),
                const Text('품목',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('상품')),
                      DataColumn(label: Text('단가')),
                      DataColumn(label: Text('수량')),
                      DataColumn(label: Text('금액')),
                    ],
                    rows: items.map((e) {
                      final name = (e['productName'] as String?) ?? '';
                      final price = e['price'] is num
                          ? (e['price'] as num).toInt()
                          : 0;
                      final qty = e['quantity'] is num
                          ? (e['quantity'] as num).toInt()
                          : 0;
                      return DataRow(cells: [
                        DataCell(Text(name)),
                        DataCell(Text(OrdersByDateView._won(price))),
                        DataCell(Text('$qty')),
                        DataCell(
                            Text(OrdersByDateView._won(price * qty))),
                      ]);
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('합계: ${OrdersByDateView._won(total)}',
                      style:
                          const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('닫기'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      '입금대기' => Colors.amber,
      '주문완료' => Colors.green,
      '확인됨' => Colors.blue,
      '출고중' => Colors.orange,
      '완료' => Colors.green,
      _ => Colors.black54,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        status.isEmpty ? '상태없음' : status,
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }
}

class _StatusMenu extends StatelessWidget {
  const _StatusMenu({required this.current, required this.onChange});
  final String current;
  final ValueChanged<String> onChange;
  static const statuses = ['입금대기', '주문완료', '확인됨', '출고중', '완료'];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '상태 변경',
      onSelected: onChange,
      itemBuilder: (_) => statuses
          .where((s) => s != current)
          .map((s) => PopupMenuItem(value: s, child: Text(s)))
          .toList(),
      child: const Padding(
        padding: EdgeInsets.all(4.0),
        child: Icon(Icons.edit, size: 18),
      ),
    );
  }
}

class ItemReportView extends StatelessWidget {
  const ItemReportView({
    super.key,
    required this.branchId,
    required this.rangeKst,
    required this.weekdays,
    this.onExportTap,
  });

  final String? branchId;
  final DateTimeRange rangeKst;
  final Set<int> weekdays;
  final VoidCallback? onExportTap;

  @override
  Widget build(BuildContext context) {
    final bid = branchId;
    if (bid == null || bid.isEmpty) {
      return const Center(
          child: Text('지점 프로필이 없습니다. /user/{uid}.branchId 를 확인하세요.'));
    }

    final q = FirebaseFirestore.instance
        .collection('branches')
        .doc(bid)
        .collection('orders')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(rangeKst.start.toUtc()))
        .where('createdAt',
            isLessThan: Timestamp.fromDate(rangeKst.end.toUtc()))
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const Center(child: Text('집계할 주문이 없습니다.'));
        }

        final docs = snap.data!.docs.where((d) {
          final ts =
              (d['createdAt'] as Timestamp?)?.toDate().toLocal();
          if (ts == null) return false;
          return weekdays.contains(ts.weekday);
        }).toList();

        if (docs.isEmpty) {
          return const Center(child: Text('선택한 요일에 해당하는 주문이 없습니다.'));
        }

        final agg = <String, _Agg>{};
        for (final d in docs) {
          final items =
              (d['items'] as List?)?.cast<Map>() ?? const [];
          for (final it in items) {
            final pid = (it['productId'] as String?) ?? '(id없음)';
            final name = (it['productName'] as String?) ?? '(이름없음)';
            final price = (it['price'] as num?)?.toInt() ?? 0;
            final qty = (it['quantity'] as num?)?.toInt() ?? 0;

            agg.putIfAbsent(pid, () => _Agg(name: name));
            final a = agg[pid]!;
            a.qty += qty;
            a.revenue += price * qty;
          }
        }

        final rows = agg.entries.toList()
          ..sort((a, b) => b.value.revenue.compareTo(a.value.revenue));
        final csv = _buildCsv(rows);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Text('품목별 합계 (${rows.length}개)',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (onExportTap != null)
                    OutlinedButton.icon(
                      onPressed: onExportTap,
                      icon: const Icon(Icons.ios_share),
                      label: const Text('내보내기'),
                    ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                          ClipboardData(text: csv));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content:
                                  Text('CSV가 클립보드에 복사되었습니다.')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('CSV 복사'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: DataTable(
                  headingRowHeight: 40,
                  columns: const [
                    DataColumn(label: Text('품목')),
                    DataColumn(label: Text('수량')),
                    DataColumn(label: Text('매출')),
                  ],
                  rows: rows
                      .map(
                        (e) => DataRow(
                          cells: [
                            DataCell(Text(e.value.name)),
                            DataCell(Text('${e.value.qty}')),
                            DataCell(Text(OrdersByDateView._won(
                                e.value.revenue))),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _buildCsv(List<MapEntry<String, _Agg>> rows) {
    final b = StringBuffer();
    b.writeln('productId,productName,qty,revenue');
    for (final e in rows) {
      b.writeln(
          '${e.key},${e.value.name},${e.value.qty},${e.value.revenue}');
    }
    return b.toString();
  }
}

class _Agg {
  _Agg({required this.name});
  final String name;
  int qty = 0;
  int revenue = 0;
}

class _ClientAgg {
  int count = 0;
  int total = 0;
}

class _ItemAgg {
  _ItemAgg({required this.name});
  final String name;
  int qty = 0;
  int revenue = 0;
}

/// ------------------------------
/// ✅ 표준단가 관리 시트 (상품 → 변형(사이즈)별 A/B/C)
/// ------------------------------
class StandardPriceSheet extends StatefulWidget {
  const StandardPriceSheet(
      {super.key, required this.branchId, required this.repo});
  final String branchId; // 현재는 미사용(override 재적용 등에 활용 가능)
  final ProductRepository repo; // 기존 인터페이스와의 호환을 위해 유지

  @override
  State<StandardPriceSheet> createState() => _StandardPriceSheetState();
}

class _PriceTriple {
  _PriceTriple({required this.a, required this.b, required this.c});
  int a;
  int b;
  int c;
}

class _StandardPriceSheetState extends State<StandardPriceSheet> {
  final _variantsRepo = VariantsRepository(FirebaseFirestore.instance);

  // key="$pid|$vid" -> 임시 가격
  final Map<String, _PriceTriple> _edited = {};
  bool _loading = true;
  List<ProductWithVariantRows> _data = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _variantsRepo.loadProductsWithVariants();
      if (mounted) {
        setState(() {
          _data = list;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('불러오기 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.6,
        builder: (_, controller) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(999)),
            ),
            const SizedBox(height: 12),
            const Text('표준단가 관리 (사이즈별)',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_loading)
              const Expanded(
                  child: Center(child: CircularProgressIndicator()))
            else if (_data.isEmpty)
              const Expanded(
                  child: Center(child: Text('표시할 변형이 없습니다.')))
            else
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  padding:
                      const EdgeInsets.fromLTRB(12, 8, 12, 120),
                  itemCount: _data.length,
                  itemBuilder: (_, i) {
                    final p = _data[i];
                    return Card(
                      margin:
                          const EdgeInsets.symmetric(vertical: 6),
                      child: ExpansionTile(
                        title: Text(p.productName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700)),
                        children: [
                          const Divider(height: 0),
                          ...p.variants.map((v) {
                            final key = '${v.pid}|${v.vid}';
                            final cur = _edited[key] ??
                                _PriceTriple(
                                  a: v.priceA,
                                  b: v.priceB,
                                  c: v.priceC,
                                );

                            InputDecoration deco(String label) =>
                                const InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  counterText: '',
                                ).copyWith(labelText: label);

                            int _parse(String s) =>
                                int.tryParse(
                                        s.replaceAll(',', '')) ??
                                0;

                            return Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  12, 10, 12, 12),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                          child: Text('• ${v.label}',
                                              style:
                                                  const TextStyle(
                                                      fontWeight:
                                                          FontWeight
                                                              .w600))),
                                      if (!v.active)
                                        const Padding(
                                          padding:
                                              EdgeInsets.only(
                                                  left: 6),
                                          child: Icon(
                                              Icons
                                                  .pause_circle_filled,
                                              size: 16,
                                              color:
                                                  Colors.orange),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          initialValue:
                                              cur.a.toString(),
                                          decoration: deco('A'),
                                          keyboardType:
                                              TextInputType
                                                  .number,
                                          maxLength: 8,
                                          onChanged: (s) =>
                                              _edited[key] =
                                                  _PriceTriple(
                                            a: _parse(s),
                                            b: (_edited[key]?.b ??
                                                cur.b),
                                            c: (_edited[key]?.c ??
                                                cur.c),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextFormField(
                                          initialValue:
                                              cur.b.toString(),
                                          decoration: deco('B'),
                                          keyboardType:
                                              TextInputType
                                                  .number,
                                          maxLength: 8,
                                          onChanged: (s) =>
                                              _edited[key] =
                                                  _PriceTriple(
                                            a: (_edited[key]?.a ??
                                                cur.a),
                                            b: _parse(s),
                                            c: (_edited[key]?.c ??
                                                cur.c),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextFormField(
                                          initialValue:
                                              cur.c.toString(),
                                          decoration: deco('C'),
                                          keyboardType:
                                              TextInputType
                                                  .number,
                                          maxLength: 8,
                                          onChanged: (s) =>
                                              _edited[key] =
                                                  _PriceTriple(
                                            a: (_edited[key]?.a ??
                                                cur.a),
                                            b: (_edited[key]?.b ??
                                                cur.b),
                                            c: _parse(s),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                        ],
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('닫기'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('저장'),
                      onPressed: _loading
                          ? null
                          : () async {
                              if (_edited.isEmpty) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('변경된 값이 없습니다.')),
                                );
                                return;
                              }
                              // key="$pid|$vid" 형식으로 수집된 변경값 저장
                              final changes =
                                  <String, Map<String, int>>{};
                              _edited.forEach((key, v) {
                                changes[key] = {
                                  'A': v.a,
                                  'B': v.b,
                                  'C': v.c
                                };
                              });

                              await _variantsRepo
                                  .saveVariantGradePrices(
                                      changes);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                const SnackBar(
                                    content: Text('저장되었습니다.')),
                              );
                              Navigator.pop(context);
                            },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
