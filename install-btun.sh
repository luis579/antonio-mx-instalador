#!/bin/bash
set -e

# ==========================================
# BTUN BHTTP INSTALLER + MENU
# ==========================================

SERV1="/etc/systemd/system/btun.service"
SERV2="/etc/systemd/system/btun-secondary.service"

BIN="/usr/local/lib/bilola-server"
CMD="/usr/local/bin/btun"

CONFIG="/etc/default/btun"

BHTTP_PORT="8080"
BHTTP_PORT2="8880"

SSH_PORT="22"
SSH_PORT2="22"

ON=false
OFF=false

# ==========================================
# COLORES DEL PANEL
# ==========================================

RESET="\033[0m"

BG_BLACK="\033[40m"

WHITE="\033[97m"
BOLD="\033[1m"
DIM="\033[2m"

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"

BORDER_BLUE="\033[1;34m"
BORDER_CYAN="\033[1;36m"
BORDER_GREEN="\033[1;32m"
BORDER_RED="\033[1;31m"
BORDER_YELLOW="\033[1;33m"
BORDER_MAGENTA="\033[1;35m"

OK="✓"
ERROR="✗"
ARROW="➜"
DOT="●"
LINE="━"

# ==========================================
# VALIDAR PUERTO
# ==========================================

valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] &&
    (( "$1" >= 1 && "$1" <= 65535 ))
}

# ==========================================
# CARGAR CONFIGURACIÓN
# ==========================================

load_config() {

    if [[ -f "$CONFIG" ]]; then
        source "$CONFIG"
    fi

    BHTTP_PORT="${BHTTP_PORT:-8080}"
    BHTTP_PORT2="${BHTTP_PORT2:-8880}"

    SSH_PORT="${SSH_PORT:-22}"
    SSH_PORT2="${SSH_PORT2:-22}"
}

# ==========================================
# GUARDAR CONFIGURACIÓN
# ==========================================

save_config() {

    mkdir -p /etc/default

    cat > "$CONFIG" <<EOF
BHTTP_PORT="$BHTTP_PORT"
BHTTP_PORT2="$BHTTP_PORT2"
SSH_PORT="$SSH_PORT"
SSH_PORT2="$SSH_PORT2"
EOF
}

# ==========================================
# INSTALAR BINARIO
# ==========================================

install_binary() {

    if [[ "$(id -u)" -ne 0 ]]; then
        echo -e "${RED}Ejecuta este comando como root.${RESET}"
        exit 1
    fi

    if [[ ! -f "$BIN" ]]; then

        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

        if [[ -f "$SCRIPT_DIR/bilola-server" ]]; then

            echo "Instalando bilola-server..."

            install -m 0755 \
                "$SCRIPT_DIR/bilola-server" \
                "$BIN"

        else

            echo -e "${RED}ERROR: no se encontró bilola-server.${RESET}"
            echo ""
            echo "Debe estar en:"
            echo "$BIN"
            echo ""
            echo "O junto al instalador:"
            echo "$SCRIPT_DIR/bilola-server"

            exit 1
        fi
    fi

    chmod 0755 "$BIN"
}

# ==========================================
# INSTALAR COMANDO BTUN
# ==========================================

install_command() {

    if [[ "$(readlink -f "${BASH_SOURCE[0]}")" != "$CMD" ]]; then

        install -m 0755 \
            "${BASH_SOURCE[0]}" \
            "$CMD"
    fi
}

# ==========================================
# CREAR SERVICIO PRINCIPAL
# ==========================================

create_service1() {

    cat > "$SERV1" <<EOF
[Unit]
Description=Bilola BHTTP Go Server - Principal
After=network-online.target ssh.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BIN --listen 0.0.0.0:$BHTTP_PORT --target 127.0.0.1:$SSH_PORT
Restart=on-failure
RestartSec=3
User=root
LimitNOFILE=65536
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
}

