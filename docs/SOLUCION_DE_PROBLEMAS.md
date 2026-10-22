# Solución de problemas

Empieza por el log. Casi todos los fallos dejan un mensaje claro en:

- `runtime\logs\setup.log` — instalación.
- `runtime\logs\mariadb.err` — MariaDB.
- `runtime\logs\laravel-console.log` — Laravel/PHP.
- `runtime\logs\edge-console.log` — proxy HTTPS.
- `ns-server\Database\Laragon\ninjasage\storage\logs\laravel.log` — excepciones.

En macOS, las rutas son las mismas con `/`.

---

## Tabla rápida

| Síntoma | Causa probable | Solución |
|---|---|---|
| `setup.bat` se cierra al instante | Error antes de mostrar la consola | Abre `cmd`, arrastra `setup.bat`, Enter; revisa `setup.log` |
| “PowerShell no se reconoce” | Windows muy antiguo o PATH roto | Usa Windows 10/11; ejecuta `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe` |
| Descarga fallida | Firewall, proxy, antivirus | Descarga manual (ver abajo) y coloca los binarios |
| `php.exe` no arranca | Falta VC++ 2015–2022 | Instala `vc_redist.x64.exe` |
| MariaDB no arranca | Puerto 3307 ocupado, datadir bloqueado | `netstat`, cierra el proceso, revisa `mariadb.err` |
| Laravel 500 | `.env`, APP_KEY, permisos, DB | Revisa `laravel.log`; ejecuta `php artisan key:generate` |
| `ERR_CONNECTION_REFUSED` | Servicios parados o Chrome sin flags | Usa `launch.bat`; comprueba puertos |
| Aviso de certificado | Certificado autofirmado | Es normal; usa el Chrome del lanzador |
| Pantalla negra | Carga inicial de Ruffle | Espera 15–25 s; pulsa ↻ |
| No aparece `macninja` | Seed incompleto o DB vieja | Revisa logs; `setup.bat` de nuevo |
| El personaje no aparece tras crearlo | El cliente vuelve al login | Vuelve a iniciar sesión |
| Puerto 8443 ocupado | Otro proxy/servidor | Cambia o cierra el proceso |
| Admin da 403 | Sesión/cookie de otro host | Abre `/admin` en la ventana del lanzador |
| Todo va lento | Primera carga, antivirus, disco | Espera; añade exclusión; SSD |
| `Unsupported type: 0x0D` en logs | Telemetría AMF | Ignóralo; no afecta al juego |

---

## Windows

### `setup.bat` no hace nada o se cierra

Abre **Símbolo del sistema** en la carpeta del proyecto y ejecuta:

```bat
setup.bat
```

Así verás el error antes de que se cierre. También puedes ejecutar directamente:

```bat
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File runtime\setup-windows.ps1
```

Si el error es de **ejecución de scripts deshabilitada**, el `-ExecutionPolicy Bypass` del
`.bat` ya lo evita. Si tu empresa bloquea PowerShell por directiva de grupo, no hay forma
de saltarlo sin administrador; usa otro PC.

### SmartScreen / “Windows protegió tu PC”

Es porque el `.bat` no está firmado:

1. **Más información**.
2. **Ejecutar de todas formas**.

También puedes desbloquear los archivos antes:

```powershell
Get-ChildItem -Recurse | Unblock-File
```

### Windows Defender / antivirus

Si `php.exe`, `node.exe` o `mariadbd.exe` desaparecen o el juego no arranca:

1. Abre **Seguridad de Windows → Protección antivirus → Administrar la configuración**.
2. Añade una exclusión para la carpeta del proyecto (o para `runtime\bin`).
3. Restaura los archivos en cuarentena.
4. Ejecuta `setup.bat --ForceTools`.

No es un falso positivo raro: son binarios portables sin firma.

### Falta Visual C++

Síntoma: `php.exe` no se ejecuta, error `VCRUNTIME140.dll` o `0xc000007b`.

Instala el redistribuidor oficial x64:

<https://aka.ms/vs/17/release/vc_redist.x64.exe>

Reinicia y vuelve a ejecutar `setup.bat`.

### Descargar las herramientas a mano

Si `setup.bat` no puede descargar:

```
runtime\bin\php\php.exe
runtime\bin\mariadb\bin\mariadbd.exe
runtime\bin\node.exe
```

Descarga:

