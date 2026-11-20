#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

APP_DIR="/etc/xray-vless-xhttp"
APP="/usr/local/bin/vless-xhttp-manager"
XRAY="/usr/local/bin/xray"
XRAY_INSTALLED_BY_SCRIPT=0

if [[ ${EUID} -ne 0 ]]; then
  echo "Ejecuta como root: sudo bash $0"
  exit 1
fi

# Este instalador es para un VPS nuevo. No toca paneles/servicios activos.
for service in x-ui 3x-ui v2ray xray xray-xhttp; do
  if systemctl is-active --quiet "${service}.service" 2>/dev/null; then
    echo "ERROR: ${service}.service está activo."
    echo "No modificaré un servidor que ya está funcionando. Usa un VPS limpio o revisa los servicios manualmente."
    exit 1
  fi
done

if [[ -e "$APP_DIR/manager.json" || -e "$APP" || -e "/etc/systemd/system/xray-xhttp.service" ]]; then
  echo "ERROR: ya existen archivos del administrador o del servicio independiente."
  echo "No se sobrescribirá ninguna configuración existente."
  exit 1
fi

if command -v ss >/dev/null 2>&1 && ss -lntH '( sport = :8181 )' | grep -q .; then
  echo "ERROR: el puerto TCP 8181 ya está ocupado. No continuaré."
  ss -lntp | grep ':8181' || true
  exit 1
fi

echo "== 1/5: Instalando dependencias =="
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl python3 iproute2

echo "== 2/5: Instalando/verificando Xray-core =="
if [[ ! -x "$XRAY" ]]; then
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
  XRAY_INSTALLED_BY_SCRIPT=1
fi
if [[ ! -x "$XRAY" ]]; then
  echo "ERROR: no se encontró el ejecutable $XRAY"
  exit 1
fi
"$XRAY" version

# Si este script instaló Xray en el VPS limpio, deshabilita el servicio estándar
# para que el servicio independiente gestione su propia configuración.
if [[ "$XRAY_INSTALLED_BY_SCRIPT" -eq 1 ]]; then
  systemctl disable --now xray.service >/dev/null 2>&1 || true
fi

mkdir -p "$APP_DIR"
chmod 700 "$APP_DIR"

echo "== 3/5: Instalando administrador VLESS + XHTTP =="
cat > "$APP" <<'PYTHON'
#!/usr/bin/env python3

import os
import sys
import json
import re
import uuid
import shutil
import subprocess
import time
import urllib.parse

from datetime import datetime
from pathlib import Path

BASE = Path("/etc/xray-vless-xhttp")
STATE = BASE / "manager.json"
CONFIG = BASE / "config.json"
UNIT = Path("/etc/systemd/system/xray-xhttp.service")
TIMER_UNIT = Path("/etc/systemd/system/vless-xhttp-expire.service")
TIMER_FILE = Path("/etc/systemd/system/vless-xhttp-expire.timer")
XRAY = Path("/usr/local/bin/xray")
MANAGER = Path("/usr/local/bin/vless-xhttp-manager")

PORT = 8181
PADDING = "100-1000"
MODE = "auto"
PATH_XHTTP = "/"
SERVICE = "xray-xhttp"


def run(args, check=True):
    return subprocess.run(args, check=check)


def load():
    if not STATE.exists():
        return None

    try:
        data = json.loads(STATE.read_text())
        if not isinstance(data.get("users"), list):
            raise ValueError("La lista de usuarios no es válida")
        return data
    except Exception as exc:
        print("Error leyendo manager.json:", exc)
        return None


def save(s):
    BASE.mkdir(parents=True, exist_ok=True)
    temp = STATE.with_suffix(".json.tmp")
    temp.write_text(json.dumps(s, indent=2) + "\n")
    os.chmod(temp, 0o600)
    temp.replace(STATE)
    os.chmod(STATE, 0o600)


def valid_uuid(value):
    try:
        return str(uuid.UUID(value)) == value.lower()
    except (ValueError, AttributeError, TypeError):
        return False


def ask(label, default=""):
    suffix = f" [{default}]" if default else ""
    value = input(label + suffix + ": ").strip()
    return value or default


def is_expired(user, now=None):
    if now is None:
        now = int(time.time())

    expiration = user.get("expires_at")

    # Compatibilidad: usuarios antiguos sin vencimiento.
    if expiration is None:
        return False

    try:
        return int(expiration) <= now
    except (ValueError, TypeError):
        # No eliminar usuarios por una fecha malformada.
        return False


