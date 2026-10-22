# Arquitectura

Este documento explica cómo encajan las piezas, por qué hay un proxy Node delante de
Laravel y qué se tocó para que un cliente Adobe AIR de 2016 funcione en Ruffle.

---

## Vista general

```
┌─────────────────────────────────────────────────────────────────────┐
│ Chrome / Edge (perfil dedicado runtime/chrome-profile)              │
│                                                                     │
│  https://ninjasage.test/play        → portada + Ruffle               │
│  https://ninjasage.test/client/...  → NinjaSage.swf parcheado       │
│  https://ninjasage.test/amf         → gateway AMF                    │
│  https://ninjasage.test/items/...   → assets del cliente             │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ HTTPS 8443 (certificado autofirmado)
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│ runtime/proxy.js (Node.js)                                          │
│  • termina TLS                                                     │
│  • sirve assets estáticos desde public/ (items, skills, game_data…) │
│  • añade CORS                                                      │
│  • reenvía el resto a 127.0.0.1:8000                               │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ HTTP
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│ php artisan serve (Laravel 12, 127.0.0.1:8000)                      │
│  • /amf → AmfController → servicios del juego                       │
│  • /admin → panel de administración                                 │
│  • /skills, /enemy → SWFs desde el cliente                          │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ PDO
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│ MariaDB 11.4 (127.0.0.1:3307)                                       │
│  datos en runtime/mysql, seeds en database/seeders                  │
└─────────────────────────────────────────────────────────────────────┘
```

El cliente Flash **no habla directamente con PHP**. Llama a
`https://ninjasage.test/amf`, y Chrome resuelve ese nombre a `127.0.0.1:8443` mediante
`--host-resolver-rules`. El proxy termina TLS y reenvía a PHP.

---

## Servicios y puertos

| Servicio | Comando | Puerto | Bind | Log |
|---|---|---|---|---|
| MariaDB | `runtime/bin/mariadb/bin/mariadbd` (Windows) o `mariadbd` (macOS) | 3307 | 127.0.0.1 | `runtime/logs/mariadb.err` |
| Laravel | `php artisan serve --host=127.0.0.1 --port=8000` | 8000 | 127.0.0.1 | `runtime/logs/laravel-console.log` |
| Proxy HTTPS | `node runtime/proxy.js` | 8443 | 127.0.0.1 | `runtime/logs/edge-console.log` |
| Juego | Chrome/Edge | — | — | DevTools |

Todos los servicios se pueden arrancar a mano. El lanzador solo los hace idempotentes:
si un puerto ya responde, no lo vuelve a arrancar.

### Por qué MariaDB en 3307

Para no chocar con un MySQL/MariaDB que el usuario ya tenga en el puerto estándar 3306.
La base de datos vive dentro del proyecto (`runtime/mysql`), así que no se mezcla con
otras instalaciones.

### Por qué un proxy Node

El servidor integrado de PHP es de un solo hilo en Windows (no soporta
`PHP_CLI_SERVER_WORKERS`). El cliente pide muchos assets (items, skills, enemigos,
sonidos, `gamedata.bin`, fuentes, WASM de Ruffle) y bloquearía las llamadas AMF. El proxy
sirve esos archivos directamente desde disco con `fs.createReadStream`, soporte de
`Range` y MIME correctos, y deja PHP libre para `/amf` y `/admin`.

En macOS/Linux el lanzador configura 4 workers de PHP, pero el proxy sigue siendo útil
para CORS, TLS y assets.

---

## Flujo de arranque

### Windows (`launch.bat` → `runtime/launch-windows.ps1`)

1. `Assert-Ready`: comprueba PHP, Node, MariaDB, `.env`, `runtime/mysql` y
   `public/game_data`.
2. `Deploy-GameFiles`:
   - copia `runtime/NinjaSage_patched3.swf` → `public/client/NinjaSage.swf`;
   - copia `arcade/play.html` y `arcade/bg.jpg`;
   - copia fuentes y placeholders;
   - copia `tools/ruffle-web/` → `public/tools/ruffle-web/` si falta;
   - crea **junctions** (`mklink /J`) para `items`, `pets`, `materials`, `npcs`,
     `enemy`, `swfpanels`, `mission`, `essentials`, `consumables`, `sounds`;
   - crea un junction de compatibilidad `storage/app/private/game_data` →
     `public/game_data`.
