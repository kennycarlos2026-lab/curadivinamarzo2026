import 'dart:async';
import 'dart:isolate';
import 'dart:math' as Math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:marquee/marquee.dart';

import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:intl/intl.dart' as intl;
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sleek_circular_slider/sleek_circular_slider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'banner_avisos.dart';
import 'versiculos_promesas.dart';
import 'alarm_manager.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
final StreamController<String?> selectNotificationStream =
    StreamController<String?>.broadcast();
final ReceivePort alarmReceivePort = ReceivePort();

@pragma('vm:entry-point')
void playRadio() async {
  final SendPort? sendPort = IsolateNameServer.lookupPortByName('alarm_port');
  if (sendPort != null) {
    sendPort.send('play');
    return;
  }

  final audioPlayer = AudioPlayer();
  try {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await JustAudioBackground.init(
        androidNotificationChannelId:
            'com.kym.lavozdelacuradivina.radio.channel.alarm',
        androidNotificationChannelName: 'Radio A Voz da Cura Divina - Alarma',
        androidNotificationOngoing: true,
        androidNotificationIcon: 'drawable/ic_notification',
      );
    }
    const String streamUrl = 'https://s10.maxcast.com.br:9083/live';
    final mediaItem = MediaItem(
      id: streamUrl,
      title: 'A Voz da Cura Divina - Alarma',
      artist: 'Radio ao vivo',
      artUri: Uri.parse('https://i.ibb.co/XZKxHq3x/LOGOFONDOBARAPPok.jpg'),
    );
    await audioPlayer
        .setAudioSource(AudioSource.uri(Uri.parse(streamUrl), tag: mediaItem));
    await audioPlayer.play();
  } catch (e) {
    debugPrint("Error playing from background alarm: $e");
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  IsolateNameServer.registerPortWithName(
      alarmReceivePort.sendPort, 'alarm_port');
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Request permissions for notifications
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    debugPrint('User granted permission');
  } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
    debugPrint('User granted provisional permission');
  } else {
    debugPrint('User declined or has not accepted permission');
  }

  // Handle foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('Got a message whilst in the foreground!');
    if (message.notification != null) {
      debugPrint(
          'Message also contained a notification: ${message.notification!.title}');
    }
  });

  // Get and print FCM Token
  try {
    String? token = await messaging.getToken();
    debugPrint("FCM Token: $token");
  } catch (e) {
    debugPrint("Error getting FCM token: $e");
  }

  await initializeDateFormatting('pt_BR', null);

  tz.initializeTimeZones();
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('ic_notification');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) async {
      selectNotificationStream.add(response.payload);
    },
  );

  bool autoPlay = false;
  final NotificationAppLaunchDetails? notificationAppLaunchDetails =
      await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
  if (notificationAppLaunchDetails?.didNotificationLaunchApp ?? false) {
    autoPlay = true;
  }

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await AndroidAlarmManager.initialize();
  }
  try {
    if (!kIsWeb) {
      await JustAudioBackground.init(
        androidNotificationChannelId:
            'com.kym.lavozdelacuradivina.radio.channel.audio',
        androidNotificationChannelName: 'Radio A Voz da Cura Divina',
        androidNotificationOngoing: true,
        notificationColor: const Color(0xFF80DEEA),
        androidNotificationIcon: 'drawable/ic_notification',
      );
    }
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  } catch (e) {
    debugPrint('Error inicializando plugins de audio: $e');
  }
  runApp(MyApp(autoPlay: autoPlay));
}

class MyApp extends StatelessWidget {
  final bool autoPlay;
  const MyApp({Key? key, this.autoPlay = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'A Voz da Cura Divina',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      home: RadioHome(autoPlay: autoPlay),
    );
  }
}

class RadioHome extends StatefulWidget {
  final bool autoPlay;
  const RadioHome({Key? key, this.autoPlay = false}) : super(key: key);
  static const String streamUrl = 'https://s10.maxcast.com.br:9083/live';

  @override
  State<RadioHome> createState() => _RadioHomeState();
}

