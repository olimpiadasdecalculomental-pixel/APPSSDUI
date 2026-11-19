import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../nucleo/estado_global.dart';

class VideoUniversalSdui extends StatefulWidget {
  final Map nodoRaw;
  const VideoUniversalSdui({super.key, required this.nodoRaw});
  @override
  State<VideoUniversalSdui> createState() => _VideoUniversalSduiState();
}

class _VideoUniversalSduiState extends State<VideoUniversalSdui> {
  VideoPlayerController? _vpCtrl;
  WebViewController? _wvCtrl;
  bool _esWebView = false;
  String? _errorVideo;

  @override
  void initState() {
    super.initState();
    _inicializarVideo();
  }

  @override
  void didUpdateWidget(covariant VideoUniversalSdui oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String oldUrl = EstadoGlobalSdui.instancia.interpolarTexto(oldWidget.nodoRaw['url']?.toString() ?? '');
    final String newUrl = EstadoGlobalSdui.instancia.interpolarTexto(widget.nodoRaw['url']?.toString() ?? '');
    if (oldUrl != newUrl) {
      _disposeControllers();
      _inicializarVideo();
    }
  }

  void _disposeControllers() {
    _vpCtrl?.dispose();
    _vpCtrl = null;
    _wvCtrl = null;
    _esWebView = false;
    _errorVideo = null;
  }

  void _inicializarVideo() {
    final url = EstadoGlobalSdui.instancia.interpolarTexto(widget.nodoRaw['url']?.toString() ?? '');
    if (url.isEmpty) {
      setState(() { _errorVideo = 'URL de video vacia'; });
      return;
    }

    if (url.contains('youtube.com') || url.contains('youtu.be') || url.contains('tiktok.com') || url.contains('drive.google.com')) {
      _esWebView = true;
      try {
        _wvCtrl = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..loadRequest(Uri.parse(url));
      } catch (e) {
        setState(() { _errorVideo = 'Error cargando WebView: $e'; });
      }
    } else {
      try {
        _vpCtrl = VideoPlayerController.networkUrl(Uri.parse(url))
          ..initialize().then((_) {
            if (mounted) setState(() {});
            if (widget.nodoRaw['autoplay'] == true) _vpCtrl!.play();
          }).catchError((e) {
            if (mounted) setState(() { _errorVideo = 'Error reproduciendo video: $e'; });
          });
      } catch (e) {
        setState(() { _errorVideo = 'Error inicializando reproductor: $e'; });
      }
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double h = double.tryParse(widget.nodoRaw['altura']?.toString() ?? '250') ?? 250.0;
    
    if (_errorVideo != null) {
      return Container(
        height: h, 
        margin: const EdgeInsets.only(bottom: 12), 
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0xFF142033), border: Border.all(color: Colors.redAccent)), 
        child: Center(child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_errorVideo!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
        )),
      );
    }

    if (_esWebView && _wvCtrl != null) {
      return Container(
        height: h, 
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
        child: WebViewWidget(controller: _wvCtrl!),
      );
    }
    if (_vpCtrl != null && _vpCtrl!.value.isInitialized) {
      return Container(
        height: h,
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.black),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(aspectRatio: _vpCtrl!.value.aspectRatio, child: VideoPlayer(_vpCtrl!)),
            IconButton(
              icon: Icon(_vpCtrl!.value.isPlaying ? Icons.pause_circle : Icons.play_circle, size: 50, color: Colors.white70),
              onPressed: () {
                setState(() {
                  _vpCtrl!.value.isPlaying ? _vpCtrl!.pause() : _vpCtrl!.play();
                });
              }
            )
          ]
        )
      );
    }
    return Container(
      height: h, 
      margin: const EdgeInsets.only(bottom: 12), 
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0xFF142033)), 
      child: const Center(child: CircularProgressIndicator(color: Color(0xFF00FF66))),
    );
  }
}

class EscanerQrSdui extends StatefulWidget {
  final Map nodoRaw;
  final void Function(String) onFeedback;
  const EscanerQrSdui({super.key, required this.nodoRaw, required this.onFeedback});

  @override
  State<EscanerQrSdui> createState() => _EscanerQrSduiState();
}

class _EscanerQrSduiState extends State<EscanerQrSdui> {
  String? _ultimoCodigo;
  DateTime? _ultimoTiempo;

