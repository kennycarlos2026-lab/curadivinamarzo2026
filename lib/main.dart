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

import 'package:permission_handler/permission_handler.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:intl/intl.dart' as intl;
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sleek_circular_slider/sleek_circular_slider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'firebase_options.dart';
import 'banner_avisos.dart';
import 'versiculos_promesas.dart';
import 'alarm_manager.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'app_strings.dart';
import 'dart:io';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
final StreamController<String?> selectNotificationStream =
    StreamController<String?>.broadcast();
final ReceivePort alarmReceivePort = ReceivePort();

// Player global
final AudioPlayer _globalAudioPlayer = AudioPlayer();

// Referencia global al handler
_StopAsPauseHandler? _globalAudioHandler;

/// Callback global para que el handler pueda forzar una URL fresca
/// antes de reproducir desde la notificación (evita audio viejo).
Future<void> Function()? _globalReinitAudio;

/// Flag global: true mientras el sistema tiene una interrupción activa 
/// (llamada entrante, timbre). Evita que stop() del handler destruya
/// el AudioService durante una interrupción del sistema.
bool _globalSystemInterruption = false;

/// Handler que intercepta el comando stop() de la notificación
/// y lo redirige a pause() para que la notificación no se destruya.
class _StopAsPauseHandler extends BaseAudioHandler {
  final AudioPlayer player;
  StreamSubscription? _playerSub;
  StreamSubscription? _mediaSub;

  _StopAsPauseHandler(this.player) {
    _bindToPlayer();
  }

  void _bindToPlayer() {
    _mediaSub?.cancel();
    _mediaSub = player.sequenceStateStream.listen((state) {
      final tag = state?.currentSource?.tag;
      if (tag is MediaItem) mediaItem.add(tag);
    });

    _playerSub?.cancel();
    _playerSub = player.playbackEventStream.listen((event) {
      final playing = player.playing;
      playbackState.add(playbackState.value.copyWith(
        controls: [
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1],
        processingState: {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[player.processingState]!,
        playing: playing,
      ));
    });
  }

  @override
  Future<void> play() async {
    // Siempre inicializamos con URL fresca (cache-busting) antes de reproducir.
    // Esto asegura audio en vivo tanto desde la UI como desde la notificación.
    if (_globalReinitAudio != null) {
      await _globalReinitAudio!();
    }
    await player.play();
  }

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> stop() async {
    // Si el sistema tiene una interrupción activa (llamada, timbre),
    // ignoramos este stop — el sistema lo envía para limpiar la notificación
    // pero NO queremos destruir el AudioService porque vamos a reconectar.
    if (_globalSystemInterruption) {
      debugPrint('[Handler] stop() ignorado — interrupción del sistema activa');
      await player.stop(); // solo detener el audio, sin tocar el servicio
      return;
    }
    // Stop iniciado por el usuario: detener completamente y eliminar notificación
    await player.stop();
    mediaItem.add(null); // Limpiar metadata fuerza el cierre de la notificación
    await super.stop(); // Notifica a AudioService que cierre el foreground service
  }

  @override
  Future<void> seek(Duration position) => player.seek(position);
}


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
        androidNotificationIcon: 'drawable/ic_stat_igual1',
      );
    }
    const String streamUrl = 'https://s10.maxcast.com.br:9083/live';
    final mediaItem = MediaItem(
      id: streamUrl,
      title: 'A Voz da Cura Divina - Alarma',
      artist: 'Radio ao vivo',
      artUri: Uri.parse('https://i.ibb.co/nNFYTMZM/ceunotifi.jpg'),
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

Future<String> _loadStreamUrl() async {
  final remoteConfig = FirebaseRemoteConfig.instance;
  await remoteConfig.setConfigSettings(RemoteConfigSettings(
    fetchTimeout: const Duration(seconds: 10),
    minimumFetchInterval: const Duration(hours: 1),
  ));
  
  // Valores por defecto si no hay internet la primera vez
  await remoteConfig.setDefaults({
    'stream_url': 'https://s10.maxcast.com.br:9083/live',
    'url_website': 'https://www.igrejaprimitivadoutrinadivina.com/',
    'url_audios': 'https://igrejaprimitivadoutrinadivina.com/internas/audios',
    'url_contacto': 'https://www.igrejaprimitivadoutrinadivina.com/contato',
    'url_pedidos': 'https://www.igrejaprimitivadoutrinadivina.com/recados',
    'url_direcciones': 'https://igrejaprimitivadoutrinadivina.com/internas/enderecos-ipdd',
    'url_apoyo': 'https://www.igrejaprimitivadoutrinadivina.com/internas/contas-bancarias',
  });
  
  try {
    await remoteConfig.fetchAndActivate();
  } catch (e) {
    debugPrint('Remote config fetch failed: $e');
  }
  return remoteConfig.getString('stream_url');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  IsolateNameServer.registerPortWithName(
      alarmReceivePort.sendPort, 'alarm_port');
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('app_lang', Platform.localeName);
  
  // Captura errores de Flutter
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // Captura errores de Dart fuera de Flutter
  PlatformDispatcher.instance.onError = (error, stack) {
    final errStr = error.toString();

    // FILTRO: Ignorar errores comunes de conectividad de just_audio
    if (errStr.contains('Loading interrupted') ||
        errStr.contains('abort') ||
        errStr.contains('Source error') ||
        errStr.contains('PlatformException(0')) {
      debugPrint('Error de red/audio ignorado para Crashlytics: $errStr');
      return true; // Retornar true evita que Crashlytics lo registre como fatal
    }

    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

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
      AndroidInitializationSettings('ic_stat_igual1');
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
    // ✅ Crear canal de notificación con visibilidad pública (pantalla bloqueada)
    const String audioChannelId = 'com.kym.lavozdelacuradivina.radio.channel.audio';
    const String audioChannelName = 'Radio A Voz da Cura Divina';
    const String audioChannelDesc = 'Reproducción de radio en vivo';

    final AndroidFlutterLocalNotificationsPlugin? androidImpl =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          audioChannelId,
          audioChannelName,
          description: audioChannelDesc,
          importance: Importance.high,
          playSound: false,
          enableVibration: false,
          showBadge: false,
        ),
      );
    }

    if (!kIsWeb) {
      await AudioService.init(
        builder: () {
          _globalAudioHandler = _StopAsPauseHandler(_globalAudioPlayer);
          return _globalAudioHandler!;
        },
        config: const AudioServiceConfig(
          androidNotificationChannelId: audioChannelId,
          androidNotificationChannelName: audioChannelName,
          notificationColor: Color(0xFF90C7F6),
          androidNotificationIcon: 'drawable/ic_stat_igual1',
          androidStopForegroundOnPause: true,
        ),
      );
    }
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.allowBluetooth,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
        flags: AndroidAudioFlags.none,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: false,    // ← vos manejás el volumen manualmente
    ));
  } catch (e) {
    // Re-lanzar: si JustAudioBackground falla, la app no puede funcionar
    debugPrint('Error CRÍTICO inicializando plugins de audio: $e');
    rethrow; // ← para que Firebase Crashlytics lo capture como fatal y no continúe silenciosamente
  }

  final streamUrl = await _loadStreamUrl();
  runApp(MyApp(autoPlay: autoPlay, streamUrl: streamUrl));
}

class MyApp extends StatelessWidget {
  final bool autoPlay;
  final String streamUrl; // AGREGAR
  const MyApp({Key? key, this.autoPlay = false, required this.streamUrl})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: t('notifAlarmTitle'),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      home: RadioHome(
          autoPlay: autoPlay, streamUrl: streamUrl), // AGREGAR streamUrl
    );
  }
}

class RadioHome extends StatefulWidget {
  final bool autoPlay;
  final String streamUrl; // AGREGAR
  const RadioHome({Key? key, this.autoPlay = false, required this.streamUrl})
      : super(key: key);

  @override
  State<RadioHome> createState() => _RadioHomeState();
}

