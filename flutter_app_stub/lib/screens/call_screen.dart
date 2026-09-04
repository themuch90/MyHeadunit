import 'package:flutter/material.dart';
import '../services/phone_service.dart';

/// Overlay fullscreen mostrato sopra qualunque schermata quando arriva
/// una chiamata. Va inserito con un Navigator.push (route) o uno Stack
/// globale ascoltato da un widget in cima all'albero (vedi main.dart).
class IncomingCallScreen extends StatelessWidget {
  final String name;
  final String number;
  final PhoneService phoneService;

  const IncomingCallScreen({
    super.key,
    required this.name,
    required this.number,
    required this.phoneService,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SizedBox(height: 48),
            Column(
              children: [
                const CircleAvatar(radius: 48, child: Icon(Icons.person, size: 48)),
                const SizedBox(height: 16),
                Text(
                  name.isNotEmpty ? name : 'Numero sconosciuto',
                  style: const TextStyle(fontSize: 24, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(number, style: const TextStyle(fontSize: 16, color: Colors.grey)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  FloatingActionButton(
                    heroTag: 'reject',
                    backgroundColor: Colors.red,
                    onPressed: () {
                      phoneService.hangup();
                      Navigator.of(context).pop();
                    },
                    child: const Icon(Icons.call_end),
                  ),
                  FloatingActionButton(
                    heroTag: 'accept',
                    backgroundColor: Colors.green,
                    onPressed: () {
                      phoneService.answer();
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => ActiveCallScreen(
                            name: name,
                            number: number,
                            phoneService: phoneService,
                          ),
                        ),
                      );
                    },
                    child: const Icon(Icons.call),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Schermata durante una chiamata attiva: muto, tastiera DTMF, chiudi.
class ActiveCallScreen extends StatefulWidget {
  final String name;
  final String number;
  final PhoneService phoneService;

  const ActiveCallScreen({
    super.key,
    required this.name,
    required this.number,
    required this.phoneService,
  });

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  bool _muted = false;
  bool _showKeypad = false;

  @override
  void initState() {
    super.initState();
    widget.phoneService.callState.listen((state) {
      if (state == CallState.idle && mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            Text(
              widget.name.isNotEmpty ? widget.name : widget.number,
              style: const TextStyle(fontSize: 24, color: Colors.white),
            ),
            const SizedBox(height: 4),
            const Text('In corso', style: TextStyle(color: Colors.greenAccent)),
            if (_showKeypad) Expanded(child: _MiniDtmfPad(phoneService: widget.phoneService))
            else const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallActionButton(
                    icon: _muted ? Icons.mic_off : Icons.mic,
                    label: 'Muto',
                    active: _muted,
                    onTap: () => setState(() => _muted = !_muted),
                    // Nota: il muto reale va implementato lato audio (PulseAudio/
                    // PipeWire sink del canale SCO), non c'e' un comando oFono
                    // dedicato: qui e' solo lo stato visuale del pulsante.
                  ),
                  FloatingActionButton(
                    backgroundColor: Colors.red,
                    onPressed: widget.phoneService.hangup,
                    child: const Icon(Icons.call_end),
                  ),
                  _CallActionButton(
                    icon: Icons.dialpad,
                    label: 'Tastiera',
                    active: _showKeypad,
                    onTap: () => setState(() => _showKeypad = !_showKeypad),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconButton(
          iconSize: 32,
          color: active ? Colors.blueAccent : Colors.white,
          icon: Icon(icon),
          onPressed: onTap,
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

class _MiniDtmfPad extends StatelessWidget {
  final PhoneService phoneService;
  const _MiniDtmfPad({required this.phoneService});

  @override
  Widget build(BuildContext context) {
    const digits = ['1','2','3','4','5','6','7','8','9','*','0','#'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: GridView.count(
        crossAxisCount: 3,
        childAspectRatio: 1.6,
        children: digits.map((d) => TextButton(
          onPressed: () => phoneService.sendDtmf(d),
          child: Text(d, style: const TextStyle(fontSize: 22, color: Colors.white)),
        )).toList(),
      ),
    );
  }
}
