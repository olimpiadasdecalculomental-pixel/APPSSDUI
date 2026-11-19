import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:shimmer/shimmer.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:drag_and_drop_lists/drag_and_drop_lists.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:toastification/toastification.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:highlight/highlight.dart' as hl_pkg;
import 'package:graphview/GraphView.dart';
import 'package:diff_match_patch/diff_match_patch.dart';

import '../nucleo/estado_global.dart';
import '../nucleo/puente_supabase.dart';
import '../nucleo/ejecutor_flujos.dart';
import 'motores_juegos_cognitivos.dart';
import 'bus_hardware_universal.dart';
import 'widgets_stitch_media.dart';

class LienzoUniversalSdui extends StatefulWidget {
  const LienzoUniversalSdui({super.key});
  @override
  State<LienzoUniversalSdui> createState() => _LienzoUniversalSduiState();
}

class _LienzoUniversalSduiState extends State<LienzoUniversalSdui> {
  final PageController _pageCtrl = PageController();
  List _pantallas = [];
  int _idxPantalla = 0;
  bool _cargando = true;

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
    toastification.show(
      context: context,
      title: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      type: msg.toLowerCase().contains('error') ? ToastificationType.error : ToastificationType.success,
      style: ToastificationStyle.fillColored,
      autoCloseDuration: const Duration(seconds: 3),
      alignment: Alignment.bottomCenter,
      showProgressBar: false,
    );
  }

  Future _sincronizarPantallas() async {
    if (mounted) setState(() => _cargando = true);
    final List listaCruda = await PuenteSupabaseSdui.sincronizarPantallasConHash();
    if (!mounted) return;
    final String rolUsuario = (EstadoGlobalSdui.instancia.leerRuta('sesion.rol')?.toString() ?? 'TODOS').toUpperCase().trim();
    final List filtradas = listaCruda.where((item) {
      if (item is! Map) return false;
      final String rolReq = (item['rol_requerido']?.toString() ?? 'TODOS').toUpperCase().trim();
      return rolReq.isEmpty || rolReq == 'TODOS' || rolUsuario == 'ADMIN' || rolReq == rolUsuario;
    }).toList();
    final int idxSeguro = filtradas.isEmpty ? 0 : _idxPantalla.clamp(0, filtradas.length - 1);
    setState(() {
      _pantallas = filtradas;
      _idxPantalla = idxSeguro;
      _cargando = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageCtrl.hasClients && _pantallas.isNotEmpty) {
        final int pagActual = (_pageCtrl.page?.round() ?? 0);
        if (pagActual >= _pantallas.length) _pageCtrl.jumpToPage(_idxPantalla);
      }
    });
  }

  void _navegarAPantalla(String pantallaId) {
    if (_pantallas.isEmpty) return;
    final int idx = _pantallas.indexWhere((p) => (p as Map)['pantalla_id']?.toString() == pantallaId);
    if (idx >= 0 && idx < _pantallas.length && _pageCtrl.hasClients) {
      HapticFeedback.selectionClick();
      _pageCtrl.animateToPage(idx, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
      setState(() => _idxPantalla = idx);
    } else {
      _mostrarFeedback('Pantalla destino: $pantallaId');
    }
  }

  Map _parsearArbolActual(int idx) {
    if (_pantallas.isEmpty || idx < 0 || idx >= _pantallas.length) return {};
    final Map reg = Map.from(_pantallas[idx] as Map);
    final dynamic rawArbol = reg['arbol_json'];
    if (rawArbol is Map) return Map.from(rawArbol);
    if (rawArbol is String && rawArbol.trim().isNotEmpty) {
      try {
        final dec = jsonDecode(rawArbol.trim());
        if (dec is Map) return Map.from(dec);
      } catch (_) {}
    }
    return {};
  }

  @override
  Widget build(BuildContext context) {
    final estado = EstadoGlobalSdui.instancia;
    final Color colPrim = RenderizadorAtomicoSdui.parsearColor(estado.leerRuta('sistema.color_primario')?.toString(), const Color(0xFF00FF66));
    final Color colSec = RenderizadorAtomicoSdui.parsearColor(estado.leerRuta('sistema.color_secundario')?.toString(), const Color(0xFF00F3FF));
    final int idxSeguro = _pantallas.isEmpty ? 0 : _idxPantalla.clamp(0, _pantallas.length - 1);
    final Map arbolActual = _parsearArbolActual(idxSeguro);
    
    final bool ocultarAppBar = arbolActual['pantalla_completa'] == true ||
        arbolActual['ocultar_appbar'] == true ||
        estado.leerRuta('sistema.pantalla_completa') == true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ocultarAppBar) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    });

    final String tituloActual = _pantallas.isNotEmpty ? ((_pantallas[idxSeguro] as Map)['titulo']?.toString() ?? 'SDUI Universal') : '0 pantallas activas';
    final String rolActivo = estado.leerRuta('sesion.rol')?.toString() ?? 'TODOS';

    return Scaffold(
      backgroundColor: const Color(0xFF050814),
      appBar: ocultarAppBar
          ? null
          : AppBar(
              backgroundColor: const Color(0xFF091024),
              elevation: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tituloActual, style: GoogleFonts.orbitron(color: colPrim, fontSize: 13, fontWeight: FontWeight.w900)),
                  Text('Esq: ${PuenteSupabaseSdui.esquemaActivo} · App: ${PuenteSupabaseSdui.appIdActivo} · Rol: $rolActivo · Pag ${_pantallas.isEmpty ? 0 : idxSeguro + 1}/${_pantallas.length}',
                      style: const TextStyle(color: Colors.white60, fontSize: 10)),
                ],
              ),
              actions: [
                IconButton(tooltip: 'Sincronizar JSON', icon: Icon(Icons.sync, color: colSec), onPressed: _sincronizarPantallas),
              ],
            ),
      body: SafeArea(
        top: !ocultarAppBar,
        bottom: !ocultarAppBar,
        child: _cargando
            ? Center(child: CircularProgressIndicator(color: colPrim))
            : _pantallas.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.layers_clear, color: colSec, size: 42),
                          const SizedBox(height: 12),
                          const Text('0 pantallas activas en este esquema/app', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: colPrim, foregroundColor: Colors.black),
                            icon: const Icon(Icons.sync, size: 18),
                            label: const Text('REINTENTAR SINCRONIZACION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                            onPressed: _sincronizarPantallas,
                          ),
                        ],
                      ),
                    ),
                  )
                : PageView.builder(
                    controller: _pageCtrl,
                    itemCount: _pantallas.length,
                    onPageChanged: (i) {
                      if (i >= 0 && i < _pantallas.length) setState(() => _idxPantalla = i);
                    },
                    itemBuilder: (ctx, idx) {
                      if (idx < 0 || idx >= _pantallas.length) return const SizedBox.shrink();
                      final Map arbol = _parsearArbolActual(idx);
                      return RefreshIndicator(
                        color: colPrim,
                        onRefresh: _sincronizarPantallas,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(14),
                          child: AnimatedBuilder(
                            animation: estado,
                            builder: (context, _) => RenderizadorAtomicoSdui.construirNodo(
                              context: context,
                              nodoRaw: arbol,
                              estado: estado,
                              onNavegar: _navegarAPantalla,
                              onRecargar: _sincronizarPantallas,
                              onFeedback: _mostrarFeedback,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
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

  static List _extraerSpotsDinamicos(Map nodoRaw, EstadoGlobalSdui estado) {
    List fuente = [];
    final String rutaDatos = nodoRaw['ruta_puntos']?.toString() ?? nodoRaw['origen_datos']?.toString() ?? '';
    final String campoY = nodoRaw['campo_y']?.toString() ?? 'valor';
    if (rutaDatos.trim().isNotEmpty) {
      final String rutaLimpia = rutaDatos.replaceAll('{{', '').replaceAll('}}', '').trim();
      final dynamic leido = estado.leerRuta(rutaLimpia);
      if (leido is List) {
        fuente = leido;
      } else if (leido is Map && leido['items'] is List) {
        fuente = leido['items'] as List;
      }
    }
    if (fuente.isEmpty && nodoRaw['puntos'] is List) fuente = nodoRaw['puntos'] as List;
    if (fuente.isEmpty) fuente = [1.5, 2.8, 2.3, 4.5, 3.9, 6.2];

    final List spots = [];
    for (int i = 0; i < fuente.length; i++) {
      final dynamic elem = fuente[i];
      double valY = 1.0;
      if (elem is num) {
        valY = elem.toDouble();
      } else if (elem is Map) {
        final dynamic cand = elem[campoY] ?? elem['total'] ?? elem['monto'] ?? elem['puntaje'] ?? elem['aciertos'] ?? (elem['datos'] is Map ? (elem['datos'] as Map)[campoY] : null) ?? 1.0;
        valY = double.tryParse(cand.toString()) ?? 1.0;
      } else {
        valY = double.tryParse(estado.interpolarTexto(elem.toString())) ?? 1.0;
      }
      spots.add(FlSpot(i.toDouble(), valY));
    }
    return spots;
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

    if (tipoUpper == 'MOTOR_SECUENCIA_MEMORIA' || tipoUpper == 'MOTOR_PIZARRA_VEDICA' || tipoUpper == 'MOTOR_MATRIZ_Y_FISICA_2D' || tipoUpper == 'MOTOR_AUDIO_VOZ_TONO') {
      return MotoresJuegosCognitivos(tipoMotor: tipoUpper, configJson: nodoRaw, onFeedback: onFeedback);
    }
    if (tipoUpper == 'SDUI_QR_VIEW' || tipoUpper == 'BUS_HARDWARE_UNIVERSAL') {
      return SduiQrViewAtomico(nodoRaw: nodoRaw, onFeedback: onFeedback);
    }
    if (tipoUpper == 'SDUI_CALENDARIO') {
      return SduiCalendarioAtomico(nodoRaw: nodoRaw, onFeedback: onFeedback);
    }
    if (tipoUpper == 'SDUI_CUBO_3D') {
      return SduiCubo3dAtomico(nodoRaw: nodoRaw);
    }

    final List hijosRaw = (nodoRaw['children'] as List?) ?? [];

    switch (tipo.toLowerCase()) {
      case 'video_universal':
        return VideoUniversalSdui(nodoRaw: nodoRaw);
      
      case 'escaner_qr':
        return EscanerQrSdui(nodoRaw: nodoRaw, onFeedback: onFeedback);
      
      case 'icono':
        final List flujo = (nodoRaw['flujo_acciones'] as List?) ?? [];
        final widgetIcono = IconoSdui(nodoRaw: nodoRaw, estado: estado);
        if (flujo.isNotEmpty) {
          return GestureDetector(
            onTap: () => EjecutorFlujosSdui.ejecutarCadena(context: context, flujoAcciones: flujo, onNavegar: onNavegar, onRecargarPantallas: onRecargar, onFeedback: onFeedback),
            child: widgetIcono,
          );
        }
        return widgetIcono;

      case 'scaffold':
      case 'column':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: hijosRaw.map((h) => h is Map ? construirNodo(context: context, nodoRaw: Map.from(h), estado: estado, onNavegar: onNavegar, onRecargar: onRecargar, onFeedback: onFeedback) : const SizedBox.shrink()).toList(),
        );

      case 'row':
        return Row(
          children: hijosRaw.map((h) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: h is Map ? construirNodo(context: context, nodoRaw: Map.from(h), estado: estado, onNavegar: onNavegar, onRecargar: onRecargar, onFeedback: onFeedback) : const SizedBox.shrink()))).toList(),
        );

      case 'stack':
        return Stack(
          children: hijosRaw.map((h) => h is Map ? construirNodo(context: context, nodoRaw: Map.from(h), estado: estado, onNavegar: onNavegar, onRecargar: onRecargar, onFeedback: onFeedback) : const SizedBox.shrink()).toList(),
        );

      case 'lottie':
        final String urlAnm = estado.interpolarTexto(nodoRaw['url']?.toString() ?? '');
        final double hLottie = double.tryParse(nodoRaw['altura']?.toString() ?? '150') ?? 150.0;
        if (urlAnm.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: hLottie,
          child: urlAnm.startsWith('http') ? Lottie.network(urlAnm) : Lottie.asset(urlAnm),
        );

      case 'markdown':
        final String mdText = estado.interpolarTexto(nodoRaw['data']?.toString() ?? nodoRaw['texto']?.toString() ?? '');
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: MarkdownBody(
            data: mdText,
            styleSheet: MarkdownStyleSheet(
              p: const TextStyle(color: Colors.white, fontSize: 13),
              h1: const TextStyle(color: Color(0xFF00FF66), fontSize: 20, fontWeight: FontWeight.bold),
              h2: const TextStyle(color: Color(0xFF00F3FF), fontSize: 18, fontWeight: FontWeight.bold),
              code: const TextStyle(color: Color(0xFFFFD700), backgroundColor: Color(0xFF142033), fontFamily: 'monospace'),
            ),
          ),
        );

      case 'codigo':
        final String lang = nodoRaw['lenguaje']?.toString() ?? 'json';
        final String codigoTxt = estado.interpolarTexto(nodoRaw['data']?.toString() ?? '');
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: HighlightView(
              codigoTxt,
              language: lang,
              theme: {'root': const TextStyle(backgroundColor: Color(0xFF0D1B2A), color: Colors.white70)},
              padding: const EdgeInsets.all(12),
              textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        );

      case 'comparador_texto':
        final String textA = estado.interpolarTexto(nodoRaw['texto_a']?.toString() ?? '');
        final String textB = estado.interpolarTexto(nodoRaw['texto_b']?.toString() ?? '');
        final List<Diff> diffs = diff(textA, textB);
        cleanupSemantic(diffs);
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF142033), borderRadius: BorderRadius.circular(8)),
          child: RichText(
            text: TextSpan(
              children: diffs.map((d) {
                if (d.operation == DIFF_INSERT) {
                  return TextSpan(text: d.text, style: const TextStyle(color: Color(0xFF00FF66), backgroundColor: Color(0x3300FF66), fontWeight: FontWeight.bold));
                } else if (d.operation == DIFF_DELETE) {
                  return TextSpan(text: d.text, style: const TextStyle(color: Colors.redAccent, decoration: TextDecoration.lineThrough));
                }
                return TextSpan(text: d.text, style: const TextStyle(color: Colors.white70));
              }).toList(),
            ),
          ),
        );

      case 'grid_pinterest':
        final int colGrid = int.tryParse(nodoRaw['columnas']?.toString() ?? '2') ?? 2;
        return MasonryGridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: colGrid,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          itemCount: hijosRaw.length,
          itemBuilder: (context, index) {
            final h = hijosRaw[index];
            return h is Map ? construirNodo(context: context, nodoRaw: Map.from(h), estado: estado, onNavegar: onNavegar, onRecargar: onRecargar, onFeedback: onFeedback) : const SizedBox.shrink();
          },
        );

      case 'kanban':
        final List colsKanban = (nodoRaw['columnas'] as List?) ?? [];
        return SizedBox(
          height: double.tryParse(nodoRaw['altura']?.toString() ?? '500') ?? 500.0,
          child: DragAndDropLists(
            children: colsKanban.map((c) {
              final Map colMap = c is Map ? c : {};
              final List itemsKanban = (colMap['items'] as List?) ?? [];
              return DragAndDropList(
                header: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(colMap['titulo']?.toString() ?? 'Columna', style: const TextStyle(color: Color(0xFF00F3FF), fontWeight: FontWeight.bold)),
                ),
                children: itemsKanban.map((it) {
                  return DragAndDropItem(
                    child: it is Map 
                        ? construirNodo(context: context, nodoRaw: Map.from(it), estado: estado, onNavegar: onNavegar, onRecargar: onRecargar, onFeedback: onFeedback) 
                        : Container(padding: const EdgeInsets.all(8), child: Text(it.toString(), style: const TextStyle(color: Colors.white))),
                  );
                }).toList(),
              );
            }).toList(),
            onItemReorder: (int oldIt, int oldList, int newIt, int newList) {
              onFeedback('Item movido a la nueva columna');
              if (nodoRaw['flujo_al_mover'] is List) {
                EjecutorFlujosSdui.ejecutarCadena(context: context, flujoAcciones: nodoRaw['flujo_al_mover'] as List, onFeedback: onFeedback);
              }
            },
            onListReorder: (int oldList, int newList) {},
            listPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            itemDivider: const SizedBox(height: 8),
          ),
        );

      case 'grafo':
        final Graph graph = Graph()..isTree = false;
        final BuchheimWalkerConfiguration builderConfig = BuchheimWalkerConfiguration()
          ..siblingSeparation = (100)
          ..levelSeparation = (150)
          ..subtreeSeparation = (150)
          ..orientation = (BuchheimWalkerConfiguration.ORIENTATION_TOP_BOTTOM);

        final List nodesRaw = (nodoRaw['nodos'] as List?) ?? [];
        final List edgesRaw = (nodoRaw['enlaces'] as List?) ?? [];
        final Map<String, Node> nodeMap = {};

        for (var nr in nodesRaw) {
          if (nr is Map) {
            final id = nr['id'].toString();
            nodeMap[id] = Node.Id(id);
          }
        }

        for (var er in edgesRaw) {
          if (er is Map) {
            final from = er['de']?.toString();
            final to = er['a']?.toString();
            if (from != null && to != null && nodeMap.containsKey(from) && nodeMap.containsKey(to)) {
              graph.addEdge(nodeMap[from]!, nodeMap[to]!);
            }
          }
        }

        return Container(
          height: double.tryParse(nodoRaw['altura']?.toString() ?? '400') ?? 400.0,
          decoration: BoxDecoration(color: const Color(0xFF0B132B), border: Border.all(color: const Color(0xFF00F3FF)), borderRadius: BorderRadius.circular(10)),
          child: InteractiveViewer(
            constrained: false,
            boundaryMargin: const EdgeInsets.all(100),
            minScale: 0.1,
            maxScale: 2.0,
            child: GraphView(
              graph: graph,
              algorithm: BuchheimWalkerAlgorithm(builderConfig, TreeEdgeRenderer(builderConfig)),
              paint: Paint()..color = Colors.white54..strokeWidth = 2..style = PaintingStyle.stroke,
              builder: (Node node) {
                final String nid = node.key?.value?.toString() ?? '';
                final Map rawN = nodesRaw.firstWhere((n) => n is Map && n['id'].toString() == nid, orElse: () => {});
                final String txt = rawN['texto']?.toString() ?? nid;
                final Color col = parsearColor(rawN['color']?.toString(), const Color(0xFF00FF66));
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFF142033), borderRadius: BorderRadius.circular(8), border: Border.all(color: col, width: 2)),
                  child: Text(txt, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                );
              },
            ),
          ),
        );

      case 'dropdown':
        final List opciones = (nodoRaw['opciones'] as List?)?.map((e) => e.toString()).toList() ?? ['Opcion 1'];
        final String campo = nodoRaw['guardar_en']?.toString() ?? 'form.dropdown';
        final String valActual = estado.leerRuta(campo)?.toString() ?? (opciones.isNotEmpty ? opciones.first : '');
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton2(
              isExpanded: true,
              hint: Text(nodoRaw['placeholder']?.toString() ?? 'Selecciona...', style: const TextStyle(color: Colors.white54)),
              items: opciones.map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(color: Colors.white, fontSize: 13)))).toList(),
              value: opciones.contains(valActual) ? valActual : null,
              onChanged: (v) {
                if (v != null) estado.escribirRuta(campo, v, notificar: true);
              },
              buttonStyleData: ButtonStyleData(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: const Color(0xFF142033), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF00F3FF))),
              ),
              dropdownStyleData: DropdownStyleData(
                decoration: BoxDecoration(color: const Color(0xFF0B132B), borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        );

      case 'datatable':
        final List cols = (nodoRaw['columnas'] as List?) ?? ['ID', 'Dato'];
        final List filas = (nodoRaw['filas'] as List?) ?? [];
        return Container(
          height: double.tryParse(nodoRaw['altura']?.toString() ?? '250') ?? 250,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: const Color(0xFF0B132B), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFFD700))),
          child: DataTable2(
            columnSpacing: 12,
            horizontalMargin: 12,
            minWidth: cols.length * 100.0,
            columns: cols.map((c) => DataColumn2(label: Text(c.toString(), style: const TextStyle(color: Color(0xFF00FF66), fontWeight: FontWeight.bold)))).toList(),
            rows: filas.map((f) {
              final List celdas = (f is List) ? f : [f.toString()];
              return DataRow(cells: celdas.map((c) => DataCell(Text(estado.interpolarTexto(c.toString()), style: const TextStyle(color: Colors.white)))).toList());
            }).toList(),
          ),
        );

      case 'mapa':
      case 'flutter_map':
        final double lat = double.tryParse(estado.interpolarTexto(nodoRaw['lat']?.toString() ?? '-17.9647')) ?? -17.9647;
        final double lng = double.tryParse(estado.interpolarTexto(nodoRaw['lng']?.toString() ?? '-67.1060')) ?? -67.1060;
        final double zoom = double.tryParse(nodoRaw['zoom']?.toString() ?? '14.5') ?? 14.5;
        final double altMapa = double.tryParse(nodoRaw['altura']?.toString() ?? '220') ?? 220.0;
        return Container(
          height: altMapa,
          margin: const EdgeInsets.only(bottom: 12),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF00F3FF), width: 1.5)),
          child: FlutterMap(
            options: MapOptions(initialCenter: LatLng(lat, lng), initialZoom: zoom),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.logicasdui.superapk'),
            ],
          ),
        );

      case 'shimmer':
        final String txtShimmer = estado.interpolarTexto(nodoRaw['texto']?.toString() ?? 'Sincronizando datos...');
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Shimmer.fromColors(
            baseColor: const Color(0xFF00F3FF),
            highlightColor: const Color(0xFF00FF66),
            child: Text(txtShimmer, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
          ),
        );

      case 'dotted_card':
        final Color colDot = parsearColor(nodoRaw['color_borde']?.toString(), const Color(0xFFFFD700));
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DottedBorder(
            color: colDot,
            strokeWidth: 1.5,
            dashPattern: const [6, 4],
            borderType: BorderType.RRect,
            radius: const Radius.circular(12),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: hijosRaw.map((h) => h is Map ? construirNodo(context: context, nodoRaw: Map.from(h), estado: estado, onNavegar: onNavegar, onRecargar: onRecargar, onFeedback: onFeedback) : const SizedBox.shrink()).toList(),
            ),
          ),
        );

      case 'image':
      case 'sdui_imagen':
      case 'avatar':
        final String urlImg = estado.interpolarTexto(nodoRaw['url']?.toString() ?? nodoRaw['src']?.toString() ?? '');
        final double alto = double.tryParse(nodoRaw['altura']?.toString() ?? '90') ?? 90.0;
        final bool esCircular = nodoRaw['circular'] == true || tipo.toLowerCase() == 'avatar';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(esCircular ? alto : 12),
              child: urlImg.startsWith('http')
                  ? Image.network(
                      urlImg,
                      height: alto,
                      width: esCircular ? alto : null,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, st) => Container(height: alto, width: alto, color: const Color(0xFF142033), child: const Icon(Icons.person, color: Color(0xFF00FF66), size: 36)),
                    )
                  : Container(height: alto, width: alto, color: const Color(0xFF142033), child: const Icon(Icons.image, color: Color(0xFF00F3FF), size: 36)),
            ),
          ),
        );

      case 'text':
        final String texto = estado.interpolarTexto(nodoRaw['data']?.toString() ?? nodoRaw['texto']?.toString() ?? '');
        final Color colorTxt = parsearColor(nodoRaw['color']?.toString(), Colors.white);
        final double fontSize = double.tryParse(nodoRaw['size']?.toString() ?? '13') ?? 13.0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(texto, style: TextStyle(color: colorTxt, fontSize: fontSize, fontWeight: FontWeight.w600)),
        );

      case 'input':
        final String campo = nodoRaw['campo']?.toString() ?? 'input_generico';
        final String label = estado.interpolarTexto(nodoRaw['label']?.toString() ?? '');
        final String placeholder = estado.interpolarTexto(nodoRaw['placeholder']?.toString() ?? '');
        final bool esMultiline = nodoRaw['multiline'] == true;
        final int maxLin = esMultiline ? (int.tryParse(nodoRaw['lineas']?.toString() ?? '6') ?? 6) : 1;
        final int minLin = esMultiline ? 3 : 1;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label.isNotEmpty)
                Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(label, style: const TextStyle(color: Color(0xFFA9C7FF), fontSize: 11, fontWeight: FontWeight.bold))),
              TextField(
                obscureText: !esMultiline && nodoRaw['password'] == true,
                maxLines: maxLin,
                minLines: minLin,
                keyboardType: esMultiline ? TextInputType.multiline : TextInputType.text,
                style: TextStyle(color: Colors.white, fontSize: esMultiline ? 12 : 13, fontFamily: esMultiline ? 'monospace' : null),
                decoration: InputDecoration(
                  hintText: placeholder,
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 11.5),
                  filled: true,
                  fillColor: const Color(0xFF0A1020),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF00F3FF))),
                ),
                onChanged: (val) => estado.escribirRuta('form.$campo', val, notificar: false),
              ),
            ],
          ),
        );

      case 'button':
        final String textoBtn = estado.interpolarTexto(nodoRaw['texto']?.toString() ?? 'EJECUTAR');
        final Color colDef = parsearColor(estado.leerRuta('sistema.color_primario')?.toString(), const Color(0xFF00FF66));
        final Color bgCol = parsearColor(nodoRaw['color']?.toString(), colDef);
        final Color fgCol = parsearColor(nodoRaw['color_texto']?.toString(), Colors.black);
        final List flujo = (nodoRaw['flujo_acciones'] as List?) ?? [];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: bgCol, foregroundColor: fgCol, padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => EjecutorFlujosSdui.ejecutarCadena(context: context, flujoAcciones: flujo, onNavegar: onNavegar, onRecargarPantallas: onRecargar, onFeedback: onFeedback),
            child: Text(textoBtn, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
          ),
        );

      case 'listview':
        return _ListaAtomicaUniversalWidget(nodoRaw: nodoRaw, onFeedback: onFeedback, onNavegar: onNavegar, onRecargar: onRecargar);

      case 'gridview':
        final int cols = int.tryParse(nodoRaw['columnas']?.toString() ?? '2') ?? 2;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: cols,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.2,
          children: hijosRaw.map((h) => h is Map ? construirNodo(context: context, nodoRaw: Map.from(h), estado: estado, onNavegar: onNavegar, onRecargar: onRecargar, onFeedback: onFeedback) : const SizedBox.shrink()).toList(),
        );

      case 'tabs':
        final List pestanas = (nodoRaw['tabs'] as List?) ?? ['Tab 1', 'Tab 2'];
        
        // Ajustar hijos para que coincidan con la cantidad de pestañas con TIPO ESTRICTO
        final List<Widget> hijosAjustados = List<Widget>.generate(pestanas.length, (idx) {
          if (idx < hijosRaw.length && hijosRaw[idx] is Map) {
            return SingleChildScrollView(
              padding: const EdgeInsets.only(top: 10), 
              child: construirNodo(context: context, nodoRaw: Map.from(hijosRaw[idx] as Map), estado: estado, onNavegar: onNavegar, onRecargar: onRecargar, onFeedback: onFeedback)
            );
          }
          return const Center(child: Text('Sin contenido', style: TextStyle(color: Colors.white54)));
        });

        return DefaultTabController(
          length: pestanas.length,
          child: Column(
            children: [
              TabBar(
                isScrollable: pestanas.length > 3,
                indicatorColor: const Color(0xFF00FF66),
                labelColor: const Color(0xFF00FF66),
                unselectedLabelColor: Colors.white60,
                tabs: pestanas.map((t) => Tab(text: t.toString())).toList(),
              ),
              SizedBox(
                height: double.tryParse(nodoRaw['altura']?.toString() ?? '360') ?? 360,
                child: TabBarView(
                  children: hijosAjustados,
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
                    children: hijosRaw.map((h) => h is Map ? construirNodo(context: ctx, nodoRaw: Map.from(h), estado: estado, onNavegar: onNavegar, onRecargar: onRecargar, onFeedback: onFeedback) : const SizedBox.shrink()).toList(),
                  ),
                ),
              ),
            );
          },
          child: Text(txtTrigger, style: const TextStyle(color: Color(0xFF00F3FF), fontWeight: FontWeight.bold)),
        );

      case 'chart':
        final List spots = _extraerSpotsDinamicos(nodoRaw, estado);
        final Color colLinea = parsearColor(nodoRaw['color']?.toString(), const Color(0xFF00FF66));
        return Container(
          height: double.tryParse(nodoRaw['altura']?.toString() ?? '190') ?? 190,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF091224), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFFD700))),
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: true),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: true),
              lineBarsData: [LineChartBarData(spots: spots.map((s) => s as FlSpot).toList(), isCurved: true, color: colLinea, barWidth: 3)],
            ),
          ),
        );

      case 'card':
      default:
        final Color colSecDef = parsearColor(estado.leerRuta('sistema.color_secundario')?.toString(), const Color(0xFF00F3FF));
        final Color bordeCol = parsearColor(nodoRaw['color_borde']?.toString(), colSecDef);
        final String tit = estado.interpolarTexto(nodoRaw['titulo']?.toString() ?? '');
        final String sub = estado.interpolarTexto(nodoRaw['subtitulo']?.toString() ?? '');
        
        final bool isGlass = nodoRaw['glass'] == true;
        final List grad = nodoRaw['gradiente'] is List ? (nodoRaw['gradiente'] as List) : [];

        Widget contenidoTarjeta = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (tit.isNotEmpty) Text(tit, style: TextStyle(color: bordeCol, fontSize: 14, fontWeight: FontWeight.w900)),
            if (sub.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4, bottom: 10), child: Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 11.5))),
            ...hijosRaw.map((h) => h is Map ? construirNodo(context: context, nodoRaw: Map.from(h), estado: estado, onNavegar: onNavegar, onRecargar: onRecargar, onFeedback: onFeedback) : const SizedBox.shrink()),
          ],
        );

        Widget tarjetaFisica;
        if (isGlass || grad.isNotEmpty) {
           tarjetaFisica = ContenedorStitchSdui(
             glass: isGlass,
             coloresHex: grad,
             colorBorde: bordeCol,
             child: contenidoTarjeta,
           );
        } else {
           tarjetaFisica = Container(
             margin: const EdgeInsets.only(bottom: 14),
             padding: const EdgeInsets.all(14),
             decoration: BoxDecoration(color: const Color(0xFF0B132B), borderRadius: BorderRadius.circular(14), border: Border.all(color: bordeCol, width: 1.5)),
             child: contenidoTarjeta,
           );
        }

        if (nodoRaw['animar'] == true) {
          return tarjetaFisica.animate().fadeIn(duration: 350.ms).slideY(begin: 0.06, end: 0);
        }
        return tarjetaFisica;
    }
  }
}