- PHP: <https://windows.php.net/downloads/releases/latest/php-8.4-nts-Win32-vs17-x64-latest.zip>
- MariaDB: <https://archive.mariadb.org/mariadb-11.4.8/winx64-packages/mariadb-11.4.8-winx64.zip>
- Node: <https://nodejs.org/dist/v22.23.4/node-v22.23.4-win-x64.zip>

Descomprime PHP directamente en `runtime\bin\php` (debe quedar `php.exe` ahí).
Descomprime MariaDB y renombra la carpeta `mariadb-11.4.8-winx64` a `runtime\bin\mariadb`.
Extrae solo `node.exe` a `runtime\bin\node.exe`.

Vuelve a ejecutar `setup.bat`.

### MariaDB no arranca

Comprueba el puerto:

```bat
netstat -ano | findstr :3307
```

Si hay un proceso, ciérralo o cámbialo. Si el log dice `InnoDB: Unable to lock`, otra
instancia de MariaDB está usando `runtime\mysql`:

```bat
tasklist | findstr /I mariadbd
taskkill /IM mariadbd.exe /F
```

Si el datadir está corrupto:

1. Copia `runtime\mysql` a otro sitio (por si acaso).
2. `stop.bat`.
3. `setup.bat --ResetDatabase`.

Esto borra personajes y cuentas. Es la última opción.

### Laravel no arranca o da 500

- Comprueba que `ns-server\Database\Laragon\ninjasage\.env` existe.
- Comprueba `APP_KEY=` no está vacío. Si lo está:

```bat
cd ns-server\Database\Laragon\ninjasage
..\..\..\..\runtime\bin\php\php.exe artisan key:generate
```

- Comprueba que MariaDB responde en 3307.
- Revisa `storage\logs\laravel.log`.
- Si el error es de permisos, ejecuta la consola como tu usuario normal (no como
  administrador) y comprueba que la carpeta no sea de solo lectura.

### “No se puede acceder al sitio” en Chrome

No abras `https://ninjasage.test` en un Chrome normal. Ese nombre solo resuelve con los
flags del lanzador. Cierra esa pestaña y ejecuta `launch.bat`.

Si el lanzador tampoco abre Chrome:

- Comprueba que Chrome o Edge estén instalados.
- Abre manualmente la URL que muestra la consola, pero con el perfil dedicado:

```bat
"C:\Program Files\Google\Chrome\Application\chrome.exe" ^
  --user-data-dir="C:\NinjaSaga\runtime\chrome-profile" ^
  --ignore-certificate-errors ^
  --host-resolver-rules="MAP ninjasage.test 127.0.0.1:8443" ^
  --app="https://ninjasage.test/play"
```

(La línea `^` es continuación en `cmd`; en PowerShell usa una sola línea o backtick.)

### Puerto 8443 ocupado

```bat
netstat -ano | findstr :8443
taskkill /PID <PID> /F
```

Si es otro programa que no puedes cerrar, cambia `$script:EdgePort` en
`runtime\windows-common.ps1` y `EDGE_PORT`/`launch.py` en macOS, además del puerto en
`.env` si corresponde. Lo más fácil es cerrar el otro programa.

### El juego carga pero los botones no responden

Debe cargar `/sounds/click.mp3`. Comprueba en DevTools → Network que devuelve 200. Si no:

- Revisa `runtime\logs\edge-console.log`.
- Comprueba que `runtime/assets` y `public/sounds` existan.
- Vuelve a ejecutar `launch.bat` (copia los assets que falten).
- Si estás usando un Chrome normal, los flags/mapeo pueden faltar.

### Se queda en negro o en la pantalla de carga

- La primera vez Ruffle descarga 9 MB de SWF y 14 MB de WASM; espera 15–25 s.
- Pulsa **↻** o recarga con F5.
- Abre DevTools (F12) → Console y mira el error.
- Comprueba que `https://ninjasage.test/client/NinjaSage.swf` devuelve 200.
- Comprueba que `https://ninjasage.test/tools/ruffle-web/ruffle.js` devuelve 200.

### No hay sonido

Chrome bloquea el audio hasta que hay una interacción. Haz clic en la página y vuelve a
entrar. El lanzador ya pasa `--autoplay-policy=no-user-gesture-required`, pero algunos
navegadores lo ignoran si la pestaña está en segundo plano.

### La cuenta de prueba no existe

Comprueba la base de datos:

```bat
runtime\bin\mariadb\bin\mariadb.exe -h127.0.0.1 -P3307 -uroot ninjasage ^
  -e "SELECT id, username FROM users;"
```