def build_config(s):
    now = int(time.time())

    active_users = [
        u for u in s["users"]
        if not is_expired(u, now)
    ]

    return {
        "log": {
            "loglevel": "warning"
        },
        "inbounds": [{
            "tag": "vless-xhttp-in",
            "listen": "0.0.0.0",
            "port": PORT,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": u["uuid"],
                        "email": u["name"]
                    }
                    for u in active_users
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "xhttp",
                "security": "none",
                "xhttpSettings": {
                    "path": PATH_XHTTP,
                    "mode": MODE,
                    "extra": {
                        "xPaddingBytes": PADDING
                    }
                }
            }
        }],
        "outbounds": [
            {
                "protocol": "freedom",
                "tag": "direct"
            },
            {
                "protocol": "blackhole",
                "tag": "block"
            }
        ]
    }


def install_unit():
    unit = f"""[Unit]
Description=Independent VLESS XHTTP Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart={XRAY} run -config {CONFIG}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
"""

    UNIT.write_text(unit)
    os.chmod(UNIT, 0o644)
    run(["systemctl", "daemon-reload"])


def install_expiration_timer():
    service = f"""[Unit]
Description=Expire VLESS XHTTP users

[Service]
Type=oneshot
ExecStart={MANAGER} --expire
"""

    timer = """[Unit]
Description=Check VLESS XHTTP user expiration

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
AccuracySec=5s
Unit=vless-xhttp-expire.service

[Install]
WantedBy=timers.target
"""

    TIMER_UNIT.write_text(service)
    TIMER_FILE.write_text(timer)

    os.chmod(TIMER_UNIT, 0o644)
    os.chmod(TIMER_FILE, 0o644)

    run(["systemctl", "daemon-reload"])
    run([
        "systemctl", "enable", "--now",
        "vless-xhttp-expire.timer"
    ])

    print("Temporizador de vencimientos habilitado.")


def activate(s):
    if not XRAY.is_file():
        print("No se encontró Xray en", XRAY)
        print("Instala Xray-core antes de activar el servidor.")
        return False

    BASE.mkdir(parents=True, exist_ok=True)

    # Crear configuración temporal para validar antes de reemplazar.
    candidate = CONFIG.with_suffix(".candidate.json")
    candidate.write_text(
        json.dumps(build_config(s), indent=2) + "\n"
    )
    os.chmod(candidate, 0o600)

    try:
        result = subprocess.run(
            [
                str(XRAY), "run", "-test",
                "-config", str(candidate)
            ],
            text=True,
            capture_output=True
        )

        if result.returncode != 0:
            print("La configuración no pasó la validación.")
            print(result.stdout)
            print(result.stderr)
            return False

        # Guardar copia de la configuración anterior.
        if CONFIG.exists():
            backup = CONFIG.with_suffix(".json.backup")
            shutil.copy2(CONFIG, backup)

        candidate.replace(CONFIG)
        os.chmod(CONFIG, 0o600)

        install_unit()

        run([
            "systemctl", "enable",
            SERVICE
        ])

        if subprocess.run(
            ["systemctl", "is-active", "--quiet", SERVICE]
        ).returncode == 0:
            run(["systemctl", "restart", SERVICE])
        else:
            run(["systemctl", "start", SERVICE])

        if subprocess.run(
            ["systemctl", "is-active", "--quiet", SERVICE]
        ).returncode != 0:
            print("Xray no está activo.")
            print("Consulta: journalctl -u xray-xhttp -n 60")
            return False

        print("Servidor activo. Puerto TCP:", PORT)
        return True

    except Exception as exc:
        print("Error activando el servicio:", exc)
        return False

    finally:
        candidate.unlink(missing_ok=True)


def make_link(s, user):
    query = {
        "type": "xhttp",
        "encryption": "none",
        "path": PATH_XHTTP,
        "host": s["host"],
        "mode": MODE,
        "x_padding_bytes": PADDING,
        "extra": json.dumps(
            {
                "mode": MODE,
                "xPaddingBytes": PADDING
            },
            separators=(",", ":")
        ),
        "security": "none"
    }

    return (
        "vless://" + user["uuid"] + "@" +
        s["address"] + ":" + str(PORT) + "?" +
        urllib.parse.urlencode(
            query,
            quote_via=urllib.parse.quote
        ) + "#" +
        urllib.parse.quote(user["name"], safe="")
    )