# ==========================================
# CREAR SERVICIO SECUNDARIO
# ==========================================

create_service2() {

    cat > "$SERV2" <<EOF
[Unit]
Description=Bilola BHTTP Go Server - Secundario
After=network-online.target ssh.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BIN --listen 0.0.0.0:$BHTTP_PORT2 --target 127.0.0.1:$SSH_PORT2
Restart=on-failure
RestartSec=3
User=root
LimitNOFILE=65536
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
}

# ==========================================
# ACTIVAR PRINCIPAL
# ==========================================

start_primary() {

    echo ""
    echo "Activando BHTTP principal..."

    create_service1

    systemctl daemon-reload
    systemctl enable --now btun.service

    sleep 1

    if systemctl is-active --quiet btun.service; then

        echo -e "${GREEN}✓ BHTTP principal ACTIVO${RESET}"
        echo "  Puerto BHTTP : $BHTTP_PORT"
        echo "  Puerto SSH   : $SSH_PORT"

    else

        echo -e "${RED}✗ Error al iniciar BHTTP principal${RESET}"
        systemctl status btun.service --no-pager || true
    fi
}

# ==========================================
# ACTIVAR SECUNDARIO
# ==========================================

start_secondary() {

    echo ""
    echo "Activando BHTTP secundario..."

    create_service2

    systemctl daemon-reload
    systemctl enable --now btun-secondary.service

    sleep 1

    if systemctl is-active --quiet btun-secondary.service; then

        echo -e "${GREEN}✓ BHTTP secundario ACTIVO${RESET}"
        echo "  Puerto BHTTP : $BHTTP_PORT2"
        echo "  Puerto SSH   : $SSH_PORT2"

    else

        echo -e "${RED}✗ Error al iniciar BHTTP secundario${RESET}"
        systemctl status btun-secondary.service --no-pager || true
    fi
}

# ==========================================
# DETENER PRINCIPAL
# ==========================================

stop_primary() {

    systemctl disable --now btun.service 2>/dev/null || true

    echo -e "${YELLOW}BHTTP principal detenido.${RESET}"
}

# ==========================================
# DETENER SECUNDARIO
# ==========================================

stop_secondary() {

    systemctl disable --now btun-secondary.service 2>/dev/null || true

    echo -e "${YELLOW}BHTTP secundario detenido.${RESET}"
}

# ==========================================
# REINICIAR AMBOS
# ==========================================

restart_all() {

    echo ""
    echo "Reiniciando servicios..."

    systemctl restart btun.service 2>/dev/null || true
    systemctl restart btun-secondary.service 2>/dev/null || true

    sleep 1

    echo ""
    echo -e "${GREEN}Servicios reiniciados.${RESET}"
}

# ==========================================
# ESTADO
# ==========================================

show_status() {

    echo ""
    echo "========================================="
    echo "             ESTADO BTUN"
    echo "========================================="
    echo ""

    echo "BHTTP PRINCIPAL"
    echo "Puerto BHTTP : $BHTTP_PORT"
    echo "Puerto SSH   : $SSH_PORT"

    if systemctl is-active --quiet btun.service; then
        echo -e "Estado       : ${GREEN}ACTIVO${RESET}"
    else
        echo -e "Estado       : ${RED}DETENIDO${RESET}"
    fi

    echo ""
    echo "BHTTP SECUNDARIO"
    echo "Puerto BHTTP : $BHTTP_PORT2"
    echo "Puerto SSH   : $SSH_PORT2"

    if systemctl is-active --quiet btun-secondary.service; then
        echo -e "Estado       : ${GREEN}ACTIVO${RESET}"
    else
        echo -e "Estado       : ${RED}DETENIDO${RESET}"
    fi

    echo ""
    echo "========================================="
    echo "             PUERTOS"
    echo "========================================="

    ss -lntp 2>/dev/null | grep -E ":$BHTTP_PORT |:$BHTTP_PORT2 " || \
        echo "No hay puertos BHTTP escuchando."

    echo ""
}

