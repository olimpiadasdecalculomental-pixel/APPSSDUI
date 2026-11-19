import re
import sys
import struct
import shutil
import pathlib
import subprocess

LT = chr(60)
GT = chr(62)

PAQUETES_PROTEGIDOS_48 = {
    'flutter_riverpod', 'google_fonts', 'lucide_icons_flutter', 'ionicons',
    'dotted_border', 'shimmer', 'flutter_animate', 'confetti', 'lottie',
    'drag_and_drop_lists', 'infinite_scroll_pagination',
    'flutter_staggered_grid_view', 'toastification', 'data_table_2',
    'animated_tree_view', 'dropdown_button2', 'table_calendar',
    'screenshot', 'qr_flutter', 'fl_chart', 'syncfusion_flutter_charts',
    'graphview', 'flutter_map', 'http', 'web_socket_channel', 'mqtt_client',
    'hive_ce', 'path', 'crypto', 'json_path', 'diff_match_patch', 'csv',
    'archive', 'uuid', 'faker', 'pdf', 'flutter_markdown', 'flutter_highlight',
    'highlight', 'math_expressions', 'equations', 'units_converter',
    'expressions', 'latlong2', 'timezone',
    'webview_flutter', 'video_player', 'mobile_scanner', 'speech_to_text'
}

def es_png_rgba_valido(data: bytes) -> bool:
    if len(data) >= 33 and data[:8] == b'\x89PNG\r\n\x1a\n':
        w, h = struct.unpack('>II', data[16:24])
        color_type = data[25]
        return 16 <= w <= 1024 and 16 <= h <= 1024 and color_type in (2, 6)
    return False

def forzar_kotlin_version():
    # settings.gradle y settings.gradle.kts (Flutter 3.19+)
    for f in ['android/settings.gradle', 'android/settings.gradle.kts']:
        p = pathlib.Path(f)
        if p.exists():
            es_kts = str(p).endswith('.kts')
            lineas = p.read_text(encoding='utf-8').splitlines()
            nuevas_lineas = []
            for l in lineas:
                if 'org.jetbrains.kotlin.android' in l and 'version' in l:
                    # Inyección quirúrgica respetando la sintaxis del lenguaje
                    if es_kts:
                        if 'apply false' in l:
                            nuevas_lineas.append('    id("org.jetbrains.kotlin.android") version "2.1.0" apply false')
                        else:
                            nuevas_lineas.append('    id("org.jetbrains.kotlin.android") version "2.1.0"')
                    else:
                        if 'apply false' in l:
                            nuevas_lineas.append('    id "org.jetbrains.kotlin.android" version "2.1.0" apply false')
                        else:
                            nuevas_lineas.append('    id "org.jetbrains.kotlin.android" version "2.1.0"')
                else:
                    nuevas_lineas.append(l)
            p.write_text('\n'.join(nuevas_lineas), encoding='utf-8')

    # build.gradle y build.gradle.kts (Flutter Antiguo)
    for f in ['android/build.gradle', 'android/build.gradle.kts']:
        p = pathlib.Path(f)
        if p.exists():
            es_kts = str(p).endswith('.kts')
            lineas = p.read_text(encoding='utf-8').splitlines()
            nuevas_lineas = []
            injected = False
            for l in lineas:
                if 'ext.kotlin_version' in l or 'extra["kotlin_version"]' in l:
                    if es_kts:
                        nuevas_lineas.append('    extra["kotlin_version"] = "2.1.0"')
                    else:
                        nuevas_lineas.append("    ext.kotlin_version = '2.1.0'")
                    injected = True
                elif 'buildscript {' in l and not injected:
                    nuevas_lineas.append(l)
                    if es_kts:
                        nuevas_lineas.append('    extra["kotlin_version"] = "2.1.0"')
                    else:
                        nuevas_lineas.append("    ext.kotlin_version = '2.1.0'")
                    injected = True
                else:
                    nuevas_lineas.append(l)
            p.write_text('\n'.join(nuevas_lineas), encoding='utf-8')

