// lib/dev/migration_tools.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// 마이그레이션 리포트 모델
class _MigReport {
  int movedTop = 0;
  int deletedTop = 0;
  int movedUser = 0;
  int deletedUser = 0;

  final List<String> errors = [];
  final List<String> skips = [];
  final List<String> successes = [];

  String format() {
    final b = StringBuffer();
    b.writeln('최상위 clients → 이관: $movedTop, 삭제: $deletedTop');
    b.writeln('user → 이관: $movedUser, 삭제: $deletedUser');
    if (errors.isNotEmpty) {
      b.writeln('\n오류(${errors.length}) ▼');
      for (final e in errors) b.writeln('• $e');
    } else {
      b.writeln('\n오류: 0');
    }
    if (skips.isNotEmpty) {
      b.writeln('\n스킵(${skips.length}) ▼');
      for (final s in skips) b.writeln('• $s');
    }
    if (successes.isNotEmpty) {
      b.writeln('\n성공(${successes.length}) 일부 ▼');
      // 너무 길어지는 것 방지: 앞 10개만 표시
      for (final s in successes.take(10)) b.writeln('• $s');
      if (successes.length > 10) {
        b.writeln('… 외 ${successes.length - 10}건');
      }
    }
    return b.toString();
  }
}

/// 잘못된 위치의 거래처 문서를
/// branches/{branchId}/clients/{clientCode} 로 이관
/// [apply] == false → 드라이런(미적용)
/// [deleteOriginals] 가 true면 실제 적용 시 원본 삭제
Future<_MigReport> migrateClients({required bool apply, bool deleteOriginals = true}) async {
  final db = FirebaseFirestore.instance;
  final r = _MigReport();

  // 1) 최상위 clients 컬렉션 → 이동
  try {
    final topClients = await db.collection('clients').get();
    for (final d in topClients.docs) {
      try {
        final m = d.data();
        final branchId = (m['branchId'] as String?)?.trim() ?? '';
        final clientCode = (m['clientCode'] as String?)?.trim() ?? d.id;
        final name = (m['name'] as String?) ?? '';
        final priceTier = (m['priceTier'] ?? 'B').toString().toUpperCase();
        final memo = (m['memo'] as String?) ?? '';
        final overrides = (m['priceOverrides'] as Map?) ;

        // 유효성 검사
        if (branchId.isEmpty || clientCode.isEmpty) {
          r.skips.add('clients/${d.id} → branchId 또는 clientCode 누락 (branchId="$branchId", clientCode="$clientCode")');
          continue;
        }

        final target = db
            .collection('branches').doc(branchId)
            .collection('clients').doc(clientCode);

        if (apply) {
          await target.set({
            'clientCode': clientCode,
            'name': name,
            'priceTier': priceTier,
            'memo': memo,
            if (overrides != null) 'priceOverrides': overrides,
            'createdAt': m['createdAt'] ?? FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          r.movedTop += 1;

          if (deleteOriginals) {
            await d.reference.delete();
            r.deletedTop += 1;
          }
          r.successes.add('clients/${d.id} → branches/$branchId/clients/$clientCode');
        } else {
          // 드라이런
          r.movedTop += 1;
          r.successes.add('[DRY] clients/${d.id} → branches/$branchId/clients/$clientCode');
        }
      } catch (e) {
        r.errors.add('clients/${d.id} 처리 중 오류: $e');
      }
    }
  } catch (e) {
    r.errors.add('최상위 clients 조회 오류: $e');
  }

  // 2) user 컬렉션 중 거래처 형태 → 이동
  try {
    final users = await db.collection('user').get();
    for (final d in users.docs) {
      try {
        final m = d.data();
        final role = (m['role'] as String?)?.toLowerCase().trim();
        if (role != 'client') {
          r.skips.add('user/${d.id} → role != "client"(role="$role")');
          continue;
        }

        final branchId = (m['branchId'] as String?)?.trim() ?? '';
        final clientCode = (m['clientCode'] as String?)?.trim() ?? '';
        final name = (m['name'] as String?) ?? '';
        final priceTier = (m['priceTier'] ?? 'B').toString().toUpperCase();
        final overrides = (m['priceOverrides'] as Map?);

        if (branchId.isEmpty || clientCode.isEmpty) {
          r.skips.add('user/${d.id} → branchId 또는 clientCode 누락 (branchId="$branchId", clientCode="$clientCode")');
          continue;
        }

        final target = db
            .collection('branches').doc(branchId)
            .collection('clients').doc(clientCode);

        if (apply) {
          await target.set({
            'clientCode': clientCode,
            'name': name,
            'priceTier': priceTier,
            if (overrides != null) 'priceOverrides': overrides,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          r.movedUser += 1;

          if (deleteOriginals) {
            // user 문서는 로그인/권한 용도로 쓸 수 있으므로 보통은 삭제하지 않음.
            // 삭제 원하면 아래 주석 해제
            // await d.reference.delete();
            // r.deletedUser += 1;
          }
          r.successes.add('user/${d.id} → branches/$branchId/clients/$clientCode');
        } else {
          r.movedUser += 1;
          r.successes.add('[DRY] user/${d.id} → branches/$branchId/clients/$clientCode');
        }
      } catch (e) {
        r.errors.add('user/${d.id} 처리 중 오류: $e');
      }
    }
  } catch (e) {
    r.errors.add('user 조회 오류: $e');
  }

  return r;
}

/// 간단한 UI
class MigrationToolsScreen extends StatefulWidget {
  const MigrationToolsScreen({super.key});

  @override
  State<MigrationToolsScreen> createState() => _MigrationToolsScreenState();
}

class _MigrationToolsScreenState extends State<MigrationToolsScreen> {
  String _log = '';
  bool _running = false;

  Future<void> _run({required bool apply}) async {
    if (_running) return;
    setState(() => _running = true);
    try {
      final rep = await migrateClients(apply: apply, deleteOriginals: true);
      setState(() => _log = rep.format());
    } catch (e) {
      setState(() => _log = '실행 오류: $e');
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Migration Tools (임시)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'clients(최상위)/user 에 흩어진 거래처 문서를\n'
              'branches/{branchId}/clients/{clientCode} 로 이관합니다.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _running ? null : () => _run(apply: false),
                    child: const Text('드라이런(미적용)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _running ? null : () => _run(apply: true),
                    child: const Text('실제 적용'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('마지막 결과', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: SingleChildScrollView(child: Text(_log.isEmpty ? '─' : _log)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
