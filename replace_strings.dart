import 'dart:io';

void main() {
  final file = File('lib/main.dart');
  var content = file.readAsStringSync();
  
  if (!content.contains("import 'app_strings.dart';")) {
    content = content.replaceFirst("import 'package:timezone/timezone.dart' as tz;", "import 'package:timezone/timezone.dart' as tz;\nimport 'app_strings.dart';");
  }

  // Replacements list
  var reps = {
    '"Versículo Diário"': "t('verseTitle')",
    "'Versículo Diário'": "t('verseTitle')",
    '"Website"': "t('menuWebsite')",
    "'Website'": "t('menuWebsite')",
    '"Reprises - Audios"': "t('menuAudios')",
    "'Reprises - Audios'": "t('menuAudios')",
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
    '"La radio se apagará en \${duration.inMinutes} minutos."': "tArgs('timerSnack', {'min': duration.inMinutes.toString()})",
    "'A rádio se desligará em \${duration.inMinutes} minutos.'": "tArgs('timerSnack', {'min': duration.inMinutes.toString()})",
    '"A rádio se desligará em \${duration.inMinutes} minutos."': "tArgs('timerSnack', {'min': duration.inMinutes.toString()})",
    "'Programar Alarme'": "t('alarmSchedule')",
    '"Programar Alarme"': "t('alarmSchedule')",
    "'Cancelar Alarme'": "t('alarmCancel')",
    '"Cancelar Alarme"': "t('alarmCancel')",
    "'Alarme cancelado.'": "t('alarmCancelMsg')",
    "'Alarma cancelada.'": "t('alarmCancelMsg')",
    '"Alarme cancelado."': "t('alarmCancelMsg')",
    '"Alarma cancelada."': "t('alarmCancelMsg')",
    "'Dias da semana'": "t('alarmDaysTitle')",
    '"Dias da semana"': "t('alarmDaysTitle')",
    "'Selecione os dias para o alarme:'": "t('alarmDaysDesc')",
    '"Selecione os dias para o alarme:"': "t('alarmDaysDesc')",
    "'Alarme único (próxima ocorrência)'": "t('alarmOnce')",
    '"Alarme único (próxima ocorrência)"': "t('alarmOnce')",
    "'Repetir semanalmente'": "t('alarmRepeat')",
    '"Repetir semanalmente"': "t('alarmRepeat')",
    "'Alarme programado para as \${intl.DateFormat(\\'HH:mm\\').format(scheduledTime)}'": "tArgs('alarmSetSnack', {'time': intl.DateFormat('HH:mm').format(scheduledTime)})",
    "'Alarme programado para as \${intl.DateFormat(\"HH:mm\").format(scheduledTime)}'": "tArgs('alarmSetSnack', {'time': intl.DateFormat('HH:mm').format(scheduledTime)})",
    '"Alarme programado para as \${intl.DateFormat(\\'HH:mm\\').format(scheduledTime)}"': "tArgs('alarmSetSnack', {'time': intl.DateFormat('HH:mm').format(scheduledTime)})",
    '"A Voz da Cura Divina"': "t('notifAlarmTitle')",
    "'A Voz da Cura Divina'": "t('notifAlarmTitle')",
    "'Alarme! Toque para ouvir a rádio'": "t('notifAlarmBody')",
    '"Alarme! Toque para ouvir a rádio"': "t('notifAlarmBody')",
    "'Alarme Despertador'": "t('notifAlarmChannel')",
    '"Alarme Despertador"': "t('notifAlarmChannel')",
    "'Canal para o alarme da rádio'": "t('notifAlarmChannelDesc')",
    '"Canal para o alarme da rádio"': "t('notifAlarmChannelDesc')",
    "'Sem conexão com a Internet. Por favor, verifique sua conexão.'": "t('errorNoInternet')",
    '"Sem conexão com a Internet. Por favor, verifique sua conexão."': "t('errorNoInternet')",
    "'No hay conexión a Internet. Por favor, verifica tu conexión.'": "t('errorNoInternet')",
    '"No hay conexión a Internet. Por favor, verifica tu conexión."': "t('errorNoInternet')",
    "'Erro ao tentar reproduzir.'": "t('errorPlayback')",
    '"Erro ao tentar reproduzir."': "t('errorPlayback')",
    "'Error al intentar reproducir.'": "t('errorPlayback')",
    '"Error al intentar reproducir."': "t('errorPlayback')",
    "'Erro de fonte de áudio: '": "t('errorAudioSource')",
    '"Erro de fonte de áudio: "': "t('errorAudioSource')",
    "'Error de fuente de audio: '": "t('errorAudioSource')",
    '"Error de fuente de audio: "': "t('errorAudioSource')",
    "'Erro de inicialização: '": "t('errorInit')",
    '"Erro de inicialização: "': "t('errorInit')",
    "'Error de inicialización: '": "t('errorInit')",
    '"Error de inicialización: "': "t('errorInit')",
    "'Tentar novamente'": "t('btnRetry')",
    '"Tentar novamente"': "t('btnRetry')",
    "'Reintentar'": "t('btnRetry')",
    '"Reintentar"': "t('btnRetry')",
    "'Cancelar'": "t('btnCancel')",
    '"Cancelar"': "t('btnCancel')",
    "'Compartilhar'": "t('menuShare')",
    '"Compartilhar"': "t('menuShare')",
    "'Confira A Voz da Cura Divina: https://play.google.com/store/apps/details?id=com.kym.lavozdelacuradivina.radio'": "t('shareText')",
    '"Confira A Voz da Cura Divina: https://play.google.com/store/apps/details?id=com.kym.lavozdelacuradivina.radio"': "t('shareText')",
    
    // Some interpolations like "Error de inicialización: \${e.toString()}"
    "'Error de inicialización: \${e.toString()}'": "t('errorInit') + e.toString()",
    "'Error de fuente de audio: \$errorStr'": "t('errorAudioSource') + errorStr",
  };

  reps.forEach((k, v) => content = content.replaceAll(k, v));
  
  // Custom logic for scheduleOneAlarm and playRadio isolating SharedPreferences
  // We need to pass lang.
  // Wait, I will do this manually inside the script just to be sure.
  
  file.writeAsStringSync(content);
  print('Done.');
}
