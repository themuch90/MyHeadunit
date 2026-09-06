import 'dart:async';
import 'dart:convert';

enum PairingState { idle, pairing, paired, failed }

class BtDevice {
  final String mac;
  final String name;
  final int? rssi;
  final bool paired;
  final bool connected;

  BtDevice({
    required this.mac,
    required this.name,
    this.rssi,
    required this.paired,
    required this.connected,
  });

  factory BtDevice.fromJson(Map<String, dynamic> json) => BtDevice(
        mac: json['mac'] as String,
        name: (json['name'] as String?) ?? 'Dispositivo sconosciuto',
        rssi: json['rssi'] as int?,
        paired: (json['paired'] as bool?) ?? false,
        connected: (json['connected'] as bool?) ?? false,
      );
}

class BluetoothService {
  final StreamSink<dynamic> _sink;

  final _devicesController = StreamController<List<BtDevice>>.broadcast();
  final _pairingRequestController =
      StreamController<Map<String, String>>.broadcast();
  final _pairingStateController = StreamController<PairingState>.broadcast();
  final _discoverableController = StreamController<bool>.broadcast();

  Stream<List<BtDevice>> get devices => _devicesController.stream;
  // Emette {device, passkey} quando serve una conferma dall'utente.
  Stream<Map<String, String>> get pairingRequest =>
      _pairingRequestController.stream;
  Stream<PairingState> get pairingState => _pairingStateController.stream;
  // true quando la head unit e' visibile/associabile dal telefono (dopo
  // makeDiscoverable()).
  Stream<bool> get discoverable => _discoverableController.stream;

  BluetoothService(this._sink, Stream<dynamic> messages) {
    messages.listen(_onMessage);
  }

  void _onMessage(dynamic event) {
    final data = jsonDecode(event as String) as Map<String, dynamic>;
    final topic = data['topic'] as String;
    final payload = data['payload'] as String;

    if (topic == 'car/bluetooth/devices') {
      final list = jsonDecode(payload) as List;
      _devicesController.add(
        list.map((e) => BtDevice.fromJson(e as Map<String, dynamic>)).toList(),
      );
    } else if (topic == 'car/bluetooth/pairing/request') {
      final map = jsonDecode(payload) as Map<String, dynamic>;
      _pairingRequestController.add({
        'device': map['device']?.toString() ?? '',
        'passkey': map['passkey']?.toString() ?? '',
      });
    } else if (topic == 'car/bluetooth/pairing/state') {
      final state = switch (payload.replaceAll('"', '')) {
        'pairing' => PairingState.pairing,
        'paired' => PairingState.paired,
        'failed' => PairingState.failed,
        _ => PairingState.idle,
      };
      _pairingStateController.add(state);
    } else if (topic == 'car/bluetooth/discoverable') {
      _discoverableController.add(payload == 'true');
    }
  }

  void _send(String topic, Map<String, dynamic> payload) {
    _sink.add(jsonEncode({
      'topic': topic,
      'payload': jsonEncode(payload),
    }));
  }

  void startScan() => _send('car/bluetooth/cmd/scan_start', {});
  void stopScan() => _send('car/bluetooth/cmd/scan_stop', {});
  void pair(String mac) => _send('car/bluetooth/cmd/pair', {'mac': mac});
  void remove(String mac) => _send('car/bluetooth/cmd/remove', {'mac': mac});
  void confirmPairing(bool accept) =>
      _send('car/bluetooth/cmd/confirm', {'accept': accept});
  // Rende la head unit visibile/associabile: usalo per far si' che sia il
  // telefono a trovare la head unit (come un normale speaker BT), invece
  // di doverla sempre cercare da qui con startScan().
  void makeDiscoverable() => _send('car/bluetooth/cmd/make_discoverable', {});

  void dispose() {
    _devicesController.close();
    _pairingRequestController.close();
    _pairingStateController.close();
    _discoverableController.close();
  }
}