3. `Start-LocalMariaDb`: arranca `mariadbd.exe` con `--datadir`, `--port=3307`,
   `--bind-address=127.0.0.1`, `--pid-file`, `--log-error`. Espera el puerto.
4. `Start-LocalLaravel`: arranca `php artisan serve` oculto, redirigiendo stdout/stderr.
5. `Start-LocalEdge`: arranca `node proxy.js` con `EDGE_PORT` y `UPSTREAM_PORT`.
6. `Open-GameBrowser`: busca Chrome/Edge y abre una ventana `--app` con:
   - `--user-data-dir=runtime/chrome-profile`
   - `--ignore-certificate-errors`
   - `--host-resolver-rules=MAP ninjasage.test 127.0.0.1:8443,...`
   - `--autoplay-policy=no-user-gesture-required`
   - `--window-size=1440,900`

### macOS/Linux (`launch.command` → `runtime/launch.py`)

Hace lo mismo, pero:

- busca binarios en Homebrew (`/opt/homebrew/bin`, `/usr/local/bin`), PATH y
  `runtime/bin`;
- usa enlaces simbólicos en vez de junctions;
- arranca MariaDB con `--socket=runtime/mysql.sock`;
- pasa `PHP_CLI_SERVER_WORKERS=4` a Laravel;
- usa `taskkill` en Windows y `killpg` en POSIX para detener.

---

## Estructura de carpetas

```
ninja saga/
├── setup.bat / launch.bat / stop.bat       ← Windows
├── launch.command / stop.command           ← macOS/Linux
├── arcade/
│   ├── play.html                           ← portada + Ruffle
│   └── bg.jpg
├── runtime/
│   ├── launch.py                           ← lanzador multiplataforma
│   ├── launch-windows.ps1                  ← lanzador Windows
│   ├── setup-windows.ps1                   ← instalador Windows
│   ├── windows-common.ps1                  ← helpers compartidos
│   ├── proxy.js                            ← edge HTTPS + assets
│   ├── NinjaSage_patched3.swf              ← cliente parcheado
│   ├── tls/                                ← certificado autofirmado (generado al arrancar)
│   ├── assets/                             ← fuentes y placeholders
│   ├── bin/                                ← PHP/MariaDB/Node portables (ignorado)
│   ├── downloads/                          ← ZIPs de instalación (ignorado)
│   ├── mysql/                              ← base de datos (ignorado)
│   ├── chrome-profile/                     ← perfil de Chrome (ignorado)
│   └── logs/                               ← logs (ignorado)
├── ns-server/
│   ├── Custom Client/NS Custom Client V1/  ← cliente original + assets
│   └── Database/Laragon/ninjasage/         ← Laravel + game_data + vendor
├── patches/                                ← fuente de Util.url y script FFDec
├── tools/
│   ├── patch_air_stubs.py                  ← parche ABC de flash.filesystem
│   ├── ruffle-web/                         ← Ruffle local
│   └── dev/                                ← utilidades de depuración
├── screenshots/
└── docs/
```

`repo/` (el volcado original) no se incluye en Git. `tools/ffdec/`, `runtime/bin/`,
`runtime/downloads/`, `runtime/mysql/`, logs y perfiles tampoco.

---

## Datos del juego

### `public/game_data`

Contiene los JSON/bin que el cliente pide al arrancar:

- `library.json` (items), `skills.json`, `pet.json`, `mission.json`, `npc.json`,
  `enemy.json`, `talents.json`, `senjutsu.json`, etc.
- `gamedata.bin`, `library.bin`, `skills.bin`, `pet.bin`, `enemy.bin`.
- Efectos (`weapon-effect.json`, `skill-effect.json`, …).

`GameDataSeeder` lee directamente `public/game_data` (con fallback a
`storage/app/private/game_data`). Antes se dependía de un enlace simbólico en `storage`;
ahora funciona igual en Windows sin privilegios.

### Seeders

`DatabaseSeeder` ejecuta, en orden:

1. `AdminUserSeeder` → `admin@admin.test` / `admin`.
2. `DemoUserSeeder` → `macninja` / `ninja1234` (idempotente; no pisa usuarios existentes).
3. `EudemonGardenSeeder`.
4. `GameDataSeeder` → items, skills, pets, misiones, NPCs, enemigos, talentos, senjutsu,
   configuración.
