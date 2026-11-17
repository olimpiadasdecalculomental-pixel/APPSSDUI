import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'nucleo/puente_supabase.dart';
import 'motores/renderizador_atomico.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A0505),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orangeAccent),
        ),
        child: Text(
          'Escudo SDUI Universal Activo: ${details.exceptionAsString()}',
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      );
    };
    await PuenteSupabaseSdui.inicializarPuenteUniversal();
    runApp(const SuperApkUniversalSduiApp());
  }, (error, stack) {
    debugPrint('Escudo Global SDUI: $error');
  });
}

class SuperApkUniversalSduiApp extends StatelessWidget {
  const SuperApkUniversalSduiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Super-APK Universal 100% SDUI',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF050814),
      ),
      home: const LienzoUniversalSdui(),
    );
  }
}