# ==========================================
# VER CONEXIONES
# ==========================================

show_connections() {

    echo ""
    echo "========================================="
    echo "          CONEXIONES BTUN"
    echo "========================================="
    echo ""

    ss -ntp 2>/dev/null | grep -E ":$BHTTP_PORT |:$BHTTP_PORT2 " || \
        echo "No hay conexiones activas."

    echo ""
}

# ==========================================
# LOG PRINCIPAL
# ==========================================

logs_primary() {

    echo ""
    echo "Mostrando logs del BHTTP principal..."
    echo "Presiona CTRL+C para salir."
    echo ""

    journalctl -u btun.service -f
}

# ==========================================
# LOG SECUNDARIO
# ==========================================

logs_secondary() {

    echo ""
    echo "Mostrando logs del BHTTP secundario..."
    echo "Presiona CTRL+C para salir."
    echo ""

    journalctl -u btun-secondary.service -f
}

# ==========================================
# CAMBIAR PUERTO PRINCIPAL
# ==========================================

change_primary_port() {

    echo ""
    read -rp "Nuevo puerto BHTTP principal: " NEW_PORT

    if ! valid_port "$NEW_PORT"; then
        echo -e "${RED}Puerto inválido.${RESET}"
        return
    fi

    if [[ "$NEW_PORT" == "$BHTTP_PORT2" ]]; then
        echo -e "${RED}Ese puerto ya está utilizado por el secundario.${RESET}"
        return
    fi

    BHTTP_PORT="$NEW_PORT"

    save_config

    create_service1

    systemctl daemon-reload

    if systemctl is-active --quiet btun.service; then
        systemctl restart btun.service
    fi

    echo ""
    echo -e "${GREEN}Puerto principal cambiado a $BHTTP_PORT${RESET}"
}

# ==========================================
# CAMBIAR PUERTO SECUNDARIO
# ==========================================

change_secondary_port() {

    echo ""
    read -rp "Nuevo puerto BHTTP secundario: " NEW_PORT

    if ! valid_port "$NEW_PORT"; then
        echo -e "${RED}Puerto inválido.${RESET}"
        return
    fi

    if [[ "$NEW_PORT" == "$BHTTP_PORT" ]]; then
        echo -e "${RED}Ese puerto ya está utilizado por el principal.${RESET}"
        return
    fi

    BHTTP_PORT2="$NEW_PORT"

    save_config

    create_service2

    systemctl daemon-reload

    if systemctl is-active --quiet btun-secondary.service; then
        systemctl restart btun-secondary.service
    fi

    echo ""
    echo -e "${GREEN}Puerto secundario cambiado a $BHTTP_PORT2${RESET}"
}

# ==========================================
# CAMBIAR SSH PRINCIPAL
# ==========================================

change_primary_ssh() {

    echo ""
    read -rp "Nuevo puerto SSH destino principal: " NEW_PORT

    if ! valid_port "$NEW_PORT"; then
        echo -e "${RED}Puerto inválido.${RESET}"
        return
    fi

    SSH_PORT="$NEW_PORT"

    save_config

    create_service1

    systemctl daemon-reload

    if systemctl is-active --quiet btun.service; then
        systemctl restart btun.service
    fi

    echo ""
    echo -e "${GREEN}SSH principal cambiado a $SSH_PORT${RESET}"
}

# ==========================================
# CAMBIAR SSH SECUNDARIO
# ==========================================

change_secondary_ssh() {

    echo ""
    read -rp "Nuevo puerto SSH destino secundario: " NEW_PORT

    if ! valid_port "$NEW_PORT"; then
        echo -e "${RED}Puerto inválido.${RESET}"
        return
    fi

    SSH_PORT2="$NEW_PORT"

    save_config

    create_service2

    systemctl daemon-reload

    if systemctl is-active --quiet btun-secondary.service; then
        systemctl restart btun-secondary.service
    fi

    echo ""
    echo -e "${GREEN}SSH secundario cambiado a $SSH_PORT2${RESET}"
}

