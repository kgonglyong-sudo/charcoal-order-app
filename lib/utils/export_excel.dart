// lib/utils/export_excel.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xls;

enum ExportSheet { byDate, byClient, byProduct }

class OrderExcelExporter {
  /// Firestore에서 기간+요일 필터로 주문을 조회하고
  /// 선택된 시트들(일자별/거래처별/품목별)로 하나의 엑셀 파일을 만들어 공유한다.
  static Future<void> export({
    required String branchId,
    required DateTimeRange rangeKst,   // [start, end) end는 다음날 00:00
    required Set<int> weekdays,        // 1=월 ... 7=일
    required Set<ExportSheet> sheets,  // 어떤 시트를 포함할지
    String? fileName,                  // 없으면 자동 생성
  }) async {
    // 1) 쿼리 (기간만 서버에서 걸고, 요일은 클라에서 필터)
    final q = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('orders')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(rangeKst.start.toUtc()))
        .where('createdAt', isLessThan: Timestamp.fromDate(rangeKst.end.toUtc()))
        .orderBy('createdAt', descending: false);

    final snap = await q.get();
    final docs = snap.docs.where((d) {
      final ts = (d['createdAt'] as Timestamp?)?.toDate().toLocal();
      if (ts == null) return false;
      return weekdays.contains(ts.weekday);
    }).toList();

    // 2) 워크북 생성
    final book = xls.Workbook();
    // Syncfusion은 기본 시트 1개 자동 생성 → 마지막에 필요 없으면 제거
    final autoSheet = book.worksheets[0];
    autoSheet.name = 'Temp';

    if (sheets.contains(ExportSheet.byDate)) {
      _buildByDateSheet(book, docs);
    }
    if (sheets.contains(ExportSheet.byClient)) {
      _buildByClientSheet(book, docs);
    }
    if (sheets.contains(ExportSheet.byProduct)) {
      _buildByProductSheet(book, docs);
    }

    // Temp 시트 제거
    if (book.worksheets.count > 1) {
      book.worksheets.removeAt(0);
    } else {
      // 아무 시트도 없으면 안내 시트 유지
      autoSheet.getRangeByIndex(1, 1).setText('데이터가 없습니다.');
    }

    // 3) 저장 & 공유
    final now = DateTime.now();
    final fname = fileName ??
        'orders_${branchId}_${_fmtYmd(now)}_${now.hour.toString().padLeft(2,'0')}${now.minute.toString().padLeft(2,'0')}.xlsx';

    final bytes = book.saveAsStream();
    book.dispose();

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fname');
    await file.writeAsBytes(bytes, flush: true);

    await Share.shareXFiles([XFile(file.path)], text: '주문 내보내기');
  }

  /// 시트 1: 일자별 합계 + 상세
  static void _buildByDateSheet(xls.Workbook book, List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final ws = book.worksheets.addWithName('일자별');
    // 헤더
    _head(ws, ['일자','시간','거래처','상태','품목(요약)','합계']);
    int r = 2;

    // 날짜별 합계 계산을 위해 정렬
    final sorted = [...docs]..sort((a,b){
      final ta = (a['createdAt'] as Timestamp).toDate();
      final tb = (b['createdAt'] as Timestamp).toDate();
      return ta.compareTo(tb);
    });

    String? curDay;
    int daySum = 0;

    for (final d in sorted) {
      final m = d.data();
      final created = (m['createdAt'] as Timestamp?)?.toDate().toLocal();
      final ymd = created!=null ? _fmtYmd(created) : '-';
      final hm  = created!=null ? _fmtHm(created) : '--:--';
      final client = (m['clientCode'] as String?) ?? '';
      final status = (m['status'] as String?) ?? '';
      final total  = (m['total'] as num?)?.toInt() ?? 0;
      final items  = (m['items'] as List?)?.cast<Map>() ?? const [];
      final title  = items.map((e)=> e['productName']).whereType<String>().join(', ');

      // 날짜 섹션 구분줄 출력
      if (curDay != ymd) {
        if (curDay != null) {
          // 직전 날짜 합계 줄 출력
          _bold(ws, r, 1, '소계 ($curDay)');
          ws.getRangeByIndex(r, 6).setNumber(daySum.toDouble());
          ws.getRangeByIndex(r, 6).numberFormat = '#,##0';
          r += 2;
        }
        curDay = ymd;
        daySum = 0;
        _section(ws, r, 1, '$ymd');
        r++;
      }

      daySum += total;
      ws.getRangeByIndex(r,1).setText(ymd);
      ws.getRangeByIndex(r,2).setText(hm);
      ws.getRangeByIndex(r,3).setText(client);
      ws.getRangeByIndex(r,4).setText(status);
      ws.getRangeByIndex(r,5).setText(title);
      ws.getRangeByIndex(r,6).setNumber(total.toDouble());
      ws.getRangeByIndex(r,6).numberFormat = '#,##0';
      r++;
    }

    // 마지막 날짜 소계
    if (curDay != null) {
      _bold(ws, r, 1, '소계 ($curDay)');
      ws.getRangeByIndex(r, 6).setNumber(daySum.toDouble());
      ws.getRangeByIndex(r, 6).numberFormat = '#,##0';
    }

    _autofit(ws, 6);
  }

  /// 시트 2: 거래처별 집계
  static void _buildByClientSheet(xls.Workbook book, List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final ws = book.worksheets.addWithName('거래처별');
    _head(ws, ['거래처','주문수','총액']);
    final map = <String,_Agg>{}; // client -> agg

    for (final d in docs) {
      final m = d.data();
      final client = (m['clientCode'] as String?) ?? '(미지정)';
      final total  = (m['total'] as num?)?.toInt() ?? 0;
      map.putIfAbsent(client, ()=> _Agg()).add(total);
    }

    final rows = map.entries.toList()..sort((a,b)=> b.value.sum.compareTo(a.value.sum));
    int r=2;
    for (final e in rows) {
      ws.getRangeByIndex(r,1).setText(e.key);
      ws.getRangeByIndex(r,2).setNumber(e.value.count.toDouble());
      ws.getRangeByIndex(r,3).setNumber(e.value.sum.toDouble());
      ws.getRangeByIndex(r,3).numberFormat = '#,##0';
      r++;
    }
    _autofit(ws, 3);
  }

  /// 시트 3: 품목별(상품ID/이름) 집계
  static void _buildByProductSheet(xls.Workbook book, List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final ws = book.worksheets.addWithName('품목별');
    _head(ws, ['productId','상품명','수량','매출']);
    final agg = <String, _ProdAgg>{}; // productId -> agg(name,qty,sum)

    for (final d in docs) {
      final items = (d['items'] as List?)?.cast<Map>() ?? const [];
      for (final it in items) {
        final pid = (it['productId'] as String?) ?? '(id없음)';
        final name = (it['productName'] as String?) ?? '(이름없음)';
        final price = (it['price'] as num?)?.toInt() ?? 0;
        final qty   = (it['quantity'] as num?)?.toInt() ?? 0;
        agg.putIfAbsent(pid, ()=> _ProdAgg(name));
        agg[pid]!.qty += qty;
        agg[pid]!.sum += price * qty;
      }
    }

    final rows = agg.entries.toList()..sort((a,b)=> b.value.sum.compareTo(a.value.sum));
    int r=2;
    for (final e in rows) {
      ws.getRangeByIndex(r,1).setText(e.key);
      ws.getRangeByIndex(r,2).setText(e.value.name);
      ws.getRangeByIndex(r,3).setNumber(e.value.qty.toDouble());
      ws.getRangeByIndex(r,4).setNumber(e.value.sum.toDouble());
      ws.getRangeByIndex(r,4).numberFormat = '#,##0';
      r++;
    }
    _autofit(ws, 4);
  }

  // ---------- helpers ----------
  static void _head(xls.Worksheet ws, List<String> cols) {
    for (int i=0; i<cols.length; i++) {
      final c = ws.getRangeByIndex(1, i+1);
      c.setText(cols[i]);
      c.cellStyle.bold = true;
    }
  }

  static void _section(xls.Worksheet ws, int r, int c, String text) {
    final cell = ws.getRangeByIndex(r, c);
    cell.setText(text);
    cell.cellStyle.bold = true;
  }

  static void _bold(xls.Worksheet ws, int r, int c, String text) {
    final cell = ws.getRangeByIndex(r, c);
    cell.setText(text);
    cell.cellStyle.bold = true;
  }

  static void _autofit(xls.Worksheet ws, int colCount) {
    for (int i=1; i<=colCount; i++) {
      ws.autoFitColumn(i);
    }
  }

  static String _fmtYmd(DateTime d){
    final y='${d.year}'.padLeft(4,'0');
    final m='${d.month}'.padLeft(2,'0');
    final day='${d.day}'.padLeft(2,'0');
    return '$y-$m-$day';
  }

  static String _fmtHm(DateTime d){
    final h='${d.hour}'.padLeft(2,'0');
    final m='${d.minute}'.padLeft(2,'0');
    return '$h:$m';
  }
}

class _Agg {
  int count = 0;
  int sum = 0;
  void add(int v){ count++; sum += v; }
}

class _ProdAgg {
  _ProdAgg(this.name);
  final String name;
  int qty = 0;
  int sum = 0;
}
