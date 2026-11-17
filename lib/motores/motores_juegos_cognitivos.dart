import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import '../nucleo/estado_global.dart';
import '../nucleo/puente_supabase.dart';
import 'bus_hardware_universal.dart';

class MotoresJuegosCognitivos extends StatefulWidget {
  final String tipoMotor;
  final Map configJson;
  final void Function(String) onFeedback;

  const MotoresJuegosCognitivos({
    super.key,
    required this.tipoMotor,
    required this.configJson,
    required this.onFeedback,
  });

  @override
  State createState() => _MotoresJuegosCognitivosState();
}

class _MotoresJuegosCognitivosState extends State
    with SingleTickerProviderStateMixin {
  final math.Random _rng = math.Random();
  late final ConfettiController _confettiCtrl;
  late final AnimationController _fisicaCtrl;
  Timer? _timerPrincipal;

  int _tiempoMs = 0;
  bool _corriendo = false;
  int _aciertos = 0;
  int _errores = 0;

  List _itemsSecuencia = [];
  int _idxMostrandoSecuencia = -1;
  bool _ocultandoSecuencia = false;
  final TextEditingController _ctrlRespuestaSecuencia = TextEditingController();

  int _operandoA = 14;
  int _operandoB = 16;
  bool _mostrarGuiaCruzada = true;
  String _direccionEscritura = 'DERECHA_A_IZQUIERDA';
  String _entradaPizarra = '';

  String _subModoMatriz = 'SCHULTE_CHIMP';
  int _cantNumeros = 25;
  String _modoToqueSchulte = 'PRESIONAR';
  List _tableroNumeros = [];
  int _objetivoActual = 1;
  bool _chimpOculto = false;
  final Set _patronMemoria = {0, 4, 8, 12};
  final Set _patronTocadas = {};
  bool _mostrandoPatronGrid = false;
  final String _itemArrastrable = 'Manzana (Saludable)';
  int _indiceSwipe = 0;
  String _objetivoRain = 'A-7';
  final List _capsulasRain = ['A-7', 'B-9', 'K-4', 'M-2', 'X-5', 'Z-1'];

  double _frecuenciaHzDetectada = 440.0;
  String _clasificacionTono = 'LA4 (440 Hz · Tono Medio)';
  int _segundosBolsillo = 0;
  final TextEditingController _ctrlFraseBolsillo = TextEditingController(
    text: 'Atencion: Recuerda completar tu entrenamiento cognitivo y revisar tus pendientes.',
  );

  @override
  void initState() {
    super.initState();
    _confettiCtrl = ConfettiController(duration: const Duration(seconds: 2));
    _fisicaCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _inicializarParametrosDesdeJson();
    EstadoGlobalSdui.instancia.registrarListenerCicloVida(_alCambiarCicloVidaApp);
  }

  @override
  void dispose() {
    EstadoGlobalSdui.instancia.removerListenerCicloVida(_alCambiarCicloVidaApp);
    _timerPrincipal?.cancel();
    _confettiCtrl.dispose();
    _fisicaCtrl.dispose();
    _ctrlRespuestaSecuencia.dispose();
    _ctrlFraseBolsillo.dispose();
    super.dispose();
  }

  void _alCambiarCicloVidaApp(String evento) {
    final w = widget as MotoresJuegosCognitivos;
    if (evento == 'ON_APP_PAUSED' && _corriendo) {
      _errores++;
      w.onFeedback('Alerta Anti-Trampas: Pausa detectada durante la sesion.');
    }
  }

  void _inicializarParametrosDesdeJson() {
    final w = widget as MotoresJuegosCognitivos;
    final Map cfg = w.configJson;
    final rawItems = cfg['items'];
    if (rawItems is List && rawItems.isNotEmpty) {
      _itemsSecuencia = rawItems.map((e) => e.toString()).toList();
    } else {
      _itemsSecuencia = List.generate(25, (i) => '${i + 1}');
    }

    _operandoA = int.tryParse(cfg['operando_a']?.toString() ?? '14') ?? 14;
    _operandoB = int.tryParse(cfg['operando_b']?.toString() ?? '16') ?? 16;
    _mostrarGuiaCruzada = cfg['mostrar_guia_cruzada'] != false;
    _direccionEscritura =
        cfg['direccion_escritura']?.toString() ?? 'DERECHA_A_IZQUIERDA';

    _cantNumeros = int.tryParse(cfg['cantidad_numeros']?.toString() ?? '25') ?? 25;
    _prepararTableroSchulte(iniciar: false);
  }

  void _iniciarCronometro() {
    _timerPrincipal?.cancel();
    _tiempoMs = 0;
    _corriendo = true;
    _timerPrincipal = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && _corriendo) {
        setState(() => _tiempoMs += 100);
      }
    });
  }

  Future _evaluarJuegoEnServidor(String juegoId) async {
    final w = widget as MotoresJuegosCognitivos;
    _corriendo = false;
    _timerPrincipal?.cancel();
    _confettiCtrl.play();

    final Map res = await PuenteSupabaseSdui.llamarRpcNano(
      'nano_evaluar_juego_o_examen',
      {
        'p_app_id': PuenteSupabaseSdui.appIdActivo,
        'p_juego_id': juegoId,
        'p_respuestas': {
          'aciertos': _aciertos,
          'errores': _errores,
          'tiempo_ms': _tiempoMs,
          'usuario_id': EstadoGlobalSdui.instancia.leerRuta('sesion.usuario_id') ?? 'JUGADOR_SDUI',
        },
      },
    );

    final String msg = res['mensaje']?.toString() ??
        'Evaluado: $_aciertos aciertos en ${(_tiempoMs / 1000).toStringAsFixed(1)}s';
    w.onFeedback(msg);
    await BusHardwareUniversal.ejecutarComandoHardware(
      comando: 'HABLAR_TTS',
      argumentos: {'texto': msg},
    );
  }

  void _iniciarSecuenciaMemoria() {
    final w = widget as MotoresJuegosCognitivos;
    final int tMuestra =
        int.tryParse(w.configJson['tiempo_muestra_ms']?.toString() ?? '800') ?? 800;
    final int tIntervalo =
        int.tryParse(w.configJson['intervalo_ms']?.toString() ?? '200') ?? 200;
    final bool ocultar = w.configJson['modo_ocultar'] != false;

    _iniciarCronometro();
    setState(() {
      _idxMostrandoSecuencia = 0;
      _ocultandoSecuencia = false;
    });

    Timer.periodic(Duration(milliseconds: tMuestra + tIntervalo), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_idxMostrandoSecuencia < _itemsSecuencia.length - 1) {
        setState(() => _idxMostrandoSecuencia++);
      } else {
        t.cancel();
        setState(() {
          _idxMostrandoSecuencia = -1;
          _ocultandoSecuencia = ocultar;
        });
      }
    });
  }

  Widget _construirMotorSecuenciaMemoria() {
    final w = widget as MotoresJuegosCognitivos;
    final String itemActual = (_idxMostrandoSecuencia >= 0 &&
            _idxMostrandoSecuencia < _itemsSecuencia.length)
        ? _itemsSecuencia[_idxMostrandoSecuencia].toString()
        : (_ocultandoSecuencia ? '¿RECUERDAS LA SECUENCIA?' : 'LISTO (${_itemsSecuencia.length} ITEMS)');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF050B18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF00FF66), width: 1.5),
          ),
          child: Text(
            itemActual,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF00FF66),
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _ctrlRespuestaSecuencia,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Escribe los primeros o ultimos items recordados separados por coma...',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
            filled: true,
            fillColor: Colors.black,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('MOSTRAR SECUENCIA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                onPressed: _iniciarSecuenciaMemoria,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF66),
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.check_circle, size: 18),
                label: const Text('EVALUAR EN SERVIDOR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                onPressed: () {
                  _aciertos += 5;
                  _evaluarJuegoEnServidor(
                    w.configJson['juego_id']?.toString() ?? 'SEC_MEMORIA',
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _teclearDigitoPizarra(String digito) {
    final w = widget as MotoresJuegosCognitivos;
    HapticFeedback.selectionClick();
    setState(() {
      if (_direccionEscritura == 'DERECHA_A_IZQUIERDA') {
        _entradaPizarra = '$digito$_entradaPizarra';
      } else {
        _entradaPizarra = '$_entradaPizarra$digito';
      }
    });

    final int esperado = _operandoA * _operandoB;
    if (int.tryParse(_entradaPizarra) == esperado) {
      _aciertos++;
      _evaluarJuegoEnServidor(w.configJson['juego_id']?.toString() ?? 'PIZARRA_VEDICA');
      setState(() {
        _operandoA = 11 + _rng.nextInt(19);
        _operandoB = 11 + _rng.nextInt(19);
        _entradaPizarra = '';
      });
    }
  }

  Widget _construirMotorPizarraVedica() {
    final int a1 = _operandoA ~/ 10;
    final int a0 = _operandoA % 10;
    final int b1 = _operandoB ~/ 10;
    final int b0 = _operandoB % 10;
    final int paso1Unidades = a0 * b0;
    final int paso2Cruzado = (a1 * b0) + (a0 * b1) + (paso1Unidades ~/ 10);
    final int paso3Decenas = (a1 * b1) + (paso2Cruzado ~/ 10);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF050B18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF00F3FF)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Escritura: $_direccionEscritura',
                    style: const TextStyle(color: Color(0xFFFFD700), fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  InkWell(
                    onTap: () => setState(() => _mostrarGuiaCruzada = !_mostrarGuiaCruzada),
                    child: Text(
                      _mostrarGuiaCruzada ? 'Ocultar Guia Simetrica' : 'Ver Guia Simetrica',
                      style: const TextStyle(color: Color(0xFF00FF66), fontSize: 10.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '$_operandoA × $_operandoB = ${_entradaPizarra.isEmpty ? "?" : _entradaPizarra}',
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
              ),
              if (_mostrarGuiaCruzada) ...[
                const Divider(color: Colors.white24),
                Text(
                  'Paso 1 (Vertical Der): $a0×$b0 = $paso1Unidades (Escribe ${paso1Unidades % 10}, lleva ${paso1Unidades ~/ 10})\n'
                  'Paso 2 (Aspa Cruzada): ($a1×$b0)+($a0×$b1)+${paso1Unidades ~/ 10} = $paso2Cruzado (Escribe ${paso2Cruzado % 10}, lleva ${paso2Cruzado ~/ 10})\n'
                  'Paso 3 (Vertical Izq): ($a1×$b1)+${paso2Cruzado ~/ 10} = $paso3Decenas',
                  style: const TextStyle(color: Color(0xFF00FF66), fontSize: 11, height: 1.35),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            ...['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'].map(
              (d) => SizedBox(
                width: 56,
                height: 42,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF142033),
                    foregroundColor: const Color(0xFF00FF66),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () => _teclearDigitoPizarra(d),
                  child: Text(d, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              ),
            ),
            SizedBox(
              width: 90,
              height: 42,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                onPressed: () => setState(() => _entradaPizarra = ''),
                child: const Text('BORRAR', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _prepararTableroSchulte({required bool iniciar}) {
    final List lista = List.generate(_cantNumeros, (i) => i + 1)..shuffle(_rng);
    setState(() {
      _tableroNumeros = lista;
      _objetivoActual = 1;
      _chimpOculto = false;
      _corriendo = iniciar;
    });
    if (iniciar) _iniciarCronometro();
  }

  void _tocarCeldaSchulte(int n) {
    if (_modoToqueSchulte == 'SOLO_MENTAL') {
      if (!_corriendo) _prepararTableroSchulte(iniciar: true);
      return;
    }
    if (!_corriendo && n == 1) {
      _iniciarCronometro();
      setState(() {
        _objetivoActual = 2;
        if (_modoToqueSchulte == 'CHIMP') _chimpOculto = true;
      });
      return;
    }
    if (!_corriendo) return;
    if (n == _objetivoActual) {
      HapticFeedback.selectionClick();
      setState(() {
        _objetivoActual++;
        _aciertos++;
      });
      if (_objetivoActual > _cantNumeros) {
        _evaluarJuegoEnServidor('SCHULTE_$_cantNumeros');
      }
    } else {
      HapticFeedback.heavyImpact();
      _errores++;
    }
  }

  Widget _construirMotorMatrizYFisica2D() {
    final w = widget as MotoresJuegosCognitivos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              {'k': 'SCHULTE_CHIMP', 't': '1. Schulte 16-50 & Chimp'},
              {'k': 'GRID_MEMORY', 't': '2. Grid Memory NxN'},
              {'k': 'DRAG_SORTER_SWIPE', 't': '3. Sorter & Swipe V/F'},
              {'k': 'ALPHA_RAIN_2D', 't': '4. AlphaRain Fisica 2D'},
            ].map((m) {
              final bool sel = _subModoMatriz == m['k'];
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(
                    m['t']!,
                    style: TextStyle(color: sel ? Colors.black : Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  selected: sel,
                  selectedColor: const Color(0xFF00FF66),
                  backgroundColor: const Color(0xFF142033),
                  onSelected: (_) { setState(() => _subModoMatriz = m['k']!); if (_subModoMatriz == 'ALPHA_RAIN_2D') { _fisicaCtrl.repeat(); } else { _fisicaCtrl.stop(); } },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        if (_subModoMatriz == 'SCHULTE_CHIMP') ...[
          Wrap(
            spacing: 6,
            children: [16, 25, 30, 35, 50].map((c) {
              final bool s = _cantNumeros == c;
              return ChoiceChip(
                label: Text('$c Nums', style: TextStyle(color: s ? Colors.black : Colors.white, fontSize: 10)),
                selected: s,
                selectedColor: const Color(0xFF00F3FF),
                onSelected: (_) {
                  setState(() => _cantNumeros = c);
                  _prepararTableroSchulte(iniciar: false);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Row(
            children: ['PRESIONAR', 'SOLO_MENTAL', 'CHIMP'].map((modo) {
              final bool act = _modoToqueSchulte == modo;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: act ? const Color(0xFFFFD700) : Colors.black,
                    ),
                    onPressed: () {
                      setState(() => _modoToqueSchulte = modo);
                      _prepararTableroSchulte(iniciar: false);
                    },
                    child: Text(modo, style: TextStyle(color: act ? Colors.black : Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold)),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _cantNumeros == 16 ? 4 : 5,
              crossAxisSpacing: 5,
              mainAxisSpacing: 5,
              childAspectRatio: _cantNumeros >= 35 ? 1.3 : 1.05,
            ),
            itemCount: _tableroNumeros.length,
            itemBuilder: (ctx, i) {
              final int val = (_tableroNumeros[i] as num).toInt();
              final bool hecho = _modoToqueSchulte != 'SOLO_MENTAL' && val < _objetivoActual;
              return InkWell(
                onTap: () => _tocarCeldaSchulte(val),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: hecho ? const Color(0xFF052E16) : const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: hecho ? const Color(0xFF00FF66) : const Color(0xFF00F3FF)),
                  ),
                  child: Text(
                    _chimpOculto && !hecho ? '?' : '$val',
                    style: TextStyle(color: hecho ? Colors.white38 : Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                ),
              );
            },
          ),
        ],
        if (_subModoMatriz == 'GRID_MEMORY') ...[
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 1.3,
            ),
            itemCount: 16,
            itemBuilder: (ctx, idx) {
              final bool activa = (_mostrandoPatronGrid && _patronMemoria.contains(idx)) ||
                  (!_mostrandoPatronGrid && _patronTocadas.contains(idx));
              return InkWell(
                onTap: () {
                  setState(() => _patronTocadas.add(idx));
                  if (_patronTocadas.containsAll(_patronMemoria)) {
                    _aciertos += 4;
                    _evaluarJuegoEnServidor('GRID_MEMORY_4X4');
                  }
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: activa ? const Color(0xFF00FF66) : const Color(0xFF142033),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${idx + 1}', style: TextStyle(color: activa ? Colors.black : Colors.white)),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _patronTocadas.clear();
                _mostrandoPatronGrid = true;
              });
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => _mostrandoPatronGrid = false);
              });
            },
            child: const Text('DESTELLAR PATRON 2 SEGUNDOS'),
          ),
        ],
        if (_subModoMatriz == 'DRAG_SORTER_SWIPE') ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Draggable(
                data: _itemArrastrable,
                feedback: Material(
                  color: Colors.transparent,
                  child: Chip(label: Text(_itemArrastrable)),
                ),
                child: Chip(
                  backgroundColor: const Color(0xFF00F3FF),
                  label: Text('Arrastra: $_itemArrastrable', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
              DragTarget(
                onAcceptWithDetails: (d) {
                  _aciertos++;
                  _evaluarJuegoEnServidor('NUTRI_SORTER_DRAG');
                },
                builder: (ctx, cand, rej) => Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF052E16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF00FF66)),
                  ),
                  child: const Text('SUELTA AQUI (CANASTA BIO)', style: TextStyle(color: Color(0xFF00FF66), fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Dismissible(
            key: ValueKey('swipe_$_indiceSwipe'),
            onDismissed: (_) {
              setState(() => _indiceSwipe++);
              _aciertos++;
              w.onFeedback('Swipe V/F procesado (#$_indiceSwipe)');
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1B4B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFF00FC)),
              ),
              child: Text(
                'Tarjeta Swipe V/F #${_indiceSwipe + 1}: Desliza a izquierda (Falso) o derecha (Verdadero)',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
        if (_subModoMatriz == 'ALPHA_RAIN_2D') ...[
          Text(
            'Atrapa Capsula Cayendo: $_objetivoRain',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: AnimatedBuilder(
              animation: _fisicaCtrl,
              builder: (ctx, _) {
                return Stack(
                  children: List.generate(_capsulasRain.length, (i) {
                    final double topPos = ((_fisicaCtrl.value + (i * 0.18)) % 1.0) * 100;
                    final String cod = _capsulasRain[i].toString();
                    return Positioned(
                      left: (i * 52.0) % 260,
                      top: topPos,
                      child: InkWell(
                        onTap: () {
                          if (cod == _objetivoRain) {
                            _aciertos++;
                            _capsulasRain.shuffle(_rng);
                            setState(() => _objetivoRain = _capsulasRain.first.toString());
                            _evaluarJuegoEnServidor('ALPHA_RAIN_2D');
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1B4B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF00F3FF)),
                          ),
                          child: Text(cod, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Future _medirFrecuenciaHz() async {
    final w = widget as MotoresJuegosCognitivos;
    final Map res = await BusHardwareUniversal.ejecutarComandoHardware(
      comando: 'DETECTAR_TONO_HZ',
      argumentos: {},
    );
    if (!mounted) return;
    setState(() {
      _frecuenciaHzDetectada = double.tryParse(res['frecuencia_hz']?.toString() ?? '440.0') ?? 440.0;
      _clasificacionTono = res['clasificacion']?.toString() ?? 'Tono Medio';
    });
    w.onFeedback('Frecuencia detectada: $_frecuenciaHzDetectada Hz ($_clasificacionTono)');
  }

  void _activarTemporizadorBolsillo(int segundos) {
    final w = widget as MotoresJuegosCognitivos;
    _timerPrincipal?.cancel();
    setState(() => _segundosBolsillo = segundos);
    w.onFeedback('Modo Bolsillo: Hablara en $segundos segundos.');
    _timerPrincipal = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (_segundosBolsillo > 1) {
        if (mounted) {
          setState(() => _segundosBolsillo--);
        } else {
          _segundosBolsillo--;
        }
      } else {
        t.cancel();
        if (mounted) setState(() => _segundosBolsillo = 0);
        await BusHardwareUniversal.ejecutarComandoHardware(
          comando: 'HABLAR_TTS',
          argumentos: {'texto': _ctrlFraseBolsillo.text},
        );
      }
    });
  }

  Widget _construirMotorAudioVozTono() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF050B18),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFF00FC)),
          ),
          child: Column(
            children: [
              Text(
                'Frecuencia Vocal: ${_frecuenciaHzDetectada.toStringAsFixed(1)} Hz · $_clasificacionTono',
                style: const TextStyle(color: Color(0xFF00FF66), fontSize: 12.5, fontWeight: FontWeight.w900),
              ),
              if (_segundosBolsillo > 0)
                Text(
                  'Disparo en Bolsillo en: ${_segundosBolsillo}s',
                  style: const TextStyle(color: Color(0xFFFFD700), fontSize: 12, fontWeight: FontWeight.bold),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _ctrlFraseBolsillo,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.black,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF66), foregroundColor: Colors.black),
              icon: const Icon(Icons.volume_up, size: 16),
              label: const Text('HABLAR TTS AHORA', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
              onPressed: () => BusHardwareUniversal.ejecutarComandoHardware(
                comando: 'HABLAR_TTS',
                argumentos: {'texto': _ctrlFraseBolsillo.text},
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black),
              icon: const Icon(Icons.timer, size: 16),
              label: const Text('MODO BOLSILLO (5 SEG)', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
              onPressed: () => _activarTemporizadorBolsillo(5),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F3FF), foregroundColor: Colors.black),
              icon: const Icon(Icons.graphic_eq, size: 16),
              label: const Text('MEDIR TONO HZ (PITCH)', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
              onPressed: _medirFrecuenciaHz,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget as MotoresJuegosCognitivos;
    final String titulo = w.configJson['titulo']?.toString() ?? w.tipoMotor;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B132B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF00FF66), width: 1.5),
      ),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      titulo,
                      style: const TextStyle(color: Color(0xFF00FF66), fontSize: 13, fontWeight: FontWeight.w900),
                    ),
                  ),
                  Text(
                    '${(_tiempoMs / 1000).toStringAsFixed(1)}s · OK:$_aciertos',
                    style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (w.tipoMotor == 'MOTOR_SECUENCIA_MEMORIA') _construirMotorSecuenciaMemoria(),
              if (w.tipoMotor == 'MOTOR_PIZARRA_VEDICA') _construirMotorPizarraVedica(),
              if (w.tipoMotor == 'MOTOR_MATRIZ_Y_FISICA_2D') _construirMotorMatrizYFisica2D(),
              if (w.tipoMotor == 'MOTOR_AUDIO_VOZ_TONO') _construirMotorAudioVozTono(),
            ],
          ),
          ConfettiWidget(
            confettiController: _confettiCtrl,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
          ),
        ],
      ),
    );
  }
}