class _ListaAtomicaUniversalWidget extends StatefulWidget {
  final Map nodoRaw;
  final void Function(String) onFeedback;
  final void Function(String) onNavegar;
  final Future Function() onRecargar;

  const _ListaAtomicaUniversalWidget({required this.nodoRaw, required this.onFeedback, required this.onNavegar, required this.onRecargar});
  @override
  State<StatefulWidget> createState() => _ListaAtomicaUniversalWidgetState();
}

class _ListaAtomicaUniversalWidgetState extends State<_ListaAtomicaUniversalWidget> {
  List _itemsRemotos = [];
  String? _siguienteCursor;
  bool _cargandoTop10 = false;
  bool _hayMasItems = true;
  final Map _cantidadesStepper = {};
  final Set _checksActivos = {};
  final Map _switchesActivos = {};
  String _radioSeleccionado = '';

  @override
  void initState() {
    super.initState();
    final Map nodo = widget.nodoRaw;
    if ((nodo['modo']?.toString() ?? 'estatico') == 'cursor_top10') _consultarCursorTop10(reiniciar: true);
  }

  Future _consultarCursorTop10({bool reiniciar = false}) async {
    if (_cargandoTop10 || (!reiniciar && !_hayMasItems)) return;
    setState(() => _cargandoTop10 = true);
    
    final Map nodo = widget.nodoRaw;
    final String col = nodo['coleccion']?.toString() ?? 'RECORDS_COGNITIVOS';
    
    final Map res = await PuenteSupabaseSdui.llamarRpcNano('nano_buscar_top10', {
      'p_app_id': PuenteSupabaseSdui.appIdActivo,
      'p_coleccion': col,
      'p_filtro': nodo['filtro'] ?? {},
      'p_cursor_fecha': reiniciar ? null : _siguienteCursor,
    });
    
    if (!mounted) return;
    setState(() {
      _cargandoTop10 = false;
      if (res['items'] is List) {
        final List nuevosItems = res['items'] as List;
        
        if (reiniciar) {
          _itemsRemotos = List.from(nuevosItems);
        } else {
          _itemsRemotos.addAll(nuevosItems);
        }
        
        _siguienteCursor = res['siguiente_cursor']?.toString();
        // Criterio inteligente de paginacion: Si me mandas menos de 10 o nulo, se acabó
        _hayMasItems = _siguienteCursor != null && _siguienteCursor != 'null' && nuevosItems.length == 10;
        
        EstadoGlobalSdui.instancia.escribirRuta('sistema.ultima_lista_top10', _itemsRemotos, notificar: false);
      }
    });
  }

