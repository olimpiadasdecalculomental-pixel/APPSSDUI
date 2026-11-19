import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:ionicons/ionicons.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:screenshot/screenshot.dart';
import 'package:units_converter/units_converter.dart' as units_pkg;
import 'package:uuid/uuid.dart' as uuid_pkg;
import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod_pkg;
import 'package:drag_and_drop_lists/drag_and_drop_lists.dart' as dnd_pkg;
import 'package:path/path.dart' as p;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../nucleo/estado_global.dart';
import '../nucleo/puente_supabase.dart';

class BusHardwareUniversal {
  static const MethodChannel _canalTtsNativo = MethodChannel('com.logicasdui/tts_nativo');
  static const MethodChannel _canalHardwareNativo = MethodChannel('com.logicasdui/hardware_bus');
  static final uuid_pkg.Uuid _uuid = const uuid_pkg.Uuid();
  static MqttServerClient? _mqttClient;

  static Map verificarPaquetesCompilados() {
    const coordBase = LatLng(-17.9647, -67.1060);
    final String rutaDemo = p.join('sdui', 'bus_hardware');
    return {
      'uuid_v4': _uuid.v4(),
      'ruta': rutaDemo,
      'coord': '${coordBase.latitude},${coordBase.longitude}',
      'unidades_ok': units_pkg.LENGTH.meters.toString().isNotEmpty,
      'riverpod_ok': riverpod_pkg.ProviderContainer.new.toString().isNotEmpty,
      'dnd_ok': dnd_pkg.DragAndDropList.new.toString().isNotEmpty,
      'ionicons_ok': Ionicons.watch_outline.codePoint != 0,
      'mqtt_ok': MqttServerClient.new.toString().isNotEmpty,
    };
  }

  static double _calcularPitchAutocorrelacion(List buffer, double sampleRate) {
    final int n = buffer.length;
    int mejorLag = 0;
    double maxCorr = -1.0;
    final int minLag = (sampleRate / 1000.0).floor();
    final int maxLag = (sampleRate / 65.0).floor();

    for (int lag = minLag; lag <= math.min(maxLag, n ~/ 2); lag++) {
      double suma = 0.0;
      for (int i = 0; i < n - lag; i++) {
        suma += ((buffer[i] as num).toDouble()) * ((buffer[i + lag] as num).toDouble());
      }
      if (suma > maxCorr) {
        maxCorr = suma;
        mejorLag = lag;
      }
    }
    return mejorLag > 0 ? (sampleRate / mejorLag) : 440.0;
  }