def make_client_json(s, user):
    return {
        "log": {
            "loglevel": "warning"
        },
        "inbounds": [{
            "tag": "socks-in",
            "listen": "127.0.0.1",
            "port": 10808,
            "protocol": "socks",
            "settings": {
                "auth": "noauth",
                "udp": True
            }
        }],
        "outbounds": [
            {
                "tag": "proxy",
                "protocol": "vless",
                "settings": {
                    "vnext": [{
                        "address": s["address"],
                        "port": PORT,
                        "users": [{
                            "id": user["uuid"],
                            "encryption": "none"
                        }]
                    }]
                },
                "streamSettings": {
                    "network": "xhttp",
                    "security": "none",
                    "xhttpSettings": {
                        "host": s["host"],
                        "path": PATH_XHTTP,
                        "mode": MODE,
                        "extra": {
                            "xPaddingBytes": PADDING
                        }
                    }
                }
            },
            {
                "protocol": "freedom",
                "tag": "direct"
            },
            {
                "protocol": "blackhole",
                "tag": "block"
            }
        ],
        "routing": {
            "rules": [{
                "type": "field",
                "inboundTag": ["socks-in"],
                "outboundTag": "proxy"
            }]
        }
    }


def export_user(s, user):
    folder = BASE / "users"
    folder.mkdir(exist_ok=True)
    os.chmod(folder, 0o700)

    safe = (
        re.sub(r"[^A-Za-z0-9_.-]", "_", user["name"])[:40]
        or "user"
    )

    linkfile = folder / (safe + ".txt")
    jsonfile = folder / (safe + ".json")

    linkfile.write_text(make_link(s, user) + "\n")
    jsonfile.write_text(
        json.dumps(make_client_json(s, user), indent=2) + "\n"
    )

    os.chmod(linkfile, 0o600)
    os.chmod(jsonfile, 0o600)

    print("\nEnlace VLESS:\n")
    print(make_link(s, user))
    print("\nArchivos generados:")
    print(linkfile)
    print(jsonfile)

    expiration = user.get("expires_at")
    if expiration is None:
        print("Vencimiento: ilimitado")
    else:
        print(
            "Vencimiento:",
            datetime.fromtimestamp(
                int(expiration)
            ).strftime("%Y-%m-%d %H:%M:%S")
        )


def setup():
    if STATE.exists():
        print("Ya existe una configuración. No se sobrescribirá.")
        return

    address = ask("IP pública o dominio del VPS")
    host = ask("Host HTTP de XHTTP", address)

    if not address or any(
        c in address for c in "/?#@ "
    ):
        print("Dirección no válida.")
        return

    if not host or any(
        c in host for c in "/?#@ "
    ):
        print("Host no válido.")
        return

    s = {
        "address": address,
        "host": host,
        "users": []
    }

    save(s)
    install_unit()
    install_expiration_timer()

    print("Configuración base creada.")
    print("Ahora crea un usuario y activa el servidor.")


def add_user(s):
    name = ask(
        "Nombre del usuario",
        "usuario" + str(len(s["users"]) + 1)
    )

    if any(u["name"] == name for u in s["users"]):
        print("Ya existe un usuario con ese nombre.")
        return

    print("1. Generar UUID automáticamente")
    print("2. Introducir UUID manualmente")

    choice = ask("Selecciona", "1")

    if choice == "2":
        uid = ask("UUID")

        if not valid_uuid(uid):
            print("UUID no válido.")
            return

        uid = str(uuid.UUID(uid))
    else:
        uid = str(uuid.uuid4())

    if any(u["uuid"] == uid for u in s["users"]):
        print("Ese UUID ya existe.")
        return

    while True:
        try:
            days = int(ask(
                "Duración en días (0 = ilimitado)",
                "30"
            ))

            if days < 0:
                print("Introduce 0 o un número positivo.")
                continue

            break

        except ValueError:
            print("Introduce un número entero.")

    expires_at = (
        int(time.time()) + days * 86400
        if days > 0 else None
    )

    user = {
        "name": name,
        "uuid": uid,
        "expires_at": expires_at
    }

    previous = list(s["users"])
    s["users"].append(user)
    save(s)

    if not activate(s):
        s["users"] = previous
        save(s)
        print("No se añadió: no se pudo activar la configuración.")
        return

    export_user(s, user)


def list_users(s):
    if not s["users"]:
        print("No hay usuarios.")
        return

    now = int(time.time())

    for i, user in enumerate(s["users"], 1):
        expiration = user.get("expires_at")

        if expiration is None:
            status = "ILIMITADO"
        elif is_expired(user, now):
            status = "VENCIDO"
        else:
            remaining = max(
                0, int(expiration) - now
            )
            days_left = remaining // 86400
            date = datetime.fromtimestamp(
                int(expiration)
            ).strftime("%Y-%m-%d %H:%M")
            status = (
                f"VENCE {date} "
                f"(quedan {days_left} días completos)"
            )

        print(
            f"{i}. {user['name']} | "
            f"{user['uuid']} | {status}"
        )