Si no aparece `macninja`, vuelve a ejecutar los seeders:

```bat
cd ns-server\Database\Laragon\ninjasage
..\..\..\..\runtime\bin\php\php.exe artisan db:seed --class=DemoUserSeeder
```

Si la tabla `users` no existe, la migración no se completó. Revisa
`runtime\logs\setup.log` y ejecuta `setup.bat` de nuevo.

### Quiero empezar de cero

```bat
stop.bat
setup.bat --ResetDatabase
```

Antes de hacerlo, copia `runtime\mysql` si quieres conservar la partida. `--ResetDatabase`
mueve la base anterior a `runtime\mysql.legacy-<fecha>` cuando detecta una instalación
previa, pero no es un backup completo si el proceso falla a mitad.

### Mover el proyecto a otro PC

Copia la carpeta **sin** `runtime\bin`, `runtime\mysql`, `runtime\chrome-profile` ni
`runtime\logs` (o cópialos solo si sabes lo que haces). En el PC nuevo ejecuta
`setup.bat`; descargará las herramientas y creará una base limpia.

No copies `runtime\mysql` entre Windows y macOS: los binarios y rutas no son compatibles.

---

## macOS / Linux

### `launch.command` no se abre

```bash
chmod +x launch.command stop.command
./launch.command
```

Si Gatekeeper lo bloquea: clic derecho → **Abrir** → **Abrir**.

### No encuentra PHP/MariaDB/Node

```bash
brew install php mariadb node
```

El lanzador añade `/opt/homebrew/bin` y `/usr/local/bin` al PATH. Si usas otro gestor,
exporta el PATH antes de lanzar.

### MariaDB no arranca

```bash
lsof -nP -iTCP:3307 -sTCP:LISTEN
tail -50 runtime/logs/mariadb.err
```

Si el socket está viejo:

```bash
rm -f runtime/mysql.sock runtime/mysql.pid
./launch.command
```

Si el datadir está corrupto, con los servicios parados:

```bash
mv runtime/mysql runtime/mysql.bak
mariadb-install-db --datadir="$PWD/runtime/mysql" \
  --auth-root-authentication-method=normal --skip-test-db
# vuelve a crear la DB y ejecuta migrate --seed (ver README)
```

### Laravel no arranca

```bash
cd ns-server/Database/Laragon/ninjasage
php artisan key:generate
php artisan migrate --seed
tail -50 storage/logs/laravel.log
```

Comprueba que `.env` tenga `DB_PORT=3307` y las rutas `SKILL_SWF_PATH`/`ENEMY_SWF_PATH`
absolutas y entre comillas.

### Chrome no abre o no resuelve `ninjasage.test`

El lanzador debe abrir Chrome con `--host-resolver-rules`. Si abres Chrome a mano, no
funcionará. Cierra Chrome y vuelve a ejecutar `./launch.command`. Si usas otro navegador,
tendrás que añadir el mapeo a `/etc/hosts` y aceptar el certificado, pero no está
soportado.

---

## Errores conocidos que puedes ignorar

### `Unsupported type: 0x0D` en Laravel

El cliente envía un evento de analytics (`Analytics.libraries`) con un tipo AMF que
SabreAMF no deserializa. Laravel devuelve 500 para esa llamada. Es telemetría; el login,
las misiones y el combate no se ven afectados. Puedes verlo en
`storage/logs/laravel.log` y en la consola de Chrome. No hace falta arreglarlo para jugar.

### Aviso de hardware acceleration de Ruffle

Ruffle muestra un modal si Chrome usa renderizado software. `arcade/play.html` lo oculta
con CSS dentro del shadow DOM. Si aparece igualmente, puedes cerrarlo o ignorarlo; no
bloquea el juego.

### Imágenes de eventos roto

Algunos banners del CDN original ya no existen. El proyecto usa placeholders locales en
`runtime/assets/tmp/`. Si ves una imagen genérica, es esperado.

---

## Cómo pedir ayuda

Incluye:

1. Sistema operativo y versión (Windows 10/11, macOS).
2. Qué archivo ejecutaste (`setup.bat`, `launch.bat`, `launch.command`).
3. El texto completo del error de la consola.
4. Las últimas 50 líneas de `runtime\logs\setup.log` y
   `runtime\logs\laravel-console.log`.
5. Si el problema es visual, una captura de DevTools → Console.

No incluyas `runtime\mysql` ni `.env` en un issue público: pueden contener datos locales.
