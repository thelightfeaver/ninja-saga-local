# Guía de Windows

Esta guía cubre la instalación, el uso diario y la solución de problemas en **Windows
10/11 de 64 bits**. La idea es que tu amigo solo tenga que descomprimir la carpeta y
hacer doble clic en `setup.bat`.

> **Validación:** además de las pruebas en macOS, el flujo completo de Windows se ejecuta
> en GitHub Actions sobre `windows-latest` con los binarios reales: instalación desde
> cero, `setup.bat`, `launch.bat`, endpoints HTTPS y recuentos de la base de datos. No
> sustituye a un PC físico, pero detecta errores de rutas, permisos y arranque. Si algo
> falla en tu equipo, `runtime\logs\setup.log` indica el paso exacto.

---

## 1. Antes de empezar

| Requisito | Detalle |
|---|---|
| Windows | 10 u 11, 64 bits |
| Espacio libre | ~1,5 GB |
| Internet | Solo para `setup.bat` (descarga ~160 MB) |
| Navegador | Chrome o Edge |
| Permisos | Usuario normal; no hace falta administrador |

**No instales nada globalmente.** PHP, MariaDB y Node.js se descargan como binarios
portables dentro de `runtime\bin\`. No se crean servicios de Windows ni entradas en
`Program Files`.

### Dónde poner la carpeta

- Recomendado: `C:\NinjaSaga` (ruta corta, sin espacios).
- Evita `C:\Program Files` (permisos) y `OneDrive`/`Dropbox` (pueden bloquear o
  sincronizar la base de datos mientras MariaDB la usa).
- Las rutas con espacios funcionan, pero cuanto más corta mejor. Windows tiene un límite
  histórico de 260 caracteres; si la ruta es muy larga, mueve el proyecto a `C:\NinjaSaga`.

---

## 2. Instalación (primera vez)

1. Descarga el repositorio:
   - **Releases → última versión → ZIP** (recomendado), o
   - **GitHub → Code → Download ZIP**, o
   - `git clone https://github.com/thelightfeaver/ninja-saga-local.git`
2. Descomprime el ZIP. Debe quedar una carpeta con `setup.bat`, `launch.bat`,
   `runtime\`, `ns-server\`, etc. **No** ejecutes los archivos desde dentro del ZIP.
3. Doble clic en **`setup.bat`**.
4. Si aparece **Windows SmartScreen**:
   - Pulsa **Más información**.
   - Pulsa **Ejecutar de todas formas**.
   - Es normal: los `.bat` no están firmados digitalmente. El código es abierto y puedes
     revisarlo antes de ejecutarlo.
5. Espera. La consola muestra el progreso:
   - `1/5 Herramientas portables` → descarga y extrae PHP, MariaDB y Node.
   - `2/5 Servidor y dependencias` → usa el `vendor/` incluido (no necesita Composer).
   - `3/5 Archivos del juego` → copia el cliente parcheado y enlaza assets.
   - `4/5 Base de datos` → inicializa MariaDB, migra y carga items/skills/misiones.
   - `5/5 Verificación` → comprueba el cliente, genera el certificado TLS local y valida
     que todo esté en su sitio.
6. Al terminar, `setup.bat` abre el juego automáticamente en Chrome/Edge.

**Tiempo estimado:** 5–15 minutos, según la conexión y el disco. La carga de datos del
juego (5.564 items, 1.162 skills, 371 enemigos, 89 misiones) es la parte más lenta.

### Cuenta de prueba Premium

| Usuario | Contraseña |
|---|---|
| `macninja` | `ninja1234` |

La cuenta se crea como **Premium** (`account_type = 1`) y empieza con **1.000.000 de
tokens**, suficientes para probar la tienda, los emblemas y las funciones Premium sin
farmear. Si vienes de una instalación anterior, vuelve a ejecutar `setup.bat`: la
migración `2026_10_22_000001_upgrade_demo_account_to_premium` la actualiza sin tocar la
contraseña ni los personajes.

Si es la primera vez, entra y crea tu personaje. Si después de crearlo el cliente vuelve
al login, vuelve a entrar: el personaje ya estará guardado.

### Panel de administración

Abre `https://ninjasage.test/admin` en la misma ventana de Chrome que abrió el lanzador:

- Usuario: `admin@admin.test`
- Contraseña: `admin`

---

## 3. Uso diario

| Acción | Archivo |
|---|---|
| Jugar | `launch.bat` |
| Detener los servicios | `stop.bat` |
| Reinstalar/actualizar herramientas | `setup.bat` (sin borrar la base de datos) |
| Instalar sin abrir el juego | `setup.bat --NoLaunch` |
| Borrar la partida y empezar de cero | `setup.bat --ResetDatabase` |
| Forzar la descarga de herramientas | `setup.bat --ForceTools` |

`setup.bat` es idempotente: si ya está todo instalado, no vuelve a descargar nada y
conserva la base de datos. `--ResetDatabase` **borra** `runtime\mysql` (hace una copia de
seguridad automática antes de continuar si detecta una base anterior).