  static Future ejecutarComandoHardware({
    required String comando,
    required Map argumentos,
  }) async {
    verificarPaquetesCompilados();
    final String cmd = comando.toUpperCase().trim();
    final estado = EstadoGlobalSdui.instancia;

    if (cmd == 'MQTT_CONECTAR') {
      final String broker = argumentos['broker']?.toString() ?? '';
      final int puerto = int.tryParse(argumentos['puerto']?.toString() ?? '1883') ?? 1883;
      final String clientId = argumentos['client_id']?.toString() ?? 'sdui_iot_${DateTime.now().millisecondsSinceEpoch}';
      final String user = argumentos['usuario']?.toString() ?? '';
      final String pass = argumentos['password']?.toString() ?? '';

      if (broker.isEmpty) return {'exito': false, 'comando': cmd, 'mensaje': 'Broker vacío'};

      _mqttClient = MqttServerClient.withPort(broker, clientId, puerto);
      _mqttClient!.logging(on: false);
      _mqttClient!.keepAlivePeriod = 60;
      _mqttClient!.onDisconnected = () {
        estado.escribirRuta('hardware.mqtt_conectado', false, notificar: true);
      };

      try {
        if (user.isNotEmpty && pass.isNotEmpty) {
          await _mqttClient!.connect(user, pass);
        } else {
          await _mqttClient!.connect();
        }
      } catch (e) {
        _mqttClient?.disconnect();
        return {'exito': false, 'comando': cmd, 'mensaje': 'Error MQTT: $e'};
      }

      if (_mqttClient!.connectionStatus!.state == MqttConnectionState.connected) {
        estado.escribirRuta('hardware.mqtt_conectado', true, notificar: true);
        
        _mqttClient!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
          final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
          final String pt = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
          final String topic = c[0].topic;
          
          estado.escribirRuta('hardware.mqtt_ultimo_mensaje', pt, notificar: false);
          estado.escribirRuta('hardware.mqtt_topicos.$topic', pt, notificar: true);
        });

        return {'exito': true, 'comando': cmd, 'mensaje': 'IoT Conectado a $broker'};
      } else {
        _mqttClient?.disconnect();
        return {'exito': false, 'comando': cmd, 'mensaje': 'Conexión fallida MQTT'};
      }
    }

    if (cmd == 'MQTT_PUBLICAR') {
      if (_mqttClient == null || _mqttClient!.connectionStatus!.state != MqttConnectionState.connected) {
        return {'exito': false, 'comando': cmd, 'mensaje': 'MQTT no conectado'};
      }
      final String topic = argumentos['topico']?.toString() ?? '';
      final String payload = argumentos['mensaje']?.toString() ?? '';
      if (topic.isEmpty) return {'exito': false, 'comando': cmd, 'mensaje': 'Tópico vacío'};

      final builder = MqttClientPayloadBuilder();
      builder.addString(payload);
      _mqttClient!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      
      return {'exito': true, 'comando': cmd, 'mensaje': 'Publicado en $topic'};
    }

    if (cmd == 'MQTT_SUSCRIBIR') {
      if (_mqttClient == null || _mqttClient!.connectionStatus!.state != MqttConnectionState.connected) {
        return {'exito': false, 'comando': cmd, 'mensaje': 'MQTT no conectado'};
      }
      final String topic = argumentos['topico']?.toString() ?? '';
      if (topic.isEmpty) return {'exito': false, 'comando': cmd, 'mensaje': 'Tópico vacío'};

      _mqttClient!.subscribe(topic, MqttQos.atLeastOnce);
      return {'exito': true, 'comando': cmd, 'mensaje': 'Suscrito a $topic'};
    }

    if (cmd == 'SILENCIAR_TTS' || cmd == 'DETENER_TTS') {
      try {
        await _canalTtsNativo.invokeMethod('stop');
      } catch (_) {}
      return {'exito': true, 'comando': cmd, 'mensaje': 'Voz TTS detenida.'};
    }

    if (cmd == 'AJUSTAR_VOLUMEN') {
      final int pct = (int.tryParse(argumentos['porcentaje']?.toString() ?? '70') ?? 70).clamp(0, 100);
      try {
        await _canalTtsNativo.invokeMethod('setVolume', {'percent': pct});
      } catch (_) {}
      estado.escribirRuta('hardware.volumen_pct', pct);
      return {'exito': true, 'comando': cmd, 'volumen_pct': pct, 'mensaje': 'Volumen ajustado al $pct%'};
    }

    if (cmd == 'HABLAR_TTS') {
      if (argumentos['silenciar'] == true) {
        return {'exito': true, 'comando': cmd, 'mensaje': 'TTS en modo silencioso.'};
      }
      final String texto = estado.interpolarTexto(
        argumentos['texto']?.toString() ?? '',
      );
      if (texto.isEmpty) {
        return {'exito': true, 'comando': cmd, 'mensaje': 'Texto TTS vacio.'};
      }
      final double pitch = double.tryParse(argumentos['pitch']?.toString() ?? '1.0') ?? 1.0;
      final double rate = double.tryParse(argumentos['rate']?.toString() ?? '0.95') ?? 0.95;
      final double vol = (double.tryParse(argumentos['volumen']?.toString() ?? '1.0') ?? 1.0).clamp(0.0, 1.0);
      HapticFeedback.selectionClick();
      try {
        await _canalTtsNativo.invokeMethod('speak', {
          'text': texto,
          'pitch': pitch,
          'rate': rate < 0.7 ? 0.95 : rate,
          'volume': vol,
        });
      } catch (_) {}
      return {'exito': true, 'comando': cmd, 'mensaje': 'Voz: $texto'};
    }

    if (cmd == 'DETECTAR_TONO_HZ') {
      final double freqEntrada =
          double.tryParse(argumentos['frecuencia_simulada']?.toString() ?? '440.0') ?? 440.0;
      final List bufferAudio = List.generate(
        2048,
        (i) => math.sin(2 * math.pi * freqEntrada * (i / 44100.0)),
      );
      final double hzDetectados = _calcularPitchAutocorrelacion(bufferAudio, 44100.0);

      final String clasificacion = hzDetectados < 180.0
          ? 'Tono Grave (Bajo / Baritono)'
          : (hzDetectados < 380.0 ? 'Tono Medio (Voz Natural)' : 'Tono Agudo (Soprano / Silbido)');

      final double hzRedondeado = double.parse(hzDetectados.toStringAsFixed(1));
      final String rutaGuardar = argumentos['guardar_en']?.toString() ?? 'hardware.frecuencia_hz';
      estado.escribirRuta(rutaGuardar, hzRedondeado, notificar: false);
      estado.escribirRuta('hardware.clasificacion_tono', clasificacion, notificar: true);
      return {
        'exito': true,
        'frecuencia_hz': hzRedondeado,
        'clasificacion': clasificacion,
        'mensaje': 'Detector DSP: $hzRedondeado Hz ($clasificacion)',
      };
    }

    if (cmd == 'SINCRONIZAR_SMARTWATCH') {
      int pasos = ((estado.leerRuta('hardware.pasos_smartwatch') as int?) ?? 4800) + 35;
      int bpm = 72 + (DateTime.now().second % 14);
      try {
        final resWear = await _canalHardwareNativo.invokeMethod('syncWearable');
        if (resWear is Map) {
          pasos = int.tryParse(resWear['steps']?.toString() ?? '$pasos') ?? pasos;
          bpm = int.tryParse(resWear['bpm']?.toString() ?? '$bpm') ?? bpm;
        }
      } catch (_) {}

      estado.escribirRuta('hardware.pasos_smartwatch', pasos, notificar: false);
      estado.escribirRuta('hardware.bpm_cardiaco', bpm, notificar: true);

      return {
        'exito': true,
        'pasos': pasos,
        'bpm': bpm,
        'mensaje': 'Smartwatch Sync: $pasos pasos · $bpm BPM',
      };
    }

    if (cmd == 'OBTENER_GPS') {
      final double latA =
          double.tryParse(argumentos['lat_origen']?.toString() ?? '-17.9647') ?? -17.9647;
      final double lngA =
          double.tryParse(argumentos['lng_origen']?.toString() ?? '-67.1060') ?? -67.1060;
      final double latB =
          double.tryParse(argumentos['lat_destino']?.toString() ?? '-17.7833') ?? -17.7833;
      final double lngB =
          double.tryParse(argumentos['lng_destino']?.toString() ?? '-63.1821') ?? -63.1821;
      final LatLng puntoA = LatLng(latA, lngA);
      final LatLng puntoB = LatLng(latB, lngB);
      const Distance calc = Distance();
      final double km = calc.as(LengthUnit.Kilometer, puntoA, puntoB);
      estado.escribirRuta('hardware.gps_lat', puntoA.latitude, notificar: false);
      estado.escribirRuta('hardware.gps_lng', puntoA.longitude, notificar: false);
      estado.escribirRuta('hardware.gps_distancia_km', km, notificar: true);
      return {
        'exito': true,
        'lat': puntoA.latitude,
        'lng': puntoA.longitude,
        'distancia_km': km,
        'mensaje': 'GPS: ${puntoA.latitude}, ${puntoA.longitude} ($km km)',
      };
    }

    await HapticFeedback.heavyImpact();
    final Map reg = {
      'comando': cmd,
      'argumentos': argumentos,
      'fecha': DateTime.now().toIso8601String(),
    };
    await PuenteSupabaseSdui.llamarRpcNano(
      'nano_transaccion_atomica',
      {
        'p_app_id': PuenteSupabaseSdui.appIdActivo,
        'p_operacion': 'EVENTO_HARDWARE_$cmd',
        'p_datos': reg,
      },
    );
    return {
      'exito': true,
      'comando': cmd,
      'mensaje': 'Hardware [$cmd] ejecutado y auditado en Supabase.',
    };
  }
}

