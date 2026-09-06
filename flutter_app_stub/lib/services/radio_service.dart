import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

enum RadioPlaybackState { stopped, playing, paused }

/// Un riferimento nella libreria musicale di Mopidy (cartella, brano,
/// artista...), come ritornato da `core.library.browse`.
enum LibraryRefType { directory, track, other }

class LibraryRef {
  final String uri;
  final String name;
  final LibraryRefType type;

  LibraryRef({required this.uri, required this.name, required this.type});

  factory LibraryRef.fromJson(Map<String, dynamic> json) => LibraryRef(
        uri: json['uri'] as String,
        name: json['name'] as String? ?? json['uri'] as String,
        type: switch (json['type']) {
          'directory' => LibraryRefType.directory,
          'track' => LibraryRefType.track,
          _ => LibraryRefType.other,
        },
      );
}

/// Client WebSocket/JSON-RPC verso Mopidy (`ws://host:6680/mopidy/ws`), che
/// gira sull'host (non in Docker, vedi setup-host.sh). Si collega
/// direttamente a Mopidy invece che tramite il WebSocket condiviso/MQTT
/// dell'api-gateway: Mopidy espone gia' un'API di rete pronta all'uso.
class RadioService {
  final WebSocketChannel _channel;
  int _nextId = 1;
  final _pending = <int, Completer<dynamic>>{};
  final _stateController = StreamController<RadioPlaybackState>.broadcast();
  final _streamTitleController = StreamController<String?>.broadcast();
  final _trackNameController = StreamController<String?>.broadcast();

  Stream<RadioPlaybackState> get state => _stateController.stream;
  /// Titolo del brano in onda (metadati ICY), quando lo stream li fornisce.
  Stream<String?> get streamTitle => _streamTitleController.stream;
  /// Nome della traccia/stazione secondo Mopidy (spesso il nome della
  /// stazione stessa per gli stream radio, es. "Groove Salad: ... [SomaFM]").
  Stream<String?> get trackName => _trackNameController.stream;

  RadioService({String host = '127.0.0.1', int port = 6680})
      : _channel =
            WebSocketChannel.connect(Uri.parse('ws://$host:$port/mopidy/ws')) {
    _channel.stream.listen(_onMessage, onError: (_) {}, cancelOnError: false);
    // Mopidy invia eventi solo sui cambi di stato, non lo stato corrente al
    // momento della connessione: senza questo una riproduzione gia' in corso
    // risulterebbe "ferma" nell'app finche' non cambia qualcosa.
    _syncInitialState();
  }

  Future<void> _syncInitialState() async {
    try {
      final state = await _call('core.playback.get_state');
      _stateController.add(_parseState(state as String?));
      final track = await _call('core.playback.get_current_track');
      if (track != null) {
        _trackNameController.add((track as Map<String, dynamic>)['name'] as String?);
      }
    } catch (_) {
      // Connessione non ancora pronta o Mopidy non raggiungibile: si
      // aggiornera' comunque al primo evento reale una volta connesso.
    }
  }

  static RadioPlaybackState _parseState(String? state) => switch (state) {
        'playing' => RadioPlaybackState.playing,
        'paused' => RadioPlaybackState.paused,
        _ => RadioPlaybackState.stopped,
      };

  void _onMessage(dynamic raw) {
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    if (msg.containsKey('id')) {
      final completer = _pending.remove(msg['id']);
      if (completer == null) return;
      if (msg.containsKey('error')) {
        completer.completeError(msg['error']);
      } else {
        completer.complete(msg['result']);
      }
      return;
    }

    switch (msg['event']) {
      case 'playback_state_changed':
        _stateController.add(_parseState(msg['new_state'] as String?));
        break;
      case 'stream_title_changed':
        _streamTitleController.add(msg['title'] as String?);
        break;
      case 'track_playback_started':
        final track = msg['tl_track']?['track'] as Map<String, dynamic>?;
        _trackNameController.add(track?['name'] as String?);
        _streamTitleController.add(null);
        break;
      case 'track_playback_ended':
        _trackNameController.add(null);
        _streamTitleController.add(null);
        break;
    }
  }

  Future<dynamic> _call(String method, [Map<String, dynamic>? params]) {
    final id = _nextId++;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    _channel.sink.add(jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    }));
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('Nessuna risposta da Mopidy per $method');
      },
    );
  }

  /// Sostituisce la tracklist con un solo stream e avvia la riproduzione.
  Future<void> playUri(String uri) async {
    await _call('core.tracklist.clear');
    await _call('core.tracklist.add', {'uris': [uri]});
    await _call('core.playback.play');
  }

  Future<void> pause() => _call('core.playback.pause');
  Future<void> resume() => _call('core.playback.resume');
  Future<void> stop() => _call('core.playback.stop');

  /// Elenca il contenuto di una cartella della libreria (Spotify, musica
  /// locale...). uri null = radice (una voce per ogni backend disponibile).
  Future<List<LibraryRef>> browse(String? uri) async {
    final result = await _call('core.library.browse', {'uri': uri});
    return (result as List)
        .cast<Map<String, dynamic>>()
        .map(LibraryRef.fromJson)
        .toList();
  }

  Future<int?> getVolume() async => (await _call('core.mixer.get_volume')) as int?;
  Future<void> setVolume(int volume) => _call('core.mixer.set_volume', {'volume': volume});

  void dispose() {
    _stateController.close();
    _streamTitleController.close();
    _trackNameController.close();
    _channel.sink.close();
  }
}
