import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Stato di una chiamata in corso.
enum CallState { idle, ringing, dialing, active }

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
/// dedicato ai topic "car/phone/*". In un'app reale questo canale WS
/// andrebbe condiviso con un unico client globale invece di aprirne uno per
/// schermata.
class PhoneService {
  final WebSocketChannel _channel;
  final _callStateController = StreamController<CallState>.broadcast();
  final _incomingCallController =
      StreamController<Map<String, String>>.broadcast();
  final _contactsController = StreamController<List<Contact>>.broadcast();

  Stream<CallState> get callState => _callStateController.stream;
  Stream<Map<String, String>> get incomingCall =>
      _incomingCallController.stream;
  Stream<List<Contact>> get contacts => _contactsController.stream;

  PhoneService(this._channel) {
    _channel.stream.listen(_onMessage);
  }

  void _onMessage(dynamic event) {
    final data = jsonDecode(event as String) as Map<String, dynamic>;
    final topic = data['topic'] as String;
    final payload = data['payload'] as String;

    if (topic == 'car/phone/call/state') {
      final state = switch (payload.replaceAll('"', '')) {
        'ringing' => CallState.ringing,
        'dialing' => CallState.dialing,
        'active' => CallState.active,
        _ => CallState.idle,
      };
      _callStateController.add(state);
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
    _channel.sink.add(jsonEncode({
      'topic': topic,
      'payload': jsonEncode(payload),
    }));
  }

  void dial(String number) => _send('car/phone/cmd/dial', {'number': number});
  void answer() => _send('car/phone/cmd/answer', {});
  void hangup() => _send('car/phone/cmd/hangup', {});
  void sendDtmf(String digit) => _send('car/phone/cmd/dtmf', {'digit': digit});
  void syncContacts() => _send('car/phone/cmd/sync_contacts', {});

  void dispose() {
    _callStateController.close();
    _incomingCallController.close();
    _contactsController.close();
  }
}
