import 'dart:io';

void main() {
  final file = File('lib/main.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll('Color(0xFF0A192F)', 'Color(0xFF183153)');
  content = content.replaceAll('Color(0xFF000D33)', 'Color(0xFF0A2254)');
  file.writeAsStringSync(content);
  print('Replaced colors successfully.');
}
