#!/usr/bin/env python3
"""Ninja Saga local launcher (macOS / Linux / Windows).

Starts (idempotently) the three local services and opens the game in a
dedicated Chrome/Edge window:

    MariaDB (3307) -> Laravel/PHP (8000) -> HTTPS edge (8443)
                                        -> https://ninjasage.test/play

The patched Flash client talks to https://ninjasage.test/amf.  Chrome is
launched with --host-resolver-rules so that hostname resolves to our local
HTTPS edge and with --ignore-certificate-errors because the edge uses a local
self-signed certificate.

On Windows the recommended entry point is launch.bat (PowerShell launcher).
This Python launcher also understands Windows and is kept for parity.

Usage:
    python3 runtime/launch.py              # start + open browser
    python3 runtime/launch.py --no-browser # only start services
    python3 runtime/launch.py --stop       # stop local services
"""
from __future__ import annotations

import argparse
import glob
import os
import shutil
import socket
import ssl
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

IS_WINDOWS = os.name == "nt"

# Finder-launched .command files do not always inherit Homebrew's PATH.
if not IS_WINDOWS:
    for _p in ("/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"):
        if _p not in os.environ.get("PATH", "").split(":"):
            os.environ["PATH"] = _p + ":" + os.environ.get("PATH", "")

ROOT = Path(__file__).resolve().parent.parent
RUNTIME = ROOT / "runtime"
NS = ROOT / "ns-server" / "Database" / "Laragon" / "ninjasage"
PUBLIC = NS / "public"
CLIENT_ASSETS = ROOT / "ns-server" / "Custom Client" / "NS Custom Client V1"
LOGS = RUNTIME / "logs"
PIDS = RUNTIME / "pids"
TLS = RUNTIME / "tls"
PROFILE = RUNTIME / "chrome-profile"
BIN = RUNTIME / "bin"

MARIADB_PORT = 3307
LARAVEL_PORT = 8000
EDGE_PORT = 8443
HOST = "ninjasage.test"

ASSET_DIRS = [
    "items", "pets", "materials", "npcs", "enemy", "swfpanels",
    "mission", "essentials", "consumables", "sounds",
]

CREATE_NO_WINDOW = 0x08000000 if IS_WINDOWS else 0


def say(msg: str) -> None:
    print(msg, flush=True)


def _first_existing(paths: list[Path]) -> Path | None:
    for p in paths:
        if p and p.exists():
            return p
    return None


def _glob(*patterns: str) -> list[Path]:
    out: list[Path] = []
    for pattern in patterns:
        out.extend(Path(p) for p in glob.glob(pattern))
    return out


def find_php() -> Path | None:
    candidates = [BIN / "php" / ("php.exe" if IS_WINDOWS else "php")]
    which = shutil.which("php")
    if which:
        candidates.append(Path(which))
    if IS_WINDOWS:
        candidates += _glob(
            "C:/laragon/bin/php/php-*/php.exe",
            "C:/xampp/php/php.exe",
            "C:/Program Files/PHP/*/php.exe",
            "C:/Program Files (x86)/PHP/*/php.exe",
        )
    return _first_existing(candidates)


def find_node() -> Path | None:
    candidates = [BIN / ("node.exe" if IS_WINDOWS else "node")]
    which = shutil.which("node")
    if which:
        candidates.append(Path(which))
    if IS_WINDOWS:
        candidates += [
            Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "nodejs" / "node.exe",
            Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)")) / "nodejs" / "node.exe",
        ]
    return _first_existing(candidates)


