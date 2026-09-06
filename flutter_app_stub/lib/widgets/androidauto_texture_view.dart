import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Mostra il framebuffer di Android Auto ricevendolo dal container
/// androidauto-bridge, che trasmette lo schermo virtuale (Xvfb, dove
/// autoapp disegna) via GStreamer/TCP su 127.0.0.1:5000, in formato grezzo
/// (nessuna codifica H.264 -- loopback, comprimere aggiungerebbe solo
/// latenza).
///
/// NOTA (da quando il progetto e' passato a Flutter Linux desktop standard,
/// senza piu' flutter-pi): il pacchetto ufficiale `video_player` di Google
/// non ha un'implementazione per Linux (solo Android/iOS/web/macOS), quindi
/// `VideoPlayerController` qui sotto non funziona finche' non si sceglie un
/// plugin video Linux-compatibile (es. `media_kit`/`media_kit_video`, che
/// ha supporto Linux maturo) e si adatta questo widget di conseguenza --
/// verificato con `flutter analyze` pulito ma NON testato a runtime.
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
      // (androidauto-bridge/launcher.py, _start_gstreamer_stream). NOTA:
      // VideoPlayerController non ha implementazione Linux (vedi commento
      // in cima al file) -- questa chiamata fallisce finche' non si integra
      // un plugin video Linux-compatibile al posto di video_player.
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
