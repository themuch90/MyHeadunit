import 'dart:async';
import 'dart:convert';

/// Stato di una chiamata in corso.
enum CallState { idle, ringing, dialing, active }

/// Stato completo della chiamata corrente: comune a tutte le UI (tastiera,
/// banner globale) cosi' che non debbano tenere traccia separatamente di
/// numero/nome del chiamante.
class CallInfo {
  final CallState state;
  final String number;
  final String name;
  const CallInfo({required this.state, this.number = '', this.name = ''});

  static const idle = CallInfo(state: CallState.idle);
}

class Contact {
  final String name;
  final List<String> numbers;
  Contact({required this.name, required this.numbers});

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
        name: (json['name'] as String?) ?? 'Sconosciuto',
        numbers: (json['numbers'] as List?)?.cast<String>() ?? const [],
      );
}

/// Wrapper sopra il WebSocket condiviso con il resto dell'app (dashboard, ecc.)
/// dedicato ai topic "car/phone/*". Riceve il sink per inviare comandi e lo
/// stream broadcast condiviso (vedi main.dart) per ascoltare i messaggi,
/// dato che lo stream grezzo di WebSocketChannel supporta un solo listener.
class PhoneService {
  final StreamSink<dynamic> _sink;
  final _callStateController = StreamController<CallInfo>.broadcast();
  final _incomingCallController =
      StreamController<Map<String, String>>.broadcast();
  final _contactsController = StreamController<List<Contact>>.broadcast();
  final _mutedController = StreamController<bool>.broadcast();

  Stream<CallInfo> get callState => _callStateController.stream;
  Stream<Map<String, String>> get incomingCall =>
      _incomingCallController.stream;
  Stream<List<Contact>> get contacts => _contactsController.stream;
  Stream<bool> get muted => _mutedController.stream;

  PhoneService(this._sink, Stream<dynamic> messages) {
    messages.listen(_onMessage);
  }

  void _onMessage(dynamic event) {
    final data = jsonDecode(event as String) as Map<String, dynamic>;
    final topic = data['topic'] as String;
    final payload = data['payload'] as String;

    if (topic == 'car/phone/call/state') {
      final map = jsonDecode(payload) as Map<String, dynamic>;
      final state = switch (map['state']) {
        'ringing' => CallState.ringing,
        'dialing' => CallState.dialing,
        'active' => CallState.active,
        _ => CallState.idle,
      };
      _callStateController.add(CallInfo(
        state: state,
        number: map['number']?.toString() ?? '',
        name: map['name']?.toString() ?? '',
      ));
    } else if (topic == 'car/phone/call/muted') {
      _mutedController.add(payload == 'true');
    } else if (topic == 'car/phone/call/incoming') {
      final map = jsonDecode(payload) as Map<String, dynamic>;
      _incomingCallController.add({
        'number': map['number']?.toString() ?? '',
        'name': map['name']?.toString() ?? '',
      });
    } else if (topic == 'car/phone/contacts') {
      final list = jsonDecode(payload) as List;
      _contactsController.add(
        list.map((e) => Contact.fromJson(e as Map<String, dynamic>)).toList(),
      );
    }
  }

  void _send(String topic, Map<String, dynamic> payload) {
    _sink.add(jsonEncode({
      'topic': topic,
      'payload': jsonEncode(payload),
    }));
  }

  void dial(String number) => _send('car/phone/cmd/dial', {'number': number});
  void answer() => _send('car/phone/cmd/answer', {});
  void hangup() => _send('car/phone/cmd/hangup', {});
  void sendDtmf(String digit) => _send('car/phone/cmd/dtmf', {'digit': digit});
  void setMute(bool muted) => _send('car/phone/cmd/mute', {'muted': muted});
  void syncContacts() => _send('car/phone/cmd/sync_contacts', {});

  void dispose() {
    _callStateController.close();
    _incomingCallController.close();
    _contactsController.close();
    _mutedController.close();
  }
}