def find_mariadb() -> dict[str, Path] | None:
    server_candidates = [BIN / "mariadb" / "bin" / ("mariadbd.exe" if IS_WINDOWS else "mariadbd")]
    for name in (("mariadbd.exe", "mysqld.exe") if IS_WINDOWS else ("mariadbd", "mysqld")):
        which = shutil.which(name)
        if which:
            server_candidates.append(Path(which))
    if IS_WINDOWS:
        server_candidates += _glob(
            "C:/laragon/bin/mariadb/mariadb-*/bin/mariadbd.exe",
            "C:/laragon/bin/mariadb/mariadb-*/bin/mysqld.exe",
            "C:/xampp/mysql/bin/mysqld.exe",
            "C:/Program Files/MariaDB*/bin/mariadbd.exe",
            "C:/Program Files/MySQL/MySQL Server*/bin/mysqld.exe",
        )
    server = _first_existing(server_candidates)
    if not server:
        return None

    bin_dir = server.parent
    def pick(names: tuple[str, ...]) -> Path:
        for name in names:
            p = bin_dir / name
            if p.exists():
                return p
        return bin_dir / names[0]

    return {
        "server": server,
        "admin": pick(("mariadb-admin.exe", "mysqladmin.exe") if IS_WINDOWS else ("mariadb-admin", "mysqladmin")),
        "client": pick(("mariadb.exe", "mysql.exe") if IS_WINDOWS else ("mariadb", "mysql")),
        "install": pick(("mariadb-install-db.exe", "mysql_install_db.exe") if IS_WINDOWS else ("mariadb-install-db", "mysql_install_db")),
    }


def port_open(port: int, host: str = "127.0.0.1") -> bool:
    try:
        with socket.create_connection((host, port), timeout=0.35):
            return True
    except OSError:
        return False


def wait_port(port: int, seconds: float, process: subprocess.Popen | None = None) -> bool:
    deadline = time.time() + seconds
    while time.time() < deadline:
        if port_open(port):
            return True
        if process is not None and process.poll() is not None:
            return False
        time.sleep(0.25)
    return port_open(port)


def wait_http(url: str, seconds: float, verify: bool = True) -> bool:
    ctx = None
    if not verify:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    deadline = time.time() + seconds
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=2, context=ctx) as r:
                if r.status < 500:
                    return True
        except Exception:
            pass
        time.sleep(0.3)
    return False


def write_pid(name: str, pid: int) -> None:
    PIDS.mkdir(parents=True, exist_ok=True)
    (PIDS / f"{name}.pid").write_text(str(pid))


def read_pid(name: str) -> int | None:
    p = PIDS / f"{name}.pid"
    if not p.exists():
        return None
    try:
        return int(p.read_text().strip())
    except ValueError:
        return None


def process_alive(pid: int | None) -> bool:
    if not pid:
        return False
    if IS_WINDOWS:
        try:
            out = subprocess.run(
                ["tasklist", "/FI", f"PID eq {pid}", "/NH"],
                capture_output=True, text=True, timeout=5,
            )
            return str(pid) in out.stdout
        except Exception:
            return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def popen_kwargs() -> dict:
    if IS_WINDOWS:
        return {"creationflags": CREATE_NO_WINDOW}
    return {"start_new_session": True}


