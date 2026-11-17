import 'package:flutter/material.dart';

class EstadoGlobalSdui extends ChangeNotifier {
  static final EstadoGlobalSdui instancia = EstadoGlobalSdui._interno();

  EstadoGlobalSdui._interno() {
    _inicializarLifecycleListener();
  }

  AppLifecycleListener? _lifecycleListener;
  final List<void Function(String evento)> _subscriptoresLifecycle = [];

  final Map<String, dynamic> _almacen = {
    'sistema': {
      'esquema_activo': 'esquema1',
      'app_id_activo': 'APP_UNIVERSAL_SDUI',
      'estado_ciclo_vida': 'RESUMED',
      'contador_pausas': 0,
      'modo_offline': false,
      'ultimo_mensaje': 'Motor SDUI Universal listo.',
    },
    'form': <String, dynamic>{},
    'sesion': <String, dynamic>{
      'usuario_id': 'USR_ANONIMO',
      'rol': 'TODOS',
    },
    'hardware': <String, dynamic>{
      'ultimo_qr': '',
      'frecuencia_hz': 0.0,
      'pasos_smartwatch': 0,
      'bpm_cardiaco': 0,
      'gps_lat': -17.7833,
      'gps_lng': -63.1821,
    },
    'ia': <String, dynamic>{
      'ultima_respuesta_gemini': '',
      'ultimo_puente_api': '',
    },
  };

  Map<String, dynamic> get almacenCompleto => _almacen;

  void _inicializarLifecycleListener() {
    _lifecycleListener = AppLifecycleListener(
      onResume: () => _dispararEventoCicloVida('ON_APP_RESUMED'),
      onPause: () => _dispararEventoCicloVida('ON_APP_PAUSED'),
      onInactive: () => _dispararEventoCicloVida('ON_APP_INACTIVE'),
      onDetach: () => _dispararEventoCicloVida('ON_APP_DETACHED'),
    );
  }

  void _dispararEventoCicloVida(String nombreEvento) {
    final sis = (_almacen['sistema'] as Map<String, dynamic>);
    sis['estado_ciclo_vida'] = nombreEvento;
    if (nombreEvento == 'ON_APP_PAUSED') {
      sis['contador_pausas'] = ((sis['contador_pausas'] as int?) ?? 0) + 1;
    }
    for (final fn in _subscriptoresLifecycle) {
      fn(nombreEvento);
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
    final partes = ruta.trim().split('.');
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
    final partes = ruta.trim().split('.');
    if (partes.isEmpty) return;
    Map<String, dynamic> actual = _almacen;
    for (int i = 0; i < partes.length - 1; i++) {
      final clave = partes[i];
      if (actual[clave] is! Map<String, dynamic>) {
        actual[clave] = <String, dynamic>{};
      }
      actual = actual[clave] as Map<String, dynamic>;
    }
    actual[partes.last] = valor;
    if (notificar) {
      notifyListeners();
    }
  }

  String interpolarTexto(String plantilla) {
    if (!plantilla.contains('{{')) return plantilla;
    final reg = RegExp(r'\{\{\s*([a-zA-Z0-9_.\-]+)\s*\}\}');
    return plantilla.replaceAllMapped(reg, (match) {
      final ruta = match.group(1) ?? '';
      final val = leerRuta(ruta);
      return val != null ? val.toString() : '';
    });
  }

  dynamic interpolarEstructura(dynamic nodo) {
    if (nodo is String) {
      return interpolarTexto(nodo);
    } else if (nodo is Map) {
      final Map<String, dynamic> resultado = {};
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