import 'package:flutter/material.dart';
import '../services/radio_service.dart';

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
  final RadioService radioService;
  const RadioScreen({super.key, required this.radioService});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  final _customStations = <RadioStation>[];
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();

  RadioStation? _current;
  RadioPlaybackState _playback = RadioPlaybackState.stopped;
  bool _connecting = false;
  String? _error;
  String? _trackName;
  String? _streamTitle;

  @override
  void initState() {
    super.initState();
    widget.radioService.state.listen((s) {
      setState(() {
        _playback = s;
        _connecting = false;
        if (s == RadioPlaybackState.stopped) {
          _current = null;
          _trackName = null;
          _streamTitle = null;
        }
      });
    });
    widget.radioService.trackName.listen((n) => setState(() => _trackName = n));
    widget.radioService.streamTitle.listen((t) => setState(() => _streamTitle = t));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _play(RadioStation station) async {
    setState(() {
      _current = station;
      _connecting = true;
      _error = null;
    });
    try {
      await widget.radioService.playUri(station.url);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossibile avviare "${station.name}": $e';
        _connecting = false;
      });
    }
  }

  void _togglePlayPause() {
    if (_playback == RadioPlaybackState.playing) {
      widget.radioService.pause();
    } else if (_playback == RadioPlaybackState.paused) {
      widget.radioService.resume();
    }
  }

  void _stop() => widget.radioService.stop();

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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: _NowPlayingCard(
            current: _current,
            connecting: _connecting,
            error: _error,
            playback: _playback,
            trackName: _trackName,
            streamTitle: _streamTitle,
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
  final RadioPlaybackState playback;
  final String? trackName;
  final String? streamTitle;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onStop;

  const _NowPlayingCard({
    required this.current,
    required this.connecting,
    required this.error,
    required this.playback,
    required this.trackName,
    required this.streamTitle,
    required this.onTogglePlayPause,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final isPlaying = playback == RadioPlaybackState.playing;
    final title = trackName ?? current?.name ?? 'Nessuna stazione';
    final subtitle = error ??
        (connecting
            ? 'Connessione...'
            : (streamTitle ?? current?.genre ?? 'Seleziona una stazione'));

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
                  Text(title, style: const TextStyle(fontSize: 18, color: Colors.white)),
                  Text(
                    subtitle,
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
