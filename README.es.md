# Android Emulator para Windows on ARM

[English](README.md) · **Español**

Ejecuta un dispositivo Android 13 real **de forma nativa** en laptops Windows on ARM (Surface Pro, Snapdragon X), con `adb` conectado y listo para desarrollar en React Native, Expo, Flutter o Kotlin.

<p align="center">
  <img src="docs/images/expo-app.png" alt="App de Expo corriendo en la ventana del emulador" width="260">
  &nbsp;
  <img src="docs/images/android-home.png" alt="Pantalla de inicio de Android" width="260">
  &nbsp;
  <img src="docs/images/about-device.png" alt="Acerca del teléfono: Android 13, LineageOS 20 arm64" width="260">
</p>
<p align="center"><sub>Una app de Expo con Fast Refresh, el inicio de Android y "Acerca del teléfono". Las tres son capturas reales en una Surface Pro.</sub></p>

---

## Por qué existe

Si desarrollas apps móviles en una laptop ARM con Windows, seguramente te topaste con esto:

- El Android Emulator de Google no funciona en Windows ARM64.
- Microsoft retiró el Subsistema de Windows para Android en marzo de 2025.
- Los emuladores de terceros están pensados para jugar, no para `adb` y Metro.

Este proyecto cubre ese hueco. Android corre en un contenedor [Waydroid](https://waydro.id) dentro de WSL2. Tu equipo es ARM y Android también, así que no se emula nada: las apps corren a la velocidad nativa del CPU. Se arranca con un comando y Windows lo ve como un dispositivo `adb` normal.

## Lo más importante

- **arm64 nativo.** Sin traducción de instrucciones: los núcleos Snapdragon ejecutan el código de Android directamente.
- **Un comando o un doble clic.** Arranca Android, abre una ventana con tamaño de teléfono y conecta `adb`. El diálogo de "¿Permitir depuración USB?" nunca aparece.
- **Hecho para desarrollar.** Funciona de entrada con `adb`, Metro, Expo Go, Fast Refresh y `adb reverse`.
- **Recursos con tope.** RAM y CPU limitados (4 GB / 4 núcleos por defecto), para que tu IDE y tu navegador sigan fluidos.
- **Reversible.** Con una opción vuelves al kernel oficial de WSL. En Windows no se instala nada, salvo la configuración de WSL y un acceso directo opcional.

## Probado en

| | |
|---|---|
| Equipo | Surface Pro, Snapdragon X Plus (8 núcleos), 16 GB RAM |
| Sistema | Windows 11 Home ARM64, build 26300 |
| WSL | 2.6.3, WSLg 1.0.71, kernel 6.6.87.2 (+ binder) |
| Android | Waydroid 1.6.2, LineageOS 20 (Android 13, API 33), imagen `arm64_only` |
| Verificado con | `adb`, Expo SDK 58 / Expo Go, Fast Refresh, entrada táctil |

Otros equipos Snapdragon X (X Elite, X Plus, X2) deberían comportarse igual. Si pruebas en uno, cuéntanos cómo te fue.

## Inicio rápido

Necesitas Windows 11 on ARM, WSL 2 (`wsl --version`), `adb.exe` de las platform-tools del Android SDK y unos 10 GB libres en disco. Ejecuta todo desde PowerShell, en la raíz del repo:

```powershell
.\windows\setup-wsl.ps1        # 1. Ubuntu 24.04 arm64 en WSL, con systemd          (~3 min)
.\windows\configure-wsl.ps1    # 2. Limita WSL a 4 GB de RAM / 4 núcleos             (instantáneo)
.\windows\install-kernel.ps1   # 3. Descarga y activa el kernel con binder precompilado (~1 min)
.\windows\android.ps1 setup    # 4. Instala Waydroid y descarga Android (~800 MB)    (10-20 min)
.\windows\create-shortcut.ps1  # 5. Opcional: ícono "Android Emulator" en el escritorio
```

Luego arráncalo:

```powershell
.\windows\android.ps1 start
```

```text
==> Opening phone window (432x936)
==> Starting Waydroid session
==> Showing Android
==> Waiting for Android to boot
==> adb bridge: 0.0.0.0:5555 -> 192.168.240.112:5555
adb key authorized.
connected to 172.22.97.155:5555
==> Ready: 172.22.97.155:5555  WayDroid arm64 only Device (arm64-v8a)
    Use it with: $env:ANDROID_SERIAL = '172.22.97.155:5555'
```

> [!NOTE]
> Los pasos 2 y 3 modifican `%USERPROFILE%\.wslconfig` (la primera vez guardan una copia en `.wslconfig.bak`) y reinician WSL. **Todas** las distros de WSL usan el kernel propio, incluida Docker Desktop. Es el mismo kernel de Microsoft más binder, así que Docker sigue funcionando.

> [!IMPORTANT]
> `setup-wsl.ps1` crea un usuario con `sudo` sin contraseña **dentro de la distro Ubuntu** (`/etc/sudoers.d/90-android-wsl`). Eso permite que los scripts de Windows controlen WSL sin quedarse esperando una contraseña.

¿Quieres Play Store? Usa `.\windows\android.ps1 setup -Gapps` y luego [registra el dispositivo con Google](https://www.google.com/android/uncertified).

## Uso diario

```powershell
.\windows\android.ps1 start                  # ventana tamaño teléfono (432x936)
.\windows\android.ps1 start -Window 480x1040 # el tamaño que quieras
.\windows\android.ps1 start -Full            # usa toda la ventana de WSLg
.\windows\android.ps1 status                 # estado de Waydroid + adb devices
.\windows\android.ps1 stop                   # apaga Android y libera la RAM
```

O usa el ícono del escritorio, como cualquier app:

- **Abrir:** doble clic en **Android Emulator**. Una consola arranca Android, conecta `adb` y muestra el serial. Puedes cerrar esa consola cuando quieras.
- **Cerrar:** haz clic en la **X** de la ventana de Android. Android se apaga, el puente adb se detiene y WSL libera la memoria. Es lo mismo que `android.ps1 stop`.
- **Volver a abrir:** doble clic en el ícono otra vez. Android siempre arranca limpio.

> [!TIP]
> El serial es `<IP de WSL>:5555`, y esa IP puede cambiar cuando WSL se reinicia. `start` siempre imprime la actual.

### React Native / Expo

```powershell
.\windows\android.ps1 start
.\windows\rn-connect.ps1                      # adb reverse para Metro (8081) y Expo (19000-19002)
$env:ANDROID_SERIAL = '<serial que imprime start>'

npx expo start --android                      # Expo Go (se instala solo la primera vez)
npx expo run:android                          # o un development build
npx react-native run-android                  # o React Native sin Expo
```

Fast Refresh funciona como en cualquier dispositivo: guardas un archivo y la pantalla se actualiza sin perder el estado. Las reglas de `adb reverse` se borran cuando Android se reinicia, así que ejecuta `rn-connect.ps1` de nuevo después de cada `start`.

### Flutter, Android Studio y otras herramientas

Todo lo que usa `adb` ve el dispositivo: `adb devices`, `flutter devices`, `flutter run -d <serial>`, `./gradlew installDebug` y el selector de dispositivos de Android Studio. Por ahora solo se verificó de punta a punta el flujo de Expo / React Native. Se agradecen reportes con otras herramientas.

## Cómo funciona

```
Windows 11 ARM64
 └─ VM de WSL2 ─ Ubuntu 24.04 arm64, kernel propio con binder
     ├─ Weston (anidado, kiosk shell) ── una ventana tamaño teléfono en tu escritorio vía WSLg
     │   └─ Waydroid ─ contenedor LXC con LineageOS 20 (Android 13, arm64)
     └─ socat :5555 ──► adbd de Android  ◄── adb.exe en Windows (vía la IP de WSL)
```

Cada pieza resuelve un problema concreto:

| Problema | Solución |
|---|---|
| El kernel de WSL no trae **binder**, el IPC de Android | [`build-kernel.sh`](wsl/kernel/build-kernel.sh) compila el kernel de Microsoft de la misma versión, más [`waydroid.config`](wsl/kernel/waydroid.config) (binder y las tablas de iptables para la red del contenedor) |
| WSLg siempre maximiza la ventana de Waydroid | Android se dibuja dentro de un **Weston** anidado en modo kiosk, con tamaño de teléfono |
| Con systemd, WSL apaga la distro cuando no hay ningún `wsl.exe` conectado | Un `wsl.exe` oculto que ejecuta [`keep-alive.sh`](wsl/keep-alive.sh) la mantiene viva mientras la ventana de Android está abierta, y luego termina solo. Se lanza vía WMI, así que cerrar la consola no lo mata |
| Android no puede volver a dibujar en una ventana nueva si su compositor desapareció | Cerrar la ventana detiene toda la sesión de Android (un `ExecStopPost` de systemd), así que cada arranque es limpio |
| Los procesos en segundo plano mueren con el `wsl.exe` que los lanzó | Weston, la sesión, la UI y el puente adb corren como **unidades de usuario de systemd**, con *linger* activado |
| El reenvío de `localhost` de WSL no es confiable con systemd | `adb` se conecta a la IP de la distro, a través de un puente `socat` |
| El diálogo "¿Permitir depuración USB?" impide automatizar | `start` autoriza de antemano tu `adbkey.pub` de Windows dentro de Android |
| No hay GPU para el Mesa de Waydroid en WSL | El render usa ANGLE + SwiftShader (por software). Para la UI de una app es de sobra |

## Kernels precompilados

No necesitas compilar nada. Un [workflow de GitHub Actions](.github/workflows/build-kernel.yml) compila el kernel con binder en un runner arm64 nativo y lo publica en [Releases](https://github.com/Jmzp/android-emulator-windows-arm/releases) como `kernel-<versión>`, con el `Image`, su `Image.sha256` y la `config` completa.

`install-kernel.ps1` lee la versión de tu kernel de WSL (`uname -r`), descarga el release correspondiente y verifica el SHA-256 antes de usarlo. Si no hay release para tu versión, lo compila localmente.

```powershell
.\windows\install-kernel.ps1                     # kernel precompilado para tu WSL (cerca de un minuto)
.\windows\install-kernel.ps1 -Version 6.6.87.2   # una versión precompilada específica
.\windows\install-kernel.ps1 -Build              # compilarlo localmente (20-60 min)
```

Los nuevos releases del kernel de Microsoft se detectan cada lunes, y cualquier cambio en `wsl/kernel/` recompila todos los kernels publicados. Para compilar otra versión a pedido: **Actions → Build WSL kernel → Run workflow**, con tags como `linux-msft-wsl-6.18.54.1`. Los forks pueden apuntar el instalador a sus propios releases con `ANDROID_WSL_RELEASE_REPO`.

## Configuración

### RAM y CPU

Android vive dentro de la VM de WSL, así que los límites de `.wslconfig` son sus límites reales. Son topes, no reservas: la memoria que Android no usa vuelve a Windows (`autoMemoryReclaim=dropCache`).

```powershell
.\windows\configure-wsl.ps1                            # por defecto: 4 GB, 4 núcleos, 4 GB de swap
.\windows\configure-wsl.ps1 -MemoryGB 6 -Processors 6  # más holgura
```

Android 13 usa unos 2–3 GB en reposo, así que 4 GB alcanzan para desarrollar. Si compilas el kernel localmente (`-Build`), sube a 6 GB o más mientras tanto: el enlazado consume mucha memoria.

### Tamaño y densidad de pantalla

El tamaño de la ventana es el tamaño de pantalla que ve Android. El valor por defecto, 432×936 a densidad 180, se comporta como un teléfono de ~384×832 dp. Puedes cambiarlo en cada arranque (`-Window 480x1040`) o simular otros dispositivos dentro de la misma ventana:

```powershell
adb shell wm density 160        # cabe más contenido (o 200 para elementos más grandes)
adb shell wm size 1080x2340     # otra resolución lógica, escalada a la ventana
adb shell wm size reset; adb shell wm density reset
```

### Variables de entorno

| Variable (Windows) | Por defecto | Uso |
|---|---|---|
| `ANDROID_WSL_DISTRO` | `Ubuntu-24.04` | Distro de WSL que hospeda Android |
| `ANDROID_WSL_ADB_PORT` | `5555` | Puerto del puente adb dentro de WSL |
| `ANDROID_WSL_RELEASE_REPO` | `Jmzp/android-emulator-windows-arm` | De dónde descarga `install-kernel.ps1` los kernels precompilados |

Las propiedades de sistema de Android están en la sección `[properties]` de `/var/lib/waydroid/waydroid.cfg`, que inicializa [`setup-waydroid.sh`](wsl/setup-waydroid.sh). Después de editarlas, ejecuta `sudo waydroid upgrade --offline`.

## Estructura del proyecto

```
.github/workflows/
  build-kernel.yml           Compila el kernel en runners arm64 y publica los Releases
windows/                     PowerShell, se ejecuta desde Windows
  setup-wsl.ps1              Instala y prepara la distro Ubuntu
  configure-wsl.ps1          Límites de RAM / CPU / swap para WSL
  install-kernel.ps1         Descarga (o compila con -Build) y activa el kernel con binder (-Revert para deshacer)
  android.ps1                setup | start | stop | status
  rn-connect.ps1             adb reverse para Metro / Expo
  create-shortcut.ps1        Acceso directo con ícono en el escritorio
  common.ps1                 Funciones compartidas
wsl/                         Bash, corre dentro de la distro
  kernel/build-kernel.sh     Clona, configura y compila el kernel de WSL
  kernel/waydroid.config     Fragmento de Kconfig (binder, netfilter)
  setup-waydroid.sh          Instala Waydroid, descarga Android y fija propiedades
  start-android.sh           Weston + sesión + UI + puente adb (unidades de systemd)
  stop-android.sh            Detiene todo lo anterior
  authorize-adb.sh           Autoriza una clave adb de Windows dentro de Android
  keep-alive.sh              Mantiene WSL encendido mientras la ventana de Android está abierta
assets/                      Ícono del acceso directo
docs/images/                 Capturas de pantalla
ROADMAP.md                   Lo que viene
```

## Solución de problemas

Todo lo relacionado con Android corre como unidades de usuario de systemd dentro de la distro (`waydroid-weston`, `waydroid-session`, `waydroid-ui`, `waydroid-adb-bridge`). Empieza por los logs:

```bash
wsl -d Ubuntu-24.04
journalctl --user -u waydroid-session -u waydroid-ui -u waydroid-weston
sudo waydroid logcat -b crash       # crashes de Android
sudo tail /var/lib/waydroid/waydroid.log
```

**Kernel y WSL**

| Síntoma | Solución |
|---|---|
| `binder is not available` | `wsl -d Ubuntu-24.04 -- uname -r` debe terminar en `-waydroid`. Si no, revisa `kernel=` en `.wslconfig` y ejecuta `wsl --shutdown`. |
| La compilación del kernel se corta sin error y WSL "se reinicia" cada ~90 s | El OOM killer mató algo, y systemd (`OOMPolicy=stop`) sigue deteniendo todo lo lanzado desde `wsl.exe`. Ejecuta `wsl --shutdown`, sube la RAM con `configure-wsl.ps1` y vuelve a compilar. La compilación es incremental. |
| `CONFIG_... did not end up =y` | La rama del kernel cambió sus dependencias. Revisa `make menuconfig` en `~/wsl-kernel-build/WSL2-Linux-Kernel`. |
| WSL se actualizó a otra versión de kernel | No se rompe nada, porque tu kernel sigue cargándose. Para seguir la nueva versión, ejecuta otra vez `install-kernel.ps1`. |
| Los scripts se cuelgan y `wsl -l -v` no responde | El servicio de WSL se trabó. Ejecuta `wsl --shutdown --force` (si hace falta, cierra antes los `wsl.exe` sueltos) y luego `android.ps1 start`. |

**Android y Waydroid**

| Síntoma | Solución |
|---|---|
| `waydroid-net.sh` falla con `table mangle does not exist` | Tu kernel es anterior a las opciones de netfilter. Ejecuta otra vez `install-kernel.ps1` con el `waydroid.config` actual. |
| Pantalla negra, y `system_server` crashea en `getCompositionColorSpaces` | El compositor rechazó el tamaño del buffer. No fijes `persist.waydroid.width/height`: lo controla el tamaño de la ventana (`-Window`). |
| Ventana negra al volver a abrir | Android seguía corriendo desde una ventana que ya no existe. Los scripts actuales lo resuelven; si pasa, ejecuta `android.ps1 stop` y luego `start`. |
| Android se apaga solo | Desapareció el `wsl.exe` oculto que lo mantiene vivo. Ejecuta `android.ps1 start` de nuevo. |
| Android sin internet | `sudo waydroid container restart`, y luego revisa que `sudo iptables -t nat -L` tenga reglas para `waydroid0`. |

**adb**

| Síntoma | Solución |
|---|---|
| `adb connect` rechazado | `waydroid status` debe mostrar `RUNNING` con una IP, y `systemctl --user status waydroid-adb-bridge` debe estar activo. |
| `failed to authenticate` | Regeneraste `%USERPROFILE%\.android\adbkey`. Ejecuta `android.ps1 start` de nuevo para autorizar la nueva clave. |
| El dispositivo aparece `offline` | Android se detuvo o WSL se reinició. Ejecuta `android.ps1 start`; puede que el serial haya cambiado. |

## Limitaciones

- **No es un AVD.** El Device Manager de Android Studio no lo administra. Aparece como dispositivo conectado por red.
- **Render por software.** Sirve para la UI de apps y para desarrollar, pero no para juegos o 3D pesado.
- **Una sola versión de Android.** LineageOS 20 (Android 13, API 33). No se puede cambiar de nivel de API como con las imágenes de AVD.
- **Solo apps arm64.** Los Snapdragon X no ejecutan código ARM de 32 bits, así que Waydroid usa la imagen `arm64_only`. Las apps solo x86 o solo `armeabi-v7a` no se instalan. Los builds de React Native y Expo incluyen `arm64-v8a` por defecto.
- **El serial puede cambiar** tras reiniciar WSL, porque se basa en la IP de WSL.

## Desinstalar

```powershell
.\windows\android.ps1 stop
.\windows\install-kernel.ps1 -Revert           # vuelve al kernel oficial de WSL
wsl --unregister Ubuntu-24.04                  # borra la distro y todo su contenido
Remove-Item "$env:USERPROFILE\wsl-kernel" -Recurse
Remove-Item "$([Environment]::GetFolderPath('Desktop'))\Android Emulator.lnk"
```

Para recuperar tus límites anteriores de WSL, copia `%USERPROFILE%\.wslconfig.bak` encima de `.wslconfig`.

## Roadmap

Serial fijo `emulator-5554`, instalador en un paso, comando `doctor`, investigación de aceleración por GPU y más: mira [ROADMAP.md](ROADMAP.md) (en inglés). Las ideas y los pull requests son bienvenidos.

## Créditos

- [Waydroid](https://waydro.id) ejecuta Android en un contenedor Linux.
- [LineageOS](https://lineageos.org) aporta las imágenes de Android que usa Waydroid.
- [Microsoft WSL2-Linux-Kernel](https://github.com/microsoft/WSL2-Linux-Kernel) es el kernel que este proyecto extiende con binder.
- [Weston](https://gitlab.freedesktop.org/wayland/weston) aporta la ventana anidada con tamaño de teléfono.

## Licencia

[MIT](LICENSE). Los scripts de este repo tienen licencia MIT. Waydroid, LineageOS y el kernel de Linux conservan sus propias licencias, y el kernel que compilas localmente es GPL-2.0.