  Widget _construirBotonesDeFila(BuildContext context, Map filaDatos, List botonesFila) {
    final estado = EstadoGlobalSdui.instancia;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: botonesFila.map((bRaw) {
          if (bRaw is! Map) return const SizedBox.shrink();
          final String txt = bRaw['texto']?.toString() ?? 'ACCION';
          final Color col = RenderizadorAtomicoSdui.parsearColor(bRaw['color']?.toString(), const Color(0xFF00FF66));
          final List flujo = (bRaw['flujo_acciones'] as List?) ?? [];
          return SizedBox(
            height: 28,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: col, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 10)),
              onPressed: () async {
                estado.escribirRuta('item_actual', filaDatos, notificar: false);
                estado.escribirRuta('form.item_id', filaDatos['id']?.toString() ?? '', notificar: false);
                estado.escribirRuta('form.item_propietario', filaDatos['propietario_id']?.toString() ?? '', notificar: false);
                estado.escribirRuta('form.item_estado', filaDatos['estado']?.toString() ?? '', notificar: false);
                await EjecutorFlujosSdui.ejecutarCadena(context: context, flujoAcciones: flujo, onNavegar: widget.onNavegar, onRecargarPantallas: widget.onRecargar, onFeedback: widget.onFeedback);
                if (bRaw['recargar_lista'] != false) await _consultarCursorTop10(reiniciar: true);
              },
              child: Text(txt, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final estado = EstadoGlobalSdui.instancia;
    final String modo = widget.nodoRaw['modo']?.toString() ?? 'action_buttons';
    final String titulo = estado.interpolarTexto(widget.nodoRaw['titulo']?.toString() ?? '');
    final List itemsJson = (widget.nodoRaw['items'] as List?) ?? [];
    final List botonesFilaGlobal = (widget.nodoRaw['botones_fila'] as List?) ?? [];

    if (modo == 'vertical_paging') {
      return Container(
        height: double.tryParse(widget.nodoRaw['altura']?.toString() ?? '260') ?? 260,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFF00FC))),
        child: PageView.builder(
          scrollDirection: Axis.vertical,
          itemCount: itemsJson.length,
          itemBuilder: (ctx, i) => Center(child: Text(estado.interpolarTexto(itemsJson[i].toString()), style: const TextStyle(color: Color(0xFF00FF66), fontSize: 16, fontWeight: FontWeight.w900))),
        ),
      );
    }

