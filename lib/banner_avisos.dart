import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

class BannerAvisos extends StatefulWidget {
  final bool isPlaying;

  const BannerAvisos({Key? key, required this.isPlaying}) : super(key: key);

  @override
  State<BannerAvisos> createState() => _BannerAvisosState();
}

class _BannerAvisosState extends State<BannerAvisos> {
  bool _isExpanded = true;
  bool _avisoActivo = false;
  String _mensaje = "";
  Color _colorFondo = Colors.black;
  Color _colorTexto = Colors.white;

  @override
  void initState() {
    super.initState();
    _fetchRemoteConfig();
  }

  Future<void> _fetchRemoteConfig() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: Duration.zero, // Set to zero for immediate testing. Increase for production to save reads.
      ));
      
      // Default value to prevent errors if not configured in Firebase yet
      await remoteConfig.setDefaults(const {
        "aviso_banner_config": '{"aviso_activo": false, "mensaje": "", "fecha_inicio": "2026-01-01T00:00:00", "fecha_fin": "2026-01-02T00:00:00", "color_fondo": "#000000", "color_texto": "#FFFFFF"}'
      });

      await remoteConfig.fetchAndActivate();
      
      final String jsonConfig = remoteConfig.getString("aviso_banner_config");
      debugPrint("RemoteConfig fetched (aviso_banner_config): $jsonConfig");
      _parseConfig(jsonConfig);
    } catch (e) {
      debugPrint("Error fetching remote config: \$e");
    }
  }

  void _parseConfig(String jsonString) {
    try {
      final data = jsonDecode(jsonString);
      // Apoyar tanto aviso_activo como visible
      final bool avisoActivo = data['aviso_activo'] ?? data['visible'] ?? false;
      final String fechaInicioStr = data['fecha_inicio'] ?? "";
      final String fechaFinStr = data['fecha_fin'] ?? "";

      final DateTime now = DateTime.now();
      // Si no vienen fechas o fallan al parsear, damos fechas muy amplias para que no falle la condición
      final DateTime fechaInicio = DateTime.tryParse(fechaInicioStr) ?? DateTime(2000);
      final DateTime fechaFin = DateTime.tryParse(fechaFinStr) ?? DateTime(2099);

      if (avisoActivo && now.isAfter(fechaInicio) && now.isBefore(fechaFin)) {
        setState(() {
          _avisoActivo = true;
          _mensaje = data['texto'] ?? data['mensaje'] ?? "Aviso importante";
          _colorFondo = _hexToColor(data['color'] ?? data['color_fondo'] ?? "#000000");
          _colorTexto = _hexToColor(data['color_texto'] ?? "#FFFFFF");
          _isExpanded = true; // Empieza extendido si hay aviso válido
        });
      } else {
        setState(() {
          _avisoActivo = false;
        });
      }
    } catch (e) {
      debugPrint("Error al parsear Remote Config: \$e");
    }
  }

  Color _hexToColor(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    final int? colorInt = int.tryParse(buffer.toString(), radix: 16);
    return Color(colorInt ?? 0xFF000000);
  }

  @override
  Widget build(BuildContext context) {
    // Si no hay aviso activo (fuera de fecha o desactivado), mostramos el diseño normal sin posibilidad de expandir
    if (!_avisoActivo) {
      return Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(15.0)),
        child: Row(
          children: [
            if (widget.isPlaying) const _BlinkingLiveIndicator(),
            Expanded(
              child: widget.isPlaying
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
          ],
        ),
      );
    }

    // Hay aviso activo. Interfaz colapsable.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: _isExpanded ? 120 : 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _isExpanded ? _colorFondo : Colors.black,
        borderRadius: BorderRadius.circular(15.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Fila superior (siempre visible): Marquee + indicador de expansión si está colapsado
          SizedBox(
            height: 30,
            child: Row(
              children: [
                if (widget.isPlaying) const _BlinkingLiveIndicator(),
                Expanded(
                  child: widget.isPlaying
                      ? Marquee(
                          text: "A Voz da Cura Divina No Ar - Evangelizando o Mundo  ",
                          style: TextStyle(color: _isExpanded ? _colorTexto : Colors.white, fontSize: 16),
                          velocity: 40.0,
                          blankSpace: 50.0,
                          crossAxisAlignment: CrossAxisAlignment.center)
                      : Center(
                          child: Text("OFFLINE",
                              style: TextStyle(
                                  color: (_isExpanded ? _colorTexto : Colors.white).withOpacity(0.7), 
                                  fontSize: 16, 
                                  fontWeight: FontWeight.bold))),
                ),
                if (!_isExpanded)
                  GestureDetector(
                    onTap: () => setState(() => _isExpanded = true),
                    child: Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 16),
                    ),
                  ),
              ],
            ),
          ),
          // Área expandida
          if (_isExpanded) ...[
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(
                        _mensaje,
                        style: TextStyle(color: _colorTexto, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _isExpanded = false),
              child: const SizedBox(
                height: 24,
                child: Icon(Icons.keyboard_arrow_up, color: Colors.white70, size: 20),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Reutilizamos el BlinkingLiveIndicator aquí para que esté disponible internamente
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
