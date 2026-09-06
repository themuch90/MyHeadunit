import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Riproduzione diretta via rete, senza passare dal backend Docker: la
/// pipeline GStreamer integrata in flutter-pi (vedi setup-host.sh,
/// BUILD_GSTREAMER_VIDEO_PLAYER_PLUGIN) gestisce nativamente anche stream
/// audio HTTP/Icecast tramite lo stesso VideoPlayerController gia' usato per
/// il video di Android Auto (vedi androidauto_texture_view.dart) -- qui
/// semplicemente non si mostra alcun widget video, solo l'audio.
class RadioStation {
  final String name;
  final String genre;
  final String url;
  const RadioStation({required this.name, required this.genre, required this.url});
}

// Stream pubblici SomaFM (icecast, nessuna autenticazione richiesta): un set
// di preset ragionevole per iniziare. L'utente puo' aggiungerne altri dal
// campo in fondo alla schermata.
const _presetStations = [
  RadioStation(
    name: 'Groove Salad',
    genre: 'Ambient / Downtempo',
    url: 'https://ice1.somafm.com/groovesalad-128-mp3',
  ),
  RadioStation(
    name: 'Beat Blender',
    genre: 'Deep House',
    url: 'https://ice1.somafm.com/beatblender-128-mp3',
  ),
  RadioStation(
    name: 'Indie Pop Rocks!',
    genre: 'Indie Pop',
    url: 'https://ice1.somafm.com/indiepop-128-mp3',
  ),
  RadioStation(
    name: 'Left Coast 70s',
    genre: 'Classic Rock anni \'70',
    url: 'https://ice1.somafm.com/seventies-128-mp3',
  ),
  RadioStation(
    name: 'Drone Zone',
    genre: 'Ambient spaziale',
    url: 'https://ice1.somafm.com/dronezone-128-mp3',
  ),
];

class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  final _customStations = <RadioStation>[];
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();

  VideoPlayerController? _controller;
  RadioStation? _current;
  bool _connecting = false;
  String? _error;

  @override
  void dispose() {
    _controller?.dispose();
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _play(RadioStation station) async {
    final old = _controller;
    setState(() {
      _controller = null;
      _current = station;
      _connecting = true;
      _error = null;
    });
    await old?.dispose();

    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(station.url));
      await controller.initialize();
      await controller.play();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _connecting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossibile avviare "${station.name}": $e';
        _connecting = false;
      });
    }
  }

  Future<void> _stop() async {
    final old = _controller;
    setState(() {
      _controller = null;
      _current = null;
      _connecting = false;
      _error = null;
    });
    await old?.dispose();
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      controller.value.isPlaying ? controller.pause() : controller.play();
    });
  }

  void _addCustomStation() {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    if (name.isEmpty || url.isEmpty) return;
    setState(() {
      _customStations.add(RadioStation(name: name, genre: 'Personalizzata', url: url));
      _nameController.clear();
      _urlController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final stations = [..._presetStations, ..._customStations];
    final isPlaying = _controller?.value.isPlaying ?? false;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: _NowPlayingCard(
            current: _current,
            connecting: _connecting,
            error: _error,
            isPlaying: isPlaying,
            onTogglePlayPause: _togglePlayPause,
            onStop: _stop,
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: stations.length,
            itemBuilder: (context, i) {
              final station = stations[i];
              final selected = _current?.url == station.url;
              return ListTile(
                leading: Icon(Icons.radio, color: selected ? Colors.blueAccent : Colors.grey),
                title: Text(station.name, style: const TextStyle(color: Colors.white)),
                subtitle: Text(station.genre, style: const TextStyle(color: Colors.grey)),
                selected: selected,
                onTap: () => _play(station),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Nome stazione',
                    hintStyle: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _urlController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'URL stream (http://...)',
                    hintStyle: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, color: Colors.blueAccent),
                tooltip: 'Aggiungi stazione',
                onPressed: _addCustomStation,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  final RadioStation? current;
  final bool connecting;
  final String? error;
  final bool isPlaying;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onStop;

  const _NowPlayingCard({
    required this.current,
    required this.connecting,
    required this.error,
    required this.isPlaying,
    required this.onTogglePlayPause,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(Icons.radio, color: current != null ? Colors.blueAccent : Colors.grey, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    current?.name ?? 'Nessuna stazione',
                    style: const TextStyle(fontSize: 18, color: Colors.white),
                  ),
                  Text(
                    error ?? (connecting ? 'Connessione...' : (current?.genre ?? 'Seleziona una stazione')),
                    style: TextStyle(
                      color: error != null ? Colors.redAccent : Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (connecting)
              const SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (current != null) ...[
              IconButton(
                iconSize: 32,
                color: Colors.white,
                icon: Icon(isPlaying ? Icons.pause_circle : Icons.play_circle),
                onPressed: onTogglePlayPause,
              ),
              IconButton(
                iconSize: 28,
                color: Colors.grey,
                icon: const Icon(Icons.stop_circle_outlined),
                onPressed: onStop,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
