import 'dart:typed_data';
import 'dart:html' as html;

Future<void> saveXlsx(Uint8List bytes, String filename) async {
  final blob = html.Blob([bytes],
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final a = html.AnchorElement(href: url)..download = filename;
  a.click();
  html.Url.revokeObjectUrl(url);
}
