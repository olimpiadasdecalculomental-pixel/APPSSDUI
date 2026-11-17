import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:expressions/expressions.dart' as expr_pkg;
import 'package:math_expressions/math_expressions.dart' as math_exp;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'estado_global.dart';
import 'puente_supabase.dart';
import '../motores/bus_hardware_universal.dart';

class EjecutorFlujosSdui {
  static Future<void> ejecutarCadena({
    required BuildContext context,
    required List<dynamic> flujoAcciones,
    void Function(String pantallaId)? onNavegar,
    Future<void> Function()? onRecargarPantallas,
    void Function(String feedback)? onFeedback,
  }) async {
    final estado = EstadoGlobalSdui.instancia;

    for (final pasoRaw in flujoAcciones) {
      if (pasoRaw is! Map) continue;
      final Map<String, dynamic> paso =
          Map<String, dynamic>.from(estado.interpolarEstructura(pasoRaw) as Map);
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

      if (accion == 'LLAMAR_RPC_NANO') {
        final String rpc = paso['rpc']?.toString() ?? 'nano_transaccion_atomica';
        final Map<String, dynamic> params = paso['parametros'] is Map
            ? Map<String, dynamic>.from(paso['parametros'] as Map)
            : {
                'p_app_id': PuenteSupabaseSdui.appIdActivo,
                'p_operacion': paso['operacion']?.toString() ?? 'INSERTAR_DOCUMENTO',
                'p_datos': paso['datos'] ?? estado.leerRuta('form') ?? {},
              };
        params.putIfAbsent('p_app_id', () => PuenteSupabaseSdui.appIdActivo);

        final resRpc = await PuenteSupabaseSdui.llamarRpcNano(
          rpc,
          params,
          esquemaOverride: paso['esquema_override']?.toString(),
        );

        final String rutaResp = paso['guardar_respuesta_en']?.toString() ?? 'sistema.ultima_respuesta_rpc';
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
        final Map<String, dynamic> payload = paso['payload'] is Map
            ? Map<String, dynamic>.from(paso['payload'] as Map)
            : {
                'prompt': paso['prompt']?.toString() ?? '',
                'tipo_puente': paso['tipo_puente']?.toString() ?? '',
                'app_destino': paso['app_destino']?.toString() ?? '',
                'endpoint_url': paso['endpoint_url']?.toString() ?? '',
              };

        final resApi = await PuenteSupabaseSdui.ejecutarPuenteApiYGemini(
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
        final Map<String, dynamic> resHw = await BusHardwareUniversal.ejecutarComandoHardware(
          comando: comandoHw,
          argumentos: paso,
        );
        final String msgHw = resHw['mensaje']?.toString() ?? 'Hardware [$comandoHw] ejecutado.';
        estado.escribirRuta('sistema.ultimo_mensaje', msgHw);
        onFeedback?.call(msgHw);
        continue;
      }

      if (accion == 'EXPORTAR_PDF') {
        final String tituloPdf = paso['titulo']?.toString() ?? 'Reporte Oficial Super-APK SDUI';
        await generarYCompartirPdf(titulo: tituloPdf, datos: paso);
        onFeedback?.call('PDF generado: $tituloPdf');
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

  static bool evaluarCondicionBooleana(String expresionStr, Map<String, dynamic> contexto) {
    try {
      final expression = expr_pkg.Expression.parse(expresionStr);
      const evaluator = expr_pkg.ExpressionEvaluator();
      final Map<String, dynamic> ctxPlano = {
        ...contexto,
        if (contexto['form'] is Map) ...(contexto['form'] as Map<String, dynamic>),
        if (contexto['sistema'] is Map) ...(contexto['sistema'] as Map<String, dynamic>),
        if (contexto['sesion'] is Map) ...(contexto['sesion'] as Map<String, dynamic>),
      };
      final resultado = evaluator.eval(expression, ctxPlano);
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

  static Future<bool> _mostrarDialogoConfirmacionSiNo({
    required BuildContext context,
    required String titulo,
    required String pregunta,
    bool esDestructivo = false,
  }) async {
    final res = await showDialog<bool>(
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

  static Future<void> generarYCompartirPdf({
    required String titulo,
    required Map<String, dynamic> datos,
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
              pw.Text(
                titulo,
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Esquema: ${PuenteSupabaseSdui.esquemaActivo} | App ID: ${PuenteSupabaseSdui.appIdActivo}',
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.Divider(),
              pw.Text(
                'Estado Global Capturado:',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                estado.almacenCompleto.toString(),
                style: const pw.TextStyle(fontSize: 9.5),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'Parametros del Reporte:',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                datos.toString(),
                style: const pw.TextStyle(fontSize: 9.5),
              ),
            ],
          );
        },
      ),
    );
    await Printing.sharePdf(bytes: await doc.save(), filename: 'reporte_sdui.pdf');
  }
}