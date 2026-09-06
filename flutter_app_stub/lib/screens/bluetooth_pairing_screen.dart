import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';

class BluetoothPairingScreen extends StatefulWidget {
  final BluetoothService btService;
  const BluetoothPairingScreen({super.key, required this.btService});

  @override
  State<BluetoothPairingScreen> createState() => _BluetoothPairingScreenState();
}

class _BluetoothPairingScreenState extends State<BluetoothPairingScreen> {
  List<BtDevice> _devices = [];
  bool _scanning = false;
  bool _discoverable = false;
  String? _pairingMac;

  @override
  void initState() {
    super.initState();
    widget.btService.devices.listen((d) => setState(() => _devices = d));
    widget.btService.discoverable.listen((d) => setState(() => _discoverable = d));

    // Quando BlueZ chiede conferma passkey, mostra il dialogo bloccante:
    // l'utente deve confermare sia qui che sul telefono.
    widget.btService.pairingRequest.listen((req) {
      _showPasskeyDialog(req['device'] ?? '', req['passkey'] ?? '');
    });

    widget.btService.pairingState.listen((state) {
      if (state == PairingState.paired || state == PairingState.failed) {
        setState(() => _pairingMac = null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(state == PairingState.paired
                ? 'Abbinamento riuscito'
                : 'Abbinamento non riuscito'),
          ));
        }
      }
    });
  }

  void _showPasskeyDialog(String device, String passkey) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Conferma abbinamento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Verifica che il telefono mostri lo stesso codice:'),
            const SizedBox(height: 12),
            Text(
              passkey,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.btService.confirmPairing(false);
              Navigator.of(context).pop();
            },
            child: const Text('Rifiuta'),
          ),
          FilledButton(
            onPressed: () {
              widget.btService.confirmPairing(true);
              Navigator.of(context).pop();
            },
            child: const Text('Conferma'),
          ),
        ],
      ),
    );
  }

  void _toggleScan() {
    setState(() => _scanning = !_scanning);
    if (_scanning) {
      widget.btService.startScan();
    } else {
      widget.btService.stopScan();
    }
  }

  void _makeDiscoverable() {
    widget.btService.makeDiscoverable();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Ora la head unit è visibile: cercala tra i dispositivi Bluetooth del telefono'),
    ));
  }

  void _onDeviceTap(BtDevice d) {
    if (d.paired) return;
    setState(() => _pairingMac = d.mac);
    widget.btService.pair(d.mac);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Expanded(
                child: Text('Dispositivi Bluetooth', style: TextStyle(fontSize: 18)),
              ),
              OutlinedButton.icon(
                onPressed: _discoverable ? null : _makeDiscoverable,
                icon: Icon(_discoverable ? Icons.bluetooth_searching : Icons.phonelink_ring),
                label: Text(_discoverable ? 'Visibile dal telefono' : 'Associa nuovo telefono'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _toggleScan,
                icon: Icon(_scanning ? Icons.stop : Icons.search),
                label: Text(_scanning ? 'Ferma ricerca' : 'Cerca dispositivi'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _devices.isEmpty
              ? Center(
                  child: Text(
                    _scanning ? 'Ricerca in corso...' : 'Nessun dispositivo trovato',
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: _devices.length,
                  itemBuilder: (context, i) {
                    final d = _devices[i];
                    final isPairingThis = _pairingMac == d.mac;
                    return ListTile(
                      leading: Icon(
                        d.connected ? Icons.bluetooth_connected : Icons.bluetooth,
                        color: d.connected ? Colors.blueAccent : Colors.grey,
                      ),
                      title: Text(d.name),
                      subtitle: Text(d.paired
                          ? (d.connected ? 'Connesso' : 'Abbinato')
                          : d.mac),
                      trailing: isPairingThis
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : d.paired
                              ? IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () => widget.btService.remove(d.mac),
                                )
                              : const Icon(Icons.chevron_right),
                      onTap: () => _onDeviceTap(d),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