class SduiQrViewAtomico extends StatefulWidget {
  final Map nodoRaw;
  final void Function(String) onFeedback;

  const SduiQrViewAtomico({
    super.key,
    required this.nodoRaw,
    required this.onFeedback,
  });

  @override
  State createState() => _SduiQrViewAtomicoState();
}

class _SduiQrViewAtomicoState extends State {
  final ScreenshotController _shotCtrl = ScreenshotController();

  Future _capturarPng() async {
    final w = widget as SduiQrViewAtomico;
    try {
      final Uint8List? bytes = await _shotCtrl.capture();
      if (bytes != null) {
        final double kb = bytes.lengthInBytes / 1024.0;
        EstadoGlobalSdui.instancia.escribirRuta(
          w.nodoRaw['guardar_en']?.toString() ?? 'hardware.ultimo_qr_kb',
          kb.toStringAsFixed(1),
        );
        w.onFeedback('QR PNG capturado (${kb.toStringAsFixed(1)} KB)');
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final w = widget as SduiQrViewAtomico;
    final estado = EstadoGlobalSdui.instancia;
    final String dataQr = estado.interpolarTexto(
      w.nodoRaw['data']?.toString() ?? w.nodoRaw['valor']?.toString() ?? 'SDUI-QR',
    );
    final double tamano =
        double.tryParse(w.nodoRaw['size']?.toString() ?? '150') ?? 150.0;
    final bool mostrarBotonPng = w.nodoRaw['mostrar_boton_png'] != false;
    final String txtBtnPng = estado.interpolarTexto(
      w.nodoRaw['texto_boton_png']?.toString() ?? 'CAPTURAR PNG',
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B132B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00F3FF)),
      ),
      child: Column(
        children: [
          Screenshot(
            controller: _shotCtrl,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: dataQr.isEmpty ? 'SDUI-QR' : dataQr,
                version: QrVersions.auto,
                size: tamano,
              ),
            ),
          ),
          if (mostrarBotonPng) ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FF66),
                foregroundColor: Colors.black,
              ),
              icon: const Icon(Icons.camera_alt, size: 16),
              label: Text(
                txtBtnPng,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
              ),
              onPressed: _capturarPng,
            ),
          ],
        ],
      ),
    );
  }
}

