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

  String _subModoMatriz = 'SCHULTE';
  int _cantNumeros = 25;
  int _dimensionN = 5;
  String _modoToqueSchulte = 'PRESIONAR';
  List _tableroNumeros = [];
  int _objetivoActual = 1;
  bool _chimpOculto = false;
  Set _patronMemoria = {0, 4, 8, 12};
  final Set _patronTocadas = {};
  bool _mostrandoPatronGrid = false;
  String _itemArrastrable = 'Item';
  String _etiquetaMetaDrag = 'SOLTAR AQUI';
  int _indiceSwipe = 0;
  String _objetivoRain = 'A-7';
  List _capsulasRain = ['A-7', 'B-9', 'K-4', 'M-2', 'X-5', 'Z-1'];

  double _frecuenciaHzDetectada = 440.0;
  String _clasificacionTono = '';
  int _segundosBolsillo = 0;
  final TextEditingController _ctrlFraseBolsillo = TextEditingController();

  static Color _hexColor(String? hex, Color def) {
    if (hex == null || hex.trim().isEmpty) return def;
    String limpio = hex.replaceAll('#', '').trim();
    if (limpio.length == 6) limpio = 'FF$limpio';
    final int? val = int.tryParse(limpio, radix: 16);
    return val != null ? Color(val) : def;
  }

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
  void didUpdateWidget(covariant StatefulWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _inicializarParametrosDesdeJson();
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
      final String msgPausa =
          w.configJson['mensaje_antitrampas']?.toString() ?? 'Pausa detectada.';
      w.onFeedback(msgPausa);
    }
  }

  void _inicializarParametrosDesdeJson() {
    final w = widget as MotoresJuegosCognitivos;
    final Map cfg = w.configJson;

    final rawItems = cfg['items'];
    if (rawItems is List && rawItems.isNotEmpty) {
      _itemsSecuencia = rawItems.map((e) => e.toString()).toList();
    } else {
      final int nItems = int.tryParse(cfg['cantidad_items']?.toString() ?? '25') ?? 25;
      _itemsSecuencia = List.generate(nItems, (i) => '${i + 1}');
    }

    _operandoA = int.tryParse(cfg['operando_a']?.toString() ?? '14') ?? 14;
    _operandoB = int.tryParse(cfg['operando_b']?.toString() ?? '16') ?? 16;
    _mostrarGuiaCruzada = cfg['mostrar_guia_cruzada'] != false;
    _direccionEscritura =
        cfg['direccion_escritura']?.toString() ?? 'DERECHA_A_IZQUIERDA';

    _subModoMatriz =
        (cfg['submodo']?.toString() ?? 'SCHULTE').toUpperCase().trim();
    _cantNumeros = int.tryParse(cfg['cantidad_numeros']?.toString() ?? '25') ?? 25;
    _dimensionN = int.tryParse(
          cfg['dimension_n']?.toString() ?? (_cantNumeros == 16 ? '4' : '5'),
        ) ??
        5;
    _modoToqueSchulte = (cfg['modo_toque']?.toString() ??
            (_subModoMatriz == 'CHIMP' ? 'CHIMP' : 'PRESIONAR'))
        .toUpperCase()
        .trim();

    if (cfg['patron'] is List) {
      _patronMemoria = (cfg['patron'] as List)
          .map((e) => int.tryParse(e.toString()) ?? 0)
          .toSet();
    }

    _itemArrastrable = cfg['item_draggable']?.toString() ?? 'Elemento';
    _etiquetaMetaDrag = cfg['etiqueta_destino']?.toString() ?? 'SOLTAR AQUI';

    if (cfg['capsulas_rain'] is List && (cfg['capsulas_rain'] as List).isNotEmpty) {
      _capsulasRain =
          (cfg['capsulas_rain'] as List).map((e) => e.toString()).toList();
      _objetivoRain = cfg['objetivo_rain']?.toString() ?? _capsulasRain.first.toString();
    }

    if (_ctrlFraseBolsillo.text.isEmpty) {
      _ctrlFraseBolsillo.text = cfg['frase_inicial']?.toString() ?? '';
    }

    if (_subModoMatriz == 'ALPHA_RAIN' || _subModoMatriz == 'ALPHA_RAIN_2D') {
      _fisicaCtrl.repeat();
    } else {
      _fisicaCtrl.stop();
    }

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
          'submodo': _subModoMatriz,
          'usuario_id':
              EstadoGlobalSdui.instancia.leerRuta('sesion.usuario_id') ?? 'JUGADOR_SDUI',
        },
      },
    );

    final String msg = res['mensaje']?.toString() ??
        'OK: $_aciertos (${(_tiempoMs / 1000).toStringAsFixed(1)}s)';
    EstadoGlobalSdui.instancia.escribirRuta('sistema.ultimo_resultado_juego', msg);
    w.onFeedback(msg);

    if (w.configJson['hablar_al_evaluar'] == true) {
      await BusHardwareUniversal.ejecutarComandoHardware(
        comando: 'HABLAR_TTS',
        argumentos: {'texto': msg},
      );
    }
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
    final Map cfg = w.configJson;
    final Color colPrimario =
        _hexColor(cfg['color_primario']?.toString(), const Color(0xFF00FF66));
    final String txtEspera =
        cfg['texto_espera']?.toString() ?? '(${_itemsSecuencia.length})';
    final String txtOculto = cfg['texto_oculto']?.toString() ?? '?';
    final String placeholder = cfg['placeholder_respuesta']?.toString() ?? '';
    final String txtIniciar = cfg['texto_boton_iniciar']?.toString() ?? 'INICIAR';
    final String txtEvaluar = cfg['texto_boton_evaluar']?.toString() ?? 'EVALUAR';

    final String itemActual = (_idxMostrandoSecuencia >= 0 &&
            _idxMostrandoSecuencia < _itemsSecuencia.length)
        ? _itemsSecuencia[_idxMostrandoSecuencia].toString()
        : (_ocultandoSecuencia ? txtOculto : txtEspera);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF050B18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colPrimario, width: 1.5),
          ),
          child: Text(
            itemActual,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colPrimario,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _ctrlRespuestaSecuencia,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: placeholder,
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
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F3FF),
                  foregroundColor: Colors.black,
                ),
                onPressed: _iniciarSecuenciaMemoria,
                child: Text(
                  txtIniciar,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colPrimario,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  _aciertos++;
                  _evaluarJuegoEnServidor(
                    cfg['juego_id']?.toString() ?? 'SEC_MEMORIA',
                  );
                },
                child: Text(
                  txtEvaluar,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                ),
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
    final w = widget as MotoresJuegosCognitivos;
    final Map cfg = w.configJson;
    final String txtBorrar = cfg['texto_boton_borrar']?.toString() ?? 'C';
    final int a1 = _operandoA ~/ 10;
    final int a0 = _operandoA % 10;
    final int b1 = _operandoB ~/ 10;
    final int b0 = _operandoB % 10;
    final int paso1 = a0 * b0;
    final int paso2 = (a1 * b0) + (a0 * b1) + (paso1 ~/ 10);
    final int paso3 = (a1 * b1) + (paso2 ~/ 10);

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
              Text(
                '$_operandoA × $_operandoB = ${_entradaPizarra.isEmpty ? "?" : _entradaPizarra}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                ),
              ),
              if (_mostrarGuiaCruzada) ...[
                const Divider(color: Colors.white24),
                Text(
                  '1) $a0×$b0=$paso1  |  2) ($a1×$b0)+($a0×$b1)+${paso1 ~/ 10}=$paso2  |  3) ($a1×$b1)+${paso2 ~/ 10}=$paso3',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF00FF66), fontSize: 11),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            ...['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'].map(
              (d) => SizedBox(
                width: 52,
                height: 40,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF142033),
                    foregroundColor: const Color(0xFF00FF66),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () => _teclearDigitoPizarra(d),
                  child: Text(d, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                ),
              ),
            ),
            SizedBox(
              width: 64,
              height: 40,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                ),
                onPressed: () => setState(() => _entradaPizarra = ''),
                child: Text(txtBorrar, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
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
    final w = widget as MotoresJuegosCognitivos;
    if (_modoToqueSchulte == 'SOLO_MENTAL') {
      if (!_corriendo) {
        _prepararTableroSchulte(iniciar: true);
      } else {
        _aciertos = _cantNumeros;
        _evaluarJuegoEnServidor(w.configJson['juego_id']?.toString() ?? 'SCHULTE_MENTAL');
      }
      return;
    }
    if (!_corriendo && n == 1) {
      _iniciarCronometro();
      setState(() {
        _objetivoActual = 2;
        _aciertos = 1;
        if (_modoToqueSchulte == 'CHIMP' || _subModoMatriz == 'CHIMP') {
          _chimpOculto = true;
        }
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
        _evaluarJuegoEnServidor(w.configJson['juego_id']?.toString() ?? 'SCHULTE_$_cantNumeros');
      }
    } else {
      HapticFeedback.heavyImpact();
      _errores++;
    }
  }

  Widget _construirMotorMatrizYFisica2D() {
    final w = widget as MotoresJuegosCognitivos;
    final Map cfg = w.configJson;
    final Color colBorde =
        _hexColor(cfg['color_primario']?.toString(), const Color(0xFF00F3FF));

    if (_subModoMatriz == 'GRID_MEMORY') {
      final int totalCeldas = _dimensionN * _dimensionN;
      final String txtDestellar =
          cfg['texto_boton_iniciar']?.toString() ?? 'DESTELLAR PATRON';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _dimensionN,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 1.25,
            ),
            itemCount: totalCeldas,
            itemBuilder: (ctx, idx) {
              final bool activa = (_mostrandoPatronGrid && _patronMemoria.contains(idx)) ||
                  (!_mostrandoPatronGrid && _patronTocadas.contains(idx));
              return InkWell(
                onTap: () {
                  if (_mostrandoPatronGrid) return;
                  setState(() => _patronTocadas.add(idx));
                  if (_patronTocadas.containsAll(_patronMemoria)) {
                    _aciertos += _patronMemoria.length;
                    _evaluarJuegoEnServidor(cfg['juego_id']?.toString() ?? 'GRID_MEMORY');
                  }
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: activa ? const Color(0xFF00FF66) : const Color(0xFF142033),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colBorde),
                  ),
                  child: Text(
                    '${idx + 1}',
                    style: TextStyle(
                      color: activa ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colBorde,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              _iniciarCronometro();
              setState(() {
                _patronTocadas.clear();
                _mostrandoPatronGrid = true;
              });
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => _mostrandoPatronGrid = false);
              });
            },
            child: Text(txtDestellar, style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      );
    }

    if (_subModoMatriz == 'DRAG_SORTER' ||
        _subModoMatriz == 'SWIPE' ||
        _subModoMatriz == 'DRAG_SORTER_SWIPE') {
      final String txtSwipe = cfg['texto_swipe']?.toString() ?? 'Desliza V / F';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                  backgroundColor: colBorde,
                  label: Text(
                    _itemArrastrable,
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              DragTarget(
                onAcceptWithDetails: (_) {
                  _aciertos++;
                  _evaluarJuegoEnServidor(cfg['juego_id']?.toString() ?? 'SORTER_DRAG');
                },
                builder: (ctx, cand, rej) => Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF052E16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF00FF66)),
                  ),
                  child: Text(
                    _etiquetaMetaDrag,
                    style: const TextStyle(
                      color: Color(0xFF00FF66),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
              _evaluarJuegoEnServidor(cfg['juego_id']?.toString() ?? 'SWIPE_VF');
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1B4B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFF00FC)),
              ),
              child: Text(
                '$txtSwipe (#${_indiceSwipe + 1})',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (_subModoMatriz == 'ALPHA_RAIN' || _subModoMatriz == 'ALPHA_RAIN_2D') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '🎯 $_objetivoRain',
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
                            setState(
                              () => _objetivoRain = _capsulasRain.first.toString(),
                            );
                            _evaluarJuegoEnServidor(
                              cfg['juego_id']?.toString() ?? 'ALPHA_RAIN',
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1B4B),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: colBorde),
                          ),
                          child: Text(
                            cod,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _dimensionN,
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
              border: Border.all(
                color: hecho ? const Color(0xFF00FF66) : colBorde,
              ),
            ),
            child: Text(
              _chimpOculto && !hecho ? '?' : '$val',
              style: TextStyle(
                color: hecho ? Colors.white38 : Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
      },
    );
  }

  Future _medirFrecuenciaHz() async {
    final w = widget as MotoresJuegosCognitivos;
    final String freqSim =
        w.configJson['frecuencia_simulada']?.toString() ?? '440.0';
    final Map res = await BusHardwareUniversal.ejecutarComandoHardware(
      comando: 'DETECTAR_TONO_HZ',
      argumentos: {'frecuencia_simulada': freqSim},
    );
    if (!mounted) return;
    setState(() {
      _frecuenciaHzDetectada =
          double.tryParse(res['frecuencia_hz']?.toString() ?? '440.0') ?? 440.0;
      _clasificacionTono = res['clasificacion']?.toString() ?? '';
    });
    w.onFeedback('${_frecuenciaHzDetectada.toStringAsFixed(1)} Hz $_clasificacionTono');
  }

  void _activarTemporizadorBolsillo(int segundos) {
    final w = widget as MotoresJuegosCognitivos;
    _timerPrincipal?.cancel();
    setState(() => _segundosBolsillo = segundos);
    w.onFeedback('Temporizador bolsillo: ${segundos}s');
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
    final w = widget as MotoresJuegosCognitivos;
    final Map cfg = w.configJson;
    final int segsBolsillo =
        int.tryParse(cfg['segundos_bolsillo']?.toString() ?? '5') ?? 5;
    final String txtHablar = cfg['texto_boton_hablar']?.toString() ?? 'HABLAR TTS';
    final String txtBolsillo =
        cfg['texto_boton_bolsillo']?.toString() ?? 'BOLSILLO (${segsBolsillo}S)';
    final String txtPitch = cfg['texto_boton_pitch']?.toString() ?? 'TONO HZ';

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
                '${_frecuenciaHzDetectada.toStringAsFixed(1)} Hz ${_clasificacionTono.isEmpty ? "" : "· $_clasificacionTono"}',
                style: const TextStyle(
                  color: Color(0xFF00FF66),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (_segundosBolsillo > 0)
                Text(
                  '${_segundosBolsillo}s',
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _ctrlFraseBolsillo,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            hintText: cfg['placeholder_frase']?.toString() ?? '',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
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
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FF66),
                foregroundColor: Colors.black,
              ),
              onPressed: () => BusHardwareUniversal.ejecutarComandoHardware(
                comando: 'HABLAR_TTS',
                argumentos: {'texto': _ctrlFraseBolsillo.text},
              ),
              child: Text(
                txtHablar,
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.black,
              ),
              onPressed: () => _activarTemporizadorBolsillo(segsBolsillo),
              child: Text(
                txtBolsillo,
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00F3FF),
                foregroundColor: Colors.black,
              ),
              onPressed: _medirFrecuenciaHz,
              child: Text(
                txtPitch,
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget as MotoresJuegosCognitivos;
    final EstadoGlobalSdui estado = EstadoGlobalSdui.instancia;
    final String titulo =
        estado.interpolarTexto(w.configJson['titulo']?.toString() ?? '');
    final Color colBorde =
        _hexColor(w.configJson['color_borde']?.toString(), const Color(0xFF00FF66));

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B132B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colBorde, width: 1.5),
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
                  if (titulo.isNotEmpty)
                    Expanded(
                      child: Text(
                        titulo,
                        style: TextStyle(
                          color: colBorde,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  Text(
                    '${(_tiempoMs / 1000).toStringAsFixed(1)}s · $_aciertos',
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (w.tipoMotor == 'MOTOR_SECUENCIA_MEMORIA')
                _construirMotorSecuenciaMemoria(),
              if (w.tipoMotor == 'MOTOR_PIZARRA_VEDICA')
                _construirMotorPizarraVedica(),
              if (w.tipoMotor == 'MOTOR_MATRIZ_Y_FISICA_2D')
                _construirMotorMatrizYFisica2D(),
              if (w.tipoMotor == 'MOTOR_AUDIO_VOZ_TONO')
                _construirMotorAudioVozTono(),
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