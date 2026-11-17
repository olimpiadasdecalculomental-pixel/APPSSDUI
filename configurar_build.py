import re
import sys
import struct
import shutil
import pathlib
import subprocess

LT = chr(60)
GT = chr(62)

def es_png_rgba_valido(data: bytes) -> bool:
    if len(data) >= 33 and data[:8] == b'\x89PNG\r\n\x1a\n':
        w, h = struct.unpack('>II', data[16:24])
        color_type = data[25]
        return 16 <= w <= 1024 and 16 <= h <= 1024 and color_type in (2, 6)
    return False

def configurar_android():
    logo = pathlib.Path('logo.png')
    res_dir = pathlib.Path('android/app/src/main/res')
    if logo.exists() and res_dir.exists():
        icono_limpio = pathlib.Path('/tmp/ic_launcher_clean.png')
        convert_ok = False
        try:
            r = subprocess.run(['convert', 'logo.png', '-resize', '192x192', 'PNG32:/tmp/ic_launcher_clean.png'], capture_output=True)
            if r.returncode == 0 and icono_limpio.exists():
                convert_ok = True
        except Exception:
            pass

        origen_icono = icono_limpio if convert_ok else (logo if es_png_rgba_valido(logo.read_bytes()) else None)
        if origen_icono is not None:
            for mipmap in res_dir.glob('mipmap-*'):
                if mipmap.is_dir():
                    for nombre in ['ic_launcher.png', 'ic_launcher_round.png']:
                        destino = mipmap / nombre
                        if destino.exists() or nombre == 'ic_launcher.png':
                            shutil.copyfile(origen_icono, destino)

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

    for ruta_s in ['android/settings.gradle', 'android/settings.gradle.kts']:
        sp = pathlib.Path(ruta_s)
        if sp.exists():
            stxt = sp.read_text(encoding='utf-8')
            stxt = re.sub(
                r'id\s+"org\.jetbrains\.kotlin\.android"\s+version\s+"[^"]+"',
                'id "org.jetbrains.kotlin.android" version "2.1.0"',
                stxt
            )
            stxt = re.sub(
                r'id\("org\.jetbrains\.kotlin\.android"\)\s+version\s+"[^"]+"',
                'id("org.jetbrains.kotlin.android") version "2.1.0"',
                stxt
            )
            sp.write_text(stxt, encoding='utf-8')

    for ruta_b in ['android/build.gradle', 'android/build.gradle.kts']:
        bp = pathlib.Path(ruta_b)
        if bp.exists():
            btxt = bp.read_text(encoding='utf-8')
            btxt = re.sub(r"ext\.kotlin_version\s*=\s*'[^']+'", "ext.kotlin_version = '2.1.0'", btxt)
            btxt = re.sub(r'ext\.kotlin_version\s*=\s*"[^"]+"', 'ext.kotlin_version = "2.1.0"', btxt)
            bp.write_text(btxt, encoding='utf-8')

    for ruta_g in ['android/app/build.gradle', 'android/app/build.gradle.kts']:
        gp = pathlib.Path(ruta_g)
        if gp.exists():
            gtxt = gp.read_text(encoding='utf-8')
            gtxt = gtxt.replace('minSdk = flutter.minSdkVersion', 'minSdk = 26')
            gtxt = gtxt.replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 26')
            gtxt = re.sub(r'minSdk\s*=\s*\d+', 'minSdk = 26', gtxt)
            gtxt = re.sub(r'minSdkVersion\s+\d+', 'minSdkVersion 26', gtxt)
            gtxt = gtxt.replace('compileSdk = flutter.compileSdkVersion', 'compileSdk = 35')
            gtxt = re.sub(r'compileSdk\s*=\s*\d+', 'compileSdk = 35', gtxt)
            gp.write_text(gtxt, encoding='utf-8')

def resolver_pubspec():
    # Resuelve las 110 librerias intactas sin recortar ni sobrescribir pubspec.yaml
    subprocess.run(['flutter', 'pub', 'get'], check=True)

def compilar_apk():
    configurar_android()
    subprocess.run(['flutter', 'pub', 'get'], check=True)
    subprocess.run(['flutter', 'build', 'apk', '--release', '--no-tree-shake-icons'], check=True)

if __name__ == '__main__':
    accion = sys.argv[1] if len(sys.argv) != 1 else 'android'
    if accion == 'android':
        configurar_android()
    elif accion == 'pub':
        resolver_pubspec()
    elif accion == 'apk':
        compilar_apk()