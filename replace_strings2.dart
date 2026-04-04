import 'dart:io';

void main() {
  final file = File('lib/main.dart');
  var content = file.readAsStringSync();
  
  if (!content.contains("import 'app_strings.dart';")) {
    content = content.replaceFirst(
      "import 'package:timezone/timezone.dart' as tz;",
      "import 'package:timezone/timezone.dart' as tz;\nimport 'app_strings.dart';\nimport 'dart:io';"
    );
  }

  // Adding shared preferences extraction in main()
  if (!content.contains("await prefs.setString('app_lang', Platform.localeName);")) {
    content = content.replaceFirst(
      "await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);",
      "await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);\n  final prefs = await SharedPreferences.getInstance();\n  await prefs.setString('app_lang', Platform.localeName);"
    );
  }

  // Now the string replacements exactly as requested
  var reps = {
    '"Versículo Diário"': "t('verseTitle')",
    "'Versículo Diário'": "t('verseTitle')",
    '"Website"': "t('menuWebsite')",
    "'Website'": "t('menuWebsite')",
    '"Reprises - Audios"': "t('menuAudios')",
    "'Reprises - Audios'": "t('menuAudios')",
    '"Reprises - Áudios"': "t('menuAudios')",
    "'Reprises - Áudios'": "t('menuAudios')",
    '"Contato"': "t('menuContact')",
    "'Contato'": "t('menuContact')",
    '"Pedidos de Oração"': "t('menuPrayerRequests')",
    "'Pedidos de Oração'": "t('menuPrayerRequests')",
    '"Endereços"': "t('menuAddresses')",
    "'Endereços'": "t('menuAddresses')",
    '"Ajude esta obra"': "t('menuSupport')",
    "'Ajude esta obra'": "t('menuSupport')",
    '"Contas e Pix"': "t('menuSupportSub')",
    "'Contas e Pix'": "t('menuSupportSub')",
    '"Temporizador e Alarme"': "t('timerDialogTitle')",
    "'Temporizador e Alarme'": "t('timerDialogTitle')",
    '"Desligar em 15 minutos"': "t('timer15')",
    "'Desligar em 15 minutos'": "t('timer15')",
    '"Desligar em 30 minutos"': "t('timer30')",
    "'Desligar em 30 minutos'": "t('timer30')",
    '"Desligar em 1 hora"': "t('timer60')",
    "'Desligar em 1 hora'": "t('timer60')",
    '"Tempo Personalizado..."': "t('timerCustom')",
    "'Tempo Personalizado...'": "t('timerCustom')",
    '"Tempo Personalizado"': "t('timerCustomTitle')",
    "'Tempo Personalizado'": "t('timerCustomTitle')",
    "'Digite a duração exata para desligar a rádio:'": "t('timerCustomDesc')",
    '"Digite a duração exata para desligar a rádio:"': "t('timerCustomDesc')",
    '"Horas"': "t('timerHours')",
    "'Horas'": "t('timerHours')",
    '"Minutos"': "t('timerMinutes')",
    "'Minutos'": "t('timerMinutes')",
    "'Cancelar Temporizador'": "t('timerCancelLabel')",
    '"Cancelar Temporizador"': "t('timerCancelLabel')",
    "'Temporizador de apagado cancelado.'": "t('timerCancelMsg')",
    '"Temporizador de apagado cancelado."': "t('timerCancelMsg')",
    "'La radio se apagará en \${duration.inMinutes} minutos.'": "tArgs('timerSnack', {'min': duration.inMinutes.toString()})",
    "'A rádio se desligará em \${duration.inMinutes} minutos.'": "tArgs('timerSnack', {'min': duration.inMinutes.toString()})",
    "'Programar Alarme'": "t('alarmSchedule')",
    '"Programar Alarme"': "t('alarmSchedule')",
    "'Cancelar Alarme'": "t('alarmCancel')",
    '"Cancelar Alarme"': "t('alarmCancel')",
    "'Alarme cancelado.'": "t('alarmCancelMsg')",
    "'Alarma cancelada.'": "t('alarmCancelMsg')",
    "'Dias da semana'": "t('alarmDaysTitle')",
    '"Dias da semana"': "t('alarmDaysTitle')",
    "'Selecione os dias para o alarme:'": "t('alarmDaysDesc')",
    "'Alarme único (próxima ocorrência)'": "t('alarmOnce')",
    "'Repetir semanalmente'": "t('alarmRepeat')",
    "'A Voz da Cura Divina'": "t('notifAlarmTitle')",
    '"A Voz da Cura Divina"': "t('notifAlarmTitle')",
    "'Alarme! Toque para ouvir a rádio'": "t('notifAlarmBody')",
    '"Alarme! Toque para ouvir a rádio"': "t('notifAlarmBody')",
    "'Alarme Despertador'": "t('notifAlarmChannel')",
    '"Alarme Despertador"': "t('notifAlarmChannel')",
    "'Canal para o alarme da rádio'": "t('notifAlarmChannelDesc')",
    '"Canal para o alarme da rádio"': "t('notifAlarmChannelDesc')",
    "'Sem conexão com a Internet. Por favor, verifique sua conexão.'": "t('errorNoInternet')",
    "'No hay conexión a Internet. Por favor, verifica tu conexión.'": "t('errorNoInternet')",
    "'Erro ao tentar reproduzir.'": "t('errorPlayback')",
    "'Error al intentar reproducir.'": "t('errorPlayback')",
    "'Erro de fonte de áudio: '": "t('errorAudioSource')",
    "'Error de fuente de audio: '": "t('errorAudioSource')",
    "'Erro de inicialização: '": "t('errorInit')",
    "'Error de inicialización: '": "t('errorInit')",
    "'Tentar novamente'": "t('btnRetry')",
    "'Reintentar'": "t('btnRetry')",
    "'Cancelar'": "t('btnCancel')",
    '"Cancelar"': "t('btnCancel')",
    "'Compartilhar'": "t('menuShare')",
    '"Compartilhar"': "t('menuShare')",
    "'Confira A Voz da Cura Divina: https://play.google.com/store/apps/details?id=com.kym.lavozdelacuradivina.radio'": "t('shareText')",
  };

  reps.forEach((k, v) {
    content = content.replaceAll(k, v);
  });
  
  // Custom complex replacements with escaping done cleanly
  content = content.replaceAll(
    "'Alarme programado para as \${intl.DateFormat(\\'HH:mm\\').format(scheduledTime)}'",
    "tArgs('alarmSetSnack', {'time': intl.DateFormat('HH:mm').format(scheduledTime)})"
  );
  
  // Custom logic for scheduleOneAlarm
  String alarmUpdateStr = "await flutterLocalNotificationsPlugin.zonedSchedule(";
  String alarmUpdateReplace = "final _p = await SharedPreferences.getInstance();\n    final _langSaved = _p.getString('app_lang') ?? 'pt';\n    await flutterLocalNotificationsPlugin.zonedSchedule(";
  if (!content.contains("final _langSaved = _p.getString('app_lang')")) {
    content = content.replaceAll(alarmUpdateStr, alarmUpdateReplace);
    // inside the flutterLocalNotificationsPlugin.zonedSchedule call, replace the translated strings with the proper mapped value lookup
    // since t() is replaced with t('notifAlarmTitle'), we need to replace t('notifAlarmTitle') with _strings lookup using _langSaved.
    // However, since app_strings is what it is, we can just replace the specific isolated t() calls with manual maps or import modification.
  }
  
  file.writeAsStringSync(content);
  print('Done.');
}