  @override
  Widget build(BuildContext context) {
    final double h = double.tryParse(widget.nodoRaw['altura']?.toString() ?? '300') ?? 300.0;
    final String ruta = widget.nodoRaw['guardar_en']?.toString() ?? 'hardware.qr_leido';
    return Container(
      height: h,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF00FF66), width: 2)),
      child: MobileScanner(
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
            final String code = barcodes.first.rawValue!;
            final ahora = DateTime.now();

            if (_ultimoCodigo == code && _ultimoTiempo != null) {
              if (ahora.difference(_ultimoTiempo!) < const Duration(seconds: 3)) {
                return;
              }
            }

            _ultimoCodigo = code;
            _ultimoTiempo = ahora;
            EstadoGlobalSdui.instancia.escribirRuta(ruta, code, notificar: true);
            widget.onFeedback('QR Detectado y copiado a $ruta');
          }
        },
      ),
    );
  }
}

class IconoSdui extends StatelessWidget {
  final Map nodoRaw;
  final EstadoGlobalSdui estado;
  const IconoSdui({super.key, required this.nodoRaw, required this.estado});

  @override
  Widget build(BuildContext context) {
    final String nombre = estado.interpolarTexto(nodoRaw['nombre']?.toString() ?? 'circle');
    final double size = double.tryParse(nodoRaw['size']?.toString() ?? '24') ?? 24.0;
    Color col = Colors.white;
    final String hex = nodoRaw['color']?.toString() ?? '';
    if (hex.isNotEmpty) {
       String limpio = hex.replaceAll('#', '').trim();
       if (limpio.length == 6) limpio = 'FF$limpio';
       final int? val = int.tryParse(limpio, radix: 16);
       if (val != null) col = Color(val);
    }
    
    IconData iconData = LucideIcons.circle;
    switch(nombre.toLowerCase()) {
      case 'home': iconData = Icons.home; break; 
      case 'user': iconData = LucideIcons.user; break;
      case 'settings': iconData = LucideIcons.settings; break;
      case 'camera': iconData = LucideIcons.camera; break;
      case 'qrcode': iconData = LucideIcons.qrCode; break;
      case 'wallet': iconData = LucideIcons.wallet; break;
      case 'check': iconData = LucideIcons.check; break;
      case 'x': iconData = LucideIcons.x; break;
      case 'menu': iconData = LucideIcons.menu; break;
      case 'heart': iconData = LucideIcons.heart; break;
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Icon(iconData, size: size, color: col),
    );
  }
}

class ContenedorStitchSdui extends StatelessWidget {
  final bool glass;
  final List coloresHex;
  final Widget child;
  final Color colorBorde;
  
  const ContenedorStitchSdui({
    super.key, 
    required this.glass, 
    required this.coloresHex, 
    required this.child,
    required this.colorBorde,
  });

  Color _hex(String h) {
    String limpio = h.replaceAll('#', '').trim();
    if (limpio.length == 6) limpio = 'FF$limpio';
    return Color(int.tryParse(limpio, radix: 16) ?? 0xFF0B132B);
  }

  @override
  Widget build(BuildContext context) {
    List<Color> gradientColors = [];
    for (var c in coloresHex) {
      gradientColors.add(_hex(c.toString()));
    }
    
    Color? colorFondo;
    LinearGradient? gradiente;

    if (gradientColors.isEmpty) {
      colorFondo = glass ? Colors.white.withValues(alpha: 0.08) : const Color(0xFF0B132B);
    } else if (gradientColors.length == 1) {
      colorFondo = glass ? Colors.white.withValues(alpha: 0.08) : gradientColors.first;
    } else {
      if (glass) {
        colorFondo = Colors.white.withValues(alpha: 0.08);
      } else {
        gradiente = LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight);
      }
    }

    BoxDecoration deco = BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: colorBorde, width: 1.5),
      color: colorFondo,
      gradient: gradiente,
      boxShadow: [
        if (gradientColors.isNotEmpty || glass)
          BoxShadow(color: colorBorde.withValues(alpha: 0.2), blurRadius: 15, spreadRadius: 1)
      ]
    );

    Widget inner = Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: deco,
      child: child,
    );

    if (glass) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: deco,
            child: child,
          ),
        ),
      );
    }
    
    return inner;
  }
}