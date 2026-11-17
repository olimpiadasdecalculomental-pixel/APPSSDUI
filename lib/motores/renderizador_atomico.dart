import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import '../nucleo/estado_global.dart';
import '../nucleo/puente_supabase.dart';
import '../nucleo/ejecutor_flujos.dart';
import 'motores_juegos_cognitivos.dart';
import 'bus_hardware_universal.dart';

class LienzoUniversalSdui extends StatefulWidget {
  const LienzoUniversalSdui({super.key});

  @override
  State createState() => _LienzoUniversalSduiState();
}

class _LienzoUniversalSduiState extends State {
  final PageController _pageCtrl = PageController();
  List _pantallas = [];
  int _idxPantalla = 0;
  bool _cargando = true;
  String _toastFeedback = '';

  @override
  void initState() {
    super.initState();
    _sincronizarPantallas();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _mostrarFeedback(String msg) {
    if (!mounted) return;
    setState(() => _toastFeedback = msg);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _toastFeedback == msg) {
        setState(() => _toastFeedback = '');
      }
    });
  }

  Future _sincronizarPantallas() async {
    if (mounted) setState(() => _cargando = true);
    final List lista = await PuenteSupabaseSdui.sincronizarPantallasConHash();
    if (!mounted) return;
    setState(() {
      _pantallas = lista;
      _idxPantalla = _idxPantalla.clamp(0, _pantallas.isEmpty ? 0 : _pantallas.length - 1);
      _cargando = false;
    });
  }

  void _navegarAPantalla(String pantallaId) {
    final int idx = _pantallas.indexWhere((p) => (p as Map)['pantalla_id']?.toString() == pantallaId);
    if (idx >= 0 && _pageCtrl.hasClients) {
      HapticFeedback.selectionClick();
      _pageCtrl.animateToPage(
        idx,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      setState(() => _idxPantalla = idx);
    } else {
      _mostrarFeedback('Pantalla destino: $pantallaId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = EstadoGlobalSdui.instancia;
    final String tituloActual = _pantallas.isNotEmpty
        ? ((_pantallas[_idxPantalla] as Map)['titulo']?.toString() ?? 'SDUI Universal')
        : 'Super-APK Universal SDUI';

    return Scaffold(
      backgroundColor: const Color(0xFF050814),
      appBar: AppBar(
        backgroundColor: const Color(0xFF091024),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tituloActual,
              style: const TextStyle(color: Color(0xFF00FF66), fontSize: 13.5, fontWeight: FontWeight.w900),
            ),
            Text(
              'Esquema: ${PuenteSupabaseSdui.esquemaActivo} · App: ${PuenteSupabaseSdui.appIdActivo} · Pag ${_idxPantalla + 1}/${_pantallas.isEmpty ? 1 : _pantallas.length}',
              style: const TextStyle(color: Colors.white60, fontSize: 10),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sincronizar JSON con Hash MD5',
            icon: const Icon(Icons.sync, color: Color(0xFF00F3FF)),
            onPressed: _sincronizarPantallas,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_cargando)
            const Center(child: CircularProgressIndicator(color: Color(0xFF00FF66)))
          else if (_pantallas.isEmpty)
            const Center(
              child: Text('Sin pantallas cargadas.', style: TextStyle(color: Colors.white70)),
            )
          else
            PageView.builder(
              controller: _pageCtrl,
              itemCount: _pantallas.length,
              onPageChanged: (i) => setState(() => _idxPantalla = i),
              itemBuilder: (ctx, idx) {
                final Map reg = Map.from(_pantallas[idx] as Map);
                final Map arbol = reg['arbol_json'] is Map
                    ? Map.from(reg['arbol_json'] as Map)
                    : {};

                return RefreshIndicator(
                  color: const Color(0xFF00FF66),
                  onRefresh: _sincronizarPantallas,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(14),
                    child: RenderizadorAtomicoSdui.construirNodo(
                      context: context,
                      nodoRaw: arbol,
                      estado: estado,
                      onNavegar: _navegarAPantalla,
                      onRecargar: _sincronizarPantallas,
                      onFeedback: _mostrarFeedback,
                    ),
                  ),
                );
              },
            ),
          if (_toastFeedback.isNotEmpty)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1428),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF00FF66), width: 1.5),
                ),
                child: Text(
                  _toastFeedback,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF00FF66), fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RenderizadorAtomicoSdui {
  static Color parsearColor(String? hex, [Color fallback = const Color(0xFF00F3FF)]) {
    if (hex == null || hex.trim().isEmpty) return fallback;
    String limpio = hex.replaceAll('#', '').trim();
    if (limpio.length == 6) limpio = 'FF$limpio';
    final int? val = int.tryParse(limpio, radix: 16);
    return val != null ? Color(val) : fallback;
  }

  static Widget construirNodo({
    required BuildContext context,
    required Map nodoRaw,
    required EstadoGlobalSdui estado,
    required void Function(String) onNavegar,
    required Future Function() onRecargar,
    required void Function(String) onFeedback,
  }) {
    final String tipo = (nodoRaw['type']?.toString() ?? nodoRaw['tipo']?.toString() ?? 'card').trim();
    final String tipoUpper = tipo.toUpperCase();

    if (tipoUpper == 'MOTOR_SECUENCIA_MEMORIA' ||
        tipoUpper == 'MOTOR_PIZARRA_VEDICA' ||
        tipoUpper == 'MOTOR_MATRIZ_Y_FISICA_2D' ||
        tipoUpper == 'MOTOR_AUDIO_VOZ_TONO') {
      return MotoresJuegosCognitivos(
        tipoMotor: tipoUpper,
        configJson: nodoRaw,
        onFeedback: onFeedback,
      );
    }

    if (tipoUpper == 'BUS_HARDWARE_UNIVERSAL') {
      return BusHardwareUniversalWidget(
        configJson: nodoRaw,
        onFeedback: onFeedback,
      );
    }

    final List hijosRaw = (nodoRaw['children'] as List?) ?? [];

    switch (tipo.toLowerCase()) {
      case 'scaffold':
      case 'column':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: hijosRaw
              .map((e) => e as Map)
              .map((h) => construirNodo(
                    context: context,
                    nodoRaw: Map.from(h),
                    estado: estado,
                    onNavegar: onNavegar,
                    onRecargar: onRecargar,
                    onFeedback: onFeedback,
                  ))
              .toList(),
        );

      case 'row':
        return Row(
          children: hijosRaw
              .map((e) => e as Map)
              .map((h) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: construirNodo(
                        context: context,
                        nodoRaw: Map.from(h),
                        estado: estado,
                        onNavegar: onNavegar,
                        onRecargar: onRecargar,
                        onFeedback: onFeedback,
                      ),
                    ),
                  ))
              .toList(),
        );

      case 'stack':
        return Stack(
          children: hijosRaw
              .map((e) => e as Map)
              .map((h) => construirNodo(
                    context: context,
                    nodoRaw: Map.from(h),
                    estado: estado,
                    onNavegar: onNavegar,
                    onRecargar: onRecargar,
                    onFeedback: onFeedback,
                  ))
              .toList(),
        );

      case 'text':
        final String texto = estado.interpolarTexto(nodoRaw['data']?.toString() ?? nodoRaw['texto']?.toString() ?? '');
        final Color colorTxt = parsearColor(nodoRaw['color']?.toString(), Colors.white);
        final double fontSize = double.tryParse(nodoRaw['size']?.toString() ?? '13') ?? 13.0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            texto,
            style: TextStyle(color: colorTxt, fontSize: fontSize, fontWeight: FontWeight.w600),
          ),
        );

      case 'input':
        final String campo = nodoRaw['campo']?.toString() ?? 'input_generico';
        final String label = estado.interpolarTexto(nodoRaw['label']?.toString() ?? '');
        final String placeholder = estado.interpolarTexto(nodoRaw['placeholder']?.toString() ?? '');
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(label, style: const TextStyle(color: Color(0xFFA9C7FF), fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              TextField(
                obscureText: nodoRaw['password'] == true,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: placeholder,
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 11.5),
                  filled: true,
                  fillColor: const Color(0xFF0A1020),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF00F3FF)),
                  ),
                ),
                onChanged: (val) => estado.escribirRuta('form.$campo', val, notificar: false),
              ),
            ],
          ),
        );

      case 'button':
        final String textoBtn = estado.interpolarTexto(nodoRaw['texto']?.toString() ?? 'EJECUTAR');
        final Color bgCol = parsearColor(nodoRaw['color']?.toString(), const Color(0xFF00FF66));
        final Color fgCol = parsearColor(nodoRaw['color_texto']?.toString(), Colors.black);
        final List flujo = (nodoRaw['flujo_acciones'] as List?) ?? [];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: bgCol,
              foregroundColor: fgCol,
              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              EjecutorFlujosSdui.ejecutarCadena(
                context: context,
                flujoAcciones: flujo,
                onNavegar: onNavegar,
                onRecargarPantallas: onRecargar,
                onFeedback: onFeedback,
              );
            },
            child: Text(textoBtn, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
          ),
        );

      case 'listview':
        return _ListaAtomicaUniversalWidget(
          nodoRaw: nodoRaw,
          onFeedback: onFeedback,
          onNavegar: onNavegar,
          onRecargar: onRecargar,
        );

      case 'gridview':
        final int cols = int.tryParse(nodoRaw['columnas']?.toString() ?? '2') ?? 2;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: cols,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.2,
          children: hijosRaw
              .map((h) => h is Map
                  ? construirNodo(
                      context: context,
                      nodoRaw: Map.from(h),
                      estado: estado,
                      onNavegar: onNavegar,
                      onRecargar: onRecargar,
                      onFeedback: onFeedback,
                    )
                  : const SizedBox.shrink())
              .toList(),
        );

      case 'tabs':
        final List pestanas = (nodoRaw['tabs'] as List?) ?? ['Tab 1', 'Tab 2'];
        return DefaultTabController(
          length: pestanas.length,
          child: Column(
            children: [
              TabBar(
                indicatorColor: const Color(0xFF00FF66),
                labelColor: const Color(0xFF00FF66),
                unselectedLabelColor: Colors.white60,
                tabs: pestanas.map((t) => Tab(text: t.toString())).toList(),
              ),
              SizedBox(
                height: double.tryParse(nodoRaw['altura']?.toString() ?? '320') ?? 320,
                child: TabBarView(
                  children: hijosRaw
                      .map((h) => h is Map
                          ? construirNodo(
                              context: context,
                              nodoRaw: Map.from(h),
                              estado: estado,
                              onNavegar: onNavegar,
                              onRecargar: onRecargar,
                              onFeedback: onFeedback,
                            )
                          : const SizedBox.shrink())
                      .toList(),
                ),
              ),
            ],
          ),
        );

      case 'modal':
        final String txtTrigger = estado.interpolarTexto(nodoRaw['texto_boton']?.toString() ?? 'Abrir Modal');
        return OutlinedButton(
          style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF00F3FF))),
          onPressed: () {
            showModalBottomSheet(
              context: context,
              backgroundColor: const Color(0xFF081024),
              builder: (ctx) => Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: hijosRaw
                        .map((h) => h is Map
                            ? construirNodo(
                                context: ctx,
                                nodoRaw: Map.from(h),
                                estado: estado,
                                onNavegar: onNavegar,
                                onRecargar: onRecargar,
                                onFeedback: onFeedback,
                              )
                            : const SizedBox.shrink())
                        .toList(),
                  ),
                ),
              ),
            );
          },
          child: Text(txtTrigger, style: const TextStyle(color: Color(0xFF00F3FF), fontWeight: FontWeight.bold)),
        );

      case 'chart':
        return Container(
          height: 190,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF091224),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFD700)),
          ),
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: true),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: true),
              lineBarsData: [
                LineChartBarData(
                  spots: const [
                    FlSpot(0, 1.5),
                    FlSpot(1, 2.8),
                    FlSpot(2, 2.3),
                    FlSpot(3, 4.5),
                    FlSpot(4, 3.9),
                    FlSpot(5, 6.2),
                  ],
                  isCurved: true,
                  color: const Color(0xFF00FF66),
                  barWidth: 3,
                ),
              ],
            ),
          ),
        );

      case 'card':
      default:
        final Color bordeCol = parsearColor(nodoRaw['color_borde']?.toString(), const Color(0xFF00F3FF));
        final String tit = estado.interpolarTexto(nodoRaw['titulo']?.toString() ?? '');
        final String sub = estado.interpolarTexto(nodoRaw['subtitulo']?.toString() ?? '');
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0B132B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: bordeCol, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (tit.isNotEmpty)
                Text(tit, style: TextStyle(color: bordeCol, fontSize: 14, fontWeight: FontWeight.w900)),
              if (sub.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 10),
                  child: Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                ),
              ...hijosRaw.map((h) => h is Map
                  ? construirNodo(
                      context: context,
                      nodoRaw: Map.from(h),
                      estado: estado,
                      onNavegar: onNavegar,
                      onRecargar: onRecargar,
                      onFeedback: onFeedback,
                    )
                  : const SizedBox.shrink()),
            ],
          ),
        );
    }
  }
}