# ==========================================
# ACTIVAR TODO
# ==========================================

start_all() {

    install_binary

    save_config

    create_service1
    create_service2

    systemctl daemon-reload

    systemctl enable --now btun.service
    systemctl enable --now btun-secondary.service

    sleep 1

    echo ""
    echo "========================================="
    echo -e "       ${GREEN}BTUN BHTTP ACTIVADO${RESET}"
    echo "========================================="
    echo ""
    echo "PRINCIPAL"
    echo "BHTTP : 0.0.0.0:$BHTTP_PORT"
    echo "SSH   : 127.0.0.1:$SSH_PORT"
    echo ""
    echo "SECUNDARIO"
    echo "BHTTP : 0.0.0.0:$BHTTP_PORT2"
    echo "SSH   : 127.0.0.1:$SSH_PORT2"
    echo ""

    show_status
}

# ==========================================
# DESINSTALAR
# ==========================================

uninstall_all() {

    echo ""
    echo "========================================="
    echo "          DESINSTALAR BTUN"
    echo "========================================="
    echo ""

    read -rp "¿Seguro que quieres eliminar BTUN? [s/N]: " RESP

    if [[ ! "$RESP" =~ ^[Ss]$ ]]; then
        echo "Cancelado."
        return
    fi

    systemctl disable --now btun.service 2>/dev/null || true
    systemctl disable --now btun-secondary.service 2>/dev/null || true

    rm -f "$SERV1"
    rm -f "$SERV2"

    systemctl daemon-reload

    rm -f "$BIN"
    rm -f "$CONFIG"

    echo ""
    echo -e "${GREEN}BTUN BHTTP eliminado correctamente.${RESET}"
    echo ""
}

# ==========================================
# MENÚ PRINCIPAL
# ==========================================

