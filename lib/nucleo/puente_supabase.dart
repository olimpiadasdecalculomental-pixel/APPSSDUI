import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart' as crypto_pkg;
import 'estado_global.dart';

class PuenteSupabaseSdui {
  static const String _defaultUrl = '[https://alxbydjpoxoavasklwpd.supabase.co](https://alxbydjpoxoavasklwpd.supabase.co)';
  static const String _defaultAnonKey = 'sb_publishable_Kc8wekwUqIs78ILNF-j-Qg_LNMYRhn0';

  static String supabaseUrl = _defaultUrl;
  static String supabaseAnonKey = _defaultAnonKey;
  static String esquemaActivo = 'esquema1';
  static String appIdActivo = 'APP_UNIVERSAL_SDUI';
  static String geminiApiKey = '';

  static File _archivoConfigSegura() {
    return File('${Directory.systemTemp.path}/sdui_boveda_contexto_v4.json');
  }

  static File _archivoCacheHive(String esq, String app) {
    final String hashKey = crypto_pkg.md5.convert(utf8.encode('${esq}_$app')).toString();
    return File('${Directory.systemTemp.path}/sdui_hive_cache_v4_$hashKey.json');
  }

  static Future inicializarPuenteUniversal() async {
    try {
      final f = _archivoConfigSegura();
      if (await f.exists()) {
        final Map data = jsonDecode(await f.readAsString()) as Map;
        if (data['esquema_activo'] != null && data['esquema_activo'].toString().trim().isNotEmpty) {
          esquemaActivo = data['esquema_activo'].toString().trim();
        }
        if (data['app_id_activo'] != null && data['app_id_activo'].toString().trim().isNotEmpty) {
          appIdActivo = data['app_id_activo'].toString().trim();
        }
        if (data['supabase_url'] != null && data['supabase_url'].toString().trim().isNotEmpty) {
          supabaseUrl = data['supabase_url'].toString().trim();
        }
        if (data['supabase_key'] != null && data['supabase_key'].toString().trim().isNotEmpty) {
          supabaseAnonKey = data['supabase_key'].toString().trim();
        }
        if (data['gemini_key'] != null && data['gemini_key'].toString().trim().isNotEmpty) {
          geminiApiKey = data['gemini_key'].toString().trim();
        }
      }
    } catch (_) {}

    EstadoGlobalSdui.instancia.escribirRuta('sistema.esquema_activo', esquemaActivo, notificar: false);
    EstadoGlobalSdui.instancia.escribirRuta('sistema.app_id_activo', appIdActivo, notificar: true);
  }

  static Future cambiarContextoMultiApp({
    required String nuevoEsquema,
    required String nuevaAppId,
    String? nuevaUrl,
    String? nuevaAnonKey,
    String? nuevaGeminiKey,
  }) async {
    if (nuevoEsquema.trim().isNotEmpty) esquemaActivo = nuevoEsquema.trim();
    if (nuevaAppId.trim().isNotEmpty) appIdActivo = nuevaAppId.trim();
    if (nuevaUrl != null && nuevaUrl.trim().isNotEmpty) supabaseUrl = nuevaUrl.trim();
    if (nuevaAnonKey != null && nuevaAnonKey.trim().isNotEmpty) supabaseAnonKey = nuevaAnonKey.trim();
    if (nuevaGeminiKey != null && nuevaGeminiKey.trim().isNotEmpty) geminiApiKey = nuevaGeminiKey.trim();

    try {
      final f = _archivoConfigSegura();
      await f.writeAsString(jsonEncode({
        'esquema_activo': esquemaActivo,
        'app_id_activo': appIdActivo,
        'supabase_url': supabaseUrl,
        'supabase_key': supabaseAnonKey,
        'gemini_key': geminiApiKey,
      }));
    } catch (_) {}

    EstadoGlobalSdui.instancia.escribirRuta('sistema.esquema_activo', esquemaActivo, notificar: false);
    EstadoGlobalSdui.instancia.escribirRuta('sistema.app_id_activo', appIdActivo, notificar: true);
  }

  static Map _construirHeaders({String? esquemaOverride}) {
    final String perfil = (esquemaOverride != null && esquemaOverride.trim().isNotEmpty)
        ? esquemaOverride.trim()
        : esquemaActivo;
    return {
      'Content-Type': 'application/json',
      'apikey': supabaseAnonKey,
      'Authorization': 'Bearer $supabaseAnonKey',
      'Accept-Profile': perfil,
      'Content-Profile': perfil,
    };
  }

