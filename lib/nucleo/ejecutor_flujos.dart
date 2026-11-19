import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:expressions/expressions.dart' as expr_pkg;
import 'package:math_expressions/math_expressions.dart' as math_exp;
import 'package:equations/equations.dart' as eq_pkg;
import 'package:csv/csv.dart';
import 'package:archive/archive.dart';
import 'package:json_path/json_path.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:uuid/uuid.dart' as uuid_pkg;
import 'estado_global.dart';
import 'puente_supabase.dart';
import '../motores/bus_hardware_universal.dart';

class EjecutorFlujosSdui {
  static const uuid_pkg.Uuid _uidGen = uuid_pkg.Uuid();

  static Future ejecutarCadena({
    required BuildContext context,
    required List flujoAcciones,
    void Function(String pantallaId)? onNavegar,
    Future Function()? onRecargarPantallas,
    void Function(String feedback)? onFeedback,
  }) async {
    final estado = EstadoGlobalSdui.instancia;

    for (final pasoRaw in flujoAcciones) {
      if (pasoRaw is! Map) continue;
      final Map paso = Map.from(estado.interpolarEstructura(pasoRaw) as Map);
      final String accion = (paso['accion']?.toString() ?? '').toUpperCase().trim();

      if (accion == 'VALIDAR_IF') {
        final String condicionStr = paso['condicion']?.toString() ?? 'true';
        final bool cumple = evaluarCondicionBooleana(condicionStr, estado.almacenCompleto);
        if (!cumple) {
          final String msgError =
              paso['mensaje_si_falso']?.toString() ?? 'Condicion requerida no cumplida.';
          estado.escribirRuta('sistema.ultimo_mensaje', msgError);
          onFeedback?.call(msgError);
          if (paso['flujo_si_falso'] is List && context.mounted) {
            await ejecutarCadena(
              context: context,
              flujoAcciones: paso['flujo_si_falso'] as List,
              onNavegar: onNavegar,
              onRecargarPantallas: onRecargarPantallas,
              onFeedback: onFeedback,
            );
          }
          return;
        }
        continue;
      }

      if (accion == 'CALCULAR_FORMULA') {
        final String formula = paso['formula']?.toString() ?? '0';
        final double valX = double.tryParse(paso['valor_x']?.toString() ?? '0') ?? 0.0;
        final double valY = double.tryParse(paso['valor_y']?.toString() ?? '0') ?? 0.0;
        final double resMat = evaluarFormulaMatematica(formula, valX: valX, valY: valY);
        final String rutaDestino = paso['guardar_en']?.toString() ?? 'form.resultado_formula';
        estado.escribirRuta(rutaDestino, resMat);
        continue;
      }

      if (accion == 'RESOLVER_ECUACION') {
        final double a = double.tryParse(paso['a']?.toString() ?? '1') ?? 1.0;
        final double b = double.tryParse(paso['b']?.toString() ?? '-5') ?? -5.0;
        final double c = double.tryParse(paso['c']?.toString() ?? '6') ?? 6.0;
        final eq = eq_pkg.Quadratic.realEquation(a: a, b: b, c: c);
        final String raices = eq.solutions().map((s) => s.real.toStringAsFixed(2)).join(', ');
        final String rutaDest = paso['guardar_en']?.toString() ?? 'form.raices_ecuacion';
        estado.escribirRuta(rutaDest, raices);
        onFeedback?.call('Raices: $raices');
        continue;
      }

      if (accion == 'EXTRAER_JSON_PATH') {
        final String expresionPath = paso['path']?.toString() ?? r'$.*';
        final String rutaOrigen = paso['origen']?.toString() ?? 'sistema.ultima_respuesta_rpc';
        final dynamic obj = estado.leerRuta(rutaOrigen);
        try {
          final jp = JsonPath(expresionPath);
          final vals = jp.read(obj).map((m) => m.value).toList();
          estado.escribirRuta(paso['guardar_en']?.toString() ?? 'form.dato_extraido', vals.toString());
        } catch (_) {}
        continue;
      }

      if (accion == 'GUARDAR_ESTADO') {
        final String ruta = paso['ruta']?.toString() ?? 'form.temporal';
        final dynamic valor = paso['valor'];
        estado.escribirRuta(ruta, valor);
        if (paso['mensaje'] != null) {
          onFeedback?.call(paso['mensaje'].toString());
        }
        continue;
      }

      if (accion == 'MOSTRAR_MODAL_SINO') {
        if (!context.mounted) return;
        final String titulo = paso['titulo']?.toString() ?? 'Confirmar Operacion';
        final String pregunta =
            paso['pregunta']?.toString() ?? '¿Deseas ejecutar esta accion ahora?';
        final bool confirmado = await _mostrarDialogoConfirmacionSiNo(
          context: context,
          titulo: titulo,
          pregunta: pregunta,
          esDestructivo: paso['destructivo'] == true,
        );
        if (!confirmado) {
          onFeedback?.call('Operacion cancelada por el usuario.');
          return;
        }
        continue;
      }

      if (accion == 'CAMBIAR_CONTEXTO_MULTI_APP') {
        final String nuevoEsq = paso['esquema']?.toString() ?? '';
        final String nuevaApp = paso['app_id']?.toString() ?? '';
        final String? nuevaUrl = paso['url']?.toString();
        final String? nuevaKey = paso['anon_key']?.toString();
        final String? nuevaGem = paso['gemini_key']?.toString();

        await PuenteSupabaseSdui.cambiarContextoMultiApp(
          nuevoEsquema: nuevoEsq,
          nuevaAppId: nuevaApp,
          nuevaUrl: nuevaUrl,
          nuevaAnonKey: nuevaKey,
          nuevaGeminiKey: nuevaGem,
        );
        await onRecargarPantallas?.call();
        final String msgCtx =
            'Conectado a Esquema [${PuenteSupabaseSdui.esquemaActivo}] · App [${PuenteSupabaseSdui.appIdActivo}]';
        estado.escribirRuta('sistema.ultimo_mensaje', msgCtx);
        onFeedback?.call(msgCtx);
        continue;
      }

      if (accion == 'EJECUTAR_REGLA_SQL' || accion == 'NANO_EJECUTAR_REGLA') {
        final String reglaId = paso['regla_id']?.toString() ?? '';
        final Map payload = paso['payload'] is Map
            ? Map.from(paso['payload'] as Map)
            : Map.from((estado.leerRuta('form') as Map?) ?? {});

        final Map resRegla = await PuenteSupabaseSdui.llamarRpcNano(
          'nano_ejecutar_regla',
          {
            'p_app_id': paso['app_id']?.toString() ?? PuenteSupabaseSdui.appIdActivo,
            'p_regla_id': reglaId,
            'p_payload': payload,
          },
          esquemaOverride: paso['esquema_override']?.toString(),
        );

        final String rutaGuardar =
            paso['guardar_respuesta_en']?.toString() ?? 'sistema.ultima_regla_sql';
        estado.escribirRuta(rutaGuardar, resRegla, notificar: false);

        if (resRegla['exito'] == true) {
          if (resRegla['usuario_id'] != null) {
            estado.escribirRuta('sesion.usuario_id', resRegla['usuario_id'].toString(), notificar: false);
          }
          if (resRegla['nombre'] != null) {
            estado.escribirRuta('sesion.nombre', resRegla['nombre'].toString(), notificar: false);
          }
          if (resRegla['rol'] != null) {
            estado.escribirRuta('sesion.rol', resRegla['rol'].toString(), notificar: false);
          }
          if (resRegla['foto_url'] != null) {
            estado.escribirRuta('sesion.foto_url', resRegla['foto_url'].toString(), notificar: false);
          }
          if (resRegla['token_entrada'] != null) {
            estado.escribirRuta('sesion.token_entrada', resRegla['token_entrada'].toString(), notificar: false);
          }
          if (resRegla['token_salida'] != null) {
            estado.escribirRuta('sesion.token_salida', resRegla['token_salida'].toString(), notificar: false);
            estado.escribirRuta('sesion.rol', 'TODOS', notificar: false);
          }
        }

        final String msgRegla =
            resRegla['mensaje']?.toString() ?? 'Regla SQL [$reglaId] ejecutada.';
        estado.escribirRuta('sistema.ultimo_mensaje', msgRegla, notificar: true);
        onFeedback?.call(msgRegla);

        if (resRegla['exito'] == false && paso['detener_si_error'] != false) {
          return;
        }
        if (paso['recargar_pantallas'] == true) {
          await onRecargarPantallas?.call();
        }
        continue;
      }

      if (accion == 'LLAMAR_RPC_NANO') {
        final String rpc = paso['rpc']?.toString() ?? 'nano_transaccion_atomica';
        Map params;

        if (paso['parametros'] is Map) {
          params = Map.from(paso['parametros'] as Map);
        } else {
          final Map pDatosFinal = Map.from((estado.leerRuta('form') as Map?) ?? {});
          // Inyección inteligente de idempotency_key para transacciones seguras
          if (pDatosFinal['idempotency_key'] == null || pDatosFinal['idempotency_key'].toString().isEmpty) {
             pDatosFinal['idempotency_key'] = _uidGen.v4();
          }

          params = {
            'p_app_id': PuenteSupabaseSdui.appIdActivo,
            'p_operacion': paso['operacion']?.toString() ?? 'INSERTAR_DOCUMENTO',
            'p_datos': pDatosFinal,
          };
        }
        
        params.putIfAbsent('p_app_id', () => PuenteSupabaseSdui.appIdActivo);

        final Map resRpc = await PuenteSupabaseSdui.llamarRpcNano(
          rpc,
          params,
          esquemaOverride: paso['esquema_override']?.toString(),
        );

        final String rutaResp =
            paso['guardar_respuesta_en']?.toString() ?? 'sistema.ultima_respuesta_rpc';
        estado.escribirRuta(rutaResp, resRpc);

        final String msg = resRpc['mensaje']?.toString() ?? 'RPC [$rpc] ejecutado.';
        estado.escribirRuta('sistema.ultimo_mensaje', msg);
        onFeedback?.call(msg);

        if (resRpc['exito'] == false && paso['detener_si_error'] != false) {
          return;
        }
        continue;
      }

      if (accion == 'LLAMAR_PUENTE_API_GEMINI') {
        final String apiId = paso['api_id']?.toString() ?? 'CONECTOR_GEMINI_PRO';
        final Map payload = paso['payload'] is Map
            ? Map.from(paso['payload'] as Map)
            : {
                'prompt': paso['prompt']?.toString() ?? '',
                'tipo_puente': paso['tipo_puente']?.toString() ?? '',
                'app_destino': paso['app_destino']?.toString() ?? '',
                'endpoint_url': paso['endpoint_url']?.toString() ?? '',
              };

        final Map resApi = await PuenteSupabaseSdui.ejecutarPuenteApiYGemini(
          apiId: apiId,
          payload: payload,
        );
        final String msgIa = resApi['respuesta_ia']?.toString() ??
            resApi['mensaje']?.toString() ??
            'Puente API/Gemini ejecutado.';
        estado.escribirRuta('sistema.ultimo_mensaje', msgIa);
        onFeedback?.call(msgIa);
        continue;
      }

      if (accion == 'EJECUTAR_HARDWARE') {
        final String comandoHw = paso['comando']?.toString() ?? 'HABLAR_TTS';
        final Map resHw = await BusHardwareUniversal.ejecutarComandoHardware(
          comando: comandoHw,
          argumentos: paso,
        );
        final String msgHw =
            resHw['mensaje']?.toString() ?? 'Hardware [$comandoHw] ejecutado.';
        estado.escribirRuta('sistema.ultimo_mensaje', msgHw);
        onFeedback?.call(msgHw);
        continue;
      }

      if (accion == 'EXPORTAR_CSV') {
        final List lista = (estado.leerRuta('sistema.ultima_lista_top10') as List?) ?? [];
        final List<List<dynamic>> filas = [
          ['id', 'coleccion', 'propietario_id', 'estado', 'datos']
        ];
        
        for (var m in lista) {
          if (m is Map) {
            filas.add([
              m['id'] ?? '',
              m['coleccion'] ?? '',
              m['propietario_id'] ?? '',
              m['estado'] ?? '',
              jsonEncode(m['datos'] ?? {})
            ]);
          }
        }

        final String csvTxt = const ListToCsvConverter().convert(filas);
        final List<int>? encodeRes = GZipEncoder().encode(utf8.encode(csvTxt));
        final List<int> gzBytes = encodeRes ?? <int>[];
        final f = File('${Directory.systemTemp.path}/export_sdui_${DateTime.now().millisecondsSinceEpoch}.csv');
        await f.writeAsString(csvTxt);
        onFeedback?.call('CSV (${filas.length - 1} filas, GZip ${gzBytes.length}B): ${f.path}');
        continue;
      }

      if (accion == 'EXPORTAR_PDF') {
        final String tituloPdf =
            paso['titulo']?.toString() ?? 'Reporte Oficial Super-APK SDUI';
        final String rutaPdf = await generarPdfNativo(titulo: tituloPdf, datos: paso);
        onFeedback?.call('PDF generado: $rutaPdf');
        continue;
      }

      if (accion == 'NAVEGAR') {
        HapticFeedback.selectionClick();
        final String destino = paso['pantalla_destino']?.toString() ?? '';
        if (destino == '__RECARGAR__') {
          await onRecargarPantallas?.call();
        } else if (destino.isNotEmpty) {
          onNavegar?.call(destino);
        }
        if (paso['mensaje'] != null) {
          onFeedback?.call(paso['mensaje'].toString());
        }
        continue;
      }
    }
  }

