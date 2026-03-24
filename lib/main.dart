
import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
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
import 'alarm_manager.dart';

@pragma('vm:entry-point')
void playRadio() async {
  final audioPlayer = AudioPlayer();
  try {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.kym.lavozdelacuradivina.radio.channel.alarm',
        androidNotificationChannelName: 'Radio A Voz da Cura Divina - Alarma',
        androidNotificationOngoing: true,
      );
    }
    const String streamUrl = 'https://s10.maxcast.com.br:9083/live';
    final mediaItem = MediaItem(id: streamUrl, title: 'A Voz da Cura Divina - Alarma', artist: 'Radio ao vivo');
    await audioPlayer.setAudioSource(AudioSource.uri(Uri.parse(streamUrl), tag: mediaItem));
    await audioPlayer.play();
  } catch (e) {
    debugPrint("Error playing from background alarm: $e");
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR', null);
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await AndroidAlarmManager.initialize();
  }
  try {
    if (!kIsWeb) {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.kym.lavozdelacuradivina.radio.channel.audio',
        androidNotificationChannelName: 'Radio A Voz da Cura Divina',
        androidNotificationOngoing: true,
        notificationColor: const Color(0xFF2196f3),
      );
    }
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  } catch (e) {
    debugPrint('Error inicializando plugins de audio: $e');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'A Voz da Cura Divina',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      home: const RadioHome(),
    );
  }
}

class RadioHome extends StatefulWidget {
  const RadioHome({Key? key}) : super(key: key);
  static const String streamUrl = 'https://s10.maxcast.com.br:9083/live';

  @override
  State<RadioHome> createState() => _RadioHomeState();
}

class _RadioHomeState extends State<RadioHome> with WidgetsBindingObserver {
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