  static Map _normalizarPayloadJson(Map origen) {
    final Map copia = Map.from(origen);
    if (copia['p_datos'] is Map) {
      final Map pDatos = Map.from(copia['p_datos'] as Map);
      final dynamic rawArbol = pDatos['arbol_json'];
      if (rawArbol is String && rawArbol.trim().isNotEmpty) {
        try {
          pDatos['arbol_json'] = jsonDecode(rawArbol.trim());
        } catch (_) {}
      }
      copia['p_datos'] = pDatos;
    }
    return copia;
  }

  static Future llamarRpcNano(
    String nombreRpc,
    Map parametros, {
    String? esquemaOverride,
  }) async {
    final uri = Uri.parse('$supabaseUrl/rest/v1/rpc/$nombreRpc');
    final Map rawHeaders = _construirHeaders(esquemaOverride: esquemaOverride);
    final Map payloadLimpio = _normalizarPayloadJson(parametros);
    try {
      final resp = await http
          .post(
            uri,
            headers: rawHeaders.map((k, v) => MapEntry(k.toString(), v.toString())),
            body: jsonEncode(payloadLimpio),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        EstadoGlobalSdui.instancia.escribirRuta('sistema.modo_offline', false, notificar: false);
        if (resp.body.isEmpty) return {'exito': true};
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) {
          return Map.from(decoded);
        }
        return {'exito': true, 'datos': decoded};
      }
      return {
        'exito': false,
        'codigo_http': resp.statusCode,
        'mensaje': 'Respuesta HTTP ${resp.statusCode}: ${resp.body}',
      };
    } catch (e) {
      EstadoGlobalSdui.instancia.escribirRuta('sistema.modo_offline', true, notificar: false);
      return {
        'exito': false,
        'modo_offline': true,
        'mensaje': 'Modo Offline activo (Cache Local): $e',
      };
    }
  }

  static Future sincronizarPantallasConHash({
    String? appOverride,
    String? esquemaOverride,
  }) async {
    final String appObj = appOverride ?? appIdActivo;
    final String esqObj = esquemaOverride ?? esquemaActivo;
    final File fCache = _archivoCacheHive(esqObj, appObj);

    String hashLocal = '';
    List? pantallasCacheadas;

    try {
      if (await fCache.exists()) {
        final Map cacheObj = jsonDecode(await fCache.readAsString()) as Map;
        hashLocal = cacheObj['version_hash']?.toString() ?? '';
        if (cacheObj['pantallas'] is List) {
          pantallasCacheadas = List.from(cacheObj['pantallas'] as List);
        }
      }
    } catch (_) {}

    final Map res = await llamarRpcNano(
      'nano_leer_pantalla',
      {
        'p_app_id': appObj,
        'p_pantalla_id': '__TODAS__',
        'p_hash_cliente': hashLocal,
      },
      esquemaOverride: esqObj,
    );

    if (res['exito'] == true) {
      if (res['sin_cambios'] == true && pantallasCacheadas != null) {
        return pantallasCacheadas;
      }

      if (res['pantallas'] is List) {
        final List listaRemota = List.from(res['pantallas'] as List);
        final String nuevoHash = res['version_hash']?.toString() ?? '';
        try {
          await fCache.writeAsString(jsonEncode({
            'version_hash': nuevoHash,
            'pantallas': listaRemota,
          }));
        } catch (_) {}
        return listaRemota;
      }
    }

    if (pantallasCacheadas != null) {
      return pantallasCacheadas;
    }

    return _semillaLocalEmergencia();
  }

  static Future ejecutarPuenteApiYGemini({
    required String apiId,
    required Map payload,
  }) async {
    final Map meta = await llamarRpcNano(
      'nano_puente_api_y_gemini',
      {
        'p_app_id': appIdActivo,
        'p_api_id': apiId,
        'p_payload': payload,
      },
    );

    final String promptUsuario = payload['prompt']?.toString() ?? '';

    if (geminiApiKey.isNotEmpty && promptUsuario.isNotEmpty) {
      try {
        final uriGem = Uri.parse(
          '[https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$geminiApiKey](https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$geminiApiKey)',
        );
        final rGem = await http
            .post(
              uriGem,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'contents': [
                  {
                    'parts': [
                      {'text': promptUsuario}
                    ]
                  }
                ]
              }),
            )
            .timeout(const Duration(seconds: 15));
        if (rGem.statusCode == 200) {
          final Map dec = jsonDecode(rGem.body) as Map;
          String textoIa = dec.toString();
          try {
            final List cands = dec['candidates'] as List;
            final Map content = (cands.first as Map)['content'] as Map;
            final List parts = content['parts'] as List;
            textoIa = (parts.first as Map)['text']?.toString() ?? textoIa;
          } catch (_) {}
          final String limpioJson = textoIa
              .replaceAll('```json', '')
              .replaceAll('```', '')
              .trim();
          EstadoGlobalSdui.instancia.escribirRuta('ia.ultima_respuesta_gemini', limpioJson, notificar: false);
          if (limpioJson.startsWith('{')) {
            EstadoGlobalSdui.instancia.escribirRuta('form.arbol_json_str', limpioJson, notificar: true);
          } else {
            EstadoGlobalSdui.instancia.escribirRuta('ia.ultima_respuesta_gemini', limpioJson, notificar: true);
          }
          return {'exito': true, 'respuesta_ia': limpioJson, 'meta_rpc': meta};
        }
      } catch (e) {
        EstadoGlobalSdui.instancia.escribirRuta('ia.ultima_respuesta_gemini', 'Error Gemini REST: $e');
      }
    }

    final String endpointExterno =
        payload['endpoint_url']?.toString() ?? meta['endpoint_url']?.toString() ?? '';
    if (endpointExterno.startsWith('http') &&
        !endpointExterno.contains('generativelanguage.googleapis.com')) {
      try {
        final rExt = await http
            .post(
              Uri.parse(endpointExterno),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 10));
        EstadoGlobalSdui.instancia.escribirRuta('ia.ultimo_puente_api', rExt.body);
        return {'exito': true, 'status': rExt.statusCode, 'body': rExt.body};
      } catch (e) {
        return {'exito': false, 'mensaje': 'Error llamando API externa: $e'};
      }
    }

    final String resumen = meta['mensaje']?.toString() ??
        'Puente API/Gemini ejecutado en esquema [$esquemaActivo].';
    EstadoGlobalSdui.instancia.escribirRuta('ia.ultima_respuesta_gemini', resumen);
    return {'exito': true, 'mensaje': resumen, 'meta': meta};
  }

  static List _semillaLocalEmergencia() {
    return [
      {
        'app_id': appIdActivo,
        'pantalla_id': 'P00_CONEXION_BASE',
        'orden': 1,
        'titulo': 'P00 · Rescate de Conexion Base',
        'rol_requerido': 'TODOS',
        'version_hash': 'rescate_v1',
        'arbol_json': {
          'type': 'column',
          'children': [
            {
              'type': 'card',
              'titulo': 'MODO RESCATE OFFLINE (SIN CACHE LOCAL)',
              'subtitulo': 'Esquema: {{sistema.esquema_activo}} · App: {{sistema.app_id_activo}}',
              'color_borde': '#00FF66',
              'children': [
                {
                  'type': 'input',
                  'campo': 'esquema',
                  'label': 'Esquema PostgreSQL:',
                  'placeholder': 'esquema1'
                },
                {
                  'type': 'input',
                  'campo': 'app_id',
                  'label': 'App ID Activa:',
                  'placeholder': 'APP_UNIVERSAL_SDUI'
                },
                {
                  'type': 'input',
                  'campo': 'gemini_key',
                  'label': 'Gemini API Key (Opcional):',
                  'placeholder': 'AIza...'
                },
                {
                  'type': 'button',
                  'texto': 'CAMBIAR_CONTEXTO_MULTI_APP',
                  'color': '#00FF66',
                  'flujo_acciones': [
                    {
                      'accion': 'CAMBIAR_CONTEXTO_MULTI_APP',
                      'esquema': '{{form.esquema}}',
                      'app_id': '{{form.app_id}}',
                      'gemini_key': '{{form.gemini_key}}'
                    }
                  ]
                }
              ]
            }
          ]
        }
      }
    ];
  }
}