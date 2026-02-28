import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class RadioPlayerWidget extends StatefulWidget {
  const RadioPlayerWidget({super.key});

  @override
  _RadioPlayerWidgetState createState() => _RadioPlayerWidgetState();
}

class _RadioPlayerWidgetState extends State<RadioPlayerWidget> {
  final AudioPlayer _audioPlayer = AudioPlayer();  // Controlador de audio
  bool isPlaying = false;  // Estado del botón de reproducción

  // URL de la transmisión de radio
  final String radioUrl = 'https://stream.zeno.fm/lla4zkqna7mvv';

  @override
  void initState() {
    super.initState();
    _audioPlayer.setUrl(radioUrl);  // Configura la URL de la radio
  }

  @override
  void dispose() {
    _audioPlayer.dispose();  // Limpia el reproductor al cerrar el widget
    super.dispose();
  }

  void _togglePlayPause() async {
    if (isPlaying) {
      await _audioPlayer.stop();
    } else {
      await _audioPlayer.play();
    }
    setState(() {
      isPlaying = !isPlaying;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            iconSize: 100.0,
            icon: Icon(
              isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: Colors.black,
            ),
            onPressed: _togglePlayPause,
          ),
          const SizedBox(height: 20),
          Text(
            isPlaying ? 'Reproduciendo' : 'Pausado',
            style: const TextStyle(fontSize: 24),
          ),
        ],
      ),
    );
  }
}
