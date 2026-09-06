import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import '../services/mopidy_config_service.dart';
import '../services/radio_service.dart';
import 'bluetooth_pairing_screen.dart';
import 'music_settings_screen.dart';

/// Sezione Impostazioni: punto unico per le configurazioni della head unit.
/// Una nuova voce si aggiunge qui come ulteriore ListTile, senza toccare la
/// barra di navigazione principale.
class SettingsScreen extends StatelessWidget {
  final BluetoothService btService;
  final RadioService radioService;
  final MopidyConfigService mopidyConfigService;

  const SettingsScreen({
    super.key,
    required this.btService,
    required this.radioService,
    required this.mopidyConfigService,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const _SectionHeader('Connettività'),
        ListTile(
          leading: const Icon(Icons.bluetooth, color: Colors.white),
          title: const Text('Bluetooth', style: TextStyle(color: Colors.white)),
          subtitle: const Text(
            'Associa un telefono, gestisci i dispositivi accoppiati',
            style: TextStyle(color: Colors.grey),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              // BluetoothPairingScreen non ha un proprio Scaffold/AppBar
              // (era pensata per stare dentro l'IndexedStack di una scheda):
              // gliene serve uno qui per avere un modo di tornare indietro,
              // dato che questa e' una kiosk touch senza tasto back fisico.
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Bluetooth')),
                body: BluetoothPairingScreen(btService: btService),
              ),
            ),
          ),
        ),
        const _SectionHeader('Musica'),
        ListTile(
          leading: const Icon(Icons.music_note, color: Colors.white),
          title: const Text('Musica (Mopidy)', style: TextStyle(color: Colors.white)),
          subtitle: const Text(
            'Account Spotify, cartella musica locale, volume',
            style: TextStyle(color: Colors.grey),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MusicSettingsScreen(
                configService: mopidyConfigService,
                radioService: radioService,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