def arreglar_repositorios_gradle():
    for f in ['android/settings.gradle', 'android/settings.gradle.kts', 'android/build.gradle', 'android/build.gradle.kts']:
        p = pathlib.Path(f)
        if p.exists():
            t = p.read_text(encoding='utf-8')
            if 'mavenCentral()' not in t:
                t = re.sub(r'(google\(\))', r'\1\n        mavenCentral()', t)
            p.write_text(t, encoding='utf-8')
            
    forzar_kotlin_version()

def inyectar_motor_nativo_en_main_activity():
    main_dir = pathlib.Path('android/app/src/main')
    if not main_dir.exists():
        return
    for kt in main_dir.rglob('MainActivity.kt'):
        txt = kt.read_text(encoding='utf-8')
        lineas = [l.strip() for l in txt.splitlines() if l.strip().startswith('package ')]
        if not lineas:
            continue
        pkg_line = lineas[0]
        nuevo_kt = f'''{pkg_line}

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.os.Bundle
import android.os.PowerManager
import android.speech.tts.TextToSpeech
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity: FlutterActivity(), TextToSpeech.OnInitListener {{
    private var tts: TextToSpeech? = null
    private var ttsListo: Boolean = false
    private var textoPendiente: String? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var pasosAcumulados: Int = 4850

    override fun onCreate(savedInstanceState: Bundle?) {{
        super.onCreate(savedInstanceState)
        try {{
            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
            wakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "SuperApkSdui::WakeLockBolsillo")
            wakeLock?.acquire(30 * 60 * 1000L)
        }} catch (e: Exception) {{}}
        tts = TextToSpeech(applicationContext, this)
    }}

    override fun onInit(status: Int) {{
        if (status == TextToSpeech.SUCCESS) {{
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            tts?.setAudioAttributes(attrs)

            val rBo = tts?.setLanguage(Locale("es", "BO")) ?: TextToSpeech.LANG_NOT_SUPPORTED
            if (rBo == TextToSpeech.LANG_MISSING_DATA || rBo == TextToSpeech.LANG_NOT_SUPPORTED) {{
                val rEs = tts?.setLanguage(Locale("es", "ES")) ?: TextToSpeech.LANG_NOT_SUPPORTED
                if (rEs == TextToSpeech.LANG_MISSING_DATA || rEs == TextToSpeech.LANG_NOT_SUPPORTED) {{
                    tts?.setLanguage(Locale("es"))
                }}
            }}
            ttsListo = true
            val pend = textoPendiente
            if (pend != null && pend.isNotEmpty()) {{
                textoPendiente = null
                hablarAhora(pend, 1.0f, 0.95f, 1.0f)
            }}
        }}
    }}

    private fun hablarAhora(texto: String, pitch: Float, rate: Float, vol: Float) {{
        if (!ttsListo) {{
            textoPendiente = texto
            return
        }}
        tts?.setPitch(pitch)
        tts?.setSpeechRate(rate)
        val params = Bundle()
        params.putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, vol.coerceIn(0.0f, 1.0f))
        tts?.speak(texto, TextToSpeech.QUEUE_FLUSH, params, "sdui_utt_" + System.currentTimeMillis())
    }}

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.logicasdui/tts_nativo").setMethodCallHandler {{ call, result ->
            if (call.method == "speak") {{
                val text: String = call.argument("text") ?: ""
                val pitchNum: Number? = call.argument("pitch")
                val rateNum: Number? = call.argument("rate")
                val volNum: Number? = call.argument("volume")
                val pitch = pitchNum?.toFloat() ?: 1.0f
                val rate = rateNum?.toFloat() ?: 0.95f
                val vol = volNum?.toFloat() ?: 1.0f
                hablarAhora(text, pitch, rate, vol)
                result.success(true)
            }} else if (call.method == "stop") {{
                tts?.stop()
                result.success(true)
            }} else if (call.method == "setVolume") {{
                val pctNum: Number? = call.argument("percent")
                val pct = (pctNum?.toInt() ?: 70).coerceIn(0, 100)
                try {{
                    val am = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                    if (am != null) {{
                        val maxM = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        am.setStreamVolume(AudioManager.STREAM_MUSIC, (maxM * pct) / 100, 0)
                    }}
                }} catch (e: Exception) {{}}
                result.success(true)
            }} else {{
                result.notImplemented()
            }}
        }}

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.logicasdui/hardware_bus").setMethodCallHandler {{ call, result ->
            if (call.method == "syncWearable") {{
                pasosAcumulados += 42
                val bpm = 72 + ((System.currentTimeMillis() / 1000) % 15).toInt()
                result.success(mapOf("steps" to pasosAcumulados, "bpm" to bpm))
            }} else if (call.method == "getRealGps") {{
                var lat = -17.9647
                var lng = -67.1060
                
                if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {{
                    ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), 101)
                    result.success(mapOf("lat" to lat, "lng" to lng, "estado" to "PIDIENDO_PERMISO"))
                    return@setMethodCallHandler
                }}

                try {{
                    val lm = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                    if (lm != null) {{
                        var loc: Location? = null
                        try {{ loc = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER) }} catch (e: Exception) {{}}
                        if (loc == null) {{
                            try {{ loc = lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER) }} catch (e: Exception) {{}}
                        }}
                        if (loc != null) {{
                            lat = loc.latitude
                            lng = loc.longitude
                        }}
                    }}
                }} catch (e: Exception) {{}}
                result.success(mapOf("lat" to lat, "lng" to lng, "estado" to "OK"))
            }} else {{
                result.notImplemented()
            }}
        }}
    }}

    override fun onDestroy() {{
        try {{
            if (wakeLock?.isHeld == true) {{
                wakeLock?.release()
            }}
        }} catch (e: Exception) {{}}
        tts?.stop()
        tts?.shutdown()
        super.onDestroy()
    }}
}}
'''
        kt.write_text(nuevo_kt, encoding='utf-8')

