#!/bin/bash

# Uruchamia Maię w zagnieżdżonym kwin_wayland (okno w bieżącej sesji),
# z osobną magistralą D-Bus, żeby nie kolidować z główną sesją.
#
# Sesją zarządza ta sama usługa co w prawdziwej sesji (maia-session-service, kompozytor kwin-nested
# z session.toml), tylko z atrapą logind: restart, wyłączenie i uśpienie trafiają do logu, nie do
# tego komputera. Usługa kończy się razem z oknem KWina (albo po wylogowaniu w Mai).
#
# Użycie:
#   ./run_maia_nested_wayland.sh [ścieżka/do/appMaiaServer]
#       - domyślnie appMaiaServer z katalogu, w którym leży ten skrypt
#   ./run_maia_nested_wayland.sh --compositor-only
#       - kompozytor i usługi bez serwera Maia (np. do uruchamiania/debugowania Mai z Qt Creatora);
#         zmienne potrzebne do połączenia zapisuje w ${ENV_FILE}
#
# Zmienne konfiguracyjne (opcjonalne):
#   MAIA_NESTED_WIDTH, MAIA_NESTED_HEIGHT - rozmiar okna (domyślnie 1280x720)
#   MAIA_NESTED_SOCKET                    - nazwa gniazda Wayland (domyślnie wayland-maia-dev)
#   MAIA_SESSION_BACKEND                  - fake (domyślnie): restart, wyłączenie i uśpienie tylko w logu;
#                                           logind: prawdziwy (np. z atrapą magistrali systemowej
#                                           w DBUS_SYSTEM_BUS_ADDRESS)
#   MAIA_QPA_PLATFORM                     - platforma Qt dla Mai (domyślnie wayland,
#                                           xcb = Maia przez Xwayland, do porównań)
#   MAIA_LOG_PORT                         - port Loggera (domyślnie 50003)
#   MAIA_LOG_FILE                         - log serwera Maia (domyślnie $XDG_RUNTIME_DIR/maia-nested-server.log,
#                                           nie log prawdziwej sesji w katalogu domowym)
#   MAIA_SESSION_SERVICE                  - program usługi sesji (domyślnie szukany obok Mai)
#   MAIA_SESSION_MANIFEST                 - session.toml (domyślnie obok skryptu: etc/maia albo ../etc/maia)
#   MAIA_WINDOWS_SERVICE                  - program usługi okien (domyślnie szukany obok Mai)
#   MAIA_NETWORK_SERVICE                  - program usługi sieci (domyślnie szukany obok Mai)
#   MAIA_NETWORK_BACKEND                  - fake (domyślnie): symulowana sieć; networkmanager: prawdziwy
#                                           NetworkManager - akcje zmieniają sieć tego komputera, a agent
#                                           haseł konkuruje z agentem głównej sesji
#   MAIA_APPEARANCE_SERVICE               - program usługi wyglądu (domyślnie szukany obok Mai)
#   MAIA_APPEARANCE_BACKEND               - kwin (domyślnie): kwinrc z XDG_CONFIG_HOME tej sesji; fake: w pamięci

ENV_FILE="${XDG_RUNTIME_DIR:-/tmp}/maia-nested-wayland.env"

# ==========================================================================
# FAZA 2: wewnątrz dbus-run-session, własna magistrala sesyjna
# ==========================================================================
if [ "${MAIA_NESTED_STAGE}" = "inside_dbus" ]; then
    unset MAIA_NESTED_STAGE
    # Dane połączenia (do skopiowania np. do Qt Creatora) zapisuje proces nested-env-file z session.toml,
    # gdy kompozytor jest gotowy (zna wtedy WAYLAND_DISPLAY i DISPLAY)
    export MAIA_NESTED_ENV_FILE="${ENV_FILE}"
    exec "${MAIA_SESSION_SERVICE}" --compositor kwin-nested ${MAIA_NESTED_WITHOUT}
fi

# ==========================================================================
# FAZA 1: start z terminala / Qt Creatora w bieżącej sesji
# ==========================================================================
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")"

if [ "$1" = "--compositor-only" ]; then
    MAIA_NESTED_APP=""
    export MAIA_NESTED_WITHOUT="--without appMaiaServer"
else
    MAIA_NESTED_APP="$(readlink -f "${1:-${SCRIPT_DIR}/appMaiaServer}")"
    if [ ! -x "${MAIA_NESTED_APP}" ]; then
        echo "[ERROR] Nie znaleziono pliku wykonywalnego: ${MAIA_NESTED_APP}" >&2
        exit 1
    fi
    export MAIA_SHELL="${MAIA_NESTED_APP}"
fi

if [ -z "${WAYLAND_DISPLAY}" ] && [ -z "${DISPLAY}" ]; then
    echo "[ERROR] Brak WAYLAND_DISPLAY i DISPLAY - zagnieżdżony KWin potrzebuje działającej sesji graficznej." >&2
    exit 1
fi

# Programy Mai: w instalacji bin/ i libexec/, w katalogu budowania bin/ i cargo/<profil>/
BIN_DIR="$(dirname "${MAIA_NESTED_APP:-${SCRIPT_PATH}}")"
find_program() {
    local name="$1" candidate
    for candidate in "${BIN_DIR}/../libexec/${name}" "${BIN_DIR}/../cargo/release/${name}" \
                     "${BIN_DIR}/../cargo/debug/${name}"; do
        if [ -x "${candidate}" ]; then
            readlink -f "${candidate}"
            return
        fi
    done
}
export MAIA_SESSION_SERVICE="${MAIA_SESSION_SERVICE:-$(find_program maia-session-service)}"
if [ ! -x "${MAIA_SESSION_SERVICE}" ]; then
    echo "[ERROR] Nie znaleziono maia-session-service obok ${BIN_DIR} (MAIA_SESSION_SERVICE wskazuje go jawnie)" >&2
    exit 1