class _RadioHomeState extends State<RadioHome>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isDarkMode = false;
  bool _isInitialLoading = true;
  String _errorMessage = '';
  late Stream<DateTime> _clockStream;
  double _volume = 1.0;
  bool _showVolumeIndicator = false;
  Timer? _volumeIndicatorTimer;
  bool _isConnecting = false;
  Timer? _sleepTimer;
  Duration? _remainingSleepTime;
  Timer? _uiUpdateTimer;
  DateTime? _alarmTime;
  static const int alarmId = 0;
  static const String chavePix = "TU_CLAVE_AQUI";

  // Web View State
  bool _isWebMode = false;
  String _currentWebUrl = '';
  InAppWebViewController? _webViewController;
  double _dragOffset = 0.0;
  bool _isDragging = false;

  late AnimationController _equalizerController;
  String _marqueeText = ''; // Variable para el texto en movimiento del mini player

  bool get _supportsAndroidAlarm =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _equalizerController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _clockStream =
        Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now())
            .asBroadcastStream();
    _loadPreferencesAndInitialize();

    alarmReceivePort.listen((message) async {
      if (message == 'play') {
        _cancelAlarm();
        if (!_audioPlayer.playerState.playing) {
          await _playOrStopStream();
        }
      }
    });

    _initializePlayer().then((_) {
      if (widget.autoPlay) _cancelAlarm();
      if (!_audioPlayer.playerState.playing) {
        _playOrStopStream();
      }
    });

    selectNotificationStream.stream.listen((String? payload) async {
      _cancelAlarm();
      if (!_audioPlayer.playerState.playing) {
        await _playOrStopStream();
      }
    });
  }

  Future<void> _loadPreferencesAndInitialize() async {
    if (_supportsAndroidAlarm) {
      final prefs = await SharedPreferences.getInstance();
      final alarmMillis = prefs.getInt('alarmTime');
      if (alarmMillis != null) {
        _alarmTime = DateTime.fromMillisecondsSinceEpoch(alarmMillis);
        if (_alarmTime!.isBefore(DateTime.now())) {
          _alarmTime = null;
          await prefs.remove('alarmTime');
        }
      }
    }
    setState(() => _isInitialLoading = false);
  }

  void _openWebMode(String url) {
    setState(() {
      _currentWebUrl = url;
      _isWebMode = true;
      _dragOffset = 0.0;
    });
  }

  void _closeWebMode() {
    setState(() {
      _isWebMode = false;
      _dragOffset = 0.0;
      _isDragging = false;
    });
  }

  Future<bool> _handlePop() async {
    if (_isWebMode) {
      if (_webViewController != null && await _webViewController!.canGoBack()) {
        _webViewController!.goBack();
        return false;
      } else {
        _closeWebMode();
        return false;
      }
    }
    return true;
  }

  Future<void> _initializePlayer() async {
    _audioPlayer.setVolume(_volume);

    // Escuchar metadatos de la radio (ICY) para el Marquee del miniplayer
    _audioPlayer.icyMetadataStream.listen((metadata) {
      if (metadata != null && metadata.info != null) {
        final title = metadata.info?.title ?? '';
        if (title.isNotEmpty && mounted) {
          setState(() {
            _marqueeText = title;
          });
        }
      }
    });

    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) setState(() {});
      if (state.playing && _errorMessage.isNotEmpty) {
        if (mounted) setState(() => _errorMessage = '');
      }
      // 1. Control determinista del Spinner basado en el estado interno
      if (state.playing &&
          (state.processingState == ProcessingState.loading ||
              state.processingState == ProcessingState.buffering)) {
        if (!_isConnecting && mounted) setState(() => _isConnecting = true);
      } else {
        if (_isConnecting && mounted) setState(() => _isConnecting = false);
      }

      // Intercept Pause -> stop() limpio. Cierra conexión y notificación.
      if (!state.playing &&
          state.processingState != ProcessingState.idle &&
          state.processingState != ProcessingState.completed) {
        _audioPlayer.stop();
      }
    });
    _audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _restartStream();
    });
    try {
      await _initializeAudio();
    } catch (e) {
      if (mounted)
        setState(
            () => _errorMessage = 'Error de inicialización: ${e.toString()}');
    } finally {
      if (mounted && _isInitialLoading) {
        setState(() => _isInitialLoading = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _equalizerController.dispose();
    _audioPlayer.dispose();
    _volumeIndicatorTimer?.cancel();
    _sleepTimer?.cancel();
    _uiUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeAudio() async {
    if (!mounted) return;
    setState(() => _errorMessage = '');
    try {
      final mediaItem = MediaItem(
        id: RadioHome.streamUrl,
        title: 'A Voz da Cura Divina',
        artist: 'Radio ao vivo',
        artUri: Uri.parse('https://i.ibb.co/XZKxHq3x/LOGOFONDOBARAPPok.jpg'),
      );
      await _audioPlayer.setAudioSource(
          AudioSource.uri(Uri.parse(RadioHome.streamUrl), tag: mediaItem),
          preload: false);
    } catch (e) {
      final errorStr = e.toString();
      // Si el usuario toca botones rápido, aborta la carga vieja. Ignoramos ese error visualmente.
      if (errorStr.contains('interrupted') ||
          errorStr.contains('aborted') ||
          errorStr.contains('cancelled')) return;

      if (mounted)
        setState(() => _errorMessage = 'Error de fuente de audio: $errorStr');
    }
  }

  Future<void> _restartStream() async {
    if (_isConnecting) return;
    try {
      await _audioPlayer.stop();
      await _initializeAudio();
    } catch (e) {
      debugPrint("Error al reiniciar el stream: $e");
    }
  }

  Future<void> _playOrStopStream() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      if (mounted)
        setState(() => _errorMessage =
            'No hay conexión a Internet. Por favor, verifica tu conexión.');
      return;
    }
    setState(() => _errorMessage = '');
    if (_audioPlayer.playerState.playing) {
      await _audioPlayer.stop();
    } else {
      try {
        if (_audioPlayer.processingState == ProcessingState.idle) {
          await _initializeAudio();
        }
        await _audioPlayer.play();
      } catch (e) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Error al intentar reproducir.';
          });
        }
      }
    }
  }

  void _showTimerAndAlarmDialog() {
    final textColor = _isDarkMode ? Colors.white70 : Colors.black;
    final titleColor = _isDarkMode ? Colors.blue.shade700 : Colors.black;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          backgroundColor: _isDarkMode ? const Color(0xFF0A192F) : Colors.white,
          title: Text('Temporizador e Alarme',
              style: TextStyle(color: titleColor)),
          children: <Widget>[
            _buildTimerOption(15, 'Desligar em 15 minutos'),
            _buildTimerOption(30, 'Desligar em 30 minutos'),
            _buildTimerOption(60, 'Desligar em 1 hora'),
            _buildCustomTimerOption(),
            if (_sleepTimer != null)
              _buildCancelOption('Cancelar Temporizador', _cancelSleepTimer,
                  'Temporizador de apagado cancelado.'),
            if (_supportsAndroidAlarm) ...[
              const Divider(),
              _buildAlarmOption('Programar Alarme', _selectAlarmTime),
              if (_alarmTime != null)
                _buildCancelOption(
                    'Cancelar Alarme', _cancelAlarm, 'Alarma cancelada.'),
            ]
          ],
        );
      },
    );
  }

  Widget _buildCustomTimerOption() {
    final textColor = _isDarkMode ? Colors.white70 : Colors.black;
    return SimpleDialogOption(
      onPressed: () {
        Navigator.pop(context);
        _selectCustomTimer();
      },
      child: Text('Tempo Personalizado...',
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
    );
  }

  Future<void> _selectCustomTimer() async {
    final TextEditingController hoursController =
        TextEditingController(text: '0');
    final TextEditingController minutesController =
        TextEditingController(text: '0');

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        final textColor = _isDarkMode ? Colors.white : Colors.black;
        final bgColor = _isDarkMode ? const Color(0xFF0A192F) : Colors.white;
        return AlertDialog(
          backgroundColor: bgColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Tempo Personalizado',
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Digite a duração exata para desligar a rádio:',
                  style: TextStyle(
                      color: textColor.withOpacity(0.8), fontSize: 14)),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: hoursController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: textColor,
                          fontSize: 24,
                          fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'Horas',
                        labelStyle: TextStyle(
                            color: textColor.withOpacity(0.6), fontSize: 14),
                        enabledBorder: OutlineInputBorder(
                            borderSide:
                                BorderSide(color: textColor.withOpacity(0.2)),
                            borderRadius: BorderRadius.circular(10)),
                        focusedBorder: OutlineInputBorder(
                            borderSide:
                                const BorderSide(color: Colors.blue, width: 2),
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(':',
                        style: TextStyle(
                            color: textColor,
                            fontSize: 24,
                            fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: minutesController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: textColor,
                          fontSize: 24,
                          fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'Minutos',
                        labelStyle: TextStyle(
                            color: textColor.withOpacity(0.6), fontSize: 14),
                        enabledBorder: OutlineInputBorder(
                            borderSide:
                                BorderSide(color: textColor.withOpacity(0.2)),
                            borderRadius: BorderRadius.circular(10)),
                        focusedBorder: OutlineInputBorder(
                            borderSide:
                                const BorderSide(color: Colors.blue, width: 2),
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar',
                  style: TextStyle(color: textColor.withOpacity(0.6))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (result == true) {
      final int hours = int.tryParse(hoursController.text) ?? 0;
      final int minutes = int.tryParse(minutesController.text) ?? 0;
      if (hours == 0 && minutes == 0) return;
      _setSleepTimer(Duration(hours: hours, minutes: minutes));
    }
  }

  Widget _buildTimerOption(int minutes, String label) {
    final textColor = _isDarkMode ? Colors.white70 : Colors.black;
    return SimpleDialogOption(
      onPressed: () {
        _setSleepTimer(Duration(minutes: minutes));
        Navigator.pop(context);
      },
      child: Text(label, style: TextStyle(color: textColor)),
    );
  }

  Widget _buildAlarmOption(String label, VoidCallback onTapped) {
    final textColor = _isDarkMode ? Colors.white70 : Colors.black;
    return SimpleDialogOption(
      onPressed: () {
        Navigator.pop(context);
        onTapped();
      },
      child: Text(label, style: TextStyle(color: textColor)),
    );
  }

  Widget _buildCancelOption(
      String label, VoidCallback onCancelled, String message) {
    return SimpleDialogOption(
      onPressed: () {
        Navigator.pop(context);
        onCancelled();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      },
      child: Text(label, style: const TextStyle(color: Colors.red)),
    );
  }

  void _setSleepTimer(Duration duration) {
    _cancelSleepTimer();
    _remainingSleepTime = duration;
    _sleepTimer = Timer(duration, () {
      if (_audioPlayer.playerState.playing) _audioPlayer.stop();
      _cancelSleepTimer();
    });
    _uiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSleepTime != null) {
        if (_remainingSleepTime! > const Duration(seconds: 1)) {
          if (mounted)
            setState(() => _remainingSleepTime =
                _remainingSleepTime! - const Duration(seconds: 1));
        } else {
          _cancelSleepTimer();
        }
      } else {
        timer.cancel();
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('La radio se apagará en ${duration.inMinutes} minutos.')),
    );
    if (mounted) setState(() {});
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _uiUpdateTimer?.cancel();
    if (mounted) {
      setState(() {
        _sleepTimer = null;
        _remainingSleepTime = null;
      });
    }
  }

  Future<void> _selectAlarmTime() async {
    final TimeOfDay? picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        builder: (context, child) {
          return Theme(
            data: _isDarkMode
                ? ThemeData.dark().copyWith(
                    colorScheme: const ColorScheme.dark(
                      primary: Colors.blue,
                      onPrimary: Colors.white,
                      surface: Color(0xFF0A192F),
                      onSurface: Colors.white,
                    ),
                  )
                : ThemeData.light(),
            child: child!,
          );
        });
    if (picked != null) {
      _scheduleAlarm(picked);
    }
  }

  Future<void> _scheduleAlarm(TimeOfDay time) async {
    if (!_supportsAndroidAlarm) return;
    final now = DateTime.now();
    DateTime scheduledTime =
        DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }

    await flutterLocalNotificationsPlugin.zonedSchedule(
      alarmId,
      'A Voz da Cura Divina',
      '¡Alarme! Toque para ouvir a rádio',
      tz.TZDateTime.from(scheduledTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'alarm_channel',
          'Alarme Despertador',
          channelDescription: 'Canal para o alarme da rádio',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          playSound: true,
          enableVibration: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'alarm',
    );

    await AndroidAlarmManager.oneShotAt(
      scheduledTime,
      alarmId,
      playRadio,
      exact: true,
      wakeup: true,
      allowWhileIdle: true,
      rescheduleOnReboot: true,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('alarmTime', scheduledTime.millisecondsSinceEpoch);
    if (mounted) {
      setState(() => _alarmTime = scheduledTime);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Alarme programado para as ${intl.DateFormat('HH:mm').format(scheduledTime)}')));
    }
  }

  Future<void> _cancelAlarm() async {
    if (!_supportsAndroidAlarm) return;
    await flutterLocalNotificationsPlugin.cancel(alarmId);
    await AndroidAlarmManager.cancel(alarmId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('alarmTime');
    if (mounted) {
      setState(() => _alarmTime = null);
    }
  }

  String _formatDuration(Duration d) {
    d = d + const Duration(seconds: 1);
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildDrawer(BuildContext context) {
    final drawerBgColor = _isDarkMode
        ? Colors.black.withOpacity(0.5)
        : Colors.white.withOpacity(0.75);
    final iconColor = _isDarkMode ? Colors.white70 : Colors.black54;
    final textColor = _isDarkMode ? Colors.white : Colors.black;

    return Drawer(
        backgroundColor: Colors.transparent,
        elevation: 0,
        width: MediaQuery.of(context).size.width * 0.75,
        child: ClipRRect(
            borderRadius: const BorderRadius.only(
                topRight: Radius.circular(40),
                bottomRight: Radius.circular(40)),
            child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                child: Container(
                    color: drawerBgColor,
                    child: SafeArea(
                        child: SingleChildScrollView(
                      child: Column(
                        children: [
                          SizedBox(
                              height: 150,
                              width: double.infinity,
                              child: Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Image.asset('assets/logoipdd.webp',
                                    fit: BoxFit.contain),
                              )),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            child: Container(
                              padding: const EdgeInsets.all(12.0),
                              decoration: BoxDecoration(
                                color: _isDarkMode
                                    ? Colors.white10
                                    : Colors.black.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.blue.withOpacity(0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.menu_book,
                                          size: 16,
                                          color: Colors.blue.shade700),
                                      const SizedBox(width: 8),
                                      Text("Versículo Diário",
                                          style: TextStyle(
                                              color: textColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    obtenerVersiculoDelDia(),
                                    style: TextStyle(
                                        color: textColor.withOpacity(0.9),
                                        fontSize: 13,
                                        fontStyle: FontStyle.italic),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(),
                          ListTile(
                              leading: Icon(Icons.language, color: iconColor),
                              title: Text("Website",
                                  style: TextStyle(color: textColor)),
                              onTap: () {
                                Navigator.pop(context);
                                _openWebMode(
                                    "https://www.igrejaprimitivadoutrinadivina.com/");
                              }),
                          ListTile(
                              leading: Icon(Icons.audio_file, color: iconColor),
                              title: Text("Reprises - Audios",
                                  style: TextStyle(color: textColor)),
                              onTap: () {
                                Navigator.pop(context);
                                _openWebMode(
                                    "https://igrejaprimitivadoutrinadivina.com/internas/audios");
                              }),
                          ListTile(
                              leading:
                                  Icon(Icons.contact_mail, color: iconColor),
                              title: Text("Contato",
                                  style: TextStyle(color: textColor)),
                              onTap: () {
                                Navigator.pop(context);
                                _openWebMode(
                                    "https://www.igrejaprimitivadoutrinadivina.com/contato");
                              }),
                          ListTile(
                              leading: Icon(Icons.notes, color: iconColor),
                              title: Text("Pedidos de Oração",
                                  style: TextStyle(color: textColor)),
                              onTap: () {
                                Navigator.pop(context);
                                _openWebMode(
                                    "https://www.igrejaprimitivadoutrinadivina.com/recados");
                              }),
                          ListTile(
                              leading:
                                  Icon(Icons.location_on, color: iconColor),
                              title: Text("Endereços",
                                  style: TextStyle(color: textColor)),
                              onTap: () {
                                Navigator.pop(context);
                                _openWebMode(
                                    "https://igrejaprimitivadoutrinadivina.com/internas/enderecos-ipdd");
                              }),
                          ListTile(
                              leading: Icon(Icons.volunteer_activism,
                                  color: iconColor),
                              title: Text("Ajude esta obra",
                                  style: TextStyle(color: textColor)),
                              onTap: () {
                                Navigator.pop(context);
                                _openWebMode(
                                    "https://www.igrejaprimitivadoutrinadivina.com/internas/contas-bancarias");
                              }),
                          const Divider(),
                          ListTile(
                              leading: Icon(Icons.alarm_add, color: iconColor),
                              title: Text("Temporizador e Alarme",
                                  style: TextStyle(color: textColor)),
                              onTap: _showTimerAndAlarmDialog),
                          ListTile(
                              leading: Icon(Icons.share, color: iconColor),
                              title: Text("Compartilhar",
                                  style: TextStyle(color: textColor)),
                              onTap: () => Share.share(
                                  'Confira A Voz da Cura Divina: https://play.google.com/store/apps/details?id=com.kym.lavozdelacuradivina.radio')),
                        ],
                      ),
                    ))))));
  }

  Widget _buildTopContainer(BuildContext context, Color textColor) {
    return Container(
      margin: const EdgeInsets.all(16.0),
      decoration:
          BoxDecoration(borderRadius: BorderRadius.circular(40.0), boxShadow: [
        BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 25,
            spreadRadius: -5,
            offset: const Offset(0, 10))
      ]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40.0),
        child: Stack(
          children: [
            if (!_isDarkMode)
              Positioned.fill(
                  child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                      child: Image.asset('assets/iconolavoz.webp',
                          fit: BoxFit.cover))),
            Positioned.fill(
              child: Container(
                  decoration: BoxDecoration(
                      color: _isDarkMode
                          ? Colors.black.withOpacity(0.2)
                          : Colors.white.withOpacity(0.75),
                      border: Border.all(
                          color: (_isDarkMode ? Colors.white : Colors.black)
                              .withOpacity(0.1)))),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
              child: Column(
                children: [
                  Row(children: [
                    ClipRRect(
                        borderRadius: BorderRadius.circular(30.0),
                        child: Image.asset('assets/iconolavoz.webp',
                            width: 150, height: 150, fit: BoxFit.cover)),
                    const SizedBox(width: 16),
                    Expanded(
                        child: GestureDetector(
                            onTap: _showTimerAndAlarmDialog,
                            child: StreamBuilder<DateTime>(
                                stream: _clockStream,
                                builder: (context, snapshot) {
                                  final now = snapshot.data ?? DateTime.now();
                                  final time =
                                      intl.DateFormat('HH:mm').format(now);
                                  String date =
                                      intl.DateFormat('E, d MMM yyyy', 'pt_BR')
                                          .format(now);
                                  if (date.isNotEmpty) {
                                    date =
                                        "${date[0].toUpperCase()}${date.substring(1)}";
                                  }
                                  return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        FittedBox(
                                            fit: BoxFit.contain,
                                            child: Text(time,
                                                style: GoogleFonts.bebasNeue(
                                                    color: textColor,
                                                    fontSize: 75,
                                                    fontWeight:
                                                        FontWeight.bold))),
                                        Text(date,
                                            style: TextStyle(
                                                color:
                                                    textColor.withOpacity(0.7),
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold)),
                                        if (_remainingSleepTime != null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                              'Apagado en: ${_formatDuration(_remainingSleepTime!)}',
                                              style: TextStyle(
                                                  color: textColor
                                                      .withOpacity(0.9),
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold))
                                        ],
                                        if (_supportsAndroidAlarm &&
                                            _alarmTime != null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                              'Alarma: ${intl.DateFormat("HH:mm").format(_alarmTime!)}',
                                              style: TextStyle(
                                                  color: Colors.amber.shade700,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold))
                                        ]
                                      ]);
                                })))
                  ]),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: BannerAvisos(
                            isPlaying: _audioPlayer.playerState.playing,
                            audioPlayer: _audioPlayer),
                      ),
                      const SizedBox(width: 8),
                      _CustomSwitch(
                        value: _isDarkMode,
                        onChanged: (value) =>
                            setState(() => _isDarkMode = value),
                        isDarkMode: _isDarkMode,
                      ),
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitBottom(
      BuildContext context,
      Color baseBgColor,
      Color headerBgColor,
      Color textColor,
      Color playIconColor,
      Color websiteIconColor,
      List<BoxShadow> neumorphicShadows,
      bool isDrawerOpen) {
    return Column(
      children: [
        Expanded(
          child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(40.0),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 25,
                        spreadRadius: -5,
                        offset: const Offset(0, 10))
                  ]),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(40.0),
                  child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                      child: Container(
                          decoration: BoxDecoration(
                              color: _isDarkMode
                                  ? Colors.blue.withOpacity(0.1)
                                  : baseBgColor.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(40.0),
                              border: Border.all(
                                  color: (_isDarkMode
                                          ? Colors.white
                                          : Colors.black)
                                      .withOpacity(0.1))),
                          child: Row(children: [
                            Expanded(
                                flex: 5,
                                child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            SleekCircularSlider(
                                                appearance: CircularSliderAppearance(
                                                    customWidths:
                                                        CustomSliderWidths(
                                                            trackWidth: 1.5,
                                                            progressBarWidth: 4,
                                                            handlerSize: 8),
                                                    customColors:
                                                        CustomSliderColors(
                                                            trackColor: textColor
                                                                .withOpacity(
                                                                    0.1),
                                                            progressBarColors: [
                                                              Colors.blue
                                                                  .shade300,
                                                              Colors
                                                                  .blue.shade800
                                                            ],
                                                            dotColor:
                                                                _isDarkMode
                                                                    ? Colors
                                                                        .white
                                                                    : Colors
                                                                        .black),
                                                    startAngle: 120,
                                                    angleRange: 25,
                                                    size:
                                                        MediaQuery.of(context)
                                                                .size
                                                                .width *
                                                            0.52),
                                                min: 0.0,
                                                max: 100.0,
                                                initialValue: (_volume * 100)
                                                    .clamp(0.0, 100.0),
                                                onChange: (double value) {
                                                  _volumeIndicatorTimer
                                                      ?.cancel();
                                                  setState(() {
                                                    _volume = (value / 100.0)
                                                        .clamp(0.0, 1.0);
                                                    _showVolumeIndicator = true;
                                                  });
                                                  _audioPlayer
                                                      .setVolume(_volume);
                                                  _volumeIndicatorTimer = Timer(
                                                      const Duration(
                                                          seconds: 2), () {
                                                    if (mounted)
                                                      setState(() =>
                                                          _showVolumeIndicator =
                                                              false);
                                                  });
                                                },
                                                innerWidget:
                                                    (double percentage) {
                                                  return Stack(
                                                      alignment:
                                                          Alignment.center,
                                                      children: [
                                                        GestureDetector(
                                                          onVerticalDragStart:
                                                              (d) {
                                                            _volumeIndicatorTimer
                                                                ?.cancel();
                                                            setState(() =>
                                                                _showVolumeIndicator =
                                                                    true);
                                                          },
                                                          onVerticalDragUpdate:
                                                              (d) {
                                                            final newVolume =
                                                                (_volume -
                                                                        d.delta.dy /
                                                                            200)
                                                                    .clamp(0.0,
                                                                        1.0);
                                                            setState(() =>
                                                                _volume =
                                                                    newVolume);
                                                            _audioPlayer
                                                                .setVolume(
                                                                    _volume);
                                                          },
                                                          onVerticalDragEnd:
                                                              (d) {
                                                            _volumeIndicatorTimer =
                                                                Timer(
                                                                    const Duration(
                                                                        seconds:
                                                                            2),
                                                                    () {
                                                              if (mounted)
                                                                setState(() =>
                                                                    _showVolumeIndicator =
                                                                        false);
                                                            });
                                                          },
                                                          child: Container(
                                                            color: Colors
                                                                .transparent,
                                                            child: Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .fromLTRB(
                                                                      22.0,
                                                                      22.0,
                                                                      22.0,
                                                                      28.0),
                                                              child: Transform
                                                                  .scale(
                                                                scale: 1.25,
                                                                child: Image.asset(
                                                                    'assets/GRILL OK.webp',
                                                                    fit: BoxFit
                                                                        .contain),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Positioned(
                                                          bottom: 2,
                                                          child: Text('Volume',
                                                              style: TextStyle(
                                                                  color: textColor
                                                                      .withOpacity(
                                                                          0.8),
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize:
                                                                      12)),
                                                        ),
                                                      ]);
                                                }),
                                            IgnorePointer(
                                              child: AnimatedOpacity(
                                                  opacity: _showVolumeIndicator
                                                      ? 1.0
                                                      : 0.0,
                                                  duration: const Duration(
                                                      milliseconds: 300),
                                                  child: Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              12),
                                                      decoration: BoxDecoration(
                                                          color: Colors.black
                                                              .withOpacity(0.6),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      15)),
                                                      child: Column(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                                _volume <= 0
                                                                    ? Icons
                                                                        .volume_off
                                                                    : (_volume <
                                                                            0.5
                                                                        ? Icons
                                                                            .volume_down
                                                                        : Icons
                                                                            .volume_up),
                                                                color: Colors
                                                                    .white,
                                                                size: 30),
                                                            const SizedBox(
                                                                height: 8),
                                                            Text(
                                                                '${(_volume * 100).toInt()}%',
                                                                style: const TextStyle(
                                                                    color: Colors
                                                                        .white,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold))
                                                          ]))),
                                            )
                                          ])
                                    ])),
                            Container(
                                width: 1,
                                height: double.infinity,
                                color: textColor.withOpacity(0.2),
                                margin:
                                    const EdgeInsets.symmetric(vertical: 40.0)),
                            Expanded(
                                flex: 3,
                                child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      GestureDetector(
                                          onTap: _playOrStopStream,
                                          child: Container(
                                              width: 70,
                                              height: 70,
                                              decoration: BoxDecoration(
                                                  gradient: !_isDarkMode && _audioPlayer.playerState.playing
                                                      ? LinearGradient(
                                                          colors: [
                                                              baseBgColor,
                                                              headerBgColor
                                                            ],
                                                          begin:
                                                              Alignment.topLeft,
                                                          end: Alignment
                                                              .bottomRight)
                                                      : null,
                                                  color: _isDarkMode
                                                      ? baseBgColor
                                                      : (_audioPlayer.playerState.playing
                                                          ? null
                                                          : baseBgColor),
                                                  shape: BoxShape.circle,
                                                  border: _isDarkMode
                                                      ? Border.all(
                                                          color: Colors
                                                              .grey.shade700,
                                                          width: 1)
                                                      : null,
                                                  boxShadow: neumorphicShadows),
                                              child: _isConnecting
                                                  ? LoadingAnimationWidget.inkDrop(
                                                      color: playIconColor,
                                                      size: 35.0)
                                                  : Icon(
                                                      _audioPlayer.playerState.playing ? Icons.stop : Icons.play_arrow,
                                                      color: playIconColor,
                                                      size: 50))),
                                      const SizedBox(height: 40),
                                      GestureDetector(
                                          onTap: () => _openWebMode(
                                              "https://www.igrejaprimitivadoutrinadivina.com/"),
                                          child: Column(children: [
                                            Container(
                                                width: 70,
                                                height: 70,
                                                decoration: BoxDecoration(
                                                    gradient: !_isDarkMode &&
                                                            isDrawerOpen
                                                        ? LinearGradient(
                                                            colors: [
                                                                baseBgColor,
                                                                headerBgColor
                                                              ],
                                                            begin: Alignment
                                                                .topLeft,
                                                            end: Alignment
                                                                .bottomRight)
                                                        : null,
                                                    color: _isDarkMode
                                                        ? baseBgColor
                                                        : (isDrawerOpen
                                                            ? null
                                                            : baseBgColor),
                                                    shape: BoxShape.circle,
                                                    border: _isDarkMode
                                                        ? Border.all(
                                                            color: Colors
                                                                .grey.shade700,
                                                            width: 1)
                                                        : null,
                                                    boxShadow:
                                                        neumorphicShadows),
                                                child: Icon(Icons.language,
                                                    color: websiteIconColor,
                                                    size: 40)),
                                            const SizedBox(height: 8),
                                            Text("WEBSITE",
                                                style: TextStyle(
                                                    color: textColor,
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.bold))
                                          ])) // Column Website
                                    ])) // Row children (right column)
                          ])) // Row Container (inner shadow)
                      ))), // ClipRRect & BackdropFilter
        ), // Expanded for top area
        Image.asset('assets/logoipdd.webp', height: 50),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildLandscapeRight(
      BuildContext context,
      Color baseBgColor,
      Color headerBgColor,
      Color textColor,
      Color playIconColor,
      List<BoxShadow> neumorphicShadows) {
    return Stack(
      children: [
        Align(
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                  onTap: _playOrStopStream,
                  child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                          gradient:
                              !_isDarkMode && _audioPlayer.playerState.playing
                                  ? LinearGradient(
                                      colors: [baseBgColor, headerBgColor],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight)
                                  : null,
                          color: _isDarkMode
                              ? baseBgColor
                              : (_audioPlayer.playerState.playing
                                  ? null
                                  : baseBgColor),
                          shape: BoxShape.circle,
                          border: _isDarkMode
                              ? Border.all(
                                  color: Colors.grey.shade700, width: 1)
                              : null,
                          boxShadow: neumorphicShadows),
                      child: _isConnecting
                          ? LoadingAnimationWidget.inkDrop(
                              color: playIconColor, size: 45.0)
                          : Icon(
                              _audioPlayer.playerState.playing
                                  ? Icons.stop
                                  : Icons.play_arrow,
                              color: playIconColor,
                              size: 70))),
              const SizedBox(height: 30),
              Container(
                width: 250,
                decoration: BoxDecoration(
                    color: _isDarkMode ? Colors.black26 : Colors.white60,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: (_isDarkMode ? Colors.white : Colors.black)
                            .withOpacity(0.05)),
                    boxShadow: neumorphicShadows),
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 8,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 12),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 24),
                  ),
                  child: Slider(
                    value: _volume,
                    min: 0.0,
                    max: 1.0,
                    activeColor: Colors.blue.shade700,
                    inactiveColor: textColor.withOpacity(0.2),
                    onChanged: (val) {
                      setState(() => _volume = val);
                      _audioPlayer.setVolume(val);
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('${(_volume * 100).toInt()}%',
                    style: TextStyle(
                        color: textColor.withOpacity(0.8),
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              )
            ],
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onVerticalDragEnd: (d) {
                if (d.primaryVelocity! < 0)
                  _showLandscapeMenu(baseBgColor, textColor);
              },
              onTap: () => _showLandscapeMenu(baseBgColor, textColor),
              child: Container(
                width: 120,
                height: 35,
                margin: const EdgeInsets.only(bottom: 5),
                decoration: BoxDecoration(
                    color: _isDarkMode ? Colors.white10 : Colors.black12,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(15), bottom: Radius.circular(5))),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: textColor.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 4),
                    Text("MENÚ",
                        style: TextStyle(
                            color: textColor.withOpacity(0.8),
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        )
      ],
    );
  }

  void _showLandscapeMenu(Color baseBgColor, Color textColor) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (BuildContext context) {
          return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                  color: baseBgColor,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(25))),
              child: Column(children: [
                const SizedBox(height: 10),
                Container(
                    width: 50,
                    height: 6,
                    decoration: BoxDecoration(
                        color: textColor.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(3))),
                const SizedBox(height: 20),
                Text("MENÚ PRINCIPAL",
                    style:
                        GoogleFonts.bebasNeue(fontSize: 32, color: textColor)),
                const SizedBox(height: 20),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 3,
                    mainAxisSpacing: 15,
                    crossAxisSpacing: 15,
                    childAspectRatio: 1.2,
                    padding: const EdgeInsets.all(20),
                    children: [
                      _buildLandscapeGridItem(Icons.timer, "Temporizador",
                          _showTimerAndAlarmDialog, textColor),
                      _buildLandscapeGridItem(Icons.alarm, "Alarme",
                          _showTimerAndAlarmDialog, textColor),
                      _buildLandscapeGridItem(
                          Icons.language, "Site", () {}, textColor),
                      _buildLandscapeGridItem(Icons.replay, "Reprise",
                          _showTimerAndAlarmDialog, textColor),
                      _buildLandscapeGridItem(
                          Icons.share, "Compartilhar", () {}, textColor),
                      _buildLandscapeGridItem(Icons.exit_to_app, "Sair",
                          () => SystemNavigator.pop(), textColor),
                    ],
                  ),
                )
              ]));
        });
  }

  Widget _buildLandscapeGridItem(
      IconData icon, String title, VoidCallback onTap, Color textColor) {
    return GestureDetector(
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
        child: Container(
            decoration: BoxDecoration(
                color: _isDarkMode
                    ? Colors.white10
                    : Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                    color: (_isDarkMode ? Colors.white : Colors.black)
                        .withOpacity(0.05))),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.blue.shade700, size: 45),
                const SizedBox(height: 12),
                Text(title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ],
            )));
  }

  @override
  Widget build(BuildContext context) {
    final Color baseBgColor =
        _isDarkMode ? const Color(0xFF0A192F) : const Color(0xFFB2EBF2);
    final Color textColor = _isDarkMode ? Colors.blue.shade700 : Colors.black;
    final Color headerBgColor =
        _isDarkMode ? Colors.black : const Color.fromARGB(255, 255, 255, 255);
    final Color playIconColor =
        _isDarkMode ? Colors.blue : const Color.fromARGB(255, 53, 53, 53);
    final Color websiteIconColor = _isDarkMode
        ? Colors.blue.shade700
        : const Color.fromARGB(255, 54, 54, 54);
    final bool isDrawerOpen = _scaffoldKey.currentState?.isDrawerOpen ?? false;
    final neumorphicShadows = _isDarkMode
        ? [
            const BoxShadow(
                color: Colors.black54, offset: Offset(5, 5), blurRadius: 10),
            const BoxShadow(
                color: Colors.white10, offset: Offset(-5, -5), blurRadius: 10)
          ]
        : [
            const BoxShadow(
                color: Colors.white, offset: Offset(-5, -5), blurRadius: 15),
            const BoxShadow(
                color: Color(0xFF82B8C2), offset: Offset(5, 5), blurRadius: 15)
          ];

    if (_isInitialLoading)
      return Scaffold(
          backgroundColor: baseBgColor,
          body: Center(
              child: LoadingAnimationWidget.inkDrop(
                  color: textColor, size: 50.0)));
    if (_errorMessage.isNotEmpty && !_audioPlayer.playerState.playing)
      return Scaffold(
          backgroundColor: baseBgColor,
          body: Center(
              child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_errorMessage,
                            style: TextStyle(color: textColor),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        ElevatedButton(
                            onPressed: _initializePlayer,
                            child: const Text('Reintentar'))
                      ]))));

    return PopScope(
      canPop: !_isWebMode,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        final shouldPop = await _handlePop();
        if (shouldPop && mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        resizeToAvoidBottomInset: false,
        drawer: MediaQuery.of(context).orientation == Orientation.landscape
            ? null
            : _buildDrawer(context),
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _isDarkMode
                      ? [
                          const Color.fromARGB(255, 0, 55, 219)
                              .withOpacity(0.9),
                          baseBgColor
                        ]
                      : [const Color(0xFF80DEEA), baseBgColor],
                  begin: _isDarkMode ? Alignment.topCenter : Alignment.topLeft,
                  end: _isDarkMode
                      ? Alignment.bottomCenter
                      : Alignment.bottomRight,
                  stops: _isDarkMode ? const [0.0, 0.4] : const [0.0, 0.9],
                ),
              ),
            ),
            if (!_isWebMode) ...[
              Positioned(
                  top: 30,
                  left: 0,
                  right: 0,
                  child: Opacity(
                      opacity: _isDarkMode ? 0.3 : 0.6,
                      child: Image.asset('assets/NUBE.webp',
                          height: 280, fit: BoxFit.cover))),
              SafeArea(
                child: MediaQuery.of(context).orientation ==
                        Orientation.landscape
                    ? Row(
                        children: [
                          Expanded(
                              flex: 4,
                              child: SingleChildScrollView(
                                  child:
                                      _buildTopContainer(context, textColor))),
                          Expanded(
                              flex: 3,
                              child: _buildLandscapeRight(
                                  context,
                                  baseBgColor,
                                  headerBgColor,
                                  textColor,
                                  playIconColor,
                                  neumorphicShadows))
                        ],
                      )
                    : Column(
                        children: [
                          _buildTopContainer(context, textColor),
                          Expanded(
                              child: _buildPortraitBottom(
                                  context,
                                  baseBgColor,
                                  headerBgColor,
                                  textColor,
                                  playIconColor,
                                  websiteIconColor,
                                  neumorphicShadows,
                                  isDrawerOpen)),
                        ],
                      ),
              ),
            ],
            if (_isWebMode) ...[
              Positioned.fill(
                child: AnnotatedRegion<SystemUiOverlayStyle>(
                  value: _isDarkMode
                      ? SystemUiOverlayStyle.light.copyWith(
                          statusBarColor: Colors.transparent,
                          systemNavigationBarColor: Colors.transparent,
                        )
                      : SystemUiOverlayStyle.dark.copyWith(
                          statusBarColor: Colors.transparent,
                          systemNavigationBarColor: Colors.transparent,
                        ),
                  child: Container(
                    color: _isDarkMode ? Colors.black : Colors.white,
                    child: _buildWebView(),
                  ),
                ),
              ),
            ],

            // CAPA 1: Mini reproductor
            Positioned(
              bottom: 60,
              left: 16,
              right: 16,
              child: IgnorePointer(
                ignoring: !_isWebMode,
                child: _buildMiniPlayer(context, textColor, playIconColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView() {
    return Column(
      children: [
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_currentWebUrl)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              useShouldOverrideUrlLoading: true,
              verticalScrollBarEnabled: true,
              disableVerticalScroll: false,
            ),
            onWebViewCreated: (controller) => _webViewController = controller,
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final uri = navigationAction.request.url;
              if (uri != null &&
                  uri.scheme != "http" &&
                  uri.scheme != "https") {
                await launchUrl(Uri.parse(uri.toString()),
                    mode: LaunchMode.externalApplication);
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
            onLoadStop: (controller, url) async {
              // Hide Web Player and unnecessary elements
              await controller.evaluateJavascript(source: """
                (function() {
                  var style = document.createElement('style');
                  style.innerHTML = `
                    .player, #player, .maxcast-player, .maxcast-player-wrapper, 
                    #maxcast-bar, iframe[src*="maxcast"], audio, video, 
                    .repro-bottom, div[class*="player"] { 
                      display: none !important; 
                    }
                  `;
                  document.head.appendChild(style);
                })();
              """);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEqualizerBars(Color barColor) {
    if (!_audioPlayer.playerState.playing) {
      return Row(
        children: List.generate(
            5,
            (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  width: 3,
                  height: 6,
                  decoration: BoxDecoration(
                      color: barColor.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(2)),
                )),
      );
    }

    return Row(
      children: List.generate(5, (index) {
        return AnimatedBuilder(
          animation: _equalizerController,
          builder: (context, child) {
            final height = 6 +
                10 *
                    Math.sin((_equalizerController.value * 2 * Math.pi) +
                            (index * 1.5))
                        .abs();
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3,
              height: height,
              decoration: BoxDecoration(
                  color: barColor.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(2)),
            );
          },
        );
      }),
    );
  }

  Widget _buildMiniPlayer(
      BuildContext context, Color textColor, Color playIconColor) {
    final playerBgColor = _isDarkMode
        ? const Color(0xFF0A192F).withOpacity(0.92)
        : const Color(0xFFB2EBF2).withOpacity(0.90);
    final contrastColor = _isDarkMode ? Colors.white : Colors.black;
    final secondaryTextColor = _isDarkMode ? Colors.white70 : Colors.black87;

    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    if (isLandscape && _isWebMode) {
      return Align(
        alignment: Alignment.centerRight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: 52,
              margin: const EdgeInsets.only(right: 34), // Un poco más separado para asegurar visibilidad
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: playerBgColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _playOrStopStream,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: contrastColor.withOpacity(0.1),
                      ),
                      child: _isConnecting
                          ? LoadingAnimationWidget.inkDrop(
                              color: contrastColor, size: 20)
                          : Icon(
                              _audioPlayer.playerState.playing
                                  ? Icons.stop
                                  : Icons.play_arrow,
                              color: contrastColor,
                              size: 22,
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 1,
                    width: 28,
                    color: contrastColor.withOpacity(0.2),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => setState(() => _isWebMode = false),
                    child: Icon(
                      Icons.keyboard_double_arrow_right,
                      color: contrastColor.withOpacity(0.8),
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AnimatedSlide(
      offset: _isWebMode ? Offset.zero : const Offset(0, 2),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            decoration: BoxDecoration(
              color: playerBgColor,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
              boxShadow: [
                BoxShadow(
                  color: _isDarkMode
                      ? Colors.black.withOpacity(0.6)
                      : const Color(0xFF7FB3BF).withOpacity(0.7),
                  blurRadius: 22,
                  spreadRadius: 3,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: _isDarkMode
                      ? Colors.black.withOpacity(0.3)
                      : const Color(0xFF5A9BAA).withOpacity(0.4),
                  blurRadius: 40,
                  spreadRadius: -2,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // PESTAÑA SUPERIOR — flecha apuntando ARRIBA, toca para colapsar
                GestureDetector(
                  onTap: () => setState(() => _isWebMode = false),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Icon(
                      Icons.keyboard_arrow_up,
                      color: contrastColor.withOpacity(0.8),
                      size: 22,
                    ),
                  ),
                ),

                // SECCIÓN CENTRAL
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icono de la radio con bordes redondeados (ahora clicable para colapsar)
                      GestureDetector(
                        onTap: () => setState(() => _isWebMode = false),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset(
                            'assets/iconolavoz.webp',
                            width: 65,
                            height: 65,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Info central + play + ecualizador
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'A Voz Da Cura Divina',
                              style: TextStyle(
                                color: contrastColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Igreja Primitiva Doutrina Divina',
                              style: TextStyle(
                                color: secondaryTextColor,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                // Botón play/stop circular
                                GestureDetector(
                                  onTap: _playOrStopStream,
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: contrastColor.withOpacity(0.1),
                                    ),
                                    child: Icon(
                                      _audioPlayer.playerState.playing
                                          ? Icons.stop
                                          : Icons.play_arrow,
                                      color: contrastColor,
                                      size: 22,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // 5 barras animadas de ecualizador
                                _buildEqualizerBars(contrastColor),
                              ],
                            ),
                          ],
                        ),
                      ),

                  // Columna lateral derecha: Logos + Flecha colapso rápida
                  GestureDetector(
                    onTap: () => setState(() => _isWebMode = false),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/nuevologoblanco.png',
                          width: 31, // 30% más pequeño (antes 44)
                          height: 31,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                        const SizedBox(height: 2),
                        Icon(
                          Icons.keyboard_double_arrow_up,
                          color: contrastColor.withOpacity(0.9),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                    ],
                  ),
                ),

                // BARRA DE VOLUMEN
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: contrastColor,
                      inactiveTrackColor: contrastColor.withOpacity(0.2),
                      thumbColor: contrastColor,
                    ),
                    child: Slider(
                      value: _volume,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (val) {
                        setState(() => _volume = val);
                        _audioPlayer.setVolume(val);
                      },
                    ),
                  ),
                ),

                // FRANJA INFERIOR — marquee con icono de live
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.30),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(28),
                      bottomRight: Radius.circular(28),
                    ),
                  ),
                  child: Row(
                    children: [
                      const _BlinkingLiveIndicator(),
                      const SizedBox(width: 6),
                      Icon(Icons.sensors,
                          color: contrastColor.withOpacity(0.6), size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SizedBox(
                          height: 15,
                          child: Marquee(
                            text: _marqueeText.isNotEmpty
                                ? _marqueeText
                                : 'A Voz da Cura Divina no Ar',
                            style: TextStyle(
                                color: contrastColor.withOpacity(0.6),
                                fontSize: 11),
                            scrollAxis: Axis.horizontal,
                            velocity: 30.0,
                            blankSpace: 80.0,
                            pauseAfterRound: const Duration(seconds: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BlinkingLiveIndicator extends StatefulWidget {
  const _BlinkingLiveIndicator({Key? key}) : super(key: key);
  @override
  _BlinkingLiveIndicatorState createState() => _BlinkingLiveIndicatorState();
}

class _BlinkingLiveIndicatorState extends State<_BlinkingLiveIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
        opacity: _controller,
        child: Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: 8),
            decoration: const BoxDecoration(
                color: Colors.red, shape: BoxShape.circle)));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _CustomSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isDarkMode;

  const _CustomSwitch(
      {Key? key,
      required this.value,
      required this.onChanged,
      required this.isDarkMode})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    const double width = 60.0;
    const double height = 30.0;
    const double thumbSize = 24.0;
    final bgColor = isDarkMode ? const Color(0xFF0A192F) : Colors.black;
    final neumorphicShadows = isDarkMode
        ? [
            const BoxShadow(
                color: Colors.black,
                offset: Offset(4, 4),
                blurRadius: 8,
                spreadRadius: 1),
            BoxShadow(
                color: Colors.blueGrey.shade900,
                offset: const Offset(-4, -4),
                blurRadius: 8,
                spreadRadius: 1)
          ]
        : [
            const BoxShadow(
                color: Color(0xFFA7B4C9),
                offset: Offset(4, 4),
                blurRadius: 8,
                spreadRadius: 1),
            const BoxShadow(
                color: Colors.white,
                offset: Offset(-4, -4),
                blurRadius: 8,
                spreadRadius: 1)
          ];
    return GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: width,
            height: height,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(height / 2),
                color: bgColor,
                boxShadow: neumorphicShadows,
                border: isDarkMode
                    ? Border.all(color: Colors.grey.shade700, width: 1)
                    : null),
            child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                    margin: const EdgeInsets.all((height - thumbSize) / 2),
                    width: thumbSize,
                    height: thumbSize,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: value
                            ? const Color.fromARGB(255, 33, 150, 243)
                            : Colors.grey.shade500),
                    child: Icon(value ? Icons.nightlight_round : Icons.wb_sunny,
                        color: value ? Colors.white : Colors.black,
                        size: 16.0)))));
  }
}