5. `XPSeeder`, `TalentSeeder`, `GameEventSeeder`, `SpecialDealsSeeder`.

En una base nueva se cargan **5.564 items, 1.162 skills, 371 enemigos y 89 misiones**.

### Base de datos

- Motor: MariaDB 11.4 (Windows) / MariaDB del sistema (macOS).
- Datadir: `runtime/mysql`.
- Base: `ninjasage`, charset `utf8mb4`, collation `utf8mb4_unicode_ci`.
- Usuario: `root` sin contraseña, solo accesible en `127.0.0.1`.
- `SESSION_VALIDATE_BYPASS=true` evita que el cliente Flash pierda la sesión al
  reconectar (el cliente no maneja cookies como un navegador normal).

No se debe copiar `runtime/mysql` entre versiones mayores de MariaDB ni con MariaDB en
marcha. Para conservar una partida, para los servicios y copia la carpeta completa.

---

## Parches del cliente

El cliente original es una app **Adobe AIR**. Ruffle no implementa `flash.filesystem`,
así que el SWF se parchea en dos pasos.

### 1. Stubs de `flash.filesystem` (`tools/patch_air_stubs.py`)

Reescribe las entradas QName de `File`, `FileStream` y `FileMode` en el ABC del SWF para
apuntar a clases Flash equivalentes del mismo tamaño, sin mover offsets. Así el cliente
puede cargar en Ruffle sin `Error #1014`.

### 2. `Util.url` (`patches/Util_fixed.as` + `patch_client.sh`)

`id.ninjasage.Util.url()` usaba `File.applicationDirectory`, que Ruffle no tiene. Se
recompiló con FFDec para usar `Character.cdn` y un fallback a `https://ninjasage.test/`.

Ese fallo era el causante de los **botones muertos**: el wrapper de clic intentaba
reproducir `sfx:click` antes de llamar al listener; si el sonido fallaba, lanzaba
`Error #1009` y el listener nunca se ejecutaba. Al arreglar `Util.url`, `/sounds/click.mp3`
carga y los clics funcionan.

### 3. Fuentes

Ruffle no tiene fuentes de sistema. `arcade/play.html` declara `fontSources` con Arial,
Arial Unicode, Verdana, Franklin Gothic y Noto Sans, y `defaultFonts` con listas de
familias. El lanzador copia `runtime/assets/fonts/*.ttf` a `public/fonts/`.

### 4. Ruffle

`tools/ruffle-web/` contiene Ruffle 0.7.1 con sus `.wasm` hasheados. El proxy sirve
`application/wasm` para que Chrome lo instancie correctamente. No se carga nada de CDNs.

---

## Seguridad y alcance

- Todo escucha en `127.0.0.1`; no hay exposición a la red local ni a Internet.
- El certificado TLS es autofirmado y vive en `runtime/tls/`. Chrome lo ignora solo en el
  perfil dedicado del lanzador.
- El admin usa credenciales locales conocidas (`admin@admin.test` / `admin`). Cámbialas
  si vas a dejar el servidor mucho tiempo.
- El juego y sus assets siguen siendo propiedad de sus titulares. Este proyecto es una
  preservación local; no es un servicio oficial.
- `setup.bat` no requiere administrador y no instala servicios. Todo vive en la carpeta.

---

## Empaquetado para Git

Se incluye:

- Código del servidor Laravel, migraciones, seeders, rutas y `vendor/` (para que Windows
  no necesite Composer).
- Cliente original y assets necesarios (`items`, `skills`, `enemy`, `pets`, …).
- `public/game_data`.
- Cliente parcheado, Ruffle, fuentes, parches, capturas y documentación.

Se excluye:

- `repo/` (volcado original de 118 MB).
- `runtime/mysql`, `runtime/bin`, `runtime/downloads`, `runtime/logs`,
  `runtime/chrome-profile`, `runtime/pids`.
- `tools/ffdec`, `tools/nsps`, ZIPs de herramientas.
- `.env`, claves privadas, logs, sesiones, cachés y copias de seguridad.
- Carpetas duplicadas de assets que el lanzador enlaza o copia en `public/`.

Los archivos grandes (.swf, .wasm, .ttf, .png) están marcados como binarios en
`.gitattributes`; los `.bat` y `.ps1` se sirven con CRLF y los `.command`/`.sh` con LF.