fi
for service in windows network appearance; do
    variable="MAIA_$(echo "${service}" | tr '[:lower:]' '[:upper:]')_SERVICE"
    if [ -z "${!variable}" ]; then
        found="$(find_program "maia-${service}-service")"
        [ -n "${found}" ] && export "${variable}=${found}"
    fi
done
if [ -z "${MAIA_SESSION_MANIFEST}" ]; then
    for candidate in "${SCRIPT_DIR}/etc/maia/session.toml" "${SCRIPT_DIR}/../etc/maia/session.toml"; do
        if [ -r "${candidate}" ]; then
            export MAIA_SESSION_MANIFEST="$(readlink -f "${candidate}")"
            break
        fi
    done
fi
export MAIA_PREFIX="$(readlink -f "${BIN_DIR}/..")"

export MAIA_NESTED_STAGE=inside_dbus
export MAIA_NESTED_SOCKET="${MAIA_NESTED_SOCKET:-wayland-maia-dev}"
# Gniazdo usługi sesji z nazwą zagnieżdżonego ekranu: XDG_SESSION_ID jest to samo co w głównej sesji
export MAIA_SESSION_SOCKET="${XDG_RUNTIME_DIR:-/tmp}/maia/session-${MAIA_NESTED_SOCKET}.sock"
# Restart, wyłączenie i uśpienie z Mai poszłyby do systemd-logind prawdziwej maszyny: atrapa
export MAIA_SESSION_BACKEND="${MAIA_SESSION_BACKEND:-fake}"
# Usługi KDE (systemd --user) należą do głównej sesji: nie uruchamiamy ich
export MAIA_SESSION_TEST=1
export MAIA_NETWORK_BACKEND="${MAIA_NETWORK_BACKEND:-fake}"
export MAIA_LOG_PORT="${MAIA_LOG_PORT:-50003}"
export MAIA_LOG_FILE="${MAIA_LOG_FILE:-${XDG_RUNTIME_DIR:-/tmp}/maia-nested-server.log}"
export MAIA_QPA_PLATFORM="${MAIA_QPA_PLATFORM:-wayland}"

# Środowisko sesji wewnątrz zagnieżdżonego KWina (jak w session/maia-session-common.sh.in)
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=KDE
export KDE_FULL_SESSION=true
export KDE_SESSION_VERSION=6
export QT_QPA_PLATFORM="wayland;xcb"
export GDK_BACKEND="wayland,x11"
export GTK_USE_PORTAL=0

# Ustawienia dystrybucji dla sesji KDE (plasma-workspace/env/*.sh) i domyślne ustawienia Mai, jak
# w session/maia-session-common.sh.in (tam opis, dlaczego). Domyślne ustawienia Mai leżą w etc/xdg: obok skryptu
# w drzewie źródeł (Maia/DeployFiles/etc/xdg) albo w katalogu instalacji (bin/../etc/xdg).
for dir in $(echo "${XDG_CONFIG_DIRS:-/etc/xdg}" | tr ':' '\n' | tac) "${XDG_CONFIG_HOME:-$HOME/.config}"; do
    for script in "${dir}"/plasma-workspace/env/*.sh; do
        [ -r "${script}" ] && . "${script}"
    done
done
MAIA_DEFAULTS_DIR="${SCRIPT_DIR}/etc/xdg"
[ -d "${MAIA_DEFAULTS_DIR}" ] || MAIA_DEFAULTS_DIR="$(readlink -f "${SCRIPT_DIR}/../etc/xdg")"
export XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/etc/xdg}:${MAIA_DEFAULTS_DIR}"
# Dane Mai (share obok bin programu Mai: plik .desktop Ustawień Maia, strony ustawień), jak w
# session/maia-session-common.sh.in
if [ -d "${BIN_DIR}/../share" ]; then
    export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}:$(readlink -f "${BIN_DIR}/../share")"
fi

echo "Uruchamianie zagnieżdżonej sesji (${MAIA_NESTED_WIDTH:-1280}x${MAIA_NESTED_HEIGHT:-720}, ${MAIA_SESSION_SERVICE})..."

# dbus-run-session: osobna magistrala D-Bus, dzięki czemu org.kde.KWin i org.maia.*
# z sesji deweloperskiej nie kolidują z główną sesją.
# WAYLAND_DISPLAY/DISPLAY z bieżącej sesji zostają - KWin otworzy się jako okno.
dbus-run-session -- "${SCRIPT_PATH}" &
DBUS_RUN_SESSION_PID=$!

# dbus-run-session nie przekazuje SIGTERM dalej, więc zatrzymanie samego skryptu
# (Stop w Qt Creatorze, kill, timeout) zostawiłoby sesję w tle.
# Kończymy usługę sesji jawnie - ona kończy Maię, usługi i KWina.
trap 'pkill -TERM -P "${DBUS_RUN_SESSION_PID}"; wait "${DBUS_RUN_SESSION_PID}"' INT TERM
wait "${DBUS_RUN_SESSION_PID}"
