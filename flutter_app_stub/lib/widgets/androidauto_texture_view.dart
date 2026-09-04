import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Mostra il framebuffer di Android Auto usando il pacchetto UFFICIALE
/// video_player di Google, senza pacchetti terzi ne' codice nativo custom.
///
/// Fonte di questa scelta: il README ufficiale di flutter-pi
/// (github.com/ardera/flutter-pi) dichiara esplicitamente che il supporto
/// GStreamer e' integrato nel motore stesso (opzione di build
/// BUILD_GSTREAMER_VIDEO_PLAYER_PLUGIN, vedi setup-host.sh) e che, una
/// volta ricompilato flutter-pi con quell'opzione, "non c'e' nulla di
/// specifico da fare lato Dart" -- si usa VideoPlayerController normale.
///
/// Il container androidauto-bridge trasmette lo schermo virtuale (Xvfb,
/// dove autoapp disegna) via GStreamer/TCP su 127.0.0.1:5000, in formato
/// grezzo (nessuna codifica H.264 -- loopback, comprimere aggiungerebbe
/// solo latenza).
class AndroidAutoTextureView extends StatefulWidget {
  const AndroidAutoTextureView({super.key});

  @override
  State<AndroidAutoTextureView> createState() => _AndroidAutoTextureViewState();
}

class _AndroidAutoTextureViewState extends State<AndroidAutoTextureView> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // Pipeline GStreamer che deve combaciare con quella lato container
      // (androidauto-bridge/launcher.py, _start_gstreamer_stream).
      // NOTA: se l'implementazione GStreamer di flutter-pi si aspetta la
      // pipeline con un prefisso URI specifico invece della stringa grezza
      // (es. "gst-pipeline://...") anziche' come dataSource diretto, e' un
      // aggiustamento minore qui, non un cambio di architettura -- verifica
      // contro l'esempio incluso nel repo flutter-pi una volta clonato.
      const pipeline = 'tcpclientsrc host=127.0.0.1 port=5000 '
          '! gdpdepay ! rtpvrawdepay ! videoconvert';

      final controller = VideoPlayerController.networkUrl(Uri.parse(pipeline));
      await controller.initialize();
      await controller.play();
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Connessione stream Android Auto fallita: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, style: const TextStyle(color: Colors.grey)),
          ),
        ),
      );
    }
    if (_controller == null || !_controller!.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return AspectRatio(
      aspectRatio: _controller!.value.aspectRatio,
      child: VideoPlayer(_controller!),
    );
  }
}