class _RadioHomeState extends State<RadioHome>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  // Getter: siempre apunta al player global actual (puede reasignarse al cambiar modo)
  AudioPlayer get _audioPlayer => _globalAudioPlayer;
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
  bool _isNavigating = false;
  List<int> _alarmDays = [];
  Timer? _bufferingWatchdog;
  DateTime? _bufferingStartedAt;
  bool _wasPlayingBeforeInterruption = false;
  bool _stoppedByHeadphones = false;
  StreamSubscription? _interruptionStreamSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  // Suscripciones del player — se cancelan al cambiar modo para evitar listeners zombie
  StreamSubscription? _icySub;
  StreamSubscription? _playerStateSub;
  StreamSubscription? _processingStateSub;
  bool _isRestarting = false;
  bool _shouldResumeWhenNetworkReturns = false;
  DateTime? _lastReconnectAttemptAt;
  bool _pendingReconnectAfterInterruption = false; // Reconexión diferida al foreground
  bool _wasManuallyPaused = false;
  DateTime? _lastResumeAttemptAt;
  bool _isInBackground = false;
  bool _interruptionActive = false; // true mientras dure una llamada/timbrada
  DateTime? _interruptionStartTime; // marca cuándo comenzó la interrupción
  // _isLiveEdgeMode es global (ver arriba de main()) — compartida con _StopAsPauseHandler

  // Web View State
  bool _isWebMode = false;
  String _currentWebUrl = '';
  InAppWebViewController? _webViewController;
  double _dragOffset = 0.0;
  bool _isDragging = false;

  late AnimationController _equalizerController;
  String _marqueeText =
      ''; // Variable para el texto en movimiento del mini player

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

    _setupConnectivityListener();
    _setupAudioSessionListeners();
  }

  Future<void> _loadPreferencesAndInitialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    if (_supportsAndroidAlarm) {
      final alarmMillis = prefs.getInt('alarmTime');
      if (alarmMillis != null) {
        _alarmTime = DateTime.fromMillisecondsSinceEpoch(alarmMillis);
        if (_alarmTime!.isBefore(DateTime.now())) {
          _alarmTime = null;
          await prefs.remove('alarmTime');
        }
      }
      final savedDays = prefs.getStringList('alarmDays');
      if (savedDays != null) {
        _alarmDays = savedDays.map((e) => int.parse(e)).toList();
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
    // Registrar callback global para que el handler de notificación
    // pueda forzar una URL fresca antes de reproducir.
    _globalReinitAudio = _initializeAudio;
    _setupPlayerStateStream();
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

  void _setupPlayerStateStream() {
    // Escuchar metadatos de la radio (ICY) para el Marquee del miniplayer
    _icySub = _audioPlayer.icyMetadataStream.listen((metadata) {
      if (metadata != null && metadata.info != null) {
        final title = metadata.info?.title ?? '';
        if (title.isNotEmpty && mounted) {
          setState(() {
            _marqueeText = title;
          });
        }
      }
    });

    _playerStateSub = _audioPlayer.playerStateStream.listen((state) async {
      if (mounted) {
        setState(() {
          if (state.playing && _errorMessage.isNotEmpty) _errorMessage = '';
        });
      }

      // Spinner: mostrar solo cuando está cargando/buffering Y jugando
      if (state.playing &&
          (state.processingState == ProcessingState.loading ||
           state.processingState == ProcessingState.buffering)) {
        if (!_isConnecting && mounted) setState(() => _isConnecting = true);

        if (state.processingState == ProcessingState.buffering) {
          _bufferingStartedAt ??= DateTime.now();
          _bufferingWatchdog ??= Timer(const Duration(seconds: 12), () {
            if (mounted &&
                _audioPlayer.playerState.playing &&
                _audioPlayer.processingState == ProcessingState.buffering &&
                _bufferingStartedAt != null &&
                DateTime.now().difference(_bufferingStartedAt!) >=
                    const Duration(seconds: 12)) {
              // Si estamos en background, no intentar reconectar — causará
              // ForegroundServiceStartNotAllowedException y loop infinito.
              // El lifecycle.resumed lo manejará al volver a primer plano.
              if (_isInBackground) {
                debugPrint('[Watchdog] En background → esperando primer plano');
                _wasPlayingBeforeInterruption = true;
                _pendingReconnectAfterInterruption = true;
              } else {
                debugPrint('[Watchdog] Forzando reconexión...');
                _shouldResumeWhenNetworkReturns = true;
                _restartStream(force: true).then((_) => _audioPlayer.play());
              }
              _bufferingWatchdog?.cancel();
              _bufferingWatchdog = null;
              _bufferingStartedAt = null;
            }
          });
        }
      } else {
        if (_isConnecting && mounted) setState(() => _isConnecting = false);
        _bufferingStartedAt = null;
        _bufferingWatchdog?.cancel();
        _bufferingWatchdog = null;
      }

      // Pausa manual desde notificación: solo marcamos la pausa para reconectar después
      if (!state.playing &&
          state.processingState == ProcessingState.ready &&
          !_isRestarting &&
          !_interruptionActive &&
          !_wasPlayingBeforeInterruption &&
          !_pendingReconnectAfterInterruption) {
        _wasManuallyPaused = true;
        _shouldResumeWhenNetworkReturns = false; // evitar reconexión si otra app interrumpe después
        debugPrint('[Player] Pausa manual detectada – marcar para reconexión fresca');
        // No llamamos a stop() ni mutamos el volumen; la notificación sigue activa.
      }

      // Play detectado después de pausa manual (desde notificación O botón):
      // el player arrancó con audio viejo → reconectar inmediatamente al live-edge
      // Play detectado después de pausa manual (desde notificación o botón):
      // Reconectamos al live‑edge creando una nueva fuente y reproduciendo.
      if (_wasManuallyPaused && state.playing && !_isRestarting && !_interruptionActive) {
        _wasManuallyPaused = false;
        debugPrint('[Player] Play post‑pausa → reconexión fresca');
        _isRestarting = true;
        _interruptionActive = true;
        try {
          await _initializeAudio(); // crea URL con timestamp nuevo
          if (mounted) {
            await _audioPlayer.play();
            _shouldResumeWhenNetworkReturns = true;
          }
        } catch (e) {
          debugPrint('[Player] Error reconexión post‑pausa: $e');
        } finally {
          _isRestarting = false;
          _interruptionActive = false;
        }
      }

      // Si se hizo stop real, limpiar la bandera (solo si no es operación interna)
      if (state.processingState == ProcessingState.idle &&
          !_interruptionActive &&
          !_isRestarting) {
        _wasManuallyPaused = false;
      }
    });

    _processingStateSub = _audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _restartStream();
    });
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isInBackground = false;
      _stoppedByHeadphones = false;
      debugPrint('[Lifecycle] App en primer plano');

      if (_pendingReconnectAfterInterruption && mounted) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted && _pendingReconnectAfterInterruption) {
            
            final isStuckBuffering =
                (_audioPlayer.processingState == ProcessingState.buffering ||
                 _audioPlayer.processingState == ProcessingState.loading) &&
                !_audioPlayer.playerState.playing;

            final alreadyActive = _audioPlayer.playerState.playing;

            if (alreadyActive && !isStuckBuffering) {
              _pendingReconnectAfterInterruption = false;
              debugPrint('[Lifecycle] Ya activo — cancelando reconexión pendiente');
            } else {
              _doReconnectAfterInterruption(fromLifecycle: true);
            }
          }
        });
      }
    }

    if (state == AppLifecycleState.paused) {
      _isInBackground = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _interruptionStreamSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _icySub?.cancel();
    _playerStateSub?.cancel();
    _processingStateSub?.cancel();
    _bufferingWatchdog?.cancel();
    _equalizerController.dispose();
    _audioPlayer.dispose();
    _volumeIndicatorTimer?.cancel();
    _sleepTimer?.cancel();
    _uiUpdateTimer?.cancel();
    super.dispose();
  }

  /// Verifica si la app tiene permiso del sistema para reproducir audio.
  Future<bool> _canPlayAudio() async {
    // Verificamos el estado interno para saber si tenemos el foco de audio.
    // Si _interruptionActive es true, otra app tiene el foco.
    return !_interruptionActive;
  }

  void _setupConnectivityListener() {
    _connectivitySubscription?.cancel();

    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) async {
      final hasNetwork = !results.contains(ConnectivityResult.none);

      debugPrint('[Connectivity] changed -> $results');

      if (!hasNetwork) {
        if (_audioPlayer.playing || _isConnecting) {
          debugPrint('[Connectivity] Sin red -> marcar reanudación pendiente');
          _shouldResumeWhenNetworkReturns = true;
        }
        return;
      }

      // 🔥 Verificar foco de audio antes de intentar reconectar
      if (_shouldResumeWhenNetworkReturns) {
        final canPlay = await _canPlayAudio();
        if (!canPlay) {
          debugPrint('[Connectivity] Red OK pero NO tenemos foco → abortar reconexión');
          _shouldResumeWhenNetworkReturns = false;
          return;
        }
      }

      if (!_shouldResumeWhenNetworkReturns) return;
      if (!mounted || _isRestarting) return;

      final now = DateTime.now();
      if (_lastReconnectAttemptAt != null &&
          now.difference(_lastReconnectAttemptAt!) <
              const Duration(seconds: 3)) {
        return;
      }
      _lastReconnectAttemptAt = now;

      debugPrint('[Connectivity] Red restaurada -> reconectando stream');
      _shouldResumeWhenNetworkReturns = false;

      if (mounted) {
        setState(() {
          _isConnecting = true;
          _errorMessage = '';
        });
      }

      try {
        _isRestarting = true;
        // No hacer pause + setAudioSource si podemos simplemente play()
        if (_audioPlayer.processingState == ProcessingState.idle) {
          await _initializeAudio();
        }
        if (mounted) await _audioPlayer.play();
      } catch (e) {
        debugPrint('[Connectivity] Error al reconectar: $e');
        _shouldResumeWhenNetworkReturns = true;
        if (mounted) {
          setState(() {
            _errorMessage = t('errorPlayback');
          });
        }
      } finally {
        _isRestarting = false;
      }
    });
  }

  Future<void> _initializeAudio() async {
    if (!mounted) return;
    setState(() => _errorMessage = '');
    try {
      // Cache‑busting: añadir timestamp para evitar buffer reciclado
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final urlWithTimestamp = widget.streamUrl.contains('?')
          ? '${widget.streamUrl}&_=$timestamp'
          : '${widget.streamUrl}?_=$timestamp';

      final mediaItem = MediaItem(
        id: urlWithTimestamp,
        title: t('notifAlarmTitle'),
        artist: 'Radio ao vivo',
        artUri: Uri.parse('https://i.ibb.co/nNFYTMZM/ceunotifi.jpg'),
      );
      await _audioPlayer.setAudioSource(
          AudioSource.uri(Uri.parse(urlWithTimestamp),
              tag: mediaItem),
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

  Future<void> _restartStream({bool force = false}) async {
    if (!force && _isConnecting) return;
    try {
      _bufferingWatchdog?.cancel();
      _bufferingWatchdog = null;
      _bufferingStartedAt = null;

      await _audioPlayer.pause();
      await _initializeAudio();
    } catch (e) {
      debugPrint("Error al reiniciar el stream: $e");
    }
  }

  /// Resetea forzosamente todo el estado cuando el player queda en un estado
  /// inválido (LateInitializationError, _isRestarting=true atascado, etc.)
  Future<void> _resetPlayerState() async {
    debugPrint('[Reset] Reseteando estado del player...');
    _isRestarting = false;
    _isConnecting = false;
    _wasPlayingBeforeInterruption = false;
    _pendingReconnectAfterInterruption = false;
    _bufferingWatchdog?.cancel();
    _bufferingWatchdog = null;
    _bufferingStartedAt = null;
    _lastResumeAttemptAt = null;

    try {
      // No dispose: el player es global y compartido con el AudioHandler.
      // Solo detener y reinicializar la fuente de audio es suficiente.
      await _audioPlayer.stop();
    } catch (_) {}

    // Reconfigurar streams (listeners) y reinicializar fuente de audio
    _setupPlayerStateStream();
    await _initializeAudio();
    debugPrint('[Reset] Player reinicializado exitosamente');
  }


  Future<void> _playOrStopStream() async {
    // Si el usuario quiere PARAR y hay una operación en curso → cancelarla siempre
    final playerIsActive = _audioPlayer.playerState.playing ||
        _audioPlayer.processingState == ProcessingState.loading ||
        _audioPlayer.processingState == ProcessingState.buffering;
    if (_isRestarting) {
      if (playerIsActive) {
        // El usuario quiere parar: cancelar cualquier reconexión en curso
        debugPrint('[PlayStop] Stop forzado — cancelando reconexión en curso');
        _isRestarting = false;
        // Caer al bloque STOP más abajo
      } else {
        final atascado = _lastResumeAttemptAt != null &&
            DateTime.now().difference(_lastResumeAttemptAt!) >
                const Duration(seconds: 15);
        if (atascado) {
          debugPrint('[PlayStop] _isRestarting atascado → forzando reset');
          await _resetPlayerState();
        } else {
          debugPrint('[PlayStop] Ya reiniciando, ignorando llamada duplicada');
          return;
        }
      }
    }

    // Registrar timestamp para detectar atascos futuros
    _lastResumeAttemptAt = DateTime.now();

    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      _shouldResumeWhenNetworkReturns = true;
      if (mounted) setState(() => _errorMessage = t('errorNoInternet'));
      return;
    }

    if (mounted) setState(() => _errorMessage = '');

    if (_audioPlayer.playerState.playing ||
        _audioPlayer.processingState == ProcessingState.loading ||
        _audioPlayer.processingState == ProcessingState.buffering) {
      // ── STOP real (botón del usuario)
      _shouldResumeWhenNetworkReturns = false;
      _wasPlayingBeforeInterruption = false;
      _bufferingWatchdog?.cancel();
      _bufferingWatchdog = null;
      _bufferingStartedAt = null;
      _isRestarting = true;
      _wasManuallyPaused = false;
      try {
        await _audioPlayer.stop();
        // ✅ Detener también el servicio de audio (elimina la notificación)
        if (_globalAudioHandler != null) {
          await _globalAudioHandler!.stop();
        }
      } finally {
        _isRestarting = false;
      }
    } else {
      // ── PLAY ─────────────────────────────────────────────────────────────────
      _isRestarting = true;
      try {
        if (mounted) setState(() { _isConnecting = true; _errorMessage = ''; });
        _bufferingWatchdog?.cancel();
        _bufferingWatchdog = null;
        _bufferingStartedAt = null;
        _wasManuallyPaused = false;
        _audioPlayer.setVolume(_volume);

        // Siempre forzamos una nueva conexión para estar en el live edge
        await _initializeAudio();

        if (mounted) {
          await _audioPlayer.play();
          _shouldResumeWhenNetworkReturns = true;
        }
      } catch (e) {
        debugPrint('[PlayStop] Error: $e');
        // Si el error es LateInitializationError → reset completo
        if (e.toString().contains('LateInitializationError') ||
            e.toString().contains('_audioHandler') ||
            e.toString().contains('single player instance')) {
          debugPrint('[PlayStop] Error crítico → reseteo completo del player');
          await _resetPlayerState();
          // Reintentar una vez después del reset
          try {
            await _audioPlayer.play();
            _shouldResumeWhenNetworkReturns = true;
          } catch (e2) {
            debugPrint('[PlayStop] Reintento fallido: $e2');
            if (mounted) setState(() => _errorMessage = t('errorPlayback'));
          }
        } else {
          _shouldResumeWhenNetworkReturns = true;
          if (mounted) setState(() => _errorMessage = t('errorPlayback'));
        }
      } finally {
        _isRestarting = false;
      }
    }
  }

  /// Reconecta al live-edge después de una interrupción (llamada, timbrada, etc.).
  /// [fromLifecycle] indica si viene del evento didChangeAppLifecycleState.
  /// Reconecta al live-edge después de una interrupción (llamada, timbrada, etc.).
  /// [fromLifecycle] indica si viene del evento didChangeAppLifecycleState.
  Future<void> _doReconnectAfterInterruption({bool fromLifecycle = false}) async {
    if (!mounted) return;
    if (!_pendingReconnectAfterInterruption) return;

    if (_isRestarting && !fromLifecycle) {
      debugPrint('[Reconnect] Descartado — ya hay reconexión en curso');
      return;
    }

    if (!fromLifecycle) {
      final now = DateTime.now();
      if (_lastResumeAttemptAt != null &&
          now.difference(_lastResumeAttemptAt!) < const Duration(seconds: 3)) {
        debugPrint('[Reconnect] Descartado — intento duplicado reciente');
        return;
      }
    }

    // ✅ DOBLE VERIFICACIÓN PARA EVITAR EFECTOS SECUNDARIOS ✅
    // 1. Verificar que el sistema nos ha devuelto el foco de audio.
    //    Si otra app (ej. YouTube, una llamada contestada) lo tiene, esto será falso.
    final canPlay = await _canPlayAudio();
    if (!canPlay) {
      debugPrint('[Reconnect] Abortado: el sistema no nos ha devuelto el foco de audio.');
      // No limpiamos _pendingReconnectAfterInterruption. Se reintentará más tarde
      // si el usuario vuelve a la app (lo que podría devolvernos el foco).
      return;
    }

    // 2. Verificar la duración de la interrupción.
    //    Si fue muy larga (>40s), asumimos que el usuario cambió de actividad.
    final interruptionDuration = _interruptionStartTime != null
        ? DateTime.now().difference(_interruptionStartTime!)
        : Duration.zero;
    if (interruptionDuration > const Duration(seconds: 40)) {
      debugPrint('[Reconnect] Abortado: la interrupción fue demasiado larga (${interruptionDuration.inSeconds}s).');
      _pendingReconnectAfterInterruption = false; // Limpiamos para no reintentar.
      _wasPlayingBeforeInterruption = false;
      return;
    }
    // ✅ FIN DE LA DOBLE VERIFICACIÓN ✅

    _pendingReconnectAfterInterruption = false;
    _wasPlayingBeforeInterruption = false; // Limpiar aquí — la interrupción ya terminó
    _lastResumeAttemptAt = DateTime.now();
    debugPrint('[Reconnect] Iniciando reconexión automática (bg=$_isInBackground, fromLifecycle=$fromLifecycle, duración=${interruptionDuration.inSeconds}s)');
    _isRestarting = true;

    try {
      if (_audioPlayer.playing ||
          _audioPlayer.processingState == ProcessingState.loading ||
          _audioPlayer.processingState == ProcessingState.buffering) {
        await _audioPlayer.stop();
      }

      if (!mounted) return;

      await _initializeAudio();
      if (mounted) {
        await _audioPlayer.play();
        _shouldResumeWhenNetworkReturns = true;
        debugPrint('[Reconnect] ✓ Completado');
      }
    } catch (e) {
      debugPrint('[Reconnect] Error: $e');
      _pendingReconnectAfterInterruption = true;
    } finally {
      _isRestarting = false;
      _interruptionActive = false;
      _interruptionStartTime = null; // Limpiar el timestamp de la interrupción
    }
  }

  Future<void> _setupAudioSessionListeners() async {
    final audioSession = await AudioSession.instance;

    audioSession.becomingNoisyEventStream.listen((_) {
      if (mounted && (_audioPlayer.playing ||
          _audioPlayer.processingState == ProcessingState.loading ||
          _audioPlayer.processingState == ProcessingState.buffering)) {
        debugPrint('[AudioSession] becomingNoisy → stop');
        _stoppedByHeadphones = true;
        _wasPlayingBeforeInterruption = false;
        _shouldResumeWhenNetworkReturns = false;
        _isRestarting = true;
        _audioPlayer.stop().then((_) => _isRestarting = false);
      }
    });

    _interruptionStreamSubscription =
        audioSession.interruptionEventStream.listen((event) async {
      debugPrint('[AudioSession] begin=${event.begin}, type=${event.type}');

      if (event.begin) {
        // ── EL SISTEMA NOS QUITA EL AUDIO ──────────────────────────────────────

        // 1. Notificaciones cortas (Ducking)
        if (event.type == AudioInterruptionType.duck) {
          debugPrint('[AudioSession] Ducking → OS baja el volumen temporalmente (sin acción)');
          return;
        }

        // 2. Interrupciones reales (Llamadas, YouTube, Spotify, Notas de voz)
        _interruptionActive = true;
        _globalSystemInterruption = true; // Proteger el AudioService durante la interrupción
        _interruptionStartTime = DateTime.now(); // Marcar inicio de la interrupción

        final wasIntendingToPlay = _audioPlayer.playing ||
            _audioPlayer.processingState == ProcessingState.loading ||
            _audioPlayer.processingState == ProcessingState.buffering ||
            _isConnecting ||
            (_shouldResumeWhenNetworkReturns && !_wasManuallyPaused);

        if (wasIntendingToPlay) {
          _wasPlayingBeforeInterruption = true;
          _wasManuallyPaused = false;
          _stoppedByHeadphones = false;

          debugPrint('[AudioSession] Interrupción externa → Pausando (stop)');
          _isRestarting = true;
          try {
            await _audioPlayer.stop();
          } catch (e) {
            debugPrint('[AudioSession] Error en stop: $e');
          } finally {
            _isRestarting = false;
          }
        }

      } else {
        // ── INTERRUPCIÓN FINALIZADA ──────────────────────────────────────────────
        if (event.type == AudioInterruptionType.duck) {
          debugPrint('[AudioSession] Fin ducking');
          _interruptionActive = false;
          return;
        }

        debugPrint('[AudioSession] Fin interrupción');
        final interruptionDuration = _interruptionStartTime != null
            ? DateTime.now().difference(_interruptionStartTime!)
            : Duration.zero;
        _interruptionStartTime = null;

        // Umbral para considerar interrupción "breve" (ej. timbre no atendido)
        const autoResumeThreshold = Duration(seconds: 40);

        if (!mounted || !_wasPlayingBeforeInterruption) {
          _wasPlayingBeforeInterruption = false;
          _isRestarting = false;
          _interruptionActive = false;
          return;
        }

        if (interruptionDuration < autoResumeThreshold) {
          debugPrint('[AudioSession] Interrupción breve (${interruptionDuration.inSeconds}s) → Intentando reconexión automática');
          // Limpiar ANTES de llamar a _doReconnectAfterInterruption:
          // - _interruptionActive=false para que _canPlayAudio() no bloquee
          // - _globalSystemInterruption=false para que el handler funcione normal
          // - _lastResumeAttemptAt=null para saltar el guard de 3s (cada timbre es un evento distinto)
          _interruptionActive = false;
          _globalSystemInterruption = false;
          _lastResumeAttemptAt = null;
          _pendingReconnectAfterInterruption = true;
          await _doReconnectAfterInterruption();
        } else {
          debugPrint('[AudioSession] Interrupción larga (${interruptionDuration.inSeconds}s) → El usuario debe reanudar manualmente');
          _wasPlayingBeforeInterruption = false;
          _isRestarting = false;
          _interruptionActive = false;
          _globalSystemInterruption = false; // liberar el flag
          _pendingReconnectAfterInterruption = false;
        }
      }
    });
  }

  void _showTimerAndAlarmDialog() {
    final textColor = _isDarkMode ? Colors.white70 : Colors.black;
    final titleColor = _isDarkMode ? Colors.blue.shade700 : Colors.black;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return SimpleDialog(
          backgroundColor: _isDarkMode ? const Color(0xFF183153) : Colors.white,
          title: Text(t('timerDialogTitle'),
              style: TextStyle(color: titleColor)),
          children: <Widget>[
            _buildTimerOption(15, t('timer15')),
            _buildTimerOption(30, t('timer30')),
            _buildTimerOption(60, t('timer60')),
            _buildCustomTimerOption(),
            if (_sleepTimer != null)
              _buildCancelOption(t('timerCancelLabel'), _cancelSleepTimer,
                  t('timerCancelMsg')),
            if (_supportsAndroidAlarm) ...[
              const Divider(),
              _buildAlarmOption(t('alarmSchedule'), _selectAlarmTime),
              if (_alarmTime != null)
                _buildCancelOption(
                    t('alarmCancel'), _cancelAlarm, t('alarmCancelMsg')),
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
      child: Text(t('timerCustom'),
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
        final bgColor = _isDarkMode ? const Color(0xFF183153) : Colors.white;
        return AlertDialog(
          backgroundColor: bgColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(t('timerCustomTitle'),
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t('timerCustomDesc'),
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
                        labelText: t('timerHours'),
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
                        labelText: t('timerMinutes'),
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
              child: Text(t('btnCancel'),
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
              Text(tArgs('timerSnack', {'min': duration.inMinutes.toString()}))),
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
                      surface: Color(0xFF183153),
                      onSurface: Colors.white,
                    ),
                  )
                : ThemeData.light(),
            child: child!,
          );
        });
    if (picked == null) return;
    final days = await _showDaySelector(_alarmDays);
    if (days == null) return;
    _alarmDays = days;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'alarmDays', _alarmDays.map((e) => e.toString()).toList());
    _scheduleAlarm(picked);
  }

  Future<List<int>?> _showDaySelector(List<int> initialDays) async {
    List<int> selectedDays = List.from(initialDays);
    final locale =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final dayLabels = locale == 'pt'
        ? ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom']
        : locale == 'es'
            ? ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom']
            : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return showDialog<List<int>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final bgColor =
                _isDarkMode ? const Color(0xFF183153) : Colors.white;
            final txtColor = _isDarkMode ? Colors.white : Colors.black;
            return AlertDialog(
              backgroundColor: bgColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text(t('alarmDaysTitle'),
                  style:
                      TextStyle(color: txtColor, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t('alarmDaysDesc'),
                      style: TextStyle(
                          color: txtColor.withOpacity(0.7), fontSize: 14)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(7, (i) {
                      final day = i + 1;
                      final isSelected = selectedDays.contains(day);
                      return GestureDetector(
                        onTap: () => setDialogState(() {
                          isSelected
                              ? selectedDays.remove(day)
                              : selectedDays.add(day);
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? Colors.blue.shade700
                                : Colors.transparent,
                            border: Border.all(
                              color: isSelected
                                  ? Colors.blue.shade700
                                  : txtColor.withOpacity(0.3),
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(dayLabels[i],
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : txtColor.withOpacity(0.7),
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              )),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    selectedDays.isEmpty
                        ? t('alarmOnce')
                        : t('alarmRepeat'),
                    style: TextStyle(
                        color: txtColor.withOpacity(0.5),
                        fontSize: 12,
                        fontStyle: FontStyle.italic),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text(t('btnCancel'),
                      style: TextStyle(color: txtColor.withOpacity(0.6))),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, selectedDays),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child:
                      const Text('OK', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _scheduleAlarm(TimeOfDay time) async {
    if (!_supportsAndroidAlarm) return;
    await _cancelAlarmInternal();
    final now = DateTime.now();
    if (_alarmDays.isEmpty) {
      DateTime scheduledTime =
          DateTime(now.year, now.month, now.day, time.hour, time.minute);
      if (scheduledTime.isBefore(now)) {
        scheduledTime = scheduledTime.add(const Duration(days: 1));
      }
      await _scheduleOneAlarm(alarmId, scheduledTime);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('alarmTime', scheduledTime.millisecondsSinceEpoch);
      if (mounted) {
        setState(() => _alarmTime = scheduledTime);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Alarme programado para as ${intl.DateFormat('HH:mm').format(scheduledTime)}')));
      }
    } else {
      DateTime? earliest;
      for (final day in _alarmDays) {
        DateTime scheduledTime =
            DateTime(now.year, now.month, now.day, time.hour, time.minute);
        while (scheduledTime.weekday != day || scheduledTime.isBefore(now)) {
          scheduledTime = scheduledTime.add(const Duration(days: 1));
        }
        await _scheduleOneAlarm(10 + day, scheduledTime);
        if (earliest == null || scheduledTime.isBefore(earliest)) {
          earliest = scheduledTime;
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('alarmTime', earliest!.millisecondsSinceEpoch);
      await prefs.setInt('alarmHour', time.hour);
      await prefs.setInt('alarmMinute', time.minute);
      if (mounted) {
        setState(() => _alarmTime = earliest);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Alarme: ${intl.DateFormat('HH:mm').format(earliest)} (${_getDayNames()})')));
      }
    }
  }

  Future<void> _scheduleOneAlarm(int id, DateTime scheduledTime) async {
    final _p = await SharedPreferences.getInstance();
    final _langSaved = _p.getString('app_lang') ?? 'pt';
    String _langCode = 'pt';
    if (_langSaved.startsWith('es')) _langCode = 'es';
    if (_langSaved.startsWith('en')) _langCode = 'en';
    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      t('notifAlarmTitle'),
      t('notifAlarmBody', _langCode),
      tz.TZDateTime.from(scheduledTime, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          'alarm_channel',
          t('notifAlarmChannel', _langCode),
          channelDescription: t('notifAlarmChannelDesc', _langCode),
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
      id,
      playRadio,
      exact: true,
      wakeup: true,
      allowWhileIdle: true,
      rescheduleOnReboot: true,
    );
  }

  String _getDayNames() {
    final locale =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final labels = locale == 'pt'
        ? ['', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom']
        : locale == 'es'
            ? ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom']
            : ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final sorted = List<int>.from(_alarmDays)..sort();
    return sorted.map((d) => labels[d]).join(', ');
  }

  Future<void> _cancelAlarm() async {
    if (!_supportsAndroidAlarm) return;
    await _cancelAlarmInternal();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('alarmTime');
    await prefs.remove('alarmDays');
    await prefs.remove('alarmHour');
    await prefs.remove('alarmMinute');
    if (mounted) {
      setState(() {
        _alarmTime = null;
        _alarmDays = [];
      });
    }
  }

  Future<void> _cancelAlarmInternal() async {
    await flutterLocalNotificationsPlugin.cancel(alarmId);
    await AndroidAlarmManager.cancel(alarmId);
    for (int day = 1; day <= 7; day++) {
      final id = 10 + day;
      await flutterLocalNotificationsPlugin.cancel(id);
      await AndroidAlarmManager.cancel(id);
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
                                      Text(t('verseTitle'),
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
                              title: Text(t('menuWebsite'), style: TextStyle(color: textColor)),
                              onTap: () {
                                Navigator.pop(context);
                                _openWebMode(FirebaseRemoteConfig.instance.getString('url_website'));
                              }),
                          ListTile(
                              leading: Icon(Icons.audio_file, color: iconColor),
                              title: Text(t('menuAudios'), style: TextStyle(color: textColor)),
                              onTap: () {
                                Navigator.pop(context);
                                _openWebMode(FirebaseRemoteConfig.instance.getString('url_audios'));
                              }),
                          ListTile(
                              leading: Icon(Icons.contact_mail, color: iconColor),
                              title: Text(t('menuContact'), style: TextStyle(color: textColor)),
                              onTap: () {
                                Navigator.pop(context);
                                _openWebMode(FirebaseRemoteConfig.instance.getString('url_contacto'));
                              }),
                          ListTile(
                              leading: Icon(Icons.notes, color: iconColor),
                              title: Text(t('menuPrayerRequests'), style: TextStyle(color: textColor)),
                              subtitle: Text(t('menuPrayerRequestsSub'), style: TextStyle(color: textColor.withOpacity(0.6))),
                              onTap: () {
                                Navigator.pop(context);
                                _openWebMode(FirebaseRemoteConfig.instance.getString('url_pedidos'));
                              }),
                          ListTile(
                              leading: Icon(Icons.location_on, color: iconColor),
                              title: Text(t('menuAddresses'), style: TextStyle(color: textColor)),
                              onTap: () {
                                Navigator.pop(context);
                                _openWebMode(FirebaseRemoteConfig.instance.getString('url_direcciones'));
                              }),
                          ListTile(
                              leading: Icon(Icons.volunteer_activism, color: iconColor),
                              title: Text(t('menuSupport'), style: TextStyle(color: textColor)),
                              subtitle: Text(t('menuSupportSub'), style: TextStyle(color: textColor.withOpacity(0.6))),
                              onTap: () {
                                Navigator.pop(context);
                                _openWebMode(FirebaseRemoteConfig.instance.getString('url_apoyo'));
                              }),
                          const Divider(),
                          ListTile(
                              leading: Icon(Icons.alarm_add, color: iconColor),
                              title: Text(t('timerDialogTitle'),
                                  style: TextStyle(color: textColor)),
                              onTap: _showTimerAndAlarmDialog),
                          ListTile(
                              leading: Icon(Icons.share, color: iconColor),
                              title: Text(t('menuShare'),
                                  style: TextStyle(color: textColor)),
                              onTap: () => Share.share(
                                  t('shareText'))),
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
            if (MediaQuery.of(context).orientation == Orientation.landscape)
              Positioned.fill(
                  child: Opacity(
                      opacity: _isDarkMode ? 0.3 : 0.6,
                      child: Image.asset('assets/NUBE.webp',
                          fit: BoxFit.cover))),
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
                        onChanged: (value) async {
                          setState(() => _isDarkMode = value);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('isDarkMode', value);
                        },
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
                                  ? Colors.blue.withOpacity(0.2)
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
                                                  ? LoadingAnimationWidget.staggeredDotsWave(
                                                      color: playIconColor,
                                                      size: 32)
                                                  : Icon(
                                                      _audioPlayer.playerState.playing ? Icons.stop : Icons.play_arrow,
                                                      color: playIconColor,
                                                      size: 50))),
                                      const SizedBox(height: 40),
                                      GestureDetector(
                                          onTap: _showOverlayMenu,
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
                          color: _isDarkMode
                              ? baseBgColor
                              : Colors.white.withOpacity(0.75),
                          shape: BoxShape.circle,
                          border: _isDarkMode
                              ? Border.all(color: Colors.grey.shade700, width: 1)
                              : Border.all(
                                  color: (Colors.black).withOpacity(0.1)),
                          boxShadow: neumorphicShadows),
                      child: _isConnecting
                          ? LoadingAnimationWidget.staggeredDotsWave(
                              color: Colors.black, size: 40)
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
                    color: _isDarkMode ? baseBgColor : Colors.white60,
                    borderRadius: BorderRadius.circular(20),
                    border: _isDarkMode
                        ? Border.all(color: Colors.grey.shade700, width: 1)
                        : Border.all(color: (Colors.black).withOpacity(0.05)),
                    boxShadow: neumorphicShadows),
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 8),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 18),
                  ),
                  child: Slider(
                    value: _volume,
                    min: 0.0,
                    max: 1.0,
                    activeColor: playIconColor,
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
                if (d.primaryVelocity! < 0) _showOverlayMenu();
              },
              onTap: () => _showOverlayMenu(),
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

  @override
  Widget build(BuildContext context) {
    final Color darkTopColor = const Color(0xFF0037DB);
    final Color baseBgColor =
        _isDarkMode ? const Color(0xFF0A2254) : const Color(0xFFC8E4FB);
    final Color textColor = _isDarkMode ? Colors.blue.shade400 : Colors.black;
    final Color headerBgColor =
        _isDarkMode ? Colors.black : const Color.fromARGB(255, 255, 255, 255);
    final Color playIconColor =
        _isDarkMode ? Colors.blue.shade700 : const Color.fromARGB(255, 53, 53, 53);
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
                color: Color(0xFF72AADF), offset: Offset(5, 5), blurRadius: 15)
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
                            child: Text(t('btnRetry')))
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
        extendBody: true,
        extendBodyBehindAppBar: true,
        drawer: MediaQuery.of(context).orientation == Orientation.landscape
            ? null
            : null, // Drawer deshabilitado en retrato a petición del usuario
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _isDarkMode
                      ? [
                          darkTopColor.withOpacity(0.9),
                          baseBgColor
                        ]
                      : [const Color(0xFF90C7F6), baseBgColor],
                  begin: _isDarkMode ? Alignment.topCenter : Alignment.topLeft,
                  end: _isDarkMode
                      ? Alignment.bottomCenter
                      : Alignment.bottomRight,
                  stops: _isDarkMode ? const [0.0, 0.4] : const [0.0, 0.9],
                ),
              ),
            ),
            if (!_isWebMode) ...[
              if (MediaQuery.of(context).orientation != Orientation.landscape)
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
                // En landscape (horizontal) quitamos el padding para que no quede franja blanca
                bottom: MediaQuery.of(context).orientation == Orientation.landscape ? 0 : 160,
                child: AnnotatedRegion<SystemUiOverlayStyle>(
                  value: _isDarkMode
                      ? SystemUiOverlayStyle.light.copyWith(
                          statusBarColor: Colors.transparent,
                          systemNavigationBarColor: Colors.transparent,
                          systemNavigationBarDividerColor: Colors.transparent,
                          systemNavigationBarContrastEnforced: false,
                        )
                      : SystemUiOverlayStyle.dark.copyWith(
                          statusBarColor: Colors.transparent,
                          systemNavigationBarColor: Colors.transparent,
                          systemNavigationBarDividerColor: Colors.transparent,
                          systemNavigationBarContrastEnforced: false,
                        ),
                  child: _buildWebView(),
                ),
              ),
            ],

            // CAPA 1: Mini reproductor + Bottom nav (solo en modo web)
            if (_isWebMode)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildWebBottomBar(context),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(_currentWebUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: true,
        allowsInlineMediaPlayback: true,
        useShouldOverrideUrlLoading: true,
        verticalScrollBarEnabled: true,
        disableVerticalScroll: false,
        transparentBackground: true,
        forceDark: ForceDark.OFF,
      ),
      onPermissionRequest: (controller, request) async {
        if (_audioPlayer.playing) {
          debugPrint('WEB: Petición de micro -> Pausando radio temporalmente');
          await _audioPlayer.pause();
        }
        var status = await Permission.microphone.status;
        if (!status.isGranted) {
          status = await Permission.microphone.request();
        }
        if (status.isGranted) {
          return PermissionResponse(
            resources: request.resources,
            action: PermissionResponseAction.GRANT,
          );
        }
        return PermissionResponse(
          resources: request.resources,
          action: PermissionResponseAction.DENY,
        );
      },
      onWebViewCreated: (controller) {
        _webViewController = controller;
        controller.addJavaScriptHandler(
          handlerName: 'controlRadio',
          callback: (args) {
            final data = args[0];
            if (data['action'] == 'pause' && _audioPlayer.playing) {
              debugPrint('WEB: Pausando radio para grabar');
              _audioPlayer.pause();
            } else if (data['action'] == 'play' && !_audioPlayer.playing) {
              debugPrint('WEB: Grabación finalizada, retomando radio');
              _audioPlayer.play();
            }
          },
        );
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final uri = navigationAction.request.url;
        if (uri == null) return NavigationActionPolicy.ALLOW;
        final String urlString = uri.toString();

        // Interceptar enlaces de Google Play (tanto https como market://)
        if (urlString.contains('play.google.com') || urlString.startsWith('market://')) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return NavigationActionPolicy.CANCEL;
        }

        // Interceptar descargas de APK (opcional pero recomendado)
        if (urlString.endsWith('.apk')) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return NavigationActionPolicy.CANCEL;
        }

        // Comportamiento original para esquemas no http/https
        if (uri.scheme != "http" && uri.scheme != "https") {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return NavigationActionPolicy.CANCEL;
        }

        return NavigationActionPolicy.ALLOW;
      },
      onLoadStop: (controller, url) async {
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

  // Barra inferior completa estilo Spotify: mini-player sólido + nav bar
  Widget _buildWebBottomBar(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final bgColor = _isDarkMode
        ? const Color(0xFF0D1B2A) // azul noche sólido modo oscuro
        : const Color(0xFFFFFFFF); // blanco puro modo claro
    final dividerColor = _isDarkMode
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.08);
    final rc = FirebaseRemoteConfig.instance;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Mini-player ──────────────────────────────────────────────
        _buildMiniPlayer(context, bgColor),
        // ── Divisor sutil ────────────────────────────────────────────
        Container(height: 1, color: dividerColor),
        // ── Bottom Nav estilo Spotify ─────────────────────────────────
        Container(
          color: bgColor,
          padding: EdgeInsets.only(
            top: 6,
            bottom: bottomPadding + 6,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _webNavItem(
                icon: Icons.home_outlined,
                label: t('menuWebsite'),
                onTap: () {
                  final url = rc.getString('url_website');
                  setState(() => _currentWebUrl = url);
                  _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
                },
                bgColor: bgColor,
              ),
              _webNavItem(
                icon: Icons.audio_file_outlined,
                label: t('menuAudios'),
                onTap: () {
                  final url = rc.getString('url_audios');
                  setState(() => _currentWebUrl = url);
                  _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
                },
                bgColor: bgColor,
              ),
              _webNavItem(
                icon: Icons.notes_outlined,
                label: t('menuPrayerRequests'),
                onTap: () {
                  final url = rc.getString('url_pedidos');
                  setState(() => _currentWebUrl = url);
                  _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
                },
                bgColor: bgColor,
              ),
              _webNavItem(
                icon: Icons.location_on_outlined,
                label: t('menuAddresses'),
                onTap: () {
                  final url = rc.getString('url_direcciones');
                  setState(() => _currentWebUrl = url);
                  _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
                },
                bgColor: bgColor,
              ),
              _webNavItem(
                icon: Icons.volunteer_activism_outlined,
                label: t('menuSupport'),
                onTap: () {
                  final url = rc.getString('url_apoyo');
                  setState(() => _currentWebUrl = url);
                  _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
                },
                bgColor: bgColor,
              ),
              _webNavItem(
                icon: Icons.close,
                label: 'Radio',
                onTap: () => setState(() => _isWebMode = false),
                bgColor: bgColor,
                isClose: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _webNavItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color bgColor,
    bool isClose = false,
  }) {
    final iconColor = _isDarkMode
        ? (isClose ? Colors.redAccent.shade100 : Colors.white70)
        : (isClose ? Colors.redAccent : Colors.black54);
    final labelColor = _isDarkMode
        ? (isClose ? Colors.redAccent.shade100 : Colors.white60)
        : (isClose ? Colors.redAccent : Colors.black45);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniPlayer(BuildContext context, Color bgColor) {
    final contrastColor = _isDarkMode ? Colors.white : Colors.black;
    final secondaryTextColor = _isDarkMode
        ? Colors.white.withOpacity(0.55)
        : Colors.black.withOpacity(0.50);
    final accentColor = _isDarkMode
        ? const Color(0xFF4A90D9)
        : const Color(0xFF1D72C8);

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (isLandscape && _isWebMode) {
      // ── Landscape: barra horizontal completa ──
      return Container(
        color: bgColor,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0), // Ajustado bottom a 0
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Artwork
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/iconolavoz.webp',
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
              ),
            ),
            const SizedBox(width: 10),

            // Título + subtítulo
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'A Voz Da Cura Divina',
                    style: TextStyle(
                      color: contrastColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _marqueeText.isNotEmpty
                        ? _marqueeText
                        : 'Igreja Primitiva Doutrina Divina',
                    style: TextStyle(color: secondaryTextColor, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Ecualizador animado
            _buildEqualizerBars(accentColor),
            const SizedBox(width: 10),

            // Botón play/stop circular
            GestureDetector(
              onTap: _playOrStopStream,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor,
                ),
                child: _isConnecting
                    ? Padding(
                        padding: const EdgeInsets.all(9),
                        child: LoadingAnimationWidget.staggeredDotsWave(
                            color: Colors.white, size: 16),
                      )
                    : Icon(
                        _audioPlayer.playerState.playing
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
              ),
            ),
            const SizedBox(width: 10),

            // Marquee de metadatos ICY
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  const _BlinkingLiveIndicator(),
                  const SizedBox(width: 5),
                  Icon(Icons.sensors, color: accentColor.withOpacity(0.7), size: 13),
                  const SizedBox(width: 5),
                  Expanded(
                    child: SizedBox(
                      height: 14,
                      child: Marquee(
                        text: _marqueeText.isNotEmpty
                            ? _marqueeText
                            : 'A Voz da Cura Divina no Ar',
                        style: TextStyle(
                          color: secondaryTextColor,
                          fontSize: 11,
                        ),
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
            const SizedBox(width: 10),

            // Volumen: ícono + slider horizontal
            Icon(
              _volume == 0 ? Icons.volume_off : Icons.volume_up,
              color: accentColor,
              size: 16,
            ),
            SizedBox(
              width: 80,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                  activeTrackColor: accentColor,
                  inactiveTrackColor: contrastColor.withOpacity(0.15),
                  thumbColor: accentColor,
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
          ],
        ),
      );
    }

    // ── Portrait: mini-player sólido borde a borde ───────────────────
    return Container(
      color: bgColor,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Fila principal: artwork | info+controls | logo+close
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Artwork
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/iconolavoz.webp',
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const SizedBox(width: 10),

              // Info central
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'A Voz Da Cura Divina',
                      style: TextStyle(
                        color: contrastColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _marqueeText.isNotEmpty
                          ? _marqueeText
                          : 'Igreja Primitiva Doutrina Divina',
                      style: TextStyle(color: secondaryTextColor, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Ecualizador mini
              _buildEqualizerBars(accentColor),
              const SizedBox(width: 10),

              // Botón play/stop
              GestureDetector(
                onTap: _playOrStopStream,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor,
                  ),
                  child: _isConnecting
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: LoadingAnimationWidget.staggeredDotsWave(
                              color: Colors.white, size: 18),
                        )
                      : Icon(
                          _audioPlayer.playerState.playing
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                ),
              ),
              const SizedBox(width: 8),

              // Volumen compacto vertical: ícono + slider rotado
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _volume == 0 ? Icons.volume_off : Icons.volume_up,
                    color: accentColor,
                    size: 16,
                  ),
                  const SizedBox(height: 2),
                  RotatedBox(
                    quarterTurns: 3,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                        activeTrackColor: accentColor,
                        inactiveTrackColor: contrastColor.withOpacity(0.15),
                        thumbColor: accentColor,
                      ),
                      child: SizedBox(
                        width: 44,
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
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Marquee de metadatos ICY
          Row(
            children: [
              const _BlinkingLiveIndicator(),
              const SizedBox(width: 5),
              Icon(Icons.sensors, color: accentColor.withOpacity(0.7), size: 13),
              const SizedBox(width: 5),
              Expanded(
                child: SizedBox(
                  height: 14,
                  child: Marquee(
                    text: _marqueeText.isNotEmpty
                        ? _marqueeText
                        : 'A Voz da Cura Divina no Ar',
                    style: TextStyle(
                      color: secondaryTextColor,
                      fontSize: 11,
                    ),
                    scrollAxis: Axis.horizontal,
                    velocity: 30.0,
                    blankSpace: 80.0,
                    pauseAfterRound: const Duration(seconds: 2),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showOverlayMenu() {
    if (_isNavigating) return;
    _isNavigating = true;
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _isNavigating = false;
    });
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        final isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;

        // Centro de expansión (Zona del icono WEBSITE)
        Offset startCenter = isLandscape
            ? Offset(screenWidth * 0.75, screenHeight * 0.5)
            : Offset(screenWidth * 0.75, screenHeight * 0.85);

        // Centro de contracción (Zona de la X)
        Offset endCenter = Offset(screenWidth - 50, 50);

        // Elegir centro según si está abriendo o cerrando
        bool isClosing = animation.status == AnimationStatus.reverse;
        Offset activeCenter = isClosing ? endCenter : startCenter;

        final overlayBgColors = _isDarkMode
            ? const Color(0xFF183153).withOpacity(0.88)
            : const Color(0xFF90C7F6).withOpacity(0.85);

        return ClipPath(
          clipper: _CircularRevealClipper(
            fraction: CurvedAnimation(
              parent: animation,
              curve: const Interval(0.0, 0.33, curve: Curves.easeOut),
            ).value,
            center: activeCenter,
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(color: overlayBgColors),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30.0, vertical: 25.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStaggeredItem(animation, 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Image.asset('assets/logoipdd.webp', height: 60),
                                _PulseCloseButton(
                                    onClose: () => Navigator.pop(context)),
                              ],
                            )),
                        const SizedBox(height: 18),
                        _buildStaggeredItem(
                          animation,
                          1,
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: Colors.black.withOpacity(0.08)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t('verseTitle'),
                                    style: GoogleFonts.inter(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.blue.shade800)),
                                const SizedBox(height: 8),
                                Text("«${obtenerVersiculoDelDia()}»",
                                    style: GoogleFonts.inter(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF4E87C0))),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 35),
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(left: 28.0),
                                  child: _buildMenuMainItem(
                                      animation,
                                      2,
                                      t('menuWebsite'),
                                      () => _openWebMenuLink(
                                          FirebaseRemoteConfig.instance.getString('url_website'))),
                                ),
                                ...[
                                  _buildMenuSubItem(
                                      animation,
                                      3,
                                      t('menuAudios'),
                                      FirebaseRemoteConfig.instance.getString('url_audios')),
                                  _buildMenuSubItem(
                                      animation, 
                                      4, 
                                      t('menuContact'),
                                      FirebaseRemoteConfig.instance.getString('url_contacto')),
                                  _buildMenuSubItem(
                                      animation,
                                      5,
                                      t('menuPrayerRequests'),
                                      FirebaseRemoteConfig.instance.getString('url_pedidos'),
                                      t('menuPrayerRequestsSub')),
                                  _buildMenuSubItem(
                                      animation, 
                                      6, 
                                      t('menuAddresses'),
                                      FirebaseRemoteConfig.instance.getString('url_direcciones')),
                                  _buildMenuSubItem(
                                      animation,
                                      7,
                                      t('menuSupport'),
                                      FirebaseRemoteConfig.instance.getString('url_apoyo'),
                                      "(${t('menuSupportSub')})"),
                                ].map((item) => Padding(
                                    padding: const EdgeInsets.only(left: 28.0),
                                    child: item)),
                                const SizedBox(height: 25),
                                Padding(
                                  padding: const EdgeInsets.only(left: 28.0),
                                  child: _buildMenuMainItem(
                                      animation, 8, t('menuAlarm'), () {
                                    if (!mounted || _isNavigating) return;
                                    _isNavigating = true;
                                    Navigator.pop(context);
                                    _showTimerAndAlarmDialog();
                                    Future.delayed(
                                        const Duration(milliseconds: 500), () {
                                      if (mounted) _isNavigating = false;
                                    });
                                  }, subText: t('menuAlarmSub')),
                                ),
                                const SizedBox(height: 15),
                                Padding(
                                  padding: const EdgeInsets.only(left: 28.0),
                                  child: _buildMenuMainItem(
                                      animation, 9, t('menuShare'), () {
                                    if (!mounted || _isNavigating) return;
                                    _isNavigating = true;
                                    Navigator.pop(context);
                                    Share.share(
                                        t('shareText'));
                                    Future.delayed(
                                        const Duration(milliseconds: 500), () {
                                      if (mounted) _isNavigating = false;
                                    });
                                  }),
                                ),

                                const SizedBox(height: 40),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openWebMenuLink(String url) async {
    if (!mounted || _isNavigating) return;
    _isNavigating = true;
    Navigator.pop(context); // Cierra el menú lateral

    try {
      _openWebMode(url); // Abre la pantalla web inmediatamente
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _isNavigating = false;
      });
    }
  }




  Widget _buildStaggeredItem(Animation<double> animation, int index,
      {required Widget child}) {
    final start = (index * 0.10).clamp(0.0, 0.7);
    final end = (start + 0.55).clamp(0.0, 1.0);

    final slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: animation,
      curve: Interval(start, end, curve: Curves.easeOutBack),
    ));

    final scaleAnimation = Tween<double>(
      begin: 0.88,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: animation,
      curve: Interval(start, end, curve: Curves.easeOutBack),
    ));

    final blurAnimation = CurvedAnimation(
      parent: animation,
      curve: Interval(start, end, curve: Curves.easeOut),
    );

    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Interval(start, end, curve: Curves.easeOut),
      ),
      child: SlideTransition(
        position: slideAnimation,
        child: ScaleTransition(
          scale: scaleAnimation,
          alignment: Alignment.centerLeft,
          child: AnimatedBuilder(
            animation: blurAnimation,
            builder: (context, child) {
              final sigma = lerpDouble(12.0, 0.0, blurAnimation.value) ?? 0.0;
              if (sigma <= 0.0) return child!;
              return ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: child,
              );
            },
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildMenuMainItem(
      Animation<double> animation, int index, String title, VoidCallback onTap,
      {String? subText}) {
    return _buildStaggeredItem(
      animation,
      index,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    height: 1.05,
                    color: const Color(0xFF4E87C0), // azul grisáceo
                  ),
                ),
                if (subText != null) ...[
                  const SizedBox(width: 15),
                  Text(
                    subText,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: _isDarkMode
                          ? const Color(0xFF88B5E0).withOpacity(0.5)
                          : Colors.black.withOpacity(0.40),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuSubItem(
      Animation<double> animation, int index, String title, String url,
      [String? subText]) {
    return _buildStaggeredItem(
      animation,
      index,
      child: GestureDetector(
        onTap: () => _openWebMenuLink(url),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    height: 1.05,
                    color: _isDarkMode
                        ? const Color(
                            0xFF88B5E0) // Tonalidad más clara del azul grisáceo
                        : Colors.black.withOpacity(0.75),
                  ),
                ),
                if (subText != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    subText,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: _isDarkMode
                          ? const Color(0xFF88B5E0).withOpacity(0.5)
                          : Colors.black.withOpacity(0.35),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PulseCloseButton extends StatefulWidget {
  final VoidCallback onClose;
  const _PulseCloseButton({Key? key, required this.onClose}) : super(key: key);

  @override
  _PulseCloseButtonState createState() => _PulseCloseButtonState();
}

class _PulseCloseButtonState extends State<_PulseCloseButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));

    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.3)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.3),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.3, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_controller);

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onClose();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTap: () => _controller.forward(),
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: Icon(
            Icons.close,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black,
            size: 42,
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
    final bgColor = isDarkMode ? const Color(0xFF183153) : Colors.black;
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

class _CircularRevealClipper extends CustomClipper<Path> {
  final double fraction;
  final Offset center;

  _CircularRevealClipper({required this.fraction, required this.center});

  @override
  Path getClip(Size size) {
    final Path path = Path();

    double maxRadius = _distance(center, Offset.zero);
    maxRadius = Math.max(maxRadius, _distance(center, Offset(size.width, 0)));
    maxRadius = Math.max(maxRadius, _distance(center, Offset(0, size.height)));
    maxRadius =
        Math.max(maxRadius, _distance(center, Offset(size.width, size.height)));

    path.addOval(Rect.fromCircle(center: center, radius: maxRadius * fraction));
    return path;
  }

  double _distance(Offset a, Offset b) {
    return Math.sqrt(Math.pow(a.dx - b.dx, 2) + Math.pow(a.dy - b.dy, 2));
  }

  @override
  bool shouldReclip(_CircularRevealClipper oldClipper) {
    return oldClipper.fraction != fraction || oldClipper.center != center;
  }
}

