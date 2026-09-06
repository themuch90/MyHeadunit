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
                      // Risponde e chiude l'overlay: la chiamata attiva viene
                      // mostrata dal banner globale in cima e dalla schermata
                      // Tastiera (vedi main.dart / dialpad_screen.dart), non
                      // da una route dedicata.
                      phoneService.answer();
                      Navigator.of(context).pop();
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

/// Bottone rotondo con etichetta usato nei controlli di chiamata attiva
/// (muto, tastiera DTMF...). Riusato sia dalla schermata Tastiera che dal
/// banner globale di chiamata.
class CallActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const CallActionButton({
    super.key,
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

/// Tastierino DTMF compatto mostrato durante una chiamata attiva.
class MiniDtmfPad extends StatelessWidget {
  final PhoneService phoneService;
  const MiniDtmfPad({super.key, required this.phoneService});

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
