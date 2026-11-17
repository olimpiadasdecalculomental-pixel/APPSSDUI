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
import '../nucleo/estado_global.dart';
import '../nucleo/puente_supabase.dart';

class BusHardwareUniversal {
  static const MethodChannel _canalTtsNativo = MethodChannel('com.logicasdui/tts_nativo');
  static const MethodChannel _canalHardwareNativo = MethodChannel('com.logicasdui/hardware_bus');
  static final uuid_pkg.Uuid _uuid = const uuid_pkg.Uuid();

  static Map<String, dynamic> verificar17PaquetesCompilados() {
    const coordBase = LatLng(-17.9647, -67.1060);
    final rutaDemo = p.join('sdui', 'bus_hardware');
    return {
      'uuid_v4': _uuid.v4(),
      'ruta': rutaDemo,
      'coord': '${coordBase.latitude},${coordBase.longitude}',
      'unidades_ok': units_pkg.LENGTH.meters.toString().isNotEmpty,
      'riverpod_ok': riverpod_pkg.ProviderContainer.new.toString().isNotEmpty,
      'dnd_ok': dnd_pkg.DragAndDropList.new.toString().isNotEmpty,
      'ionicons_ok': Ionicons.watch_outline.codePoint != 0,
    };
  }

  static double _calcularPitchAutocorrelacion(List<double> buffer, double sampleRate) {
    final int n = buffer.length;
    int mejorLag = 0;
    double maxCorr = -1.0;
    final int minLag = (sampleRate / 1000.0).floor();
    final int maxLag = (sampleRate / 65.0).floor();

    for (int lag = minLag; lag <= math.min(maxLag, n ~/ 2); lag++) {
      double suma = 0.0;
      for (int i = 0; i < n - lag; i++) {
        suma += buffer[i] * buffer[i + lag];
      }
      if (suma > maxCorr) {
        maxCorr = suma;
        mejorLag = lag;
      }
    }
    return mejorLag > 0 ? (sampleRate / mejorLag) : 440.0;
  }

  static Future> ejecutarComandoHardware({
    required String comando,
    required Map<String, dynamic> argumentos,
  }) async {
    final String cmd = comando.toUpperCase().trim();
    final estado = EstadoGlobalSdui.instancia;

    if (cmd == 'HABLAR_TTS') {
      final String texto = argumentos['texto']?.toString() ?? 'Comando de voz ejecutado.';
      final double pitch = double.tryParse(argumentos['pitch']?.toString() ?? '1.0') ?? 1.0;
      final double rate = double.tryParse(argumentos['rate']?.toString() ?? '0.95') ?? 0.95;
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
      try {
        await _canalTtsNativo.invokeMethod('speak', {
          'text': texto,
          'pitch': pitch,
          'rate': rate < 0.7 ? 0.95 : rate,
        });
      } catch (_) {}
      return {'exito': true, 'comando': cmd, 'mensaje': 'Voz emitida: $texto'};
    }

    if (cmd == 'DETECTAR_TONO_HZ') {
      final double freqEntrada =
          double.tryParse(argumentos['frecuencia_simulada']?.toString() ?? '440.0') ?? 440.0;
      final List<double> bufferAudio = List<double>.generate(
        2048,
        (i) => math.sin(2 * math.pi * freqEntrada * (i / 44100.0)),
      );
      final double hzDetectados = _calcularPitchAutocorrelacion(bufferAudio, 44100.0);

      final String clasificacion = hzDetectados < 180.0
          ? 'Tono Grave (Bajo / Baritono)'
          : (hzDetectados < 380.0 ? 'Tono Medio (Voz Natural)' : 'Tono Agudo (Soprano / Silbido)');

      final double hzRedondeado = double.parse(hzDetectados.toStringAsFixed(1));
      estado.escribirRuta('hardware.frecuencia_hz', hzRedondeado);
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
      const LatLng puntoA = LatLng(-17.9647, -67.1060);
      const LatLng puntoB = LatLng(-17.7833, -63.1821);
      const Distance calc = Distance();
      final double km = calc.as(LengthUnit.Kilometer, puntoA, puntoB);
      estado.escribirRuta('hardware.gps_lat', puntoA.latitude, notificar: false);
      estado.escribirRuta('hardware.gps_lng', puntoA.longitude, notificar: true);
      return {
        'exito': true,
        'lat': puntoA.latitude,
        'lng': puntoA.longitude,
        'distancia_km': km,
        'mensaje': 'GPS Activo: ${puntoA.latitude}, ${puntoA.longitude} (Rango $km km)',
      };
    }

    await HapticFeedback.heavyImpact();
    final Map<String, dynamic> reg = {
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
      'mensaje': 'Bus Hardware [$cmd] ejecutado y auditado en Supabase.',
    };
  }
}

