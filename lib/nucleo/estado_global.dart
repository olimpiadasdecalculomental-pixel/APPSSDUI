import 'package:flutter/material.dart';

class EstadoGlobalSdui extends ChangeNotifier {
  static final EstadoGlobalSdui instancia = EstadoGlobalSdui._interno();

  EstadoGlobalSdui._interno() {
    _inicializarLifecycleListener();
  }

  AppLifecycleListener? _lifecycleListener;
  final List _subscriptoresLifecycle = [];

  final Map _almacen = {
    'sistema': {
      'esquema_activo': 'esquema1',
      'app_id_activo': 'APP_UNIVERSAL_SDUI',
      'estado_ciclo_vida': 'RESUMED',
      'contador_pausas': 0,
      'modo_offline': false,
      'color_primario': '#00FF66',
      'color_secundario': '#00F3FF',
      'pantalla_completa': false,
      'ultimo_mensaje': 'Motor SDUI Universal v4.2 listo.',
      'ultima_lista_top10': [],
      'ultima_respuesta_rpc': {},
      'ultima_regla_sql': {},
      'config_global': {},
    },
    'form': {},
    'sesion': {
      'usuario_id': 'USR_ANONIMO',
      'nombre': 'Invitado',
      'rol': 'TODOS',
      'foto_url': '',
      'token_entrada': '',
      'token_salida': '',
    },
    'hardware': {
      'ultimo_qr': '',
      'frecuencia_hz': 440.0,
      'pasos_smartwatch': 4850,
      'bpm_cardiaco': 74,
      'gps_lat': -17.9647,
      'gps_lng': -67.1060,
      'volumen_pct': 80,
      'fecha_seleccionada': '',
    },
    'ia': {
      'ultima_respuesta_gemini': '',
      'ultimo_puente_api': '',
    },
  };

  Map get almacenCompleto => _almacen;

  void _inicializarLifecycleListener() {
    _lifecycleListener = AppLifecycleListener(
      onResume: () => _dispararEventoCicloVida('ON_APP_RESUMED'),
      onPause: () => _dispararEventoCicloVida('ON_APP_PAUSED'),
      onInactive: () => _dispararEventoCicloVida('ON_APP_INACTIVE'),
      onDetach: () => _dispararEventoCicloVida('ON_APP_DETACHED'),
    );
  }

  void _dispararEventoCicloVida(String nombreEvento) {
    final Map sis = _almacen['sistema'] as Map;
    sis['estado_ciclo_vida'] = nombreEvento;
    if (nombreEvento == 'ON_APP_PAUSED') {
      sis['contador_pausas'] = ((sis['contador_pausas'] as int?) ?? 0) + 1;
    }
    for (final fn in _subscriptoresLifecycle) {
      (fn as Function(String))(nombreEvento);
    }
    notifyListeners();
  }

  void registrarListenerCicloVida(void Function(String evento) callback) {
    if (!_subscriptoresLifecycle.contains(callback)) {
      _subscriptoresLifecycle.add(callback);
    }
  }

  void removerListenerCicloVida(void Function(String evento) callback) {
    _subscriptoresLifecycle.remove(callback);
  }

  dynamic leerRuta(String ruta) {
    final List partes = ruta.trim().split('.');
    dynamic actual = _almacen;
    for (final p in partes) {
      if (actual is Map && actual.containsKey(p)) {
        actual = actual[p];
      } else {
        return null;
      }
    }
    return actual;
  }

  void escribirRuta(String ruta, dynamic valor, {bool notificar = true}) {
    final List partes = ruta.trim().split('.');
    if (partes.isEmpty) return;
    Map actual = _almacen;
    for (int i = 0; i < partes.length - 1; i++) {
      final String clave = partes[i].toString();
      if (actual[clave] is! Map) {
        actual[clave] = {};
      }
      actual = actual[clave] as Map;
    }
    actual[partes.last.toString()] = valor;
    if (notificar) {
      notifyListeners();
    }
  }

  String interpolarTexto(String plantilla) {
    if (!plantilla.contains('{{')) return plantilla;
    final reg = RegExp(r'\{\{\s*([a-zA-Z0-9_.\-]+)\s*\}\}');
    return plantilla.replaceAllMapped(reg, (match) {
      final String ruta = match.group(1) ?? '';
      final val = leerRuta(ruta);
      return val != null ? val.toString() : '';
    });
  }

  dynamic interpolarEstructura(dynamic nodo) {
    if (nodo is String) {
      return interpolarTexto(nodo);
    } else if (nodo is Map) {
      final Map resultado = {};
      nodo.forEach((k, v) {
        resultado[k.toString()] = interpolarEstructura(v);
      });
      return resultado;
    } else if (nodo is List) {
      return nodo.map((e) => interpolarEstructura(e)).toList();
    }
    return nodo;
  }
}