  bool get _supportsAndroidAlarm => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clockStream = Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()).asBroadcastStream();
    _loadPreferencesAndInitialize();
    _initializePlayer();
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

  Future<void> _initializePlayer() async {
    _audioPlayer.setVolume(_volume);
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) setState(() {});
      if (state.playing &&
          _isConnecting &&
          (state.processingState == ProcessingState.ready || state.processingState == ProcessingState.buffering)) {
        if (mounted) setState(() => _isConnecting = false);
      }
    });
    _audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _restartStream();
    });
    try {
      await _initializeAudio();
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Error de inicialización: ${e.toString()}');
    } finally {
      if (mounted && _isInitialLoading) {
         setState(() => _isInitialLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _volumeIndicatorTimer?.cancel();
    _sleepTimer?.cancel();
    _uiUpdateTimer?.cancel();
    _audioPlayer.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initializeAudio() async {
    if (!mounted) return;
    setState(() => _errorMessage = '');
    try {
      final mediaItem = MediaItem(id: RadioHome.streamUrl, title: 'A Voz da Cura Divina', artist: 'Radio ao vivo');
      await _audioPlayer.setAudioSource(AudioSource.uri(Uri.parse(RadioHome.streamUrl), tag: mediaItem), preload: false);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Error de fuente de audio: ${e.toString()}');
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
      if (mounted) setState(() => _errorMessage = 'No hay conexión a Internet. Por favor, verifica tu conexión.');
      return;
    }
    setState(() => _errorMessage = '');
    if (_audioPlayer.playerState.playing) {
      await _audioPlayer.stop();
      if (mounted) setState(() => _isConnecting = false);
    } else {
      try {
        if (_audioPlayer.processingState == ProcessingState.idle) {
            await _initializeAudio();
        }
        if (mounted) setState(() => _isConnecting = true);
        await _audioPlayer.play();
      } catch (e) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Error al intentar reproducir.';
            _isConnecting = false;
          });
        }
      }
    }
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo abrir $urlString')));
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
          title: Text('Temporizador e Alarme', style: TextStyle(color: titleColor)),
          children: <Widget>[
            _buildTimerOption(15, 'Desligar em 15 minutos'),
            _buildTimerOption(30, 'Desligar em 30 minutos'),
            _buildTimerOption(60, 'Desligar em 1 hora'),
            if (_sleepTimer != null)
              _buildCancelOption('Cancelar Temporizador', _cancelSleepTimer, 'Temporizador de apagado cancelado.'),
            if (_supportsAndroidAlarm) ...[
              const Divider(),
              _buildAlarmOption('Programar Alarme', _selectAlarmTime),
              if (_alarmTime != null) _buildCancelOption('Cancelar Alarme', _cancelAlarm, 'Alarma cancelada.'),
            ]
          ],
        );
      },
    );
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

  Widget _buildCancelOption(String label, VoidCallback onCancelled, String message) {
    return SimpleDialogOption(
      onPressed: () {
        Navigator.pop(context);
        onCancelled();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
          if (mounted) setState(() => _remainingSleepTime = _remainingSleepTime! - const Duration(seconds: 1));
        } else {
          _cancelSleepTimer();
        }
      } else {
        timer.cancel();
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('La radio se apagará en ${duration.inMinutes} minutos.')),
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
    DateTime scheduledTime = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Alarma programada para las ${intl.DateFormat('HH:mm').format(scheduledTime)}')));
    }
  }

  Future<void> _cancelAlarm() async {
    if (!_supportsAndroidAlarm) return;
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
    final drawerBgColor = _isDarkMode ? Colors.black.withOpacity(0.5) : Colors.white.withOpacity(0.75);
    final iconColor = _isDarkMode ? Colors.white70 : Colors.black54;
    final textColor = _isDarkMode ? Colors.white : Colors.black;

    return Drawer(
        backgroundColor: Colors.transparent,
        elevation: 0,
        width: MediaQuery.of(context).size.width * 0.75,
        child: ClipRRect(
            borderRadius: const BorderRadius.only(topRight: Radius.circular(40), bottomRight: Radius.circular(40)),
            child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                child: Container(
                    color: drawerBgColor,
                    child: SafeArea(
                      child: Column(
                        children: [
                          SizedBox(
                              height: 150,
                              width: double.infinity,
                              child: Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Image.asset('assets/logoipdd.webp', fit: BoxFit.contain),
                              )),
                          ListTile(
                              leading: Icon(Icons.timer_outlined, color: iconColor),
                              title: Text("Temporizador de Sono", style: TextStyle(color: textColor)),
                              onTap: _showTimerAndAlarmDialog),
                          if (_supportsAndroidAlarm)
                            ListTile(
                                leading: Icon(Icons.alarm, color: iconColor),
                                title: Text("Alarme Despertador", style: TextStyle(color: textColor)),
                                onTap: _showTimerAndAlarmDialog),
                          const Divider(),
                          ListTile(
                              leading: Icon(Icons.language, color: iconColor),
                              title: Text("Site e Reprise", style: TextStyle(color: textColor)),
                              onTap: () => _launchURL("https://igrejaprimitivadoutrinadivina.com/")),
                          ListTile(
                              leading: Icon(Icons.notes, color: iconColor),
                              title: Text("Pedidos de Oração", style: TextStyle(color: textColor)),
                              onTap: () => _launchURL("https://www.igrejaprimitivadoutrinadivina.com/recados")),
                          ListTile(
                              leading: Icon(Icons.location_on, color: iconColor),
                              title: Text("Endereços", style: TextStyle(color: textColor)),
                              onTap: () =>
                                  _launchURL("https://igrejaprimitivadoutrinadivina.com/internas/enderecos-ipdd")),
                          ListTile(
                              leading: Icon(Icons.volunteer_activism, color: iconColor),
                              title: Text("Ajude esta obra", style: TextStyle(color: textColor)),
                              onTap: () =>
                                  _launchURL("https://www.igrejaprimitivadoutrinadivina.com/internas/contas-bancarias")),
                          ListTile(
                              leading: Icon(Icons.share, color: iconColor),
                              title: Text("Compartilhar", style: TextStyle(color: textColor)),
                              onTap: () => Share.share(
                                  'Confira A Voz da Cura Divina: https://play.google.com/store/apps/details?id=com.kym.lavozdelacuradivina.radio')),
                        ],
                      ),
                    )))));
  }

  Widget _buildTopContainer(BuildContext context, Color textColor) {
    return Container(
      margin: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40.0),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 25, spreadRadius: -5, offset: const Offset(0, 10))]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40.0),
        child: Stack(
          children: [
            if (!_isDarkMode)
              Positioned.fill(
                  child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                      child: Image.asset('assets/iconolavoz.webp', fit: BoxFit.cover))),
            Positioned.fill(
              child: Container(
                  decoration: BoxDecoration(
                      color: _isDarkMode ? Colors.black.withOpacity(0.2) : Colors.white.withOpacity(0.75),
                      border: Border.all(color: (_isDarkMode ? Colors.white : Colors.black).withOpacity(0.1)))),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
              child: Column(
                children: [
                  Row(children: [
                    ClipRRect(
                        borderRadius: BorderRadius.circular(30.0),
                        child: Image.asset('assets/iconolavoz.webp', width: 150, height: 150, fit: BoxFit.cover)),
                    const SizedBox(width: 16),
                    Expanded(
                        child: GestureDetector(
                            onTap: _showTimerAndAlarmDialog,
                            child: StreamBuilder<DateTime>(
                                stream: _clockStream,
                                builder: (context, snapshot) {
                                  final now = snapshot.data ?? DateTime.now();
                                  final time = intl.DateFormat('HH:mm').format(now);
                                  String date = intl.DateFormat('E, d MMM yyyy', 'pt_BR').format(now);
                                  if (date.isNotEmpty) {
                                    date = "${date[0].toUpperCase()}${date.substring(1)}";
                                  }
                                  return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        FittedBox(
                                            fit: BoxFit.contain,
                                            child: Text(time,
                                                style: GoogleFonts.bebasNeue(
                                                    color: textColor, fontSize: 75, fontWeight: FontWeight.bold))),
                                        Text(date, style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 16, fontWeight: FontWeight.bold)),
                                        if (_remainingSleepTime != null) ...[
                                          const SizedBox(height: 4),
                                          Text('Apagado en: ${_formatDuration(_remainingSleepTime!)}',
                                              style: TextStyle(color: textColor.withOpacity(0.9), fontSize: 14, fontWeight: FontWeight.bold))
                                        ],
                                        if (_supportsAndroidAlarm && _alarmTime != null) ...[
                                          const SizedBox(height: 4),
                                          Text('Alarma: ${intl.DateFormat("HH:mm").format(_alarmTime!)}',
                                              style: TextStyle(color: Colors.amber.shade700, fontSize: 14, fontWeight: FontWeight.bold))
                                        ]
                                      ]);
                                })))
                  ]),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                            height: 30,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(15.0)),
                            child: Row(children: [
                              if (_audioPlayer.playerState.playing) const _BlinkingLiveIndicator(),
                              Expanded(
                                child: _audioPlayer.playerState.playing
                                    ? Marquee(
                                        text: "A Voz da Cura Divina No Ar - Evangelizando o Mundo  ",
                                        style: const TextStyle(color: Colors.white, fontSize: 16),
                                        velocity: 40.0,
                                        blankSpace: 50.0,
                                        crossAxisAlignment: CrossAxisAlignment.center)
                                    : Center(
                                        child: Text("OFFLINE",
                                            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16, fontWeight: FontWeight.bold))),
                              ),
                            ])),
                      ),
                      const SizedBox(width: 8),
                      _CustomSwitch(
                        value: _isDarkMode,
                        onChanged: (value) => setState(() => _isDarkMode = value),
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

  Widget _buildPortraitBottom(BuildContext context, Color baseBgColor, Color headerBgColor, Color textColor, Color playIconColor, Color websiteIconColor, List<BoxShadow> neumorphicShadows, bool isDrawerOpen) {
    return Column(
        children: [
          Expanded(
            child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(40.0), boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 25, spreadRadius: -5, offset: const Offset(0, 10))
                ]),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(40.0),
                  child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                      child: Container(
                          decoration: BoxDecoration(
                              color: _isDarkMode ? Colors.blue.withOpacity(0.1) : baseBgColor.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(40.0),
                              border: Border.all(color: (_isDarkMode ? Colors.white : Colors.black).withOpacity(0.1))),
                          child: Row(children: [
                            Expanded(
                                flex: 5,
                                child: Column(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      Stack(alignment: Alignment.center, children: [
                                            SleekCircularSlider(
                                                appearance: CircularSliderAppearance(
                                                    customWidths: CustomSliderWidths(trackWidth: 1.5, progressBarWidth: 4, handlerSize: 8),
                                                    customColors: CustomSliderColors(
                                                        trackColor: textColor.withOpacity(0.1),
                                                        progressBarColors: [Colors.blue.shade300, Colors.blue.shade800],
                                                        dotColor: _isDarkMode ? Colors.white : Colors.black),
                                                    startAngle: 120,
                                                    angleRange: 25,
                                                    size: MediaQuery.of(context).size.width * 0.52),
                                                min: 0.0,
                                                max: 100.0,
                                                initialValue: (_volume * 100).clamp(0.0, 100.0),
                                                onChange: (double value) {
                                                  _volumeIndicatorTimer?.cancel();
                                                  setState(() {
                                                    _volume = (value / 100.0).clamp(0.0, 1.0);
                                                    _showVolumeIndicator = true;
                                                  });
                                                  _audioPlayer.setVolume(_volume);
                                                  _volumeIndicatorTimer = Timer(const Duration(seconds: 2), () {
                                                    if (mounted) setState(() => _showVolumeIndicator = false);
                                                  });
                                                },
                                                innerWidget: (double percentage) {
                                                  return Stack(alignment: Alignment.center, children: [
                                                    GestureDetector(
                                                      onVerticalDragStart: (d) {
                                                        _volumeIndicatorTimer?.cancel();
                                                        setState(() => _showVolumeIndicator = true);
                                                      },
                                                      onVerticalDragUpdate: (d) {
                                                        final newVolume = (_volume - d.delta.dy / 200).clamp(0.0, 1.0);
                                                        setState(() => _volume = newVolume);
                                                        _audioPlayer.setVolume(_volume);
                                                      },
                                                      onVerticalDragEnd: (d) {
                                                        _volumeIndicatorTimer = Timer(const Duration(seconds: 2), () {
                                                          if (mounted) setState(() => _showVolumeIndicator = false);
                                                        });
                                                      },
                                                      child: Container(
                                                        color: Colors.transparent,
                                                        child: Padding(
                                                          padding: const EdgeInsets.fromLTRB(22.0, 22.0, 22.0, 28.0),
                                                          child: Transform.scale(
                                                            scale: 1.25,
                                                            child: Image.asset('assets/GRILL OK.webp', fit: BoxFit.contain),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    Positioned(
                                                      bottom: 2,
                                                      child: Text('Volume',
                                                          style: TextStyle(color: textColor.withOpacity(0.8), fontWeight: FontWeight.bold, fontSize: 12)),
                                                    ),
                                                  ]);
                                                }),
                                            IgnorePointer(
                                              child: AnimatedOpacity(
                                                  opacity: _showVolumeIndicator ? 1.0 : 0.0,
                                                  duration: const Duration(milliseconds: 300),
                                                  child: Container(
                                                      padding: const EdgeInsets.all(12),
                                                      decoration: BoxDecoration(
                                                          color: Colors.black.withOpacity(0.6),
                                                          borderRadius: BorderRadius.circular(15)),
                                                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                                                        Icon(
                                                            _volume <= 0 ? Icons.volume_off : (_volume < 0.5 ? Icons.volume_down : Icons.volume_up),
                                                            color: Colors.white, size: 30),
                                                        const SizedBox(height: 8),
                                                        Text('${(_volume * 100).toInt()}%',
                                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                                                      ]))),
                                            )
                                          ])
                                    ])),
                            Container(
                                width: 1,
                                height: double.infinity,
                                color: textColor.withOpacity(0.2),
                                margin: const EdgeInsets.symmetric(vertical: 40.0)),
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
                                                      ? LinearGradient(colors: [baseBgColor, headerBgColor], begin: Alignment.topLeft, end: Alignment.bottomRight)
                                                      : null,
                                                  color: _isDarkMode ? baseBgColor : (_audioPlayer.playerState.playing ? null : baseBgColor),
                                                  shape: BoxShape.circle,
                                                  border: _isDarkMode ? Border.all(color: Colors.grey.shade700, width: 1) : null,
                                                  boxShadow: neumorphicShadows),
                                              child: _isConnecting
                                                  ? LoadingAnimationWidget.inkDrop(color: playIconColor, size: 35.0)
                                                  : Icon(_audioPlayer.playerState.playing ? Icons.stop : Icons.play_arrow, color: playIconColor, size: 50))),
                                      const SizedBox(height: 40),
                                      GestureDetector(
                                          onTap: () { _scaffoldKey.currentState?.openDrawer(); },
                                          child: Column(children: [
                                            Container(
                                                width: 70,
                                                height: 70,
                                                decoration: BoxDecoration(
                                                    gradient: !_isDarkMode && isDrawerOpen
                                                        ? LinearGradient(colors: [baseBgColor, headerBgColor], begin: Alignment.topLeft, end: Alignment.bottomRight)
                                                        : null,
                                                    color: _isDarkMode ? baseBgColor : (isDrawerOpen ? null : baseBgColor),
                                                    shape: BoxShape.circle,
                                                    border: _isDarkMode ? Border.all(color: Colors.grey.shade700, width: 1) : null,
                                                    boxShadow: neumorphicShadows),
                                                child: Icon(Icons.language, color: websiteIconColor, size: 40)),
                                            const SizedBox(height: 8),
                                            Text("WEBSITE", style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold))
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

  Widget _buildLandscapeRight(BuildContext context, Color baseBgColor, Color headerBgColor, Color textColor, Color playIconColor, List<BoxShadow> neumorphicShadows) {
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
                            gradient: !_isDarkMode && _audioPlayer.playerState.playing
                                ? LinearGradient(colors: [baseBgColor, headerBgColor], begin: Alignment.topLeft, end: Alignment.bottomRight)
                                : null,
                            color: _isDarkMode ? baseBgColor : (_audioPlayer.playerState.playing ? null : baseBgColor),
                            shape: BoxShape.circle,
                            border: _isDarkMode ? Border.all(color: Colors.grey.shade700, width: 1) : null,
                            boxShadow: neumorphicShadows),
                        child: _isConnecting
                            ? LoadingAnimationWidget.inkDrop(color: playIconColor, size: 45.0)
                            : Icon(_audioPlayer.playerState.playing ? Icons.stop : Icons.play_arrow, color: playIconColor, size: 70))),
                const SizedBox(height: 30),
                Container(
                  width: 250,
                  decoration: BoxDecoration(
                    color: _isDarkMode ? Colors.black26 : Colors.white60,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: (_isDarkMode ? Colors.white : Colors.black).withOpacity(0.05)),
                    boxShadow: neumorphicShadows
                  ),
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 8,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
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
                  child: Text('${(_volume * 100).toInt()}%', style: TextStyle(color: textColor.withOpacity(0.8), fontWeight: FontWeight.bold, fontSize: 16)),
                )
              ],
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: GestureDetector(
                onVerticalDragEnd: (d) { if (d.primaryVelocity! < 0) _showLandscapeMenu(baseBgColor, textColor); },
                onTap: () => _showLandscapeMenu(baseBgColor, textColor),
                child: Container(
                  width: 120,
                  height: 35,
                  margin: const EdgeInsets.only(bottom: 5),
                  decoration: BoxDecoration(
                    color: _isDarkMode ? Colors.white10 : Colors.black12,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(15), bottom: Radius.circular(5))
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(width: 40, height: 4, decoration: BoxDecoration(color: textColor.withOpacity(0.5), borderRadius: BorderRadius.circular(2))),
                      const SizedBox(height: 4),
                      Text("MENÚ", style: TextStyle(color: textColor.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.bold)),
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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25))
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(width: 50, height: 6, decoration: BoxDecoration(color: textColor.withOpacity(0.3), borderRadius: BorderRadius.circular(3))),
              const SizedBox(height: 20),
              Text("MENÚ PRINCIPAL", style: GoogleFonts.bebasNeue(fontSize: 32, color: textColor)),
              const SizedBox(height: 20),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: 15,
                  crossAxisSpacing: 15,
                  childAspectRatio: 1.2,
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildLandscapeGridItem(Icons.timer, "Temporizador", _showTimerAndAlarmDialog, textColor),
                    _buildLandscapeGridItem(Icons.alarm, "Alarme", _showTimerAndAlarmDialog, textColor),
                    _buildLandscapeGridItem(Icons.language, "Site", () { }, textColor),
                    _buildLandscapeGridItem(Icons.replay, "Reprise", _showTimerAndAlarmDialog, textColor),
                    _buildLandscapeGridItem(Icons.share, "Compartilhar", () { }, textColor),
                    _buildLandscapeGridItem(Icons.exit_to_app, "Sair", () => SystemNavigator.pop(), textColor),
                  ],
                ),
              )
            ]
          )
        );
      }
    );
  }

  Widget _buildLandscapeGridItem(IconData icon, String title, VoidCallback onTap, Color textColor) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          color: _isDarkMode ? Colors.white10 : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: (_isDarkMode ? Colors.white : Colors.black).withOpacity(0.05))
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.blue.shade700, size: 45),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        )
      )
    );
  }


  @override
  Widget build(BuildContext context) {
    final Color baseBgColor = _isDarkMode ? const Color(0xFF0A192F) : const Color(0xFFB2EBF2);
    final Color textColor = _isDarkMode ? Colors.blue.shade700 : Colors.black;
    final Color headerBgColor = _isDarkMode ? Colors.black : const Color.fromARGB(255, 255, 255, 255);
    final Color playIconColor = _isDarkMode ? Colors.blue : const Color.fromARGB(255, 53, 53, 53);
    final Color websiteIconColor = _isDarkMode ? Colors.blue.shade700 : const Color.fromARGB(255, 54, 54, 54);
    final bool isDrawerOpen = _scaffoldKey.currentState?.isDrawerOpen ?? false;
    final neumorphicShadows = _isDarkMode
        ? [ const BoxShadow(color: Colors.black54, offset: Offset(5, 5), blurRadius: 10), const BoxShadow(color: Colors.white10, offset: Offset(-5, -5), blurRadius: 10) ]
        : [ const BoxShadow(color: Colors.white, offset: Offset(-5, -5), blurRadius: 15), const BoxShadow(color: Color(0xFF82B8C2), offset: Offset(5, 5), blurRadius: 15) ];

    if (_isInitialLoading)
      return Scaffold(backgroundColor: baseBgColor, body: Center(child: LoadingAnimationWidget.inkDrop(color: textColor, size: 50.0)));
    if (_errorMessage.isNotEmpty)
      return Scaffold(
          backgroundColor: baseBgColor,
          body: Center(
              child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(_errorMessage, style: TextStyle(color: textColor), textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    ElevatedButton(onPressed: _initializePlayer, child: const Text('Reintentar'))
                  ]))));

    return Scaffold(
      key: _scaffoldKey,
      drawer: MediaQuery.of(context).orientation == Orientation.landscape ? null : _buildDrawer(context),
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isDarkMode
                    ? [const Color.fromARGB(255, 0, 55, 219).withOpacity(0.9), baseBgColor]
                    : [const Color(0xFF80DEEA), baseBgColor],
                begin: _isDarkMode ? Alignment.topCenter : Alignment.topLeft,
                end: _isDarkMode ? Alignment.bottomCenter : Alignment.bottomRight,
                stops: _isDarkMode ? const [0.0, 0.4] : const [0.0, 0.9],
              ),
            ),
          ),
          Positioned(
              top: 30,
              left: 0,
              right: 0,
              child: Opacity(opacity: _isDarkMode ? 0.3 : 0.6, child: Image.asset('assets/NUBE.webp', height: 280, fit: BoxFit.cover))),
          SafeArea(
            child: MediaQuery.of(context).orientation == Orientation.landscape
                ? Row(
                    children: [
                      Expanded(flex: 4, child: SingleChildScrollView(child: _buildTopContainer(context, textColor))),
                      Expanded(flex: 3, child: _buildLandscapeRight(context, baseBgColor, headerBgColor, textColor, playIconColor, neumorphicShadows))
                    ],
                  )
                : Column(
                    children: [
                      _buildTopContainer(context, textColor),
                      Expanded(child: _buildPortraitBottom(context, baseBgColor, headerBgColor, textColor, playIconColor, websiteIconColor, neumorphicShadows, isDrawerOpen)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _BlinkingLiveIndicator extends StatefulWidget {
  const _BlinkingLiveIndicator({Key? key}) : super(key: key);
  @override
  _BlinkingLiveIndicatorState createState() => _BlinkingLiveIndicatorState();
}

class _BlinkingLiveIndicatorState extends State<_BlinkingLiveIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
        opacity: _controller,
        child: Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: 8),
            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)));
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

  const _CustomSwitch({Key? key, required this.value, required this.onChanged, required this.isDarkMode}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const double width = 60.0;
    const double height = 30.0;
    const double thumbSize = 24.0;
    final bgColor = isDarkMode ? const Color(0xFF0A192F) : Colors.black;
    final neumorphicShadows = isDarkMode
        ? [
            const BoxShadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 8, spreadRadius: 1),
            BoxShadow(color: Colors.blueGrey.shade900, offset: const Offset(-4, -4), blurRadius: 8, spreadRadius: 1)
          ]
        : [
            const BoxShadow(color: Color(0xFFA7B4C9), offset: Offset(4, 4), blurRadius: 8, spreadRadius: 1),
            const BoxShadow(color: Colors.white, offset: Offset(-4, -4), blurRadius: 8, spreadRadius: 1)
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
                border: isDarkMode ? Border.all(color: Colors.grey.shade700, width: 1) : null),
            child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                    margin: const EdgeInsets.all((height - thumbSize) / 2),
                    width: thumbSize,
                    height: thumbSize,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: value ? const Color.fromARGB(255, 33, 150, 243) : Colors.grey.shade500),
                    child: Icon(value ? Icons.nightlight_round : Icons.wb_sunny, color: value ? Colors.white : Colors.black, size: 16.0)))));
  }
}