  static bool evaluarCondicionBooleana(String expresionStr, Map contexto) {
    try {
      final expression = expr_pkg.Expression.parse(expresionStr);
      const evaluator = expr_pkg.ExpressionEvaluator();
      final Map ctxPlano = {};
      contexto.forEach((k, v) => ctxPlano[k.toString()] = v);
      if (contexto['form'] is Map) {
        (contexto['form'] as Map).forEach((k, v) => ctxPlano[k.toString()] = v);
      }
      if (contexto['sistema'] is Map) {
        (contexto['sistema'] as Map).forEach((k, v) => ctxPlano[k.toString()] = v);
      }
      if (contexto['sesion'] is Map) {
        (contexto['sesion'] as Map).forEach((k, v) => ctxPlano[k.toString()] = v);
      }
      final resultado = evaluator.eval(
        expression,
        ctxPlano.map((k, v) => MapEntry(k.toString(), v)),
      );
      if (resultado is bool) return resultado;
      return resultado != null && resultado != false && resultado != 0 && resultado != '';
    } catch (_) {
      return true;
    }
  }

  static double evaluarFormulaMatematica(
    String formula, {
    double valX = 0.0,
    double valY = 0.0,
  }) {
    try {
      final parser = math_exp.Parser();
      final exp = parser.parse(formula);
      final cm = math_exp.ContextModel();
      cm.bindVariable(math_exp.Variable('x'), math_exp.Number(valX));
      cm.bindVariable(math_exp.Variable('y'), math_exp.Number(valY));
      final eval = exp.evaluate(math_exp.EvaluationType.REAL, cm);
      return double.tryParse(eval.toString()) ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  static Future _mostrarDialogoConfirmacionSiNo({
    required BuildContext context,
    required String titulo,
    required String pregunta,
    bool esDestructivo = false,
  }) async {
    final res = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1224),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: esDestructivo ? const Color(0xFFFF4D4D) : const Color(0xFF00FF66),
            width: 1.8,
          ),
        ),
        title: Text(
          titulo,
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
        ),
        content: Text(
          pregunta,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('NO, CANCELAR', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: esDestructivo ? const Color(0xFFFF4D4D) : const Color(0xFF00FF66),
              foregroundColor: esDestructivo ? Colors.white : Colors.black,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('SI, CONFIRMAR', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
    return res == true;
  }

  static Future generarPdfNativo({
    required String titulo,
    required Map datos,
  }) async {
    final doc = pw.Document();
    final estado = EstadoGlobalSdui.instancia;
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(titulo, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Text('Esquema: ${PuenteSupabaseSdui.esquemaActivo} | App ID: ${PuenteSupabaseSdui.appIdActivo}', style: const pw.TextStyle(fontSize: 11)),
              pw.Divider(),
              pw.Text('Estado Global:', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.Text(estado.almacenCompleto.toString(), style: const pw.TextStyle(fontSize: 9.5)),
            ],
          );
        },
      ),
    );
    final bytes = await doc.save();
    final f = File('${Directory.systemTemp.path}/reporte_sdui_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await f.writeAsBytes(bytes);
    return '${f.path} (${(bytes.length / 1024).toStringAsFixed(1)} KB)';
  }
}