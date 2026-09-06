import 'dart:async';
import 'package:flutter/material.dart';
import '../services/phone_service.dart';
import 'call_screen.dart';

class DialpadScreen extends StatefulWidget {
  final PhoneService phoneService;
  const DialpadScreen({super.key, required this.phoneService});

  @override
  State<DialpadScreen> createState() => _DialpadScreenState();
}

class _DialpadScreenState extends State<DialpadScreen> {
  String _number = '';
  CallInfo _call = CallInfo.idle;
  bool _muted = false;
  bool _showKeypad = false;
  StreamSubscription<CallInfo>? _callSub;
  StreamSubscription<bool>? _mutedSub;

  static const _keys = [
    ['1', ''], ['2', 'ABC'], ['3', 'DEF'],
    ['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO'],
    ['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ'],
    ['*', ''], ['0', '+'], ['#', ''],
  ];

  @override
  void initState() {
    super.initState();
    // La schermata riflette lo stato reale della chiamata (oFono), non solo
    // quella avviata da qui: risponde anche a chiamate accettate dall'overlay
    // di chiamata in arrivo o composte dalla Rubrica.
    _callSub = widget.phoneService.callState.listen((call) {
      setState(() {
        _call = call;
        if (call.state == CallState.idle) {
          _showKeypad = false;
          _muted = false;
        }
      });
    });
    _mutedSub = widget.phoneService.muted.listen((m) => setState(() => _muted = m));
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _mutedSub?.cancel();
    super.dispose();
  }

  void _onKeyTap(String digit) {
    // Solo composizione locale: il DTMF va inviato esclusivamente durante
    // una chiamata attiva (vedi MiniDtmfPad in call_screen.dart), non
    // mentre si sta ancora scrivendo il numero da chiamare -- inviarlo qui
    // faceva partire la chiamata ad ogni cifra digitata.
    setState(() => _number += digit);
  }

  void _onBackspace() {
    if (_number.isEmpty) return;
    setState(() => _number = _number.substring(0, _number.length - 1));
  }

  void _onCall() {
    if (_number.isEmpty) return;
    widget.phoneService.dial(_number);
  }

  @override
  Widget build(BuildContext context) {
    if (_call.state != CallState.idle) {
      return _buildInCallView();
    }
    return _buildDialerView();
  }

  Widget _buildInCallView() {
    final label = switch (_call.state) {
      CallState.dialing => 'Chiamata in corso...',
      CallState.ringing => 'Chiamata in arrivo',
      CallState.active => 'In corso',
      CallState.idle => '',
    };
    final number = _call.number.isNotEmpty ? _call.number : _number;
    // L'identificativo del chiamante via HFP (oFono) spesso porta solo il
    // numero, senza nome: si cerca comunque il nome nella rubrica gia'
    // sincronizzata prima di mostrare il numero grezzo.
    final contactName = _call.name.isNotEmpty
        ? _call.name
        : widget.phoneService.contactNameFor(number);
    final title = contactName ?? (number.isNotEmpty ? number : 'Numero sconosciuto');

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const SizedBox(height: 32),
          const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 24, color: Colors.white)),
          if (contactName != null && number.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(number, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          ],
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.greenAccent)),
          if (_showKeypad)
            Expanded(child: MiniDtmfPad(phoneService: widget.phoneService))
          else
            const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CallActionButton(
                  icon: _muted ? Icons.mic_off : Icons.mic,
                  label: 'Muto',
                  active: _muted,
                  onTap: () => widget.phoneService.setMute(!_muted),
                ),
                FloatingActionButton(
                  backgroundColor: Colors.red,
                  onPressed: widget.phoneService.hangup,
                  child: const Icon(Icons.call_end),
                ),
                CallActionButton(
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
    );
  }

  Widget _buildDialerView() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Center(
              child: Text(
                _number.isEmpty ? 'Componi numero' : _number,
                style: TextStyle(
                  fontSize: 28,
                  color: _number.isEmpty ? Colors.grey : Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            // childAspectRatio calcolato dallo spazio disponibile (invece di
            // un valore fisso) cosi' le 4 righe di tasti riempiono
            // esattamente l'area assegnata: con un rapporto fisso, su uno
            // schermo largo (tipico di un autoradio) le celle diventavano
            // piu' alte dello spazio disponibile e la griglia richiedeva
            // uno scroll per vedere le ultime righe (0 e #).
            child: LayoutBuilder(
              builder: (context, constraints) {
                const crossAxisCount = 3;
                const rowCount = 4;
                final cellWidth = constraints.maxWidth / crossAxisCount;
                final cellHeight = constraints.maxHeight / rowCount;
                return GridView.count(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: cellWidth / cellHeight,
                  physics: const NeverScrollableScrollPhysics(),
                  children: _keys.map((k) => _DialKey(
                    digit: k[0],
                    letters: k[1],
                    onTap: () => _onKeyTap(k[0]),
                  )).toList(),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            // Spazio esplicito sotto la griglia: senza, i tasti 0/# e i
            // pulsanti di chiamata/cancella apparivano troppo vicini,
            // quasi sovrapposti.
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                const SizedBox(width: 56),
                FloatingActionButton(
                  backgroundColor: Colors.green,
                  onPressed: _onCall,
                  child: const Icon(Icons.call),
                ),
                IconButton(
                  iconSize: 32,
                  onPressed: _onBackspace,
                  icon: const Icon(Icons.backspace_outlined),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DialKey extends StatelessWidget {
  final String digit;
  final String letters;
  final VoidCallback onTap;

  const _DialKey({required this.digit, required this.letters, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(digit, style: const TextStyle(fontSize: 26, color: Colors.white)),
          if (letters.isNotEmpty)
            Text(letters, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }
}
