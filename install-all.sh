#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ANTONIO MX - Instalador unificado BTUN BHTTP + VLESS XHTTP
# Compatible con Ubuntu/Debian x86_64.

REPO="luis579/antonio-mx-instalador"
BRANCH="main"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
DOMAIN="ionox.antoniomx.blog"
BTUN_PORT1=8080
BTUN_PORT2=8880
VLESS_PORT=8181
BIN_SHA256="e7315241cca11acc2c483604f94ea80905248fc5a751954eec67497cb7f7e82b"

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RESET='\033[0m'

ok()   { echo -e "${GREEN}[OK]${RESET} $*"; }
warn() { echo -e "${YELLOW}[AVISO]${RESET} $*"; }
fail() { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || fail "Ejecuta como root: sudo bash install-all.sh"
[[ "$(uname -m)" == "x86_64" ]] || fail "Este bilola-server es x86-64. Arquitectura detectada: $(uname -m)"

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) ;;
    *) warn "Distribución no verificada: ${PRETTY_NAME:-desconocida}. Se intentará continuar." ;;
  esac
else
  warn "No se pudo identificar la distribución."
fi

command -v apt-get >/dev/null 2>&1 || fail "Se requiere Ubuntu/Debian con apt-get."
command -v systemctl >/dev/null 2>&1 || fail "Se requiere systemd."

echo -e "${CYAN}"
echo "======================================================"
echo "          ANTONIO MX - INSTALADOR AUTOMATICO"
echo "              BTUN BHTTP + VLESS XHTTP"
echo "======================================================"
echo -e "${RESET}"
echo "Dominio VLESS : ${DOMAIN}"
echo "BTUN          : TCP ${BTUN_PORT1} y ${BTUN_PORT2} -> SSH 22"
echo "VLESS XHTTP   : TCP ${VLESS_PORT}"
echo ""

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl iproute2 python3

# Evitar pisar servicios que ya estén escuchando en los puertos previstos.
for port in "$BTUN_PORT1" "$BTUN_PORT2" "$VLESS_PORT"; do
  if ss -lntH "sport = :${port}" 2>/dev/null | grep -q .; then
    ss -lntp "sport = :${port}" || true
    fail "El puerto TCP ${port} ya está ocupado. No se modificó ese servicio."
  fi
done

if getent ahostsv4 "$DOMAIN" >/dev/null 2>&1; then
  ok "El dominio ${DOMAIN} resuelve por DNS."
else
  warn "El dominio ${DOMAIN} todavía no resuelve. Configura un registro DNS A hacia la IP pública de esta VPS antes de conectar clientes."
fi

WORK="$(mktemp -d /tmp/antonio-mx-install.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

download() {
  local name="$1"
  echo "Descargando ${name}..."
  curl -fL --retry 3 --connect-timeout 15 "${RAW}/${name}" -o "${WORK}/${name}"
  [[ -s "${WORK}/${name}" ]] || fail "Descarga vacía: ${name}"
}

download "install-btun.sh"
download "bilola-server"
download "instalar-vless-xhttp.sh"

echo "${BIN_SHA256}  ${WORK}/bilola-server" | sha256sum -c - || fail "El hash del binario bilola-server no coincide. Se cancela la instalación."

chmod 0755 "${WORK}/install-btun.sh" "${WORK}/bilola-server" "${WORK}/instalar-vless-xhttp.sh"

echo ""
echo "======================================================"
echo " 1/2 - INSTALANDO BTUN BHTTP"
echo "======================================================"
bash "${WORK}/install-btun.sh" --on --port "$BTUN_PORT1" --port2 "$BTUN_PORT2" --ssh 22 --ssh2 22

systemctl is-active --quiet btun.service || fail "BTUN principal no quedó activo. Revisa: journalctl -u btun -n 60"
systemctl is-active --quiet btun-secondary.service || fail "BTUN secundario no quedó activo. Revisa: journalctl -u btun-secondary -n 60"
ok "BTUN principal y secundario están activos."

# Abrir puertos en firewalls locales conocidos, solo si están activos.
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow "${BTUN_PORT1}/tcp"
  ufw allow "${BTUN_PORT2}/tcp"
  ufw allow "${VLESS_PORT}/tcp"
  ok "Reglas UFW agregadas para los tres puertos TCP."
elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="${BTUN_PORT1}/tcp"
  firewall-cmd --permanent --add-port="${BTUN_PORT2}/tcp"
  firewall-cmd --permanent --add-port="${VLESS_PORT}/tcp"
  firewall-cmd --reload
  ok "Reglas firewalld agregadas para los tres puertos TCP."
else
  warn "No se detectó UFW/firewalld activo. Si tu proveedor tiene firewall externo, permite TCP 8080, 8880 y 8181."
fi

echo ""
echo "======================================================"
echo " 2/2 - INSTALANDO VLESS XHTTP"
echo "======================================================"
echo "Se configurará automáticamente address y host como ${DOMAIN}."
echo "La configuración actual usa security=none (sin TLS)."
echo ""

# El instalador original abre su menú. Se envían las opciones de configuración
# inicial, activación del servicio y salida; el administrador queda instalado.
printf '1\n%s\n%s\n2\n0\n' "$DOMAIN" "$DOMAIN" | bash "${WORK}/instalar-vless-xhttp.sh"

systemctl is-active --quiet xray-xhttp.service || fail "VLESS XHTTP no quedó activo. Revisa: journalctl -u xray-xhttp -n 80"
systemctl is-enabled --quiet xray-xhttp.service || warn "El servicio Xray no quedó habilitado al arranque."
systemctl is-enabled --quiet btun.service || warn "BTUN principal no quedó habilitado al arranque."
systemctl is-enabled --quiet btun-secondary.service || warn "BTUN secundario no quedó habilitado al arranque."

echo ""
echo -e "${GREEN}======================================================"
echo "       INSTALACION AUTOMATICA COMPLETADA"
echo "======================================================${RESET}"
echo ""
echo "Servicios:"
systemctl --no-pager --full status btun.service btun-secondary.service xray-xhttp.service | sed -n '1,45p' || true
echo ""
echo "Administrador VLESS:"
echo "  vless-xhttp-manager"
echo ""
echo "Logs:"
echo "  journalctl -u btun -f"
echo "  journalctl -u btun-secondary -f"
echo "  journalctl -u xray-xhttp -f"
echo ""
echo "IMPORTANTE:"
echo "  1. Comprueba que ionox.antoniomx.blog tenga un registro DNS A hacia esta VPS."
echo "  2. La configuración actual de VLESS usa security=none; no tiene TLS."
echo "  3. Crea tus usuarios VLESS con: vless-xhttp-manager"
echo "  4. Permite TCP 8080, 8880 y 8181 también en el firewall del proveedor."