    if (modo == 'cursor_top10') {
      final String txtSig = widget.nodoRaw['texto_siguiente']?.toString() ?? 'SIGUIENTE CURSOR (LIMIT 10)';
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF0B132B), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF00F3FF))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (titulo.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(titulo, style: const TextStyle(color: Color(0xFF00F3FF), fontSize: 12.5, fontWeight: FontWeight.w900))),
                  IconButton(icon: const Icon(Icons.refresh, color: Color(0xFF00FF66), size: 18), onPressed: () => _consultarCursorTop10(reiniciar: true)),
                ],
              ),
            if (_cargandoTop10 && _itemsRemotos.isEmpty)
              const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else if (_itemsRemotos.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(widget.nodoRaw['texto_vacio']?.toString() ?? '0 registros encontrados.', style: const TextStyle(color: Colors.white60, fontSize: 11.5)))
            else
              ..._itemsRemotos.map((rawIt) {
                final Map it = rawIt is Map ? rawIt : {};
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF142033), borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${it['propietario_id'] ?? ''} · [${it['estado'] ?? ''}]', style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('${it['datos'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 11.5)),
                      if (botonesFilaGlobal.isNotEmpty) _construirBotonesDeFila(context, it, botonesFilaGlobal),
                    ],
                  ),
                );
              }),
              
            if (_itemsRemotos.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: _hayMasItems 
                    ? (_cargandoTop10 
                        ? const Padding(padding: EdgeInsets.all(8.0), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) 
                        : TextButton(onPressed: () => _consultarCursorTop10(reiniciar: false), child: Text(txtSig, style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11))))
                    : const Padding(
                        padding: EdgeInsets.only(top: 8.0, right: 8.0),
                        child: Text('NO HAY MÁS RESULTADOS', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
              ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF0B132B), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFFD700))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (titulo.isNotEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(titulo, style: const TextStyle(color: Color(0xFFFFD700), fontSize: 13, fontWeight: FontWeight.w900))),
          ...List.generate(itemsJson.length, (i) {
            final dynamic item = itemsJson[i];
            final String labelItem = item is Map ? estado.interpolarTexto(item['titulo']?.toString() ?? item['texto']?.toString() ?? '') : estado.interpolarTexto(item.toString());

            if (modo == 'stepper') {
              final int cant = (_cantidadesStepper[i] as int?) ?? 1;
              return ListTile(
                dense: true,
                title: Text(labelItem, style: const TextStyle(color: Colors.white, fontSize: 12)),
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
            if (modo == 'checkbox') {
              return CheckboxListTile(
                dense: true,
                value: _checksActivos.contains(i),
                activeColor: const Color(0xFFFFD700),
                checkColor: Colors.black,
                title: Text(labelItem, style: const TextStyle(color: Colors.white, fontSize: 12)),
                onChanged: (v) => setState(() => v == true ? _checksActivos.add(i) : _checksActivos.remove(i)),
              );
            }
            if (modo == 'switch') {
              return SwitchListTile(
                dense: true,
                value: (_switchesActivos[i] as bool?) ?? false,
                activeColor: const Color(0xFF00FF66),
                title: Text(labelItem, style: const TextStyle(color: Colors.white, fontSize: 12)),
                onChanged: (v) => setState(() => _switchesActivos[i] = v),
              );
            }
            if (modo == 'radio') {
              return RadioListTile(
                dense: true,
                value: labelItem,
                groupValue: _radioSeleccionado,
                activeColor: const Color(0xFF00F3FF),
                title: Text(labelItem, style: const TextStyle(color: Colors.white, fontSize: 12)),
                onChanged: (v) => setState(() => _radioSeleccionado = v?.toString() ?? labelItem),
              );
            }

            final List botonesItem = (item is Map && item['botones'] is List) ? (item['botones'] as List) : botonesFilaGlobal;
            final List flujoUnico = (item is Map && item['flujo_acciones'] is List) ? (item['flujo_acciones'] as List) : [];
            final String txtBtn = (item is Map && item['texto_boton'] != null) ? item['texto_boton'].toString() : 'EJECUTAR';

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF142033), borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(labelItem, style: const TextStyle(color: Colors.white, fontSize: 11.5))),
                      if (flujoUnico.isNotEmpty)
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00FF66), foregroundColor: Colors.black),
                          onPressed: () => EjecutorFlujosSdui.ejecutarCadena(context: context, flujoAcciones: flujoUnico, onNavegar: widget.onNavegar, onRecargarPantallas: widget.onRecargar, onFeedback: widget.onFeedback),
                          child: Text(txtBtn, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                        ),
                    ],
                  ),
                  if (botonesItem.isNotEmpty) _construirBotonesDeFila(context, item is Map ? item : {'titulo': labelItem}, botonesItem),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}