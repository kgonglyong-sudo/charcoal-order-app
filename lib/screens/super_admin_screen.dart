// lib/screens/super_admin_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// CSV → Firestore 업로드 유틸
import '../utils/csv_loader.dart';

// 매니저 화면의 표준단가 시트 재사용 (선택 사항)
import 'manager_home_screen.dart' show StandardPriceSheet, ProductRepository;

// 로그인 게이트
import '../main.dart' show AuthGate;

class SuperAdminScreen extends StatefulWidget {
  const SuperAdminScreen({super.key});
  @override
  State<SuperAdminScreen> createState() => _SuperAdminScreenState();
}

class _SuperAdminScreenState extends State<SuperAdminScreen> {
  String? _branchId; // null = 전체 지점
  late DateTimeRange _rangeKst;
  bool _all = false; // 전체보기(필터 끄기)
  bool _busy = false; // CSV 업로드 진행 플래그
  String _log = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day); // 오늘 00:00
    final end = start.add(const Duration(days: 1));       // 내일 00:00
    _rangeKst = DateTimeRange(start: start, end: end);
  }

  Future<void> _pickRange() async {
    final res = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(
        start: _rangeKst.start,
        end: _rangeKst.end.subtract(const Duration(days: 1)),
      ),
      helpText: '조회 기간 선택',
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

  // =========================
  // CSV → Firestore 업로드
  // =========================
  Future<void> _importCsvToFirestore() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _log = '업로드 시작…';
    });
    try {
      final loader = CsvLoader(FirebaseFirestore.instance);
      await loader.importProducts('assets/products_v2.csv');
      setState(() => _log = 'products_v2.csv 업로드 완료');

      await loader.importVariants('assets/variants_v2.csv');
      setState(() => _log = 'variants_v2.csv 업로드 완료');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV → Firestore 업로드 완료')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('업로드 실패: $e')),
        );
      }
      setState(() => _log = '에러: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 로그인 가드
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Future.microtask(() {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (_) => false,
        );
      });
      return const SizedBox.shrink();
    }

    // UTC 경계
    final startUtc = _rangeKst.start.toUtc();
    final endUtc = _rangeKst.end.toUtc();

    // 기본: 모든 지점 orders를 collectionGroup으로 모으기
    Query<Map<String, dynamic>> q =
        FirebaseFirestore.instance.collectionGroup('orders');

    if (!_all) {
      q = q
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startUtc))
          .where('createdAt', isLessThan: Timestamp.fromDate(endUtc));
    }
    if (_branchId != null) {
      q = q.where('branchId', isEqualTo: _branchId);
    }
    q = q.orderBy('createdAt', descending: true).limit(500);

    return Scaffold(
      appBar: AppBar(
        title: const Text('슈퍼관리자 — 주문'),
        actions: [
          IconButton(
            tooltip: '상품마스터 보기',
            icon: const Icon(Icons.inventory_2),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: const VariantsAuditSheet(),
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: '표준단가(사이즈별) 편집',
            icon: const Icon(Icons.sell),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: StandardPriceSheet(
                      branchId: 'admin',
                      repo: ProductRepository(FirebaseFirestore.instance),
                    ),
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'CSV → Firestore 업로드',
            onPressed: _busy ? null : _importCsvToFirestore,
            icon: const Icon(Icons.upload_file),
          ),
          const _CurrentUserInfo(),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(88),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _BranchDropdown(
                            value: _branchId,
                            onChanged: (v) => setState(() => _branchId = v),
                          ),
                          OutlinedButton.icon(
                            onPressed: _all ? null : _pickRange,
                            icon: const Icon(Icons.date_range),
                            label: Text(
                              _all
                                  ? '날짜필터 꺼짐'
                                  : '${_fmt(_rangeKst.start)} ~ ${_fmt(_rangeKst.end.subtract(const Duration(days: 1)))}',
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 40),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('전체보기'),
                              Switch(
                                value: _all,
                                onChanged: (v) => setState(() => _all = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () {
                        final now = DateTime.now();
                        final start = DateTime(now.year, now.month, now.day);
                        final end = start.add(const Duration(days: 1));
                        setState(() {
                          _all = false;
                          _branchId = null;
                          _rangeKst = DateTimeRange(start: start, end: end);
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('오늘로 초기화'),
                    ),
                  ],
                ),
                if (_busy || _log.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (_busy)
                        const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      if (_busy) const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _log,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _busy ? Colors.deepPurple : Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final err = snap.error.toString();
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 40),
                  const SizedBox(height: 12),
                  Text('에러: $err', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  const Text(
                    '• collectionGroup 인덱스 링크를 콘솔 로그에서 생성하세요.\n'
                    '• permission-denied면 admin 권한인지 확인.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('해당 조건의 주문이 없습니다.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemBuilder: (_, i) {
              final d = docs[i].data();
              final created =
                  (d['createdAt'] as Timestamp?)?.toDate().toLocal();
              final branch = (d['branchId'] ?? '').toString();
              final client = (d['clientCode'] ?? '').toString();
              final total =
                  (d['total'] is num) ? (d['total'] as num).toInt() : 0;
              final status = (d['status'] ?? '').toString();
              final items = (d['items'] as List? ?? [])
                  .cast<Map<String, dynamic>>();
              final titles = items
                  .map((e) => e['productName'])
                  .whereType<String>()
                  .join(', ');

              return ListTile(
                tileColor: Colors.white,
                title: Text('[${_fmtDT(created)}] $branch • $client'),
                subtitle: Text(titles),
                trailing: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_won(total),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(status),
                  ],
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemCount: docs.length,
          );
        },
      ),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _fmtDT(DateTime? d) =>
      d == null
          ? '-'
          : '${_fmt(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _won(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    int c = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      buf.write(s[i]);
      c++;
      if (c == 3 && i != 0) {
        buf.write(',');
        c = 0;
      }
    }
    return String.fromCharCodes(buf.toString().runes.toList().reversed) + '원';
  }
}

// ====== 누락되어 컴파일 에러났던 위젯들 ======

class _BranchDropdown extends StatelessWidget {
  const _BranchDropdown({required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final q =
        FirebaseFirestore.instance.collection('branches').orderBy('name');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        final items = <DropdownMenuItem<String?>>[
          const DropdownMenuItem(value: null, child: Text('전체 지점')),
        ];
        if (snap.hasData) {
          for (final d in snap.data!.docs) {
            final name = d.data()['name'] ?? d.id;
            items.add(DropdownMenuItem(value: d.id, child: Text(name)));
          }
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: DropdownButton<String?>(
            isExpanded: true,
            value: value,
            items: items,
            onChanged: onChanged,
          ),
        );
      },
    );
  }
}

class _CurrentUserInfo extends StatelessWidget {
  const _CurrentUserInfo();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '-';

    if (uid == '-') {
      return const Padding(
        padding: EdgeInsets.only(right: 8),
        child: Chip(label: Text('로그인 안 됨')),
      );
    }

    final userDoc =
        FirebaseFirestore.instance.collection('user').doc(uid).snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDoc,
      builder: (context, snap) {
        final role = snap.data?.data()?['role']?.toString() ?? '?';
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Chip(label: Text('UID ${uid.substring(0, 6)} • $role')),
              const SizedBox(width: 6),
              IconButton(
                tooltip: '로그아웃',
                icon: const Icon(Icons.logout, size: 20),
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const AuthGate()),
                      (_) => false,
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// ===================================================================
/// 상품마스터 점검 시트
/// ===================================================================
class VariantsAuditSheet extends StatefulWidget {
  const VariantsAuditSheet({super.key});
  @override
  State<VariantsAuditSheet> createState() => _VariantsAuditSheetState();
}

class _VariantsAuditSheetState extends State<VariantsAuditSheet> {
  bool _loading = true;
  List<_P> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ps = await FirebaseFirestore.instance
          .collection('products')
          .orderBy('name')
          .get();

      final out = <_P>[];
      for (final p in ps.docs) {
        final name = (p['name'] ?? p.id).toString();
        final vs = await p.reference
            .collection('variants')
            .orderBy('sortOrder')
            .get();
        final variants = vs.docs.map((v) {
          final m = v.data();
          final label = (m['label'] ?? v.id).toString();
          final gp = (m['gradePrices'] as Map?) ?? {};
          int toInt(x) => x is num ? x.toInt() : int.tryParse('${x ?? ''}') ?? 0;
          return _V(
            vid: v.id,
            label: label,
            a: toInt(gp['A']),
            b: toInt(gp['B']),
            c: toInt(gp['C']),
          );
        }).toList();
        out.add(_P(pid: p.id, name: name, variants: variants));
      }
      if (mounted) setState(() => _rows = out);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.6,
        builder: (_, controller) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            const Text('상품마스터 (products / variants)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_rows.isEmpty)
              const Expanded(child: Center(child: Text('표시할 데이터가 없습니다.')))
            else
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  itemCount: _rows.length,
                  itemBuilder: (_, i) {
                    final p = _rows[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ExpansionTile(
                        title: Text('${p.name}  ·  ${p.variants.length}개',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('VID')),
                                DataColumn(label: Text('사이즈/라벨')),
                                DataColumn(label: Text('A')),
                                DataColumn(label: Text('B')),
                                DataColumn(label: Text('C')),
                              ],
                              rows: p.variants
                                  .map(
                                    (v) => DataRow(
                                      cells: [
                                        DataCell(Text(v.vid)),
                                        DataCell(Text(v.label)),
                                        DataCell(Text('${v.a}')),
                                        DataCell(Text('${v.b}')),
                                        DataCell(Text('${v.c}')),
                                      ],
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('닫기'),
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

class _P {
  _P({required this.pid, required this.name, required this.variants});
  final String pid;
  final String name;
  final List<_V> variants;
}

class _V {
  _V({required this.vid, required this.label, required this.a, required this.b, required this.c});
  final String vid;
  final String label;
  final int a, b, c;
}
