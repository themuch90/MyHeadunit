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

  static const _keys = [
    ['1', ''], ['2', 'ABC'], ['3', 'DEF'],
    ['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO'],
    ['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ'],
    ['*', ''], ['0', '+'], ['#', ''],
  ];

  void _onKeyTap(String digit) {
    // Solo composizione locale: il DTMF va inviato esclusivamente durante
    // una chiamata attiva (vedi _MiniDtmfPad in call_screen.dart), non
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActiveCallScreen(
          name: '',
          number: _number,
          phoneService: widget.phoneService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            child: GridView.count(
              crossAxisCount: 3,
              childAspectRatio: 1.4,
              children: _keys.map((k) => _DialKey(
                digit: k[0],
                letters: k[1],
                onTap: () => _onKeyTap(k[0]),
              )).toList(),
            ),
          ),
          Row(
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
