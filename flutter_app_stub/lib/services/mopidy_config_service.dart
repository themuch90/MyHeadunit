import 'dart:io';

class MopidySettings {
  final bool spotifyEnabled;
  final String spotifyClientId;
  final String spotifyClientSecret;
  final String spotifyUsername;
  final String spotifyPassword;
  final String localMediaDir;

  const MopidySettings({
    this.spotifyEnabled = false,
    this.spotifyClientId = '',
    this.spotifyClientSecret = '',
    this.spotifyUsername = '',
    this.spotifyPassword = '',
    this.localMediaDir = '/var/lib/mopidy/media',
  });

  MopidySettings copyWith({
    bool? spotifyEnabled,
    String? spotifyClientId,
    String? spotifyClientSecret,
    String? spotifyUsername,
    String? spotifyPassword,
    String? localMediaDir,
  }) =>
      MopidySettings(
        spotifyEnabled: spotifyEnabled ?? this.spotifyEnabled,
        spotifyClientId: spotifyClientId ?? this.spotifyClientId,
        spotifyClientSecret: spotifyClientSecret ?? this.spotifyClientSecret,
        spotifyUsername: spotifyUsername ?? this.spotifyUsername,
        spotifyPassword: spotifyPassword ?? this.spotifyPassword,
        localMediaDir: localMediaDir ?? this.localMediaDir,
      );
}

/// Legge/scrive /etc/mopidy/mopidy-user.conf (credenziali Spotify, cartella
/// musica locale) e applica le modifiche a Mopidy. L'app gira come utente
/// normale, non root: setup-host.sh prepara in anticipo i permessi sul file
/// (gruppo dedicato "mopidy-config") e i comandi sudo NOPASSWD scoped per
/// riavviare il servizio e rilanciare la scansione della libreria locale.
class MopidyConfigService {
  static const _configPath = '/etc/mopidy/mopidy-user.conf';
  static const _scanCommand =
      '/usr/bin/mopidy --config /usr/share/mopidy/conf.d:/etc/mopidy/mopidy.conf:/etc/mopidy/mopidy-user.conf local scan';

  Future<MopidySettings> load() async {
    final file = File(_configPath);
    if (!await file.exists()) return const MopidySettings();

    final values = <String, String>{};
    String section = '';
    for (final rawLine in await file.readAsLines()) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1);
        continue;
      }
      final i = line.indexOf('=');
      if (i < 0) continue;
      values['$section.${line.substring(0, i).trim()}'] = line.substring(i + 1).trim();
    }

    return MopidySettings(
      spotifyEnabled: values['spotify.enabled'] == 'true',
      spotifyClientId: values['spotify.client_id'] ?? '',
      spotifyClientSecret: values['spotify.client_secret'] ?? '',
      spotifyUsername: values['spotify.username'] ?? '',
      spotifyPassword: values['spotify.password'] ?? '',
      localMediaDir: values['local.media_dir'] ?? '/var/lib/mopidy/media',
    );
  }

  /// Scrive la configurazione e riavvia Mopidy per applicarla. Ritorna un
  /// messaggio di errore, o null se tutto e' andato a buon fine.
  Future<String?> save(MopidySettings s) async {
    final content = '''
[local]
media_dir = ${s.localMediaDir}

[spotify]
enabled = ${s.spotifyEnabled}
client_id = ${s.spotifyClientId}
client_secret = ${s.spotifyClientSecret}
username = ${s.spotifyUsername}
password = ${s.spotifyPassword}
''';
    try {
      await File(_configPath).writeAsString(content);
    } catch (e) {
      return 'Scrittura di $_configPath fallita: $e';
    }
    final result = await Process.run('sudo', ['systemctl', 'restart', 'mopidy.service']);
    if (result.exitCode != 0) {
      return 'Riavvio di Mopidy fallito: ${result.stderr}';
    }
    return null;
  }

  /// Rilancia la scansione della libreria locale. Ferma Mopidy prima di
  /// scansionare (mopidy-local usa un DB SQLite che il servizio in
  /// esecuzione tiene aperto) e lo riavvia subito dopo.
  Future<String?> refreshLocalLibrary() async {
    await Process.run('sudo', ['systemctl', 'stop', 'mopidy.service']);
    final scan = await Process.run(
      'sudo', ['-u', 'mopidy', ..._scanCommand.split(' ')],
    );
    await Process.run('sudo', ['systemctl', 'start', 'mopidy.service']);
    if (scan.exitCode != 0) {
      return 'Scansione libreria fallita: ${scan.stderr}';
    }
    return null;
  }
}