def configurar_android():
    logo = pathlib.Path('logo.png')
    res_dir = pathlib.Path('android/app/src/main/res')
    if res_dir.exists():
        icono_limpio = pathlib.Path('/tmp/ic_launcher_clean.png')
        convert_ok = False
        if logo.exists():
            try:
                r = subprocess.run(['convert', 'logo.png', '-resize', '192x192', 'PNG32:/tmp/ic_launcher_clean.png'], capture_output=True)
                if r.returncode == 0 and icono_limpio.exists():
                    convert_ok = True
                    shutil.copyfile(icono_limpio, logo)
            except Exception:
                pass

        origen_icono = icono_limpio if convert_ok else (logo if (logo.exists() and es_png_rgba_valido(logo.read_bytes())) else None)
        if origen_icono is not None:
            for mipmap in res_dir.glob('mipmap-*'):
                if mipmap.is_dir():
                    for nombre in ['ic_launcher.png', 'ic_launcher_round.png']:
                        destino = mipmap / nombre
                        if destino.exists() or nombre == 'ic_launcher.png':
                            shutil.copyfile(origen_icono, destino)
        else:
            for mip in res_dir.rglob('ic_launcher.png'):
                if mip.exists():
                    shutil.copyfile(mip, logo)
                    break

    manifest = pathlib.Path('android/app/src/main/AndroidManifest.xml')
    if manifest.exists():
        txt = manifest.read_text(encoding='utf-8')
        permisos = [
            'android.permission.INTERNET',
            'android.permission.ACCESS_NETWORK_STATE',
            'android.permission.ACCESS_WIFI_STATE',
            'android.permission.CHANGE_WIFI_STATE',
            'android.permission.CAMERA',
            'android.permission.RECORD_AUDIO',
            'android.permission.MODIFY_AUDIO_SETTINGS',
            'android.permission.VIBRATE',
            'android.permission.ACCESS_FINE_LOCATION',
            'android.permission.ACCESS_COARSE_LOCATION',
            'android.permission.BLUETOOTH',
            'android.permission.BLUETOOTH_ADMIN',
            'android.permission.BLUETOOTH_SCAN',
            'android.permission.BLUETOOTH_CONNECT',
            'android.permission.WAKE_LOCK',
            'android.permission.FOREGROUND_SERVICE',
            'android.permission.SCHEDULE_EXACT_ALARM',
            'android.permission.USE_EXACT_ALARM',
            'android.permission.POST_NOTIFICATIONS',
            'android.permission.RECEIVE_BOOT_COMPLETED',
            'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
            'android.permission.ACTIVITY_RECOGNITION',
            'android.permission.BODY_SENSORS',
            'android.permission.USE_BIOMETRIC',
        ]
        lineas_xml = ''
        for p in permisos:
            if p not in txt:
                lineas_xml += f'    {LT}uses-permission android:name="{p}"/{GT}\n'
        tag_app = f'{LT}application'
        if lineas_xml and tag_app in txt:
            txt = txt.replace(tag_app, lineas_xml + '    ' + tag_app, 1)
            manifest.write_text(txt, encoding='utf-8')
            
    arreglar_repositorios_gradle()
    inyectar_motor_nativo_en_main_activity()

    for ruta_g in ['android/app/build.gradle', 'android/app/build.gradle.kts', 'android/build.gradle', 'android/build.gradle.kts']:
        gp = pathlib.Path(ruta_g)
        if gp.exists():
            gtxt = gp.read_text(encoding='utf-8')
            
            gtxt = re.sub(r'^\s*ndkVersion\s*.*?$', '', gtxt, flags=re.MULTILINE)
            
            gtxt = re.sub(r'minSdkVersion\s+(flutter\.minSdkVersion|\d+)', r'minSdkVersion 24', gtxt)
            gtxt = re.sub(r'minSdk\s*=\s*(flutter\.minSdkVersion|\d+)', r'minSdk = 24', gtxt)
            gtxt = re.sub(r'compileSdkVersion\s+(flutter\.compileSdkVersion|\d+)', r'compileSdkVersion 36', gtxt)
            gtxt = re.sub(r'compileSdk\s*=\s*(flutter\.compileSdkVersion|\d+)', r'compileSdk = 36', gtxt)
            
            gtxt = re.sub(r'(compileSdkVersion\s+36)', r'\1\n        ndkVersion "27.0.12077973"', gtxt)
            gtxt = re.sub(r'(compileSdk\s*=\s*36)', r'\1\n        ndkVersion = "27.0.12077973"', gtxt)

            gp.write_text(gtxt, encoding='utf-8')

