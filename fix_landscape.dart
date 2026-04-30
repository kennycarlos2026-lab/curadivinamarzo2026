import 'dart:io';

void main() {
  final file = File('lib/main.dart');
  var content = file.readAsStringSync();

  // Find the landscape block start and end markers
  const start = '    if (isLandscape && _isWebMode) {\r\n      // En landscape, mostrar solo columna lateral compacta';
  const end = '    }\r\n\r\n    // ── Portrait: mini-player sólido borde a borde ───────────────────';

  if (!content.contains(start)) {
    print('START MARKER NOT FOUND');
    return;
  }

  const replacement = '''    if (isLandscape && _isWebMode) {
      // ── Landscape: barra horizontal completa ──
      return Container(
        color: bgColor,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
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

    // ── Portrait: mini-player sólido borde a borde ───────────────────''';

  // Replace from start marker to end marker (exclusive of end marker itself)
  final startIdx = content.indexOf(start);
  final endIdx = content.indexOf(end);
  
  if (startIdx == -1 || endIdx == -1) {
    print('Markers not found. start=$startIdx end=$endIdx');
    return;
  }

  // Replace from startIdx to just before the "// ── Portrait" comment
  final before = content.substring(0, startIdx);
  final after = content.substring(endIdx + end.length);
  
  content = before + replacement + after;
  file.writeAsStringSync(content);
  print('Done! Landscape mini-player replaced successfully.');
}
