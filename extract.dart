import 'dart:io';
void main() {
  final bytes = File('old_main3.dart').readAsBytesSync();
  final sb = StringBuffer();
  for (int i = 0; i < bytes.length; i += 2) {
    if (i + 1 < bytes.length) {
      if (bytes[i] == 0 && bytes[i+1] == 0) continue;
      sb.writeCharCode(bytes[i] | (bytes[i+1] << 8));
    }
  }
  final text = sb.toString();
  final start = text.indexOf('Widget _buildLandscapeRight');
  if (start == -1) { print("Not found"); return; }
  final end = text.indexOf('Widget _buildLandscapeGridItem', start);
  File('landscape_code_out.txt').writeAsStringSync(text.substring(start, end));
}
