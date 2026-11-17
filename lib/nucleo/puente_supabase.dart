import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'estado_global.dart';

class PuenteSupabaseSdui {
  static const String _defaultUrl = 'https://alxbydjpoxoavasklwpd.supabase.co';
  static const String _defaultAnonKey = 'sb_publishable_Kc8wekwUqIs78ILNF-j-Qg_LNMYRhn0';

  static const FlutterSecureStorage _bovedaSegura = FlutterSecureStorage();
  static Box? _cajaHiveCache;

  static String supabaseUrl = _defaultUrl;
  static String supabaseAnonKey = _defaultAnonKey;
  static String esquemaActivo = 'esquema1';
  static String appIdActivo = 'APP_UNIVERSAL_SDUI';
  static String geminiApiKey = '';

  static Future<void> inicializarPuenteUniversal() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      Hive.init(dir.path);
      _cajaHiveCache = await Hive.openBox('sdui_universal_cache_v3');
    } catch (_) {}

    try {
      final esqGuardado = await _bovedaSegura.read(key: 'sdui_esquema_activo');
      final appGuardada = await _bovedaSegura.read(key: 'sdui_app_id_activo');
      final urlGuardada = await _bovedaSegura.read(key: 'sdui_supabase_url');
      final keyGuardada = await _bovedaSegura.read(key: 'sdui_supabase_key');
      final gemGuardada = await _bovedaSegura.read(key: 'sdui_gemini_key');

      if (esqGuardado != null && esqGuardado.trim().isNotEmpty) {
        esquemaActivo = esqGuardado.trim();
      }
      if (appGuardada != null && appGuardada.trim().isNotEmpty) {
        appIdActivo = appGuardada.trim();
      }
      if (urlGuardada != null && urlGuardada.trim().isNotEmpty) {
        supabaseUrl = urlGuardada.trim();
      }
      if (keyGuardada != null && keyGuardada.trim().isNotEmpty) {
        supabaseAnonKey = keyGuardada.trim();
      }
      if (gemGuardada != null && gemGuardada.trim().isNotEmpty) {
        geminiApiKey = gemGuardada.trim();
      }
    } catch (_) {}

    EstadoGlobalSdui.instancia.escribirRuta('sistema.esquema_activo', esquemaActivo, notificar: false);
    EstadoGlobalSdui.instancia.escribirRuta('sistema.app_id_activo', appIdActivo, notificar: true);
  }

  static Future<void> cambiarContextoMultiApp({
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
      await _bovedaSegura.write(key: 'sdui_esquema_activo', value: esquemaActivo);
      await _bovedaSegura.write(key: 'sdui_app_id_activo', value: appIdActivo);
      if (nuevaUrl != null && nuevaUrl.isNotEmpty) {
        await _bovedaSegura.write(key: 'sdui_supabase_url', value: supabaseUrl);
      }
      if (nuevaAnonKey != null && nuevaAnonKey.isNotEmpty) {
        await _bovedaSegura.write(key: 'sdui_supabase_key', value: supabaseAnonKey);
      }
      if (nuevaGeminiKey != null && nuevaGeminiKey.isNotEmpty) {
        await _bovedaSegura.write(key: 'sdui_gemini_key', value: geminiApiKey);
      }
    } catch (_) {}

    EstadoGlobalSdui.instancia.escribirRuta('sistema.esquema_activo', esquemaActivo, notificar: false);
    EstadoGlobalSdui.instancia.escribirRuta('sistema.app_id_activo', appIdActivo, notificar: true);
  }

  static Map<String, String> _construirHeaders({String? esquemaOverride}) {
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

  static Future> llamarRpcNano(
    String nombreRpc,
    Map<String, dynamic> parametros, {
    String? esquemaOverride,
  }) async {
    final uri = Uri.parse('$supabaseUrl/rest/v1/rpc/$nombreRpc');
    try {
      final resp = await http
          .post(
            uri,
            headers: _construirHeaders(esquemaOverride: esquemaOverride),
            body: jsonEncode(parametros),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        EstadoGlobalSdui.instancia.escribirRuta('sistema.modo_offline', false, notificar: false);
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
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
        'mensaje': 'Modo Offline activo (Cache Hive): $e',
      };
    }
  }

  static Future<List>> sincronizarPantallasConHash({
    String? appOverride,
    String? esquemaOverride,
  }) async {
    final String appObj = appOverride ?? appIdActivo;
    final String esqObj = esquemaOverride ?? esquemaActivo;
    final String claveHash = 'hash_${esqObj}_$appObj';
    final String clavePantallas = 'pantallas_${esqObj}_$appObj';

    final String hashLocal = _cajaHiveCache?.get(claveHash)?.toString() ?? '';

    final res = await llamarRpcNano(
      'nano_leer_pantalla',
      {
        'p_app_id': appObj,
        'p_pantalla_id': '__TODAS__',
        'p_hash_cliente': hashLocal,
      },
      esquemaOverride: esqObj,
    );

    if (res['exito'] == true) {
      if (res['sin_cambios'] == true && _cajaHiveCache != null) {
        final guardado = _cajaHiveCache?.get(clavePantallas);
        if (guardado is String && guardado.isNotEmpty) {
          final List listaDec = jsonDecode(guardado) as List;
          return listaDec.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }

      if (res['pantallas'] is List) {
        final List listaRemota = res['pantallas'] as List;
        final List> pantallasTipadas =
            listaRemota.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        final String nuevoHash = res['version_hash']?.toString() ?? '';
        try {
          await _cajaHiveCache?.put(claveHash, nuevoHash);
          await _cajaHiveCache?.put(clavePantallas, jsonEncode(pantallasTipadas));
        } catch (_) {}
        return pantallasTipadas;
      }
    }

    if (_cajaHiveCache != null) {
      final respaldo = _cajaHiveCache?.get(clavePantallas);
      if (respaldo is String && respaldo.isNotEmpty) {
        final List listaRes = jsonDecode(respaldo) as List;
        return listaRes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    }

    return _semillaLocalEmergencia();
  }

  static Future> ejecutarPuenteApiYGemini({
    required String apiId,
    required Map<String, dynamic> payload,
  }) async {
    final meta = await llamarRpcNano(
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
        final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: geminiApiKey);
        final response = await model.generateContent([Content.text(promptUsuario)]);
        final textoIa = response.text ?? 'Respuesta generada por Gemini.';
        EstadoGlobalSdui.instancia.escribirRuta('ia.ultima_respuesta_gemini', textoIa);
        return {'exito': true, 'respuesta_ia': textoIa, 'meta_rpc': meta};
      } catch (e) {
        EstadoGlobalSdui.instancia.escribirRuta('ia.ultima_respuesta_gemini', 'Error Gemini: $e');
      }
    }

    final String endpointExterno = payload['endpoint_url']?.toString() ?? meta['endpoint_url']?.toString() ?? '';
    if (endpointExterno.startsWith('http') && !endpointExterno.contains('generativelanguage.googleapis.com')) {
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
        'Puente API/Gemini listo. Configura tu API Key o revisa colecciones_datos.';
    EstadoGlobalSdui.instancia.escribirRuta('ia.ultima_respuesta_gemini', resumen);
    return {'exito': true, 'mensaje': resumen, 'meta': meta};
  }

  static List> _semillaLocalEmergencia() {
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
                  'campo': 'supabase_url',
                  'label': 'URL Proyecto Supabase:',
                  'placeholder': 'https://tu-proyecto.supabase.co'
                },
                {
                  'type': 'input',
                  'campo': 'supabase_key',
                  'label': 'Anon Key Supabase:',
                  'placeholder': 'sb_publishable_...'
                },
                {
                  'type': 'input',
                  'campo': 'nuevo_esquema',
                  'label': 'Esquema Activo (esquema1, esquema2, etc.):',
                  'placeholder': 'esquema1'
                },
                {
                  'type': 'input',
                  'campo': 'nueva_app_id',
                  'label': 'App ID Activa:',
                  'placeholder': 'APP_UNIVERSAL_SDUI'
                },
                {
                  'type': 'input',
                  'campo': 'gemini_key',
                  'label': 'API Key de Gemini IA (Opcional):',
                  'placeholder': 'AIza...'
                },
                {
                  'type': 'button',
                  'texto': 'CONECTAR Y SINCRONIZAR DESDE SUPABASE',
                  'color': '#00FF66',
                  'flujo_acciones': [
                    {
                      'accion': 'CAMBIAR_CONTEXTO_MULTI_APP',
                      'esquema': '{{form.nuevo_esquema}}',
                      'app_id': '{{form.nueva_app_id}}',
                      'url': '{{form.supabase_url}}',
                      'anon_key': '{{form.supabase_key}}',
                      'gemini_key': '{{form.gemini_key}}'
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