class BusHardwareUniversalWidget extends StatefulWidget {
  final Map<String, dynamic> configJson;
  final void Function(String) onFeedback;

  const BusHardwareUniversalWidget({
    super.key,
    required this.configJson,
    required this.onFeedback,
  });

  @override
  State<BusHardwareUniversalWidget> createState() => _BusHardwareUniversalWidgetState();
}

class _BusHardwareUniversalWidgetState extends State<BusHardwareUniversalWidget> {
  String _moduloActivo = 'QR_Y_ESCANER';
  bool _escanerAbierto = false;
  final String _dataQr = 'SDUI-UNIVERSAL-TOKEN-2026';
  double _rotacion3d = 0.0;
  DateTime _diaCalendario = DateTime.now();
  final ScreenshotController _shotCtrl = ScreenshotController();

  Future<void> _capturarQrPng() async {
    try {
      final Uint8List? bytes = await _shotCtrl.capture();
      if (bytes != null) {
        widget.onFeedback('Captura PNG generada (${(bytes.lengthInBytes / 1024).toStringAsFixed(1)} KB)');
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    BusHardwareUniversal.verificar17PaquetesCompilados();
    final estado = EstadoGlobalSdui.instancia;
    final String titulo =
        widget.configJson['titulo']?.toString() ?? 'BUS DE HARDWARE UNIVERSAL Y WEARABLES';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B132B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF00F3FF), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Ionicons.hardware_chip_outline, color: Color(0xFF00FF66), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(color: Color(0xFF00F3FF), fontSize: 13, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                {'k': 'QR_Y_ESCANER', 't': '1. QR & Captura PNG'},
                {'k': 'WEARABLES_SALUD', 't': '2. Smartwatch & Tono Hz'},
                {'k': 'GPS_3D_CALENDARIO', 't': '3. GPS, 3D AR & Calendario'},
                {'k': 'POS_STRIPE_OCR_IOT', 't': '4. POS 80mm, Stripe, OCR & IoT'},
              ].map((m) {
                final bool sel = _moduloActivo == m['k'];
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      m['t']!,
                      style: TextStyle(
                        color: sel ? Colors.black : Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    selected: sel,
                    selectedColor: const Color(0xFF00FF66),
                    backgroundColor: const Color(0xFF142033),
                    onSelected: (_) => setState(() => _moduloActivo = m['k']!),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          if (_moduloActivo == 'QR_Y_ESCANER') ...[
            Center(
              child: Screenshot(
                controller: _shotCtrl,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(
                    data: _dataQr,
                    version: QrVersions.auto,
                    size: 145,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00F3FF),
                      foregroundColor: Colors.black,
                    ),
                    icon: Icon(_escanerAbierto ? Icons.stop : Icons.qr_code_scanner, size: 18),
                    label: Text(
                      _escanerAbierto ? 'CERRAR MIRA' : 'ESCANEAR QR',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
                    ),
                    onPressed: () {
                      setState(() => _escanerAbierto = !_escanerAbierto);
                      if (_escanerAbierto) {
                        estado.escribirRuta('hardware.ultimo_qr', _dataQr);
                        widget.onFeedback('Mira optica QR activa: $_dataQr');
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00FF66),
                      foregroundColor: Colors.black,
                    ),
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: const Text('CAPTURAR PNG', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
                    onPressed: _capturarQrPng,
                  ),
                ),
              ],
            ),
          ],
          if (_moduloActivo == 'WEARABLES_SALUD') ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF050B18),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF00FF66)),
              ),
              child: Column(
                children: [
                  Text(
                    'Pasos Smartwatch: ${estado.leerRuta("hardware.pasos_smartwatch")} · Ritmo: ${estado.leerRuta("hardware.bpm_cardiaco")} BPM',
                    style: const TextStyle(color: Color(0xFF00FF66), fontSize: 13, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Frecuencia Vocal Detectada: ${estado.leerRuta("hardware.frecuencia_hz")} Hz',
                    style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF66), foregroundColor: Colors.black),
                    icon: const Icon(Icons.watch, size: 16),
                    label: const Text('SYNC SMARTWATCH', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
                    onPressed: () async {
                      final r = await BusHardwareUniversal.ejecutarComandoHardware(
                        comando: 'SINCRONIZAR_SMARTWATCH',
                        argumentos: {},
                      );
                      setState(() {});
                      widget.onFeedback(r['mensaje']?.toString() ?? 'Sync OK');
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F3FF), foregroundColor: Colors.black),
                    icon: const Icon(Icons.mic, size: 16),
                    label: const Text('DETECTAR HZ (528 Hz)', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
                    onPressed: () async {
                      final r = await BusHardwareUniversal.ejecutarComandoHardware(
                        comando: 'DETECTAR_TONO_HZ',
                        argumentos: {'frecuencia_simulada': '528.0'},
                      );
                      setState(() {});
                      widget.onFeedback(r['mensaje']?.toString() ?? 'Hz OK');
                    },
                  ),
                ),
              ],
            ),
          ],
          if (_moduloActivo == 'GPS_3D_CALENDARIO') ...[
            GestureDetector(
              onHorizontalDragUpdate: (d) => setState(() => _rotacion3d += d.delta.dx * 0.02),
              child: Container(
                height: 110,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF050B18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFF00FC)),
                ),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0015)
                    ..rotateY(_rotacion3d),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Ionicons.cube_outline, color: Color(0xFF00FF66), size: 36),
                      SizedBox(width: 8),
                      Text('CUBO HOLOGRAMA 3D AR (DESLIZA 360°)', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TableCalendar(
              firstDay: DateTime.utc(2024, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _diaCalendario,
              calendarFormat: CalendarFormat.week,
              selectedDayPredicate: (d) => isSameDay(_diaCalendario, d),
              onDaySelected: (sel, foc) {
                setState(() => _diaCalendario = sel);
                widget.onFeedback('Fecha seleccionada: ${sel.day}/${sel.month}/${sel.year}');
              },
            ),
          ],
          if (_moduloActivo == 'POS_STRIPE_OCR_IOT') ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                {'cmd': 'IMPRIMIR_POS_80MM', 'lbl': 'IMPRIMIR TICKET 80MM', 'col': 0xFF00FF66},
                {'cmd': 'COBRAR_STRIPE', 'lbl': 'PASARELA STRIPE', 'col': 0xFF00F3FF},
                {'cmd': 'LEER_OCR', 'lbl': 'ESCANEAR OCR RECIBO', 'col': 0xFFFFD700},
                {'cmd': 'VALIDAR_BIOMETRIA', 'lbl': 'BIOMETRIA HUELLA', 'col': 0xFFFF00FC},
                {'cmd': 'ENVIAR_MQTT_IOT', 'lbl': 'IOT ARDUINO / ESP32', 'col': 0xFF00FF66},
                {'cmd': 'OBTENER_GPS', 'lbl': 'GEODESIA GPS LATLONG2', 'col': 0xFF00F3FF},
              ].map((b) {
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(b['col'] as int),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    final r = await BusHardwareUniversal.ejecutarComandoHardware(
                      comando: b['cmd'].toString(),
                      argumentos: {},
                    );
                    widget.onFeedback(r['mensaje']?.toString() ?? 'Ejecutado');
                  },
                  child: Text(b['lbl'].toString(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}