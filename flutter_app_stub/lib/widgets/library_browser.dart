import 'package:flutter/material.dart';
import '../services/radio_service.dart';

/// Naviga la libreria musicale di Mopidy (Spotify, musica locale...) via
/// `core.library.browse`: root, cartelle, brani, uniformi per ogni backend.
class LibraryBrowser extends StatefulWidget {
  final RadioService radioService;
  const LibraryBrowser({super.key, required this.radioService});

  @override
  State<LibraryBrowser> createState() => _LibraryBrowserState();
}

class _LibraryBrowserState extends State<LibraryBrowser> {
  final _stack = <LibraryRef?>[null];
  List<LibraryRef> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.radioService.browse(_stack.last?.uri);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossibile caricare la libreria: $e';
        _loading = false;
      });
    }
  }

  void _open(LibraryRef ref) {
    if (ref.type == LibraryRefType.directory) {
      setState(() => _stack.add(ref));
      _load();
    } else {
      widget.radioService.playUri(ref.uri);
    }
  }

  void _back() {
    setState(() => _stack.removeLast());
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_stack.length > 1)
          ListTile(
            leading: const Icon(Icons.arrow_back, color: Colors.white),
            title: Text(_stack.last!.name, style: const TextStyle(color: Colors.white)),
            onTap: _back,
          ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)));
    }
    if (_entries.isEmpty) {
      return const Center(child: Text('Vuota', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: _entries.length,
      itemBuilder: (context, i) {
        final ref = _entries[i];
        final isDirectory = ref.type == LibraryRefType.directory;
        return ListTile(
          leading: Icon(isDirectory ? Icons.folder : Icons.music_note, color: Colors.grey),
          title: Text(ref.name, style: const TextStyle(color: Colors.white)),
          trailing: isDirectory ? const Icon(Icons.chevron_right, color: Colors.grey) : null,
          onTap: () => _open(ref),
        );
      },
    );
  }
}
