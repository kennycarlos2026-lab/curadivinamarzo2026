import 'dart:io';

void main() {
  final file = File('lib/main.dart');
  var content = file.readAsStringSync();
  
  content = content.replaceAll('"Alarme"', "t('menuAlarm')");
  content = content.replaceAll('"e Temporizador"', "t('menuAlarmSub')");
  content = content.replaceAll('"(Contas e Pix)"', '"(\${t(\\'menuSupportSub\\')})"');
  
  file.writeAsStringSync(content);
  print('Done replacements.');
}