menu() {

    load_config

    while true; do

        clear

        # Fondo negro completo
        printf "\033[40m\033[2J\033[H"

        echo ""

        # ==========================================
        # ENCABEZADO
        # ==========================================

        printf "${BORDER_CYAN}${BOLD}+--------------------------------------------------------------+${RESET}\n"
        printf "${BORDER_CYAN}${BOLD}|${RESET}${WHITE}${BOLD}                    ANTONIO MX PANEL                         ${RESET}${BORDER_CYAN}${BOLD}|${RESET}\n"
        printf "${BORDER_CYAN}${BOLD}|${RESET}${WHITE}${BOLD}                         BTUN BHTTP                           ${RESET}${BORDER_CYAN}${BOLD}|${RESET}\n"
        printf "${BORDER_CYAN}${BOLD}+--------------------------------------------------------------+${RESET}\n"

        echo ""

        # ==========================================
        # ESTADO DE SERVIDORES
        # ==========================================

        if systemctl is-active --quiet btun.service; then
            STATUS1="${GREEN}${BOLD}ACTIVO${RESET}"
        else
            STATUS1="${RED}${BOLD}DETENIDO${RESET}"
        fi

        if systemctl is-active --quiet btun-secondary.service; then
            STATUS2="${GREEN}${BOLD}ACTIVO${RESET}"
        else
            STATUS2="${RED}${BOLD}DETENIDO${RESET}"
        fi

        printf "${BORDER_BLUE}${BOLD}+--------------------------------------------------------------+${RESET}\n"
        printf "${BORDER_BLUE}${BOLD}|${RESET}${WHITE}${BOLD}                       SERVIDORES                            ${RESET}${BORDER_BLUE}${BOLD}|${RESET}\n"
        printf "${BORDER_BLUE}${BOLD}+--------------------------------------------------------------+${RESET}\n"

        printf "${BORDER_BLUE}|${RESET}  ${WHITE}${BOLD}PRINCIPAL${RESET}                         ${WHITE}${BOLD}SECUNDARIO${RESET}       ${BORDER_BLUE}|${RESET}\n"

        printf "${BORDER_BLUE}|${RESET}  ${WHITE}BHTTP :${RESET} ${CYAN}${BHTTP_PORT}${RESET}                         ${WHITE}BHTTP :${RESET} ${CYAN}${BHTTP_PORT2}${RESET}       ${BORDER_BLUE}|${RESET}\n"

        printf "${BORDER_BLUE}|${RESET}  ${WHITE}SSH   :${RESET} ${CYAN}${SSH_PORT}${RESET}                           ${WHITE}SSH   :${RESET} ${CYAN}${SSH_PORT2}${RESET}         ${BORDER_BLUE}|${RESET}\n"

        printf "${BORDER_BLUE}|${RESET}  ${WHITE}Estado:${RESET} ${STATUS1}                     ${WHITE}Estado:${RESET} ${STATUS2}       ${BORDER_BLUE}|${RESET}\n"

        printf "${BORDER_BLUE}${BOLD}+--------------------------------------------------------------+${RESET}\n"

        echo ""

        # ==========================================
        # MENÚ
        # ==========================================

        printf "${BORDER_MAGENTA}${BOLD}+--------------------------------------------------------------+${RESET}\n"
        printf "${BORDER_MAGENTA}${BOLD}|${RESET}${WHITE}${BOLD}                           MENU                               ${RESET}${BORDER_MAGENTA}${BOLD}|${RESET}\n"
        printf "${BORDER_MAGENTA}${BOLD}+--------------------------------------------------------------+${RESET}\n"

        # FILA 1
        printf "${BORDER_MAGENTA}|${RESET}  ${BLUE}${BOLD}01${RESET} ${WHITE}Activar ambos${RESET}              ${BLUE}${BOLD}02${RESET} ${WHITE}Activar principal${RESET}     ${BORDER_MAGENTA}|${RESET}\n"

        # FILA 2
        printf "${BORDER_MAGENTA}|${RESET}  ${BLUE}${BOLD}03${RESET} ${WHITE}Activar secundario${RESET}         ${BLUE}${BOLD}04${RESET} ${WHITE}Detener principal${RESET}     ${BORDER_MAGENTA}|${RESET}\n"

        # FILA 3
        printf "${BORDER_MAGENTA}|${RESET}  ${BLUE}${BOLD}05${RESET} ${WHITE}Detener secundario${RESET}         ${BLUE}${BOLD}06${RESET} ${WHITE}Reiniciar ambos${RESET}        ${BORDER_MAGENTA}|${RESET}\n"

        # FILA 4
        printf "${BORDER_MAGENTA}|${RESET}  ${BLUE}${BOLD}07${RESET} ${WHITE}Puerto BHTTP principal${RESET}      ${BLUE}${BOLD}08${RESET} ${WHITE}Puerto BHTTP secundario${RESET} ${BORDER_MAGENTA}|${RESET}\n"

        # FILA 5
        printf "${BORDER_MAGENTA}|${RESET}  ${BLUE}${BOLD}09${RESET} ${WHITE}Puerto SSH principal${RESET}        ${BLUE}${BOLD}10${RESET} ${WHITE}Puerto SSH secundario${RESET}  ${BORDER_MAGENTA}|${RESET}\n"

        # FILA 6
        printf "${BORDER_MAGENTA}|${RESET}  ${BLUE}${BOLD}11${RESET} ${WHITE}Ver estado${RESET}                  ${BLUE}${BOLD}12${RESET} ${WHITE}Ver conexiones${RESET}        ${BORDER_MAGENTA}|${RESET}\n"

        # FILA 7
        printf "${BORDER_MAGENTA}|${RESET}  ${BLUE}${BOLD}13${RESET} ${WHITE}Logs principal${RESET}              ${BLUE}${BOLD}14${RESET} ${WHITE}Logs secundario${RESET}       ${BORDER_MAGENTA}|${RESET}\n"

        # FILA 8
        printf "${BORDER_MAGENTA}|${RESET}  ${BLUE}${BOLD}15${RESET} ${WHITE}Desinstalar BTUN${RESET}            ${BLUE}${BOLD}00${RESET} ${WHITE}Salir${RESET}                  ${BORDER_MAGENTA}|${RESET}\n"

        printf "${BORDER_MAGENTA}${BOLD}+--------------------------------------------------------------+${RESET}\n"

        echo ""

        printf "${WHITE}--------------------------------------------------------------${RESET}\n"
        printf "${CYAN}${BOLD} BTUN${RESET}${WHITE} > Selecciona una opcion: ${RESET}"

        read -r OPCION

        case "$OPCION" in

            1)
                start_all
                read -rp "Presiona ENTER para continuar..."
                ;;

            2)
                install_binary
                save_config
                create_service1
                systemctl daemon-reload
                systemctl enable --now btun.service
                echo ""
                echo -e "${GREEN}${OK} ${WHITE}BHTTP principal activado.${RESET}"
                read -rp "Presiona ENTER para continuar..."
                ;;

            3)
                install_binary
                save_config
                create_service2
                systemctl daemon-reload
                systemctl enable --now btun-secondary.service
                echo ""
                echo -e "${GREEN}${OK} ${WHITE}BHTTP secundario activado.${RESET}"
                read -rp "Presiona ENTER para continuar..."
                ;;

            4)
                stop_primary
                read -rp "Presiona ENTER para continuar..."
                ;;

            5)
                stop_secondary
                read -rp "Presiona ENTER para continuar..."
                ;;

            6)
                restart_all
                read -rp "Presiona ENTER para continuar..."
                ;;

            7)
                change_primary_port
                read -rp "Presiona ENTER para continuar..."
                ;;

            8)
                change_secondary_port
                read -rp "Presiona ENTER para continuar..."
                ;;

            9)
                change_primary_ssh
                read -rp "Presiona ENTER para continuar..."
                ;;

            10)
                change_secondary_ssh
                read -rp "Presiona ENTER para continuar..."
                ;;

            11)
                show_status
                read -rp "Presiona ENTER para continuar..."
                ;;

            12)
                show_connections
                read -rp "Presiona ENTER para continuar..."
                ;;

            13)
                logs_primary
                ;;

            14)
                logs_secondary
                ;;

            15)
                uninstall_all
                read -rp "Presiona ENTER para continuar..."
                ;;

            0)
                clear
                printf "\033[0m"
                exit 0
                ;;

            *)
                echo ""
                echo -e "${RED}${ERROR} ${WHITE}Opcion invalida.${RESET}"
                sleep 2
                ;;
        esac

    done
}

