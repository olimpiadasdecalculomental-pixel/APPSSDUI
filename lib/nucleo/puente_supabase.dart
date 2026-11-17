import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart' as crypto_pkg;
import 'estado_global.dart';

class PuenteSupabaseSdui {
  static const String _defaultUrl = 'https://alxbydjpoxoavasklwpd.supabase.co';
  static const String _defaultAnonKey = 'sb_publishable_Kc8wekwUqIs78ILNF-j-Qg_LNMYRhn0';

  static String supabaseUrl = _defaultUrl;
  static String supabaseAnonKey = _defaultAnonKey;
  static String esquemaActivo = 'esquema1';
  static String appIdActivo = 'APP_UNIVERSAL_SDUI';
  static String geminiApiKey = '';

  static File _archivoConfigSegura() {
    return File('${Directory.systemTemp.path}/sdui_boveda_contexto_v3.json');
  }

  static File _archivoCacheHive(String esq, String app) {
    final String hashKey = crypto_pkg.md5.convert(utf8.encode('${esq}_$app')).toString();
    return File('${Directory.systemTemp.path}/sdui_hive_cache_$hashKey.json');
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

  static Future llamarRpcNano(
    String nombreRpc,
    Map parametros, {
    String? esquemaOverride,
  }) async {
    final uri = Uri.parse('$supabaseUrl/rest/v1/rpc/$nombreRpc');
    final Map rawHeaders = _construirHeaders(esquemaOverride: esquemaOverride);
    try {
      final resp = await http
          .post(
            uri,
            headers: rawHeaders.map((k, v) => MapEntry(k.toString(), v.toString())),
            body: jsonEncode(parametros),
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
    List pantallasCacheadas = [];

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
      if (res['sin_cambios'] == true && pantallasCacheadas.isNotEmpty) {
        return pantallasCacheadas;
      }

      if (res['pantallas'] is List && (res['pantallas'] as List).isNotEmpty) {
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

    if (pantallasCacheadas.isNotEmpty) {
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
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$geminiApiKey',
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
            .timeout(const Duration(seconds: 12));
        if (rGem.statusCode == 200) {
          final Map dec = jsonDecode(rGem.body) as Map;
          final String textoIa = dec.toString();
          EstadoGlobalSdui.instancia.escribirRuta('ia.ultima_respuesta_gemini', textoIa);
          return {'exito': true, 'respuesta_ia': textoIa, 'meta_rpc': meta};
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
        'pantalla_id': 'P01_CONSOLA_MULTI_APP',
        'orden': 1,
        'titulo': '1. Consola Multi-Esquema & Multi-App',
        'rol_requerido': 'TODOS',
        'version_hash': 'local_v1',
        'arbol_json': {
          'type': 'column',
          'children': [
            {
              'type': 'card',
              'titulo': 'SUPER-APK UNIVERSAL 100% SDUI (MOTOR AGNOSTICO)',
              'subtitulo': 'Esquema: {{sistema.esquema_activo}} · App: {{sistema.app_id_activo}} · Ciclo: {{sistema.estado_ciclo_vida}}',
              'color_borde': '#00FF66',
              'children': [
                {
                  'type': 'input',
                  'campo': 'nuevo_esquema',
                  'label': 'Cambiar Esquema PostgreSQL (esquema1, esquema2):',
                  'placeholder': 'esquema1'
                },
                {
                  'type': 'input',
                  'campo': 'nueva_app_id',
                  'label': 'Cambiar App ID Activa:',
                  'placeholder': 'APP_UNIVERSAL_SDUI'
                },
                {
                  'type': 'button',
                  'texto': 'CONECTAR Y SINCRONIZAR DESDE SUPABASE',
                  'color': '#00FF66',
                  'flujo_acciones': [
                    {
                      'accion': 'CAMBIAR_CONTEXTO_MULTI_APP',
                      'esquema': '{{form.nuevo_esquema}}',
                      'app_id': '{{form.nueva_app_id}}'
                    }
                  ]
                }
              ]
            }
          ]
        }
      },
      {
        'app_id': appIdActivo,
        'pantalla_id': 'P02_MOTORES_COGNITIVOS',
        'orden': 2,
        'titulo': '2. Motores Cognitivos Parametricos',
        'rol_requerido': 'TODOS',
        'version_hash': 'local_v2',
        'arbol_json': {
          'type': 'column',
          'children': [
            {
              'type': 'MOTOR_SECUENCIA_MEMORIA',
              'juego_id': 'SEC_25_NUMS',
              'titulo': '1. MOTOR_SECUENCIA_MEMORIA (25 Items)',
              'items': ['1','2','3','4','5','6','7','8','9','10','11','12','13','14','15','16','17','18','19','20','21','22','23','24','25'],
              'tiempo_muestra_ms': 900,
              'intervalo_ms': 250,
              'modo_ocultar': true
            },
            {
              'type': 'MOTOR_PIZARRA_VEDICA',
              'juego_id': 'VEDICA_CRUZADA',
              'titulo': '2. MOTOR_PIZARRA_VEDICA (Derecha a Izquierda)',
              'operando_a': 14,
              'operando_b': 16,
              'mostrar_guia_cruzada': true,
              'direccion_escritura': 'DERECHA_A_IZQUIERDA'
            },
            {
              'type': 'MOTOR_MATRIZ_Y_FISICA_2D',
              'juego_id': 'MATRIZ_SCHULTE_50',
              'titulo': '3. MOTOR_MATRIZ_Y_FISICA_2D (Schulte 16-50, Chimp, Sorter, AlphaRain)',
              'dimension_n': 5,
              'cantidad_numeros': 25
            },
            {
              'type': 'MOTOR_AUDIO_VOZ_TONO',
              'juego_id': 'VOZ_HZ_BOLSILLO',
              'titulo': '4. MOTOR_AUDIO_VOZ_TONO (Frecuencia Hz + Voz Bolsillo)'
            }
          ]
        }
      },
      {
        'app_id': appIdActivo,
        'pantalla_id': 'P03_HARDWARE_Y_LISTAS',
        'orden': 3,
        'titulo': '3. Bus Hardware, Wearables & Listas',
        'rol_requerido': 'TODOS',
        'version_hash': 'local_v3',
        'arbol_json': {
          'type': 'column',
          'children': [
            {
              'type': 'BUS_HARDWARE_UNIVERSAL',
              'titulo': 'BUS DE HARDWARE UNIVERSAL (QR, POS 80mm, OCR, GPS, 3D, IoT, Smartwatch)'
            },
            {
              'type': 'listview',
              'modo': 'catalogo_8_listas',
              'titulo': 'CATALOGO DE LISTAS INTERACTIVAS CON BOTONES Y CURSOR TOP-10'
            }
          ]
        }
      }
    ];
  }
}