def ensure_tls() -> None:
    cert, key = TLS / "cert.pem", TLS / "key.pem"
    if cert.exists() and key.exists():
        return
    TLS.mkdir(parents=True, exist_ok=True)
    say("· Generando certificado TLS local…")
    openssl = shutil.which("openssl")
    if openssl:
        subprocess.run(
            [
                openssl, "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                "-keyout", str(key), "-out", str(cert), "-days", "825",
                "-subj", f"/CN={HOST}",
                "-addext", f"subjectAltName=DNS:{HOST},DNS:*.{HOST}",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return
    php = find_php()
    generator = TLS / "generate.php"
    if php and generator.exists():
        env = dict(os.environ)
        cnf = php.parent / "extras" / "ssl" / "openssl.cnf"
        if cnf.exists():
            env["OPENSSL_CONF"] = str(cnf)
        subprocess.run([str(php), str(generator), HOST], check=True, env=env)
        return
    raise SystemExit(
        "Falta runtime/tls/cert.pem y no encontré openssl ni PHP para generarlo.\n"
        "Vuelve a descargar el proyecto o ejecuta setup.bat."
    )


def _make_junction(link: Path, target: Path) -> bool:
    link.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        ["cmd", "/c", "mklink", "/J", str(link), str(target.resolve())],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        creationflags=CREATE_NO_WINDOW,
    )
    return result.returncode == 0


def link_client_assets() -> None:
    if not CLIENT_ASSETS.exists():
        return
    for name in ASSET_DIRS:
        src = CLIENT_ASSETS / name
        dst = PUBLIC / name
        if not src.is_dir() or dst.exists() or dst.is_symlink():
            continue
        try:
            if IS_WINDOWS:
                if not _make_junction(dst, src):
                    shutil.copytree(src, dst, dirs_exist_ok=True)
            else:
                dst.symlink_to(os.path.relpath(src, dst.parent), target_is_directory=True)
        except OSError as exc:
            say(f"⚠ No se pudo enlazar {name}: {exc}")


def deploy_client() -> None:
    """Make sure the patched client and static extras are in Laravel's public/."""
    RUNTIME.mkdir(exist_ok=True)
    src = RUNTIME / "NinjaSage_patched3.swf"
    dst = PUBLIC / "client" / "NinjaSage.swf"
    if not src.exists():
        raise SystemExit("Falta runtime/NinjaSage_patched3.swf (cliente parcheado).")
    dst.parent.mkdir(parents=True, exist_ok=True)
    if not dst.exists() or dst.stat().st_size != src.stat().st_size:
        shutil.copy2(src, dst)
        say("· Cliente parcheado desplegado en public/client/NinjaSage.swf")

    for srcf, dstf in [
        (ROOT / "arcade" / "play.html", PUBLIC / "play.html"),
        (ROOT / "arcade" / "bg.jpg", PUBLIC / "arcade" / "bg.jpg"),
    ]:
        if srcf.exists():
            dstf.parent.mkdir(parents=True, exist_ok=True)
            if not dstf.exists() or srcf.read_bytes() != dstf.read_bytes():
                shutil.copy2(srcf, dstf)

    for src_dir, dst_dir in [
        (RUNTIME / "assets" / "fonts", PUBLIC / "fonts"),
        (RUNTIME / "assets" / "tmp", PUBLIC / "tmp"),
    ]:
        if src_dir.exists():
            dst_dir.mkdir(parents=True, exist_ok=True)
            for f in src_dir.iterdir():
                if f.is_file():
                    target = dst_dir / f.name
                    if not target.exists() or target.stat().st_size != f.stat().st_size:
                        shutil.copy2(f, target)

    ruffle_src = ROOT / "tools" / "ruffle-web"
    ruffle_dst = PUBLIC / "tools" / "ruffle-web"
    if ruffle_src.exists() and not (ruffle_dst / "ruffle.js").exists():
        ruffle_dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(ruffle_src, ruffle_dst)

    link_client_assets()


def start_mariadb() -> None:
    db = find_mariadb()
    if not db:
        hint = "Ejecuta setup.bat o instala MariaDB/MySQL." if IS_WINDOWS else "Instálalo con: brew install mariadb"
        raise SystemExit(f"No encontré mariadbd/mysqld. {hint}")

    if port_open(MARIADB_PORT):
        probe = subprocess.run(
            [str(db["admin"]), "--host=127.0.0.1", f"--port={MARIADB_PORT}", "-uroot", "ping"],
            capture_output=True, text=True,
        )
        if probe.returncode == 0:
            say(f"✔ MariaDB ya está escuchando en :{MARIADB_PORT}")
            return
        raise SystemExit(
            f"El puerto {MARIADB_PORT} está ocupado por otro proceso que no responde como MariaDB.\n"
            "Ciérralo o cambia el puerto en runtime/launch.py y .env."
        )

    datadir = RUNTIME / "mysql"
    if not (datadir / "mysql").exists():
        raise SystemExit(
            "La base de datos local no está inicializada (falta runtime/mysql).\n"
            "Ejecuta setup.bat (Windows) o consulta README.md → «Instalación desde cero»."
        )
    LOGS.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(db["server"]),
        f"--datadir={datadir}",
        f"--port={MARIADB_PORT}",
        f"--bind-address=127.0.0.1",
        f"--pid-file={RUNTIME / 'mysql.pid'}",
        f"--log-error={LOGS / 'mariadb.err'}",
    ]
    if not IS_WINDOWS:
        cmd.append(f"--socket={RUNTIME / 'mysql.sock'}")
    with open(LOGS / "mariadb-console.log", "ab") as log:
        proc = subprocess.Popen(cmd, cwd=ROOT, stdout=log, stderr=log, **popen_kwargs())
    write_pid("mariadb", proc.pid)
    if not wait_port(MARIADB_PORT, 25, proc):
        tail = (LOGS / "mariadb.err").read_text(errors="replace")[-2500:] if (LOGS / "mariadb.err").exists() else ""
        raise SystemExit(f"MariaDB no arrancó.\n{tail}")
    say(f"✔ MariaDB iniciada en :{MARIADB_PORT}")


