import 'dart:io';

String _lang() {
  try {
    final l = Platform.localeName;
    if (l.startsWith('es')) return 'es';
    if (l.startsWith('en')) return 'en';
  } catch (_) {}
  return 'pt'; // base/fallback
}

const _strings = {
  // ─────────────────────────────────────────
  // OVERLAY MENU
  // ─────────────────────────────────────────
  'verseTitle': {
    'pt': 'Versículo Diário',
    'es': 'Versículo Diario',
    'en': 'Daily Verse',
  },
  'menuWebsite': {
    'pt': 'Website',
    'es': 'Sitio Web',
    'en': 'Website',
  },
  'menuAudios': {
    'pt': 'Reprises - Áudios',
    'es': 'Reprises - Audios',
    'en': 'Replays - Audio',
  },
  'menuContact': {
    'pt': 'Contato',
    'es': 'Contacto',
    'en': 'Contact',
  },
  'menuPrayerRequests': {
    'pt': 'Peça oração',
    'es': 'Pida oración',
    'en': 'Request Prayer',
  },
  'menuPrayerRequestsSub': {
    'pt': '– Testemunho',
    'es': '– Testimonio',
    'en': '– Testimony',
  },
  'menuAddresses': {
    'pt': 'Endereços',
    'es': 'Direcciones',
    'en': 'Locations',
  },
  'menuSupport': {
    'pt': 'Ajude esta obra',
    'es': 'Apoya esta obra',
    'en': 'Support this ministry',
  },
  'menuSupportSub': {
    'pt': 'Contas e Pix',
    'es': 'Cuentas',
    'en': 'Accounts & transfers',
  },
  'menuAlarm': {
    'pt': 'Alarme',
    'es': 'Alarma',
    'en': 'Alarm',
  },
  'menuAlarmSub': {
    'pt': 'e Temporizador',
    'es': 'y Temporizador',
    'en': 'and Timer',
  },
  'menuShare': {
    'pt': 'Compartilhar',
    'es': 'Compartir',
    'en': 'Share',
  },
  'shareText': {
    'pt': 'Confira A Voz da Cura Divina https://play.google.com/store/apps/details?id=com.kym.lavozdelacuradivina.radio',
    'es': 'Escucha A Voz da Cura Divina https://play.google.com/store/apps/details?id=com.kym.lavozdelacuradivina.radio',
    'en': 'Listen to A Voz da Cura Divina https://play.google.com/store/apps/details?id=com.kym.lavozdelacuradivina.radio',
  },

  // ─────────────────────────────────────────
  // DIÁLOGO TEMPORIZADOR / ALARMA
  // ─────────────────────────────────────────
  'timerDialogTitle': {
    'pt': 'Temporizador e Alarme',
    'es': 'Temporizador y Alarma',
    'en': 'Timer & Alarm',
  },
  'timer15': {
    'pt': 'Desligar em 15 minutos',
    'es': 'Apagar en 15 minutos',
    'en': 'Turn off in 15 minutes',
  },
  'timer30': {
    'pt': 'Desligar em 30 minutos',
    'es': 'Apagar en 30 minutos',
    'en': 'Turn off in 30 minutes',
  },
  'timer60': {
    'pt': 'Desligar em 1 hora',
    'es': 'Apagar en 1 hora',
    'en': 'Turn off in 1 hour',
  },
  'timerCustom': {
    'pt': 'Tempo Personalizado...',
    'es': 'Tiempo personalizado...',
    'en': 'Custom time...',
  },
  'timerCustomTitle': {
    'pt': 'Tempo Personalizado',
    'es': 'Tiempo personalizado',
    'en': 'Custom time',
  },
  'timerCustomDesc': {
    'pt': 'Digite a duração exata para desligar a rádio',
    'es': 'Escribe el tiempo exacto para apagar la radio',
    'en': 'Enter the exact time to turn off the radio',
  },
  'timerHours': {
    'pt': 'Horas',
    'es': 'Horas',
    'en': 'Hours',
  },
  'timerMinutes': {
    'pt': 'Minutos',
    'es': 'Minutos',
    'en': 'Minutes',
  },
  'timerCancelLabel': {
    'pt': 'Cancelar Temporizador',
    'es': 'Cancelar Temporizador',
    'en': 'Cancel Timer',
  },
  'timerCancelMsg': {
    'pt': 'Temporizador de apagado cancelado.',
    'es': 'Temporizador cancelado.',
    'en': 'Timer cancelled.',
  },
  'timerSnack': {
    'pt': 'A rádio se desligará em {min} minutos.',
    'es': 'La radio se apagará en {min} minutos.',
    'en': 'Radio will turn off in {min} minutes.',
  },
  'alarmSchedule': {
    'pt': 'Programar Alarme',
    'es': 'Programar Alarma',
    'en': 'Set Alarm',
  },
  'alarmCancel': {
    'pt': 'Cancelar Alarme',
    'es': 'Cancelar Alarma',
    'en': 'Cancel Alarm',
  },
  'alarmCancelMsg': {
    'pt': 'Alarme cancelado.',
    'es': 'Alarma cancelada.',
    'en': 'Alarm cancelled.',
  },
  'alarmDaysTitle': {
    'pt': 'Dias da semana',
    'es': 'Días de la semana',
    'en': 'Days of the week',
  },
  'alarmDaysDesc': {
    'pt': 'Selecione os dias para o alarme',
    'es': 'Selecciona los días para la alarma',
    'en': 'Select the alarm days',
  },
  'alarmOnce': {
    'pt': 'Alarme único — próxima ocorrência',
    'es': 'Alarma única — próxima vez',
    'en': 'One-time alarm — next occurrence',
  },
  'alarmRepeat': {
    'pt': 'Repetir semanalmente',
    'es': 'Repetir semanalmente',
    'en': 'Repeat weekly',
  },
  'alarmSetSnack': {
    'pt': 'Alarme programado para as {time}',
    'es': 'Alarma programada para las {time}',
    'en': 'Alarm set for {time}',
  },

  // ─────────────────────────────────────────
  // NOTIFICACIONES
  // ─────────────────────────────────────────
  'notifAlarmTitle': {
    'pt': 'A Voz da Cura Divina',
    'es': 'A Voz da Cura Divina',
    'en': 'A Voz da Cura Divina',
  },
  'notifAlarmBody': {
    'pt': 'Alarme! Toque para ouvir a rádio',
    'es': '¡Alarma! Toca para escuchar la radio',
    'en': 'Alarm! Tap to listen to the radio',
  },
  'notifAlarmChannel': {
    'pt': 'Alarme Despertador',
    'es': 'Alarma de Radio',
    'en': 'Radio Alarm',
  },
  'notifAlarmChannelDesc': {
    'pt': 'Canal para o alarme da rádio',
    'es': 'Canal para la alarma de la radio',
    'en': 'Channel for the radio alarm',
  },

  // ─────────────────────────────────────────
  // ERRORES / CONECTIVIDAD
  // ─────────────────────────────────────────
  'errorNoInternet': {
    'pt': 'Sem conexão com a Internet. Por favor, verifique sua conexão.',
    'es': 'Sin conexión a Internet. Por favor, verifica tu conexión.',
    'en': 'No Internet connection. Please check your connection.',
  },
  'errorPlayback': {
    'pt': 'Erro ao tentar reproduzir.',
    'es': 'Error al intentar reproducir.',
    'en': 'Error trying to play.',
  },
  'errorAudioSource': {
    'pt': 'Erro de fonte de áudio: ',
    'es': 'Error de fuente de audio: ',
    'en': 'Audio source error: ',
  },
  'errorInit': {
    'pt': 'Erro de inicialização: ',
    'es': 'Error de inicialización: ',
    'en': 'Initialization error: ',
  },
  'btnRetry': {
    'pt': 'Tentar novamente',
    'es': 'Reintentar',
    'en': 'Retry',
  },
  'btnCancel': {
    'pt': 'Cancelar',
    'es': 'Cancelar',
    'en': 'Cancel',
  },

  // ─────────────────────────────────────────
  // MODO DE SEÑAL / BUFFER
  // ─────────────────────────────────────────
  'menuSignal': {
    'pt': 'Qualidade do Sinal',
    'es': 'Calidad de Señal',
    'en': 'Signal Quality',
  },
  'signalDialogTitle': {
    'pt': 'Modo de Reprodução',
    'es': 'Modo de Reproducción',
    'en': 'Playback Mode',
  },
  'signalStableTitle': {
    'pt': 'Estável',
    'es': 'Estable',
    'en': 'Stable',
  },
  'signalStableDesc': {
    'pt': 'Protege contra quedas de sinal.\nIdeal para redes móveis ou instáveis.',
    'es': 'Protege ante cortes de señal.\nIdeal para redes móviles o inestables.',
    'en': 'Protects against signal drops.\nBest for mobile or unstable networks.',
  },
  'signalLiveTitle': {
    'pt': 'Ao Vivo',
    'es': 'En Vivo',
    'en': 'Live Edge',
  },
  'signalLiveDesc': {
    'pt': 'Mínimo atraso em relação ao ar.\nRequer conexão estável (Wi-Fi).',
    'es': 'Mínimo retraso respecto al aire.\nRequiere señal estable (Wi-Fi).',
    'en': 'Minimum delay from broadcast.\nRequires stable connection (Wi-Fi).',
  },
  'signalChanged': {
    'pt': 'Modo alterado. Reconectando...',
    'es': 'Modo cambiado. Reconectando...',
    'en': 'Mode changed. Reconnecting...',
  },
  'signalNotifStable': {
    'pt': '📶 Estável',
    'es': '📶 Estable',
    'en': '📶 Stable',
  },
  'signalNotifLive': {
    'pt': '⚡ Ao Vivo',
    'es': '⚡ En Vivo',
    'en': '⚡ Live',
  },
};

/// Función principal de traducción
String t(String key, [String? forceLang]) {
  final lang = forceLang ?? _lang();
  return _strings[key]?[lang] ?? _strings[key]?['pt'] ?? key;
}

/// Para strings con variables: t('timerSnack', {'min': '15'})
String tArgs(String key, Map<String, String> args) {
  String result = t(key);
  args.forEach((k, v) => result = result.replaceAll('{\$k}', v));
  return result;
}