# ==========================================
# AYUDA CLI
# ==========================================

usage() {

    echo "================================="
    echo "       BTUN BHTTP INSTALLER"
    echo "================================="
    echo ""
    echo "Uso:"
    echo ""
    echo "  btun"
    echo "      Abrir menú"
    echo ""
    echo "  btun --on"
    echo "      Activar ambos puertos"
    echo ""
    echo "  btun --on --port 8080 --port2 8081"
    echo "      Activar ambos puertos"
    echo ""
    echo "  btun --off"
    echo "      Desinstalar BTUN"
    echo ""
    echo "Opciones:"
    echo ""
    echo "  -p, --port PORT"
    echo "      Puerto BHTTP principal"
    echo ""
    echo "  -p2, --port2 PORT"
    echo "      Puerto BHTTP secundario"
    echo ""
    echo "  -s, --ssh PORT"
    echo "      Puerto SSH principal"
    echo ""
    echo "  -s2, --ssh2 PORT"
    echo "      Puerto SSH secundario"
    echo ""
    echo "  --on"
    echo "      Activar ambos servicios"
    echo ""
    echo "  --off"
    echo "      Desinstalar"
    echo ""
    exit 1
}

# ==========================================
# PROGRAMA PRINCIPAL
# ==========================================

load_config

