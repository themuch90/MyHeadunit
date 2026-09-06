import 'package:flutter/material.dart';
import '../services/phone_service.dart';

/// Barra compatta mostrata in cima all'app (sopra qualunque scheda) quando
/// c'e' una chiamata in corso (in composizione o attiva), cosi' l'utente puo'
/// mettere in muto o chiudere la chiamata senza dover tornare sulla scheda
/// Tastiera. La chiamata in arrivo (stato "ringing") resta invece gestita
/// dall'overlay fullscreen dedicato (IncomingCallScreen), che chiede
/// esplicitamente accetta/rifiuta.
class CallBanner extends StatelessWidget {
  final CallInfo call;
  final bool muted;
  final PhoneService phoneService;

  const CallBanner({
    super.key,
    required this.call,
    required this.muted,
    required this.phoneService,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = call.state == CallState.active;
    final label = isActive ? 'In corso' : 'Chiamata in corso...';
    // L'identificativo del chiamante via HFP spesso porta solo il numero:
    // si cerca il nome nella rubrica gia' sincronizzata prima di mostrare
    // il numero grezzo (vedi PhoneService.contactNameFor).
    final contactName = call.name.isNotEmpty
        ? call.name
        : phoneService.contactNameFor(call.number);
    final title = contactName ??
        (call.number.isNotEmpty ? call.number : 'Numero sconosciuto');

    return Material(
      color: isActive ? Colors.green[800] : Colors.orange[800],
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.call, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(label,
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(muted ? Icons.mic_off : Icons.mic, color: Colors.white),
                tooltip: 'Muto',
                onPressed: () => phoneService.setMute(!muted),
              ),
              IconButton(
                icon: const Icon(Icons.call_end, color: Colors.white),
                tooltip: 'Chiudi chiamata',
                onPressed: phoneService.hangup,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
