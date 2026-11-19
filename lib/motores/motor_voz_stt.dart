import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';

class MotorVozStt {
  static final SpeechToText _stt = SpeechToText();
  static bool _inicializado = false;

  static Future escuchar({int duracionSegundos = 5}) async {
    if (!_inicializado) {
      _inicializado = await _stt.initialize(
        onError: (e) => print('Error STT: $e'),
        onStatus: (s) => print('STT Status: $s'),
      );
    }

    if (!_inicializado) {
      return {'exito': false, 'mensaje': 'No se pudo iniciar el micrófono o faltan permisos.'};
    }

    final completer = Completer();
    String textoTemporal = '';

    await _stt.listen(
      onResult: (result) {
        textoTemporal = result.recognizedWords;
        if (result.finalResult) {
          _stt.stop();
          if (!completer.isCompleted) {
            completer.complete({'exito': true, 'texto_reconocido': textoTemporal.trim()});
          }
        }
      },
      localeId: 'es_ES',
    );

    Future.delayed(Duration(seconds: duracionSegundos), () {
      if (!completer.isCompleted) {
        _stt.stop();
        if (textoTemporal.trim().isNotEmpty) {
          completer.complete({'exito': true, 'texto_reconocido': textoTemporal.trim()});
        } else {
          completer.complete({'exito': false, 'mensaje': 'No se escuchó ninguna voz.'});
        }
      }
    });

    return completer.future;
  }
}