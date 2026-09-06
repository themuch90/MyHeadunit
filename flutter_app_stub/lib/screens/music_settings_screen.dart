import 'package:flutter/material.dart';
import '../services/mopidy_config_service.dart';
import '../services/radio_service.dart';

class MusicSettingsScreen extends StatefulWidget {
  final MopidyConfigService configService;
  final RadioService radioService;

  const MusicSettingsScreen({
    super.key,
    required this.configService,
    required this.radioService,
  });

  @override
  State<MusicSettingsScreen> createState() => _MusicSettingsScreenState();
}

class _MusicSettingsScreenState extends State<MusicSettingsScreen> {
  bool _loading = true;
  bool _spotifyEnabled = false;
  final _clientId = TextEditingController();
  final _clientSecret = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _mediaDir = TextEditingController();

  double? _volume;

  @override
  void initState() {
    super.initState();
    _load();
    widget.radioService.getVolume().then((v) {
      if (mounted && v != null) setState(() => _volume = v.toDouble());
    });
  }

  Future<void> _load() async {
    final s = await widget.configService.load();
    if (!mounted) return;
    setState(() {
      _spotifyEnabled = s.spotifyEnabled;
      _clientId.text = s.spotifyClientId;
      _clientSecret.text = s.spotifyClientSecret;
      _username.text = s.spotifyUsername;
      _password.text = s.spotifyPassword;
      _mediaDir.text = s.localMediaDir;
      _loading = false;
    });
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final settings = MopidySettings(
      spotifyEnabled: _spotifyEnabled,
      spotifyClientId: _clientId.text.trim(),
      spotifyClientSecret: _clientSecret.text.trim(),
      spotifyUsername: _username.text.trim(),
      spotifyPassword: _password.text,
      localMediaDir: _mediaDir.text.trim(),
    );
    final error = await widget.configService.save(settings);
    _notify(error ?? 'Impostazioni salvate, Mopidy riavviato');
  }

  Future<void> _refreshLibrary() async {
    _notify('Aggiornamento libreria in corso...');
    final error = await widget.configService.refreshLocalLibrary();
    _notify(error ?? 'Libreria aggiornata');
  }

  @override
  void dispose() {
    _clientId.dispose();
    _clientSecret.dispose();
    _username.dispose();
    _password.dispose();
    _mediaDir.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Musica (Mopidy)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Spotify', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'Serve un account Spotify Premium e un\'app registrata su '
            'developer.spotify.com. L\'estensione Mopidy-Spotify attuale '
            'richiede Mopidy 4, incompatibile con Mopidy 3 (usato qui per '
            'radio/musica locale): salvare le credenziali le tiene pronte, '
            'ma la riproduzione Spotify non è ancora attiva su questo host.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          SwitchListTile(
            title: const Text('Abilita Spotify'),
            value: _spotifyEnabled,
            onChanged: (v) => setState(() => _spotifyEnabled = v),
          ),
          TextField(
            controller: _clientId,
            decoration: const InputDecoration(labelText: 'Client ID'),
          ),
          TextField(
            controller: _clientSecret,
            decoration: const InputDecoration(labelText: 'Client secret'),
            obscureText: true,
          ),
          TextField(
            controller: _username,
            decoration: const InputDecoration(labelText: 'Nome utente Spotify'),
          ),
          TextField(
            controller: _password,
            decoration: const InputDecoration(labelText: 'Password'),
            obscureText: true,
          ),
          const SizedBox(height: 24),
          const Text('Musica locale', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _mediaDir,
            decoration: const InputDecoration(labelText: 'Cartella musica'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _refreshLibrary,
            icon: const Icon(Icons.refresh),
            label: const Text('Aggiorna libreria'),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Salva e riavvia Mopidy')),
          const SizedBox(height: 24),
          const Text('Volume', style: TextStyle(fontWeight: FontWeight.bold)),
          Row(
            children: [
              const Icon(Icons.volume_down),
              Expanded(
                child: Slider(
                  value: _volume ?? 0,
                  min: 0,
                  max: 100,
                  onChanged: (v) => setState(() => _volume = v),
                  onChangeEnd: (v) => widget.radioService.setVolume(v.round()),
                ),
              ),
              const Icon(Icons.volume_up),
            ],
          ),
        ],
      ),
    );
  }
}
