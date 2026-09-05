import 'dart:async';
import 'dart:convert';

enum AndroidAutoState { stopped, starting, active, error }

/// Nota: questo servizio NON riceve il video di Android Auto. Avvia/ferma il
/// processo 'autoapp' (container androidauto-bridge), che apre una propria
/// finestra Wayland. Il compositor (Weston, sull'host) la porta in primo
/// piano quando la sessione diventa attiva: e' un cambio di finestra tra
/// client separati, non un embedding dentro l'albero widget di Flutter.
class AndroidAutoService {
  final StreamSink<dynamic> _sink;
  final _stateController = StreamController<AndroidAutoState>.broadcast();

  Stream<AndroidAutoState> get state => _stateController.stream;

  AndroidAutoService(this._sink, Stream<dynamic> messages) {
    messages.listen(_onMessage);
  }

  void _onMessage(dynamic event) {
    final data = jsonDecode(event as String) as Map<String, dynamic>;
    if (data['topic'] != 'car/androidauto/state') return;
    final payload = (data['payload'] as String).replaceAll('"', '');
    final state = switch (payload) {
      'starting' => AndroidAutoState.starting,
      'active' => AndroidAutoState.active,
      'error' => AndroidAutoState.error,
      _ => AndroidAutoState.stopped,
    };
    _stateController.add(state);
  }

  void _send(String topic) {
    _sink.add(jsonEncode({'topic': topic, 'payload': '{}'}));
  }

  void start() => _send('car/androidauto/cmd/start');
  void stop() => _send('car/androidauto/cmd/stop');

  void dispose() => _stateController.close();
}