### Qué hace `launch.bat`

1. Comprueba que las herramientas y la base de datos existan.
2. Copia el cliente parcheado y los assets a `public/` si hace falta.
3. Arranca MariaDB en `127.0.0.1:3307`.
4. Arranca Laravel/PHP en `127.0.0.1:8000`.
5. Arranca el proxy HTTPS en `127.0.0.1:8443`.
6. Abre Chrome/Edge con un perfil dedicado (`runtime\chrome-profile`), mapeando
   `ninjasage.test` a `127.0.0.1:8443` y aceptando el certificado local.

Los servicios quedan en segundo plano. Puedes cerrar la ventana de la consola; el juego
sigue funcionando. Para pararlos, usa `stop.bat`.

---

## 4. Qué descarga `setup.bat`

Las URLs se comprueban al momento de escribir esto. Todas son oficiales:

| Herramienta | Versión | Origen |
|---|---|---|
| PHP | 8.4 NTS x64 | `windows.php.net` |
| MariaDB | 11.4.8 x64 | `archive.mariadb.org` |
| Node.js | 22.23.4 x64 | `nodejs.org` |

- MariaDB y Node.js se verifican con SHA-256 contra los archivos oficiales.
- PHP se descarga por HTTPS desde el sitio oficial.
- Los ZIP se guardan en `runtime\downloads\`; puedes reutilizarlos si reinstalas.
- Las herramientas extraídas viven en `runtime\bin\` y están excluidas de Git.

### Si la descarga falla

Puedes descargar los ZIP manualmente y colocarlos así:

```
runtime\
  bin\
    php\php.exe                 ← contenido del ZIP de PHP
    mariadb\bin\mariadbd.exe    ← carpeta mariadb-11.4.8-winx64 renombrada a mariadb
    node.exe                    ← node.exe extraído del ZIP de Node
  downloads\                    ← opcional; aquí puedes dejar los ZIP
```

Enlaces directos:

- PHP: <https://windows.php.net/downloads/releases/latest/php-8.4-nts-Win32-vs17-x64-latest.zip>
- MariaDB: <https://archive.mariadb.org/mariadb-11.4.8/winx64-packages/mariadb-11.4.8-winx64.zip>
- Checksum MariaDB: <https://archive.mariadb.org/mariadb-11.4.8/winx64-packages/sha256sums.txt>
- Node: <https://nodejs.org/dist/v22.23.4/node-v22.23.4-win-x64.zip>
- Checksum Node: <https://nodejs.org/dist/v22.23.4/SHASUMS256.txt>

Después vuelve a ejecutar `setup.bat`: detectará los binarios y no los descargará.

> **PHP y Visual C++:** el build oficial de PHP para Windows necesita el
> *Microsoft Visual C++ Redistributable 2015–2022 x64*. Windows 10/11 suele traerlo, pero
> si `php.exe` no arranca, instálalo desde
> <https://aka.ms/vs/17/release/vc_redist.x64.exe> y vuelve a intentar.

---

## 5. Comprobaciones y puertos

Los tres servicios escuchan solo en `127.0.0.1`:

| Servicio | Puerto | Cómo comprobarlo |
|---|---|---|
| MariaDB | 3307 | `netstat -ano | findstr :3307` |
| Laravel | 8000 | `netstat -ano | findstr :8000` |
| Proxy HTTPS | 8443 | `netstat -ano | findstr :8443` |

Si un puerto está ocupado, `launch.bat` muestra un error. Para liberarlo:

```bat
netstat -ano | findstr :3307
taskkill /PID <PID> /F
```

No uses el puerto 3306: está reservado para una instalación de MySQL/MariaDB que el
usuario ya tenga. El proyecto usa 3307 a propósito.

### Comprobar que el servidor responde

Con `launch.bat` en marcha, abre en Chrome:

- `https://ninjasage.test/play` → portada del juego.
- `https://ninjasage.test/amf` → respuesta del gateway (puede estar vacía; no debe dar
  error de conexión).
- `https://ninjasage.test/admin` → panel de administración.

Si Chrome dice “no se puede acceder al sitio”, casi siempre es porque abriste la URL en
un Chrome normal, sin los flags del lanzador. Cierra esa pestaña y usa `launch.bat`.

---

## 6. Logs y diagnóstico

| Log | Qué contiene |
|---|---|
| `runtime\logs\setup.log` | Todo el proceso de instalación; el primer sitio a mirar |
| `runtime\logs\mariadb.err` | Errores de MariaDB (arranque, puerto, datos) |
| `runtime\logs\laravel-console.log` | Peticiones y errores del servidor Laravel |
| `runtime\logs\edge-console.log` | Arranque del proxy HTTPS |
| `ns-server\Database\Laragon\ninjasage\storage\logs\laravel.log` | Excepciones detalladas de Laravel |

Para verlos en vivo (PowerShell):