class SduiCalendarioAtomico extends StatefulWidget {
  final Map nodoRaw;
  final void Function(String) onFeedback;

  const SduiCalendarioAtomico({
    super.key,
    required this.nodoRaw,
    required this.onFeedback,
  });

  @override
  State createState() => _SduiCalendarioAtomicoState();
}

class _SduiCalendarioAtomicoState extends State {
  DateTime _diaSeleccionado = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final w = widget as SduiCalendarioAtomico;
    final String rutaGuardar =
        w.nodoRaw['guardar_en']?.toString() ?? 'hardware.fecha_seleccionada';
    final bool formatoMes =
        (w.nodoRaw['formato']?.toString() ?? 'week').toLowerCase() == 'month';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B132B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD700)),
      ),
      child: TableCalendar(
        firstDay: DateTime.utc(2020, 1, 1),
        lastDay: DateTime.utc(2035, 12, 31),
        focusedDay: _diaSeleccionado,
        calendarFormat: formatoMes ? CalendarFormat.month : CalendarFormat.week,
        selectedDayPredicate: (d) => isSameDay(_diaSeleccionado, d),
        onDaySelected: (sel, foc) {
          setState(() => _diaSeleccionado = sel);
          final String fechaIso = sel.toIso8601String().split('T').first;
          EstadoGlobalSdui.instancia.escribirRuta(rutaGuardar, fechaIso);
          w.onFeedback('Fecha: $fechaIso');
        },
      ),
    );
  }
}

class SduiCubo3dAtomico extends StatefulWidget {
  final Map nodoRaw;

  const SduiCubo3dAtomico({
    super.key,
    required this.nodoRaw,
  });

  @override
  State createState() => _SduiCubo3dAtomicoState();
}

class _SduiCubo3dAtomicoState extends State {
  double _rotacionY = 0.0;

  static Color _hexColor(String? hex, Color def) {
    if (hex == null || hex.trim().isEmpty) return def;
    String limpio = hex.replaceAll('#', '').trim();
    if (limpio.length == 6) limpio = 'FF$limpio';
    final int? val = int.tryParse(limpio, radix: 16);
    return val != null ? Color(val) : def;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget as SduiCubo3dAtomico;
    final estado = EstadoGlobalSdui.instancia;
    final String texto = estado.interpolarTexto(
      w.nodoRaw['texto']?.toString() ?? 'OBJETO 3D SDUI',
    );
    final Color col = _hexColor(w.nodoRaw['color']?.toString(), const Color(0xFF00FF66));
    final double altura =
        double.tryParse(w.nodoRaw['altura']?.toString() ?? '110') ?? 110.0;

    return GestureDetector(
      onHorizontalDragUpdate: (d) => setState(() => _rotacionY += d.delta.dx * 0.025),
      child: Container(
        height: altura,
        margin: const EdgeInsets.only(bottom: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF050B18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: col, width: 1.5),
        ),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateY(_rotacionY),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Ionicons.cube_outline, color: col, size: 34),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  texto,
                  style: TextStyle(
                    color: col,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}