class _ListaAtomicaUniversalWidget extends StatefulWidget {
  final Map nodoRaw;
  final void Function(String) onFeedback;
  final void Function(String) onNavegar;
  final Future Function() onRecargar;

  const _ListaAtomicaUniversalWidget({
    required this.nodoRaw,
    required this.onFeedback,
    required this.onNavegar,
    required this.onRecargar,
  });

  @override
  State createState() => _ListaAtomicaUniversalWidgetState();
}

class _ListaAtomicaUniversalWidgetState extends State {
  List _itemsRemotos = [];
  String? _siguienteCursor;
  bool _cargandoTop10 = false;
  int _tipoListaDemo = 0;
  final Map _cantidadesStepper = {0: 2, 1: 1, 2: 3};
  final Set _checksActivos = {0, 2};
  final Map _switchesActivos = {0: true, 1: false, 2: true};
  String _radioSeleccionado = 'OPCION_1';

  @override
  void initState() {
    super.initState();
    final Map nodo = (widget as _ListaAtomicaUniversalWidget).nodoRaw;
    final String modo = nodo['modo']?.toString() ?? 'estatico';
    if (modo == 'cursor_top10') {
      _consultarCursorTop10(reiniciar: true);
    }
  }

  Future _consultarCursorTop10({bool reiniciar = false}) async {
    setState(() => _cargandoTop10 = true);
    final Map nodo = (widget as _ListaAtomicaUniversalWidget).nodoRaw;
    final String col = nodo['coleccion']?.toString() ?? 'RECORDS_COGNITIVOS';
    final Map res = await PuenteSupabaseSdui.llamarRpcNano(
      'nano_buscar_top10',
      {
        'p_app_id': PuenteSupabaseSdui.appIdActivo,
        'p_coleccion': col,
        'p_filtro': nodo['filtro'] ?? {},
        'p_cursor_fecha': reiniciar ? null : _siguienteCursor,
      },
    );
    if (!mounted) return;
    setState(() {
      _cargandoTop10 = false;
      if (res['items'] is List) {
        _itemsRemotos = List.from(res['items'] as List);
        _siguienteCursor = res['siguiente_cursor']?.toString();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget as _ListaAtomicaUniversalWidget;
    final String modo = w.nodoRaw['modo']?.toString() ?? 'catalogo_8_listas';
    final String titulo = w.nodoRaw['titulo']?.toString() ?? 'Lista Universal SDUI';

    if (modo == 'vertical_paging') {
      final List items = (w.nodoRaw['items'] as List?) ??
          ['Reel SDUI #1 (Vertical Paging)', 'Reel SDUI #2 (TikTok Feed)', 'Reel SDUI #3 (Stream 9:16)'];
      return Container(
        height: 260,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFF00FC)),
        ),
        child: PageView.builder(
          scrollDirection: Axis.vertical,
          itemCount: items.length,
          itemBuilder: (ctx, i) => Center(
            child: Text(
              items[i].toString(),
              style: const TextStyle(color: Color(0xFF00FF66), fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      );
    }

    if (modo == 'cursor_top10') {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0B132B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF00F3FF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(titulo, style: const TextStyle(color: Color(0xFF00F3FF), fontSize: 12.5, fontWeight: FontWeight.w900)),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Color(0xFF00FF66), size: 18),
                  onPressed: () => _consultarCursorTop10(reiniciar: true),
                ),
              ],
            ),
            if (_cargandoTop10)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_itemsRemotos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Sin registros en esta coleccion aun.', style: TextStyle(color: Colors.white60, fontSize: 11.5)),
              )
            else
              ..._itemsRemotos.map((rawIt) {
                final Map it = rawIt is Map ? rawIt : {};
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF142033), borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    '${it['propietario_id'] ?? 'ID'} · [${it['estado']}] · ${it['datos']}',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                );
              }),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _consultarCursorTop10(reiniciar: false),
                  child: const Text('SIGUIENTE CURSOR (LIMIT 10) ▶', style: TextStyle(color: Color(0xFFFFD700), fontSize: 11)),
                ),
              ],
            ),
          ],
        ),
      );
    }

    const List nombresTecnicos = [
      '1. ActionButtonListView (Botones Aprobar/Ejecutar)',
      '2. StepperQuantityListView (Contadores [-] y [+])',
      '3. CheckboxBatchListView (Seleccion por Lote)',
      '4. SwitchToggleListView (Interruptores ON/OFF)',
      '5. RadioExclusiveListView (Seleccion Unica)',
      '6. AccordionExpansionListView (Cajon Desplegable)',
      '7. QuickToolbarCardList (Barra Voz/Copiar/QR)',
      '8. CursorPaginatedTop10List (B-Tree LIMIT 10)',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B132B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD700)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titulo, style: const TextStyle(color: Color(0xFFFFD700), fontSize: 13, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(nombresTecnicos.length, (i) {
                final bool sel = _tipoListaDemo == i;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text('Tipo #${i + 1}', style: TextStyle(color: sel ? Colors.black : Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold)),
                    selected: sel,
                    selectedColor: const Color(0xFF00FF66),
                    backgroundColor: const Color(0xFF142033),
                    onSelected: (_) => setState(() => _tipoListaDemo = i),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            nombresTecnicos[_tipoListaDemo].toString(),
            style: const TextStyle(color: Color(0xFF00F3FF), fontSize: 11.5, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 8),
          ...List.generate(3, (i) {
            if (_tipoListaDemo == 1) {
              final int cant = (_cantidadesStepper[i] as int?) ?? 1;
              return ListTile(
                dense: true,
                title: Text('Item Inventario #${i + 1} (Stepper)', style: const TextStyle(color: Colors.white, fontSize: 12)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.remove_circle, color: Colors.redAccent), onPressed: () => setState(() => _cantidadesStepper[i] = cant > 0 ? cant - 1 : 0)),
                    Text('$cant', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.add_circle, color: Color(0xFF00FF66)), onPressed: () => setState(() => _cantidadesStepper[i] = cant + 1)),
                  ],
                ),
              );
            }
            if (_tipoListaDemo == 2) {
              return CheckboxListTile(
                dense: true,
                value: _checksActivos.contains(i),
                activeColor: const Color(0xFFFFD700),
                checkColor: Colors.black,
                title: Text('Registro Seleccionable #${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                onChanged: (v) => setState(() => v == true ? _checksActivos.add(i) : _checksActivos.remove(i)),
              );
            }
            if (_tipoListaDemo == 3) {
              return SwitchListTile(
                dense: true,
                value: (_switchesActivos[i] as bool?) ?? false,
                activeColor: const Color(0xFF00FF66),
                title: Text('Permiso / Sensor Activo #${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                onChanged: (v) => setState(() => _switchesActivos[i] = v),
              );
            }
            if (_tipoListaDemo == 4) {
              final String valOp = 'OPCION_${i + 1}';
              return RadioListTile(
                dense: true,
                value: valOp,
                groupValue: _radioSeleccionado,
                activeColor: const Color(0xFF00F3FF),
                title: Text('Opcion Exclusiva #${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                onChanged: (v) => setState(() => _radioSeleccionado = v?.toString() ?? valOp),
              );
            }
            if (_tipoListaDemo == 5) {
              return ExpansionTile(
                title: Text('Fila Desplegable #${i + 1} (ExpansionTile)', style: const TextStyle(color: Colors.white, fontSize: 12)),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: ElevatedButton(
                      onPressed: () => w.onFeedback('Sub-accion ejecutada en fila #${i + 1}'),
                      child: const Text('EJECUTAR SUB-ACCION'),
                    ),
                  ),
                ],
              );
            }
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF142033), borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Fila Interactiva #${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11.5)),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF66), foregroundColor: Colors.black),
                    onPressed: () => w.onFeedback('Accion ejecutada en fila #${i + 1}'),
                    child: const Text('ACCION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}