# SIN ARGUMENTOS = MENU
if [[ $# -eq 0 ]]; then

    if [[ "$(id -u)" -ne 0 ]]; then
        echo -e "${RED}Ejecuta el menú como root.${RESET}"
        exit 1
    fi

    install_binary
    install_command

    menu
fi

# ==========================================
# ARGUMENTOS
# ==========================================

while [[ $# -gt 0 ]]; do

    case "$1" in

        -p|--port)

            shift
            [[ $# -gt 0 ]] || usage

            valid_port "$1" || {
                echo "Puerto BHTTP inválido: $1"
                exit 1
            }

            BHTTP_PORT="$1"
            shift
            ;;

        -p2|--port2)

            shift
            [[ $# -gt 0 ]] || usage

            valid_port "$1" || {
                echo "Puerto BHTTP secundario inválido: $1"
                exit 1
            }

            BHTTP_PORT2="$1"
            shift
            ;;

        -s|--ssh)

            shift
            [[ $# -gt 0 ]] || usage

            valid_port "$1" || {
                echo "Puerto SSH inválido: $1"
                exit 1
            }

            SSH_PORT="$1"
            shift
            ;;

        -s2|--ssh2)

            shift
            [[ $# -gt 0 ]] || usage

            valid_port "$1" || {
                echo "Puerto SSH secundario inválido: $1"
                exit 1
            }

            SSH_PORT2="$1"
            shift
            ;;

        --on)

            ON=true
            shift
            ;;

        --off)

            OFF=true
            shift
            ;;

        -h|--help)

            usage
            ;;

        *)

            echo "Opción desconocida: $1"
            usage
            ;;
    esac
done

# ==========================================
# ON / OFF
# ==========================================

if $ON && $OFF; then

    echo "No puedes usar --on y --off al mismo tiempo."
    exit 1
fi

if $ON; then

    if [[ "$(id -u)" -ne 0 ]]; then
        echo "Ejecuta este comando como root."
        exit 1
    fi

    if [[ "$BHTTP_PORT" == "$BHTTP_PORT2" ]]; then
        echo "ERROR: los dos puertos BHTTP no pueden ser iguales."
        exit 1
    fi

    install_binary
    install_command

    save_config

    create_service1
    create_service2

    systemctl daemon-reload

    systemctl enable --now btun.service
    systemctl enable --now btun-secondary.service

    sleep 1

    echo ""
    echo "================================="
    echo "     BTUN BHTTP ACTIVADO"
    echo "================================="
    echo ""
    echo "PRINCIPAL"
    echo "BHTTP : 0.0.0.0:$BHTTP_PORT"
    echo "SSH   : 127.0.0.1:$SSH_PORT"
    echo ""
    echo "SECUNDARIO"
    echo "BHTTP : 0.0.0.0:$BHTTP_PORT2"
    echo "SSH   : 127.0.0.1:$SSH_PORT2"
    echo ""

    if systemctl is-active --quiet btun.service; then
        echo -e "Principal  : ${GREEN}ACTIVO${RESET}"
    else
        echo -e "Principal  : ${RED}ERROR${RESET}"
    fi

    if systemctl is-active --quiet btun-secondary.service; then
        echo -e "Secundario : ${GREEN}ACTIVO${RESET}"
    else
        echo -e "Secundario : ${RED}ERROR${RESET}"
    fi

    echo ""
    echo "Puertos escuchando:"

    ss -lntp 2>/dev/null | \
        grep -E ":$BHTTP_PORT |:$BHTTP_PORT2 " || true

    exit 0
fi

if $OFF; then

    if [[ "$(id -u)" -ne 0 ]]; then
        echo "Ejecuta este comando como root."
        exit 1
    fi

    uninstall_all
    exit 0
fi

usage