def start_laravel() -> None:
    if port_open(LARAVEL_PORT):
        say(f"✔ Laravel ya está escuchando en :{LARAVEL_PORT}")
        return
    php = find_php()
    if not php:
        hint = "Ejecuta setup.bat." if IS_WINDOWS else "Instálalo con: brew install php"
        raise SystemExit(f"No encontré PHP. {hint}")
    if not (NS / "vendor" / "autoload.php").exists():
        raise SystemExit("Faltan las dependencias de Laravel (vendor/). Ejecuta setup.bat o composer install.")
    LOGS.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    if not IS_WINDOWS:
        env["PHP_CLI_SERVER_WORKERS"] = "4"
    with open(LOGS / "laravel-console.log", "ab") as log:
        proc = subprocess.Popen(
            [str(php), "artisan", "serve", "--host=127.0.0.1", f"--port={LARAVEL_PORT}"],
            cwd=NS, env=env, stdout=log, stderr=log, **popen_kwargs(),
        )
    write_pid("laravel", proc.pid)
    if not wait_port(LARAVEL_PORT, 25, proc):
        raise SystemExit("Laravel no arrancó. Revisa runtime/logs/laravel-console.log")
    say(f"✔ Laravel iniciado en :{LARAVEL_PORT}")


def start_edge() -> None:
    if port_open(EDGE_PORT):
        say(f"✔ Edge HTTPS ya está escuchando en :{EDGE_PORT}")
        return
    node = find_node()
    if not node:
        hint = "Ejecuta setup.bat." if IS_WINDOWS else "Instálalo con: brew install node"
        raise SystemExit(f"No encontré Node.js. {hint}")
    ensure_tls()
    LOGS.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, EDGE_PORT=str(EDGE_PORT), UPSTREAM_PORT=str(LARAVEL_PORT))
    with open(LOGS / "edge-console.log", "ab") as log:
        proc = subprocess.Popen(
            [str(node), str(RUNTIME / "proxy.js")],
            cwd=ROOT, env=env, stdout=log, stderr=log, **popen_kwargs(),
        )
    write_pid("edge", proc.pid)
    if not wait_port(EDGE_PORT, 15, proc):
        raise SystemExit("El proxy HTTPS no arrancó. Revisa runtime/logs/edge-console.log")
    if not wait_http(f"https://127.0.0.1:{EDGE_PORT}/amf", 10, verify=False):
        raise SystemExit("El proxy HTTPS no responde. Revisa runtime/logs/edge-console.log")
    say(f"✔ Edge HTTPS iniciado en https://{HOST}:{EDGE_PORT}")


def chrome_candidates() -> list[Path]:
    if IS_WINDOWS:
        pf = os.environ.get("ProgramFiles", "C:/Program Files")
        pf86 = os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)")
        local = os.environ.get("LOCALAPPDATA", "")
        candidates = [
            Path(pf) / "Google" / "Chrome" / "Application" / "chrome.exe",
            Path(pf86) / "Google" / "Chrome" / "Application" / "chrome.exe",
            Path(pf) / "Microsoft" / "Edge" / "Application" / "msedge.exe",
            Path(pf86) / "Microsoft" / "Edge" / "Application" / "msedge.exe",
        ]
        if local:
            candidates.insert(2, Path(local) / "Google" / "Chrome" / "Application" / "chrome.exe")
        return candidates
    candidates = [
        Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
        Path("/Applications/Chromium.app/Contents/MacOS/Chromium"),
        Path("/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"),
    ]
    for name in ("google-chrome", "chromium", "chromium-browser"):
        which = shutil.which(name)
        if which:
            candidates.append(Path(which))
    return candidates


def open_browser() -> None:
    chrome = _first_existing(chrome_candidates())
    if not chrome:
        say(f"⚠ No encontré Chrome ni Edge. Abre manualmente https://{HOST}/play")
        return
    PROFILE.mkdir(parents=True, exist_ok=True)
    page_url = f"https://{HOST}/play?l={int(time.time())}"
    rules = (
        f"MAP {HOST} 127.0.0.1:{EDGE_PORT},"
        f"MAP ninjasage.id 127.0.0.1:{EDGE_PORT},"
        f"MAP ns-assets.ninjasage.id 127.0.0.1:{EDGE_PORT},"
        f"MAP www.ninjasage.id 127.0.0.1:{EDGE_PORT}"
    )
    args = [
        str(chrome),
        f"--user-data-dir={PROFILE}",
        "--ignore-certificate-errors",
        f"--host-resolver-rules={rules}",
        "--autoplay-policy=no-user-gesture-required",
        "--ignore-gpu-blocklist",
        "--test-type",
        "--no-first-run",
        "--no-default-browser-check",
        "--window-size=1440,900",
        f"--app={page_url}",
    ]
    try:
        subprocess.Popen(
            args, cwd=ROOT,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            **popen_kwargs(),
        )
        say("✔ Abriendo Ninja Saga en el navegador…")
    except Exception as exc:  # noqa: BLE001
        say(f"⚠ No se pudo abrir el navegador directamente ({exc}).")
        say(f"  Abre manualmente https://{HOST}/play con el lanzador.")


def stop_services() -> None:
    say("Deteniendo servicios locales…")
    db = find_mariadb()
    if db:
        if IS_WINDOWS:
            if port_open(MARIADB_PORT):
                subprocess.run(
                    [str(db["admin"]), "--host=127.0.0.1", f"--port={MARIADB_PORT}", "-uroot", "shutdown"],
                    check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                )
        elif (RUNTIME / "mysql.sock").exists():
            subprocess.run(
                [str(db["admin"]), f"--socket={RUNTIME / 'mysql.sock'}", "-uroot", "shutdown"],
                check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
    for name in ("edge", "laravel", "mariadb"):
        pid = read_pid(name)
        if process_alive(pid):
            if IS_WINDOWS:
                subprocess.run(
                    ["taskkill", "/PID", str(pid), "/T", "/F"],
                    check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    creationflags=CREATE_NO_WINDOW,
                )
            else:
                try:
                    os.killpg(os.getpgid(pid), 15)
                except OSError:
                    try:
                        os.kill(pid, 15)
                    except OSError:
                        pass
        p = PIDS / f"{name}.pid"
        if p.exists():
            p.unlink()
    time.sleep(0.8)
    say("✔ Servicios detenidos. (El navegador puede seguir abierto; ciérralo o recarga.)")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-browser", action="store_true", help="no abrir el navegador")
    parser.add_argument("--stop", action="store_true", help="detener los servicios")
    args = parser.parse_args()

    if args.stop:
        stop_services()
        return

    if not NS.exists():
        raise SystemExit(f"No encontré el servidor en {NS}")
    LOGS.mkdir(parents=True, exist_ok=True)
    PIDS.mkdir(parents=True, exist_ok=True)

    say("")
    say("  NINJA SAGA · servidor local")
    say("  ──────────────────────────")
    deploy_client()
    start_mariadb()
    start_laravel()
    start_edge()
    say("")
    say(f"  Listo: https://{HOST}/play")
    say("  Cuenta premium:    macninja / ninja1234")
    say(f"  Panel admin:        https://{HOST}/admin  (admin@admin.test / admin)")
    say("  Detener servicios:  " + ("stop.bat" if IS_WINDOWS else "./stop.command"))
    say("")
    if not args.no_browser:
        open_browser()


if __name__ == "__main__":
    main()
