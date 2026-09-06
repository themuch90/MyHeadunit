import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'services/phone_service.dart';
import 'services/bluetooth_service.dart';
import 'services/androidauto_service.dart';
import 'widgets/androidauto_texture_view.dart';
import 'widgets/call_banner.dart';
import 'screens/dialpad_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/call_screen.dart';
import 'screens/bluetooth_pairing_screen.dart';

void main() {
  // Il supporto GStreamer e' integrato in flutter-pi stesso (compilato con
  // BUILD_GSTREAMER_VIDEO_PLAYER_PLUGIN=ON, vedi setup-host.sh): non
  // serve alcuna registrazione esplicita lato Dart, si usa direttamente il
  // pacchetto ufficiale video_player.
  runApp(const HeadUnitApp());
}

class HeadUnitApp extends StatelessWidget {
  const HeadUnitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const RootScreen(),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  // Un solo WebSocket condiviso da dashboard e servizio telefono.
  final WebSocketChannel _channel =
      WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:8080/ws'));
  // Lo stream di WebSocketChannel supporta un solo listener: lo rendiamo
  // broadcast per poterlo condividere tra dashboard, telefono, bluetooth
  // e Android Auto, che altrimenti si scontrerebbero con
  // "Bad state: Stream has already been listened to.".
  late final Stream<dynamic> _messages = _channel.stream.asBroadcastStream();
  late final PhoneService _phoneService;
  late final BluetoothService _btService;
  late final AndroidAutoService _aaService;

  int _tabIndex = 0;
  final Map<String, String> _canSignals = {};
  CallInfo _call = CallInfo.idle;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _phoneService = PhoneService(_channel.sink, _messages);
    _btService = BluetoothService(_channel.sink, _messages);
    _aaService = AndroidAutoService(_channel.sink, _messages);

    // Stato di chiamata globale: alimenta il banner in cima mostrato sopra
    // qualunque scheda (dashboard, rubrica, bluetooth...), non solo sulla
    // scheda Tastiera che ha gia' la sua vista di chiamata in linea.
    _phoneService.callState.listen((call) => setState(() => _call = call));
    _phoneService.muted.listen((m) => setState(() => _muted = m));

    // Instrada anche i messaggi CAN (car/can/*) verso la dashboard.
    _messages.listen((event) {
      final data = jsonDecode(event as String) as Map<String, dynamic>;
      final topic = data['topic'] as String;
      if (topic.startsWith('car/can/')) {
        final payload = jsonDecode(data['payload'] as String) as Map<String, dynamic>;
        setState(() => _canSignals[topic.split('/').last] = payload['value'].toString());
      }
    });

    // Ascolto globale: una chiamata in arrivo apre l'overlay sopra qualunque
    // schermata l'utente stia guardando (dashboard, media, mappa...).
    _phoneService.incomingCall.listen((call) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => IncomingCallScreen(
            name: call['name'] ?? '',
            number: call['number'] ?? '',
            phoneService: _phoneService,
          ),
          fullscreenDialog: true,
        ),
      );
    });
  }

  @override
  void dispose() {
    _phoneService.dispose();
    _btService.dispose();
    _aaService.dispose();
    _channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardTab(signals: _canSignals, aaService: _aaService),
      DialpadScreen(phoneService: _phoneService),
      ContactsScreen(phoneService: _phoneService),
      BluetoothPairingScreen(btService: _btService),
    ];

    // Il banner in cima e' mostrato per chiamate in composizione/attive
    // (dialing/active) su qualunque scheda; la chiamata in arrivo (ringing)
    // resta gestita dall'overlay fullscreen dedicato (accetta/rifiuta), che
    // copre gia' tutto lo schermo.
    final showCallBanner =
        _call.state == CallState.dialing || _call.state == CallState.active;

    return Scaffold(
      body: Column(
        children: [
          if (showCallBanner)
            CallBanner(call: _call, muted: _muted, phoneService: _phoneService),
          // IndexedStack invece di screens[_tabIndex]: tiene tutte le schede
          // montate contemporaneamente (solo quella selezionata e' visibile),
          // cosi' il loro stato locale (es. lista dispositivi Bluetooth
          // trovati/accoppiati) sopravvive al cambio scheda invece di essere
          // ricreato da zero ogni volta.
          Expanded(
            child: SafeArea(
              top: !showCallBanner,
              child: IndexedStack(index: _tabIndex, children: screens),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.speed), label: 'Cruscotto'),
          NavigationDestination(icon: Icon(Icons.dialpad), label: 'Tastiera'),
          NavigationDestination(icon: Icon(Icons.contacts), label: 'Rubrica'),
          NavigationDestination(icon: Icon(Icons.bluetooth), label: 'Bluetooth'),
        ],
      ),
    );
  }
}

class DashboardTab extends StatefulWidget {
  final Map<String, String> signals;
  final AndroidAutoService aaService;
  const DashboardTab({super.key, required this.signals, required this.aaService});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  AndroidAutoState _aaState = AndroidAutoState.stopped;

  @override
  void initState() {
    super.initState();
    widget.aaService.state.listen((s) => setState(() => _aaState = s));
  }

  @override
  Widget build(BuildContext context) {
    if (_aaState == AndroidAutoState.active) {
      return Column(
        children: [
          Expanded(child: AndroidAutoTextureView()),
          _AndroidAutoTile(state: _aaState, aaService: widget.aaService),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 1.6,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              children: [
                _SignalCard(label: 'RPM', value: widget.signals['rpm']),
                _SignalCard(label: 'Velocità', value: widget.signals['speed']),
                _SignalCard(label: 'Temp. motore', value: widget.signals['coolant_temp']),
                _SignalCard(label: 'Carburante', value: widget.signals['fuel_level']),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _AndroidAutoTile(state: _aaState, aaService: widget.aaService),
        ],
      ),
    );
  }
}

class _AndroidAutoTile extends StatelessWidget {
  final AndroidAutoState state;
  final AndroidAutoService aaService;

  const _AndroidAutoTile({required this.state, required this.aaService});

  @override
  Widget build(BuildContext context) {
    final isActive = state == AndroidAutoState.active;
    final isStarting = state == AndroidAutoState.starting;

    String label;
    switch (state) {
      case AndroidAutoState.active:
        label = 'Sessione attiva';
        break;
      case AndroidAutoState.starting:
        label = 'Avvio in corso...';
        break;
      case AndroidAutoState.error:
        label = 'Errore, riprova';
        break;
      case AndroidAutoState.stopped:
        label = 'Non connesso';
    }

    return Card(
      color: Colors.grey[900],
      child: ListTile(
        leading: Icon(Icons.android, color: isActive ? Colors.green : Colors.grey),
        title: const Text('Android Auto'),
        subtitle: Text(label, style: const TextStyle(color: Colors.grey)),
        trailing: isStarting
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : ElevatedButton(
                onPressed: isActive ? aaService.stop : aaService.start,
                child: Text(isActive ? 'Interrompi' : 'Avvia'),
              ),
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  final String label;
  final String? value;

  const _SignalCard({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey[900],
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 8),
            Text(
              value ?? '--',
              style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
