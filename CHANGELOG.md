# Changelog

Todas las versiones notables de este montaje. El proyecto sigue un esquema simple
`MAJOR.MINOR.PATCH`.

## v1.0.1 — 2026-10-22

Versión pensada para que la cuenta de prueba venga lista para jugar sin limitaciones.

### Añadido

- Cuenta de prueba **Premium**: `macninja` / `ninja1234` se crea con
  `account_type = 1` y **1.000.000 de tokens**.
- Migración `2026_10_22_000001_upgrade_demo_account_to_premium`: actualiza la cuenta
  `macninja` de una instalación v1.0.0 sin cambiar su contraseña ni sus personajes.
- El smoke test de Windows comprueba el tipo de cuenta y los tokens del jugador de
  prueba, además de los recuentos de items, skills, enemigos y usuarios.

### Cambiado

- `README.md`, `README.en.md`, `docs/WINDOWS.md` y `docs/ARQUITECTURA.md` documentan la
  cuenta Premium y sus credenciales.
- Los mensajes de `setup.bat` y `launch.bat` muestran «Cuenta premium».

## v1.0.0 — 2026-10-22

Primera versión publicada como paquete autónomo para Windows y macOS.

### Añadido

- Instalador `setup.bat` para Windows 10/11 x64:
  - PHP 8.4 NTS x64 portable.
  - MariaDB 11.4.8 x64 portable.
  - Node.js 22.23.4 x64 portable.
  - Verificación SHA-256 de MariaDB y Node.js.
  - Inicialización de la base de datos, migraciones y seeders.
  - Instalación sin administrador y sin servicios de Windows.
- Lanzador `launch.bat` y parada `stop.bat` para Windows.
- `runtime/launch-windows.ps1`, `runtime/setup-windows.ps1`,
  `runtime/windows-common.ps1` y `runtime/stop-windows.ps1`.
- Cuenta de prueba `macninja` / `ninja1234` mediante `DemoUserSeeder`.
- Certificado TLS autofirmado generado automáticamente en el primer arranque; el
  repositorio no incluye ninguna clave privada.
- Documentación en español:
  - `README.md`
  - `docs/WINDOWS.md`
  - `docs/ARQUITECTURA.md`
  - `docs/SOLUCION_DE_PROBLEMAS.md`
  - `NOTICE.md`
- Guía rápida en inglés: `README.en.md`.
- Licencia MIT para el código propio.

### Cambiado

- `runtime/proxy.js` ahora sirve los assets estáticos directamente desde
  `public/` (items, sonidos, game_data, Ruffle, fuentes…) con MIME correctos, CORS y
  soporte de `Range`. PHP queda libre para `/amf`.
- `runtime/launch.py` es multiplataforma: detecta binarios, crea junctions en Windows,
  usa Chrome/Edge, maneja `taskkill` y no usa socket en Windows.
- `GameDataSeeder` lee `public/game_data` directamente, sin depender de un enlace en
  `storage/`.
- `.env.example` es portable: `APP_KEY` vacía, `DB_PORT=3307`, rutas de skills/enemigos
  vacías para que las rellene el instalador.
- El instalador de Windows usa las opciones correctas de `mariadb-install-db.exe`
  (`--datadir`, `--port`), no las de la versión Unix.
- Se eliminaron las carpetas duplicadas `Items/` y `Skills/` del servidor Laravel; los
  assets viven en `ns-server/Custom Client/NS Custom Client V1/` y se enlazan en
  `public/`.
- El servidor PHP de Windows se arranca directamente (`php -S`) en lugar de
  `artisan serve`, porque Laravel activa `PHP_CLI_SERVER_WORKERS`, que la build oficial
  de PHP para Windows no soporta.

### Corregido

- Botones muertos en el cliente: `Util.url` usa `Character.cdn` y `/sounds/click.mp3`
  carga correctamente.
- Textos en blanco por fuentes de sistema ausentes en Ruffle.
- `Error #1014` de `flash.filesystem` mediante stubs ABC.
- Resolución de `ninjasage.test` sin tocar `/etc/hosts` ni pedir `sudo`.
- CORS para los endpoints de `ninjasage.id` / `ns-assets.ninjasage.id`.
- Imágenes de eventos del CDN muerto sustituidas por placeholders locales.
- `game_events.image_url` en migraciones.
- Se corrigió `launch.bat` en un proceso nuevo (faltaba `Ensure-Directories` fuera del
  instalador) y `stop.bat` ya no falla por el aviso de MariaDB sin contraseña.

### Conocido / limitado

- La telemetría `Analytics.libraries` devuelve un 500 AMF (`Unsupported type: 0x0D`).
  No afecta al juego.
- PvP, chat y clanes no se probaron a fondo.
- Ruffle no reproduce Flash exactamente; puede haber diferencias visuales o sonoras.
- El flujo de Windows se prueba automáticamente en GitHub Actions (`windows-latest`):
  instalación desde cero, arranque, endpoints HTTPS y datos sembrados. No se probó en un
  PC físico.
- No se incluye el volcado original `repo/` (118 MB) ni FFDec.

## Base

- Servidor privado: `pseudownload/Ninja-Saga-Private-Server`.
- Cliente y datos: incluidos en `ns-server/`.
- Ruffle 0.7.1.