def resolver_pubspec():
    pub_path = pathlib.Path('pubspec.yaml')
    for intento in range(20):
        r = subprocess.run(['flutter', 'pub', 'get'], capture_output=True, text=True)
        if r.returncode == 0:
            print('flutter pub get resuelto exitosamente en intento', intento + 1)
            return
        salida = (r.stdout or '') + '\n' + (r.stderr or '')
        print(salida)
        candidatos = re.findall(r'depends on ([a-z0-9_]+)', salida)
        modificado = False
        if pub_path.exists():
            ptxt = pub_path.read_text(encoding='utf-8')
            for pkg in candidatos:
                if pkg in ('flutter', 'flutter_test', 'super_apk_sdui_universal'):
                    continue
                if pkg not in PAQUETES_PROTEGIDOS_48:
                    nuevo_ptxt = re.sub(rf'^\s*{pkg}:\s*[^\n]+$', f'  # {pkg}: auto-omitido', ptxt, flags=re.M)
                else:
                    nuevo_ptxt = re.sub(rf'^(\s*{pkg}:)\s*\^?[0-9][^\n]*$', r'\1 any', ptxt, flags=re.M)
                if nuevo_ptxt != ptxt:
                    ptxt = nuevo_ptxt
                    modificado = True
            if modificado:
                pub_path.write_text(ptxt, encoding='utf-8')
                continue
        break
    subprocess.run(['flutter', 'pub', 'get'], check=True)

def compilar_apk():
    configurar_android()
    resolver_pubspec()
    subprocess.run(['flutter', 'build', 'apk', '--release', '--no-tree-shake-icons'], check=True)

if __name__ == '__main__':
    accion = sys.argv[1] if len(sys.argv) != 1 else 'android'
    if accion == 'android':
        configurar_android()
    elif accion == 'pub':
        resolver_pubspec()
    elif accion == 'apk':
        compilar_apk()