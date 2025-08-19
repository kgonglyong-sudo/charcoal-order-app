// lib/utils/delivery_utils.dart
import 'package:intl/intl.dart';

/// 요일 라벨 (1=월 ... 7=일)
String wdLabel(int wd) => const ['월','화','수','목','금','토','일'][wd-1];

/// 이번 주(월~일 기준)에서 days(예: [1,4])의 '가장 가까운 날짜'를 구해 텍스트로 반환.
/// 오늘이 해당 요일이면 오늘 날짜가 나옵니다.
/// ex) "2025-08-13(수)"
String nextDeliveryThisWeekLabel(List<int> days, {DateTime? now}) {
  now ??= DateTime.now();
  // 이번 주 월요일 00:00
  final monday = now.subtract(Duration(days: now.weekday - 1));
  DateTime? pick;
  for (final d in (days.toList()..sort())) {
    final date = DateTime(monday.year, monday.month, monday.day).add(Duration(days: d - 1));
    if (pick == null || date.isBefore(pick!)) {
      // 이번 주 내 날짜만
      pick = date;
    }
    // 오늘 이후/이전 상관없이 이번 주 날짜를 보여주는 요구라면 위 로직이면 충분.
    // 만약 '오늘 이전 요일은 다음 주'로 넘기고 싶으면 조건을 바꿔줘.
  }
  if (pick == null) return '-';
  final f = DateFormat('yyyy-MM-dd');
  return '${f.format(pick)}(${wdLabel(pick.weekday)})';
}

/// 선택된 요일 배열을 "월, 목" 같은 문자열로
String daysLabel(List<int> days) {
  final s = days.toList()..sort();
  return s.map(wdLabel).join(', ');
}