def delete_user(s):
    list_users(s)

    if not s["users"]:
        return

    try:
        n = int(ask("Número del usuario a eliminar")) - 1
        user = s["users"][n]
    except (ValueError, IndexError):
        print("Selección inválida.")
        return

    if ask(
        f"Escribe BORRAR para eliminar a {user['name']}"
    ) != "BORRAR":
        print("Cancelado.")
        return

    previous = list(s["users"])
    s["users"].pop(n)
    save(s)

    if not activate(s):
        s["users"] = previous
        save(s)
        print("No se pudo aplicar la eliminación.")
        return

    print("Usuario eliminado y servicio reiniciado.")
    print("No compartas los enlaces antiguos de este usuario.")


def choose_export(s):
    list_users(s)

    if not s["users"]:
        return

    try:
        n = int(ask("Número del usuario")) - 1
        user = s["users"][n]

        if is_expired(user):
            print("Este usuario ya venció; no exportes su enlace.")
            return

        export_user(s, user)

    except (ValueError, IndexError):
        print("Selección inválida.")


def expire_users():
    s = load()

    if not s:
        return

    now = int(time.time())
    active = [
        u for u in s["users"]
        if not is_expired(u, now)
    ]

    if len(active) == len(s["users"]):
        return

    previous = list(s["users"])
    s["users"] = active
    save(s)

    print("Retirando usuarios vencidos...")

    if not activate(s):
        s["users"] = previous
        save(s)
        print("ERROR: no se pudo aplicar la expiración.")
        print("Revisa el servicio y vuelve a intentarlo.")
        return

    print("Usuarios vencidos retirados del servidor.")


def uninstall():
    print("Se eliminarán el servicio y los datos del administrador.")
    print("El binario compartido de Xray se conservará.")

    if ask("Escribe DESINSTALAR para confirmar") != "DESINSTALAR":
        print("Cancelado.")
        return

    run([
        "systemctl", "disable", "--now",
        "vless-xhttp-expire.timer"
    ], check=False)

    run([
        "systemctl", "disable", "--now", SERVICE
    ], check=False)

    TIMER_FILE.unlink(missing_ok=True)
    TIMER_UNIT.unlink(missing_ok=True)
    UNIT.unlink(missing_ok=True)

    run(["systemctl", "daemon-reload"])

    shutil.rmtree(BASE, ignore_errors=True)

    print("Administrador, usuarios y datos propios eliminados.")
    print("Xray-core se conserva para no romper otros servicios.")
    sys.exit(0)


def menu():
    if os.geteuid() != 0:
        print("Ejecuta como root.")
        sys.exit(1)

    while True:
        print("""
===== VLESS XHTTP MANAGER =====
1. Configurar servidor
2. Instalar/activar servidor
3. Crear usuario (UUID automático o manual)
4. Eliminar usuario
5. Listar usuarios y vencimientos
6. Generar enlace y JSON de usuario
7. Estado del servicio
8. Ver últimos errores
9. Desinstalar administrador y borrar sus datos
0. Salir
""")

        choice = ask("Opción")
        s = load()

        if choice == "1":
            setup()

        elif choice == "2":
            if not s:
                print("Primero configura el servidor (opción 1).")
            else:
                activate(s)
                install_expiration_timer()

        elif choice == "3":
            if not s:
                print("Primero configura el servidor.")
            else:
                add_user(s)

        elif choice == "4":
            if s:
                delete_user(s)
            else:
                print("No hay configuración.")

        elif choice == "5":
            list_users(s or {"users": []})

        elif choice == "6":
            if s:
                choose_export(s)
            else:
                print("No hay configuración.")

        elif choice == "7":
            run([
                "systemctl", "status", SERVICE, "--no-pager"
            ], check=False)
            run([
                "systemctl", "list-timers",
                "vless-xhttp-expire.timer"
            ], check=False)

        elif choice == "8":
            run([
                "journalctl", "-u", SERVICE,
                "-n", "60", "--no-pager"
            ], check=False)

        elif choice == "9":
            uninstall()

        elif choice == "0":
            break

        else:
            print("Opción no válida.")


if __name__ == "__main__":
    if os.geteuid() != 0:
        print("Ejecuta como root.")
        sys.exit(1)

    if len(sys.argv) > 1 and sys.argv[1] == "--expire":
        expire_users()
    else:
        menu()
PYTHON
chmod 700 "$APP"
python3 -m py_compile "$APP"
chown root:root "$APP"

echo "== 4/5: Instalación base completada =="
echo "== 5/5: Abriendo el administrador =="
echo "En el menú, usa la opción 1 para configurar el servidor."
exec python3 "$APP"