```powershell
Get-Content runtime\logs\laravel-console.log -Wait
Get-Content runtime\logs\mariadb.err -Wait
```

### Acceso directo a la base de datos

```bat
runtime\bin\mariadb\bin\mariadb.exe -h127.0.0.1 -P3307 -uroot ninjasage
```

Dentro de MariaDB:

```sql
SHOW TABLES;
SELECT COUNT(*) FROM items;
SELECT username FROM users;
```

### Cambiar la contraseña de la cuenta de prueba

La forma más sencilla es crear otra cuenta desde el juego. Si necesitas reparar
`macninja`, puedes usar Laravel:

```bat
cd ns-server\Database\Laragon\ninjasage
..\..\..\..\runtime\bin\php\php.exe artisan tinker
```

Y dentro de Tinker:

```php
$u = App\Models\User::where('username', 'macninja')->first();
$u->password = 'ninja1234'; // el modelo lo hashea solo
$u->save();
```

(La ruta relativa al PHP portátil es incómoda; también puedes usar
`C:\NinjaSaga\runtime\bin\php\php.exe` directamente, o ejecutar `launch.bat` y usar la
consola de Laravel desde la raíz.)

---

## 7. Desinstalar o mover el proyecto

### Desinstalar

1. Ejecuta `stop.bat`.
2. Borra la carpeta del proyecto.
3. No hay servicios, claves de registro ni archivos fuera de la carpeta.

Si quieres conservar tu partida, copia `runtime\mysql` antes de borrar.

### Mover el proyecto a otro disco

1. Para los servicios con `stop.bat`.
2. Mueve la carpeta completa.
3. Ejecuta `launch.bat` de nuevo.

No copies `runtime\bin` entre arquitecturas distintas ni `runtime\mysql` entre versiones
mayores de MariaDB. Si algo falla, borra `runtime\mysql` (con copia) y ejecuta
`setup.bat --ResetDatabase`.

---

## macOS y Linux

### macOS (proyecto ya instalado)

```bash
./launch.command      # jugar
./stop.command        # detener
```

Si el Finder dice que no se puede abrir, clic derecho → **Abrir**, o:

```bash
chmod +x launch.command stop.command
```

### macOS desde cero

```bash
brew install php mariadb node

cd "ns-server/Database/Laragon/ninjasage"
cp .env.example .env
# Edita .env: APP_URL=https://ninjasage.test, DB_PORT=3307,
# SKILL_SWF_PATH y ENEMY_SWF_PATH con rutas absolutas.
php artisan key:generate

cd ../../../..
mariadb-install-db --datadir="$PWD/runtime/mysql" \
  --auth-root-authentication-method=normal --skip-test-db
mariadbd --datadir="$PWD/runtime/mysql" --port=3307 \
  --bind-address=127.0.0.1 --socket="$PWD/runtime/mysql.sock" &
mysql -h127.0.0.1 -P3307 -uroot -e \
  "CREATE DATABASE ninjasage CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

cd "ns-server/Database/Laragon/ninjasage"
php artisan migrate --seed

cd ../../../..
./launch.command
```

En macOS, `launch.command` usa Homebrew (`/opt/homebrew/bin` o `/usr/local/bin`). Si PHP
o MariaDB están en otra ruta, añádela al `PATH` antes de lanzar.

### Linux

`runtime/launch.py` es multiplataforma y debería funcionar con PHP 8.2+, MariaDB y
Node.js instalados por el sistema. No está probado a fondo; los pasos son los mismos que
en macOS, usando el gestor de paquetes de tu distribución. El lanzador crea enlaces
simbólicos en `public/`, igual que en macOS.

---

## Limitaciones conocidas en Windows

- **No hay soporte para Windows 7/8.** Node.js 22 y PHP 8.4 requieren Windows 10+.
- **Un solo worker PHP.** El servidor integrado de PHP en Windows no puede usar varios
  workers. Por eso el proxy de Node sirve los assets estáticos; las llamadas AMF siguen
  pasando por PHP. Para un jugador local es suficiente.
- **Antivirus.** Algunos antivirus escanean `php.exe`, `node.exe` y `mariadbd.exe` en el
  primer arranque y tardan. Si los ponen en cuarentena, restaura la carpeta y añade una
  exclusión.
- **Firewall.** Si Windows pregunta, permite el acceso a redes privadas. Los servicios
  solo escuchan en `127.0.0.1`, así que no se exponen a Internet.
- **Certificado.** El navegador avisa del certificado autofirmado. Es esperado; el
  lanzador arranca Chrome con `--ignore-certificate-errors` para evitarlo.
- **SmartScreen.** Los `.bat` no están firmados. “Más información → Ejecutar de todas
  formas” es el comportamiento esperado.
- **Rutas largas.** Si la ruta supera ~120 caracteres, `setup.bat` avisa. Mueve el
  proyecto a `C:\NinjaSaga`.

Para el resto de síntomas, consulta
[`SOLUCION_DE_PROBLEMAS.md`](SOLUCION_DE_PROBLEMAS.md).
