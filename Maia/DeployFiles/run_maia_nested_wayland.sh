#!/bin/bash

# Uruchamia Maię w zagnieżdżonym kwin_wayland (okno w bieżącej sesji),
# z osobną magistralą D-Bus, żeby nie kolidować z główną sesją.
# Zastępuje dawny run_maia_in_xephyr.sh.
#
# Użycie:
#   ./run_maia_nested_wayland.sh [ścieżka/do/appMaiaServer]
#       - domyślnie appMaiaServer z katalogu, w którym leży ten skrypt
#   ./run_maia_nested_wayland.sh --compositor-only
#       - sam kompozytor (np. do uruchamiania/debugowania Mai z Qt Creatora);
#         zmienne potrzebne do połączenia zapisuje w ${ENV_FILE}
#
# Zmienne konfiguracyjne (opcjonalne):
#   MAIA_NESTED_WIDTH, MAIA_NESTED_HEIGHT - rozmiar okna (domyślnie 1280x720)
#   MAIA_NESTED_SOCKET                    - nazwa gniazda Wayland (domyślnie wayland-maia-dev)
#   MAIA_QPA_PLATFORM                     - platforma Qt dla Mai (domyślnie wayland,
#                                           xcb = Maia przez Xwayland, do porównań)
#   MAIA_LOG_PORT                         - port Loggera (domyślnie 50003)

ENV_FILE="${XDG_RUNTIME_DIR:-/tmp}/maia-nested-wayland.env"

# ==========================================================================
# FAZA 2: uruchomione przez zagnieżdżony KWin (--exit-with-session)
# ==========================================================================
if [ "${MAIA_NESTED_STAGE}" = "inside_kwin" ]; then
    unset MAIA_NESTED_STAGE
    unset KWIN_WAYLAND_NO_PERMISSION_CHECKS

    # Zapisujemy dane połączenia z zagnieżdżoną sesją (do skopiowania np. do Qt Creatora)
    {
        echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY}"
        echo "DISPLAY=${DISPLAY}"
        echo "XAUTHORITY=${XAUTHORITY}"
        echo "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS}"
        echo "QT_QPA_PLATFORM=${MAIA_QPA_PLATFORM:-wayland}"
        echo "MAIA_LOG_PORT=${MAIA_LOG_PORT}"
    } > "${ENV_FILE}"

    echo "--- Zagnieżdżona sesja Maia gotowa, dane połączenia w: ${ENV_FILE} ---"
    cat "${ENV_FILE}"

    if command -v dbus-update-activation-environment >/dev/null 2>&1; then
        dbus-update-activation-environment WAYLAND_DISPLAY DISPLAY XAUTHORITY \
            XDG_SESSION_TYPE XDG_CURRENT_DESKTOP KDE_FULL_SESSION KDE_SESSION_VERSION
    fi

    if [ -z "${MAIA_NESTED_APP}" ]; then
        # Tryb --compositor-only: utrzymujemy sesję przy życiu do zamknięcia okna KWina
        echo "Tryb --compositor-only: uruchom Maię z powyższymi zmiennymi środowiskowymi."
        exec sleep infinity
    fi

    # Maia natywnie na Waylandzie. Platforma przez -platform, żeby aplikacje
    # uruchamiane z Mai dziedziczyły QT_QPA_PLATFORM="wayland;xcb" (fallback na Xwayland).
    echo "Uruchamianie ${MAIA_NESTED_APP} (-platform ${MAIA_QPA_PLATFORM:-wayland})..."
    cd "$(dirname "${MAIA_NESTED_APP}")" || exit 1
    exec env -u QT_QPA_PLATFORMTHEME \
             -u QT_PLUGIN_PATH \
             "${MAIA_NESTED_APP}" -platform "${MAIA_QPA_PLATFORM:-wayland}"
fi

# ==========================================================================
# FAZA 1: start z terminala / Qt Creatora w bieżącej sesji
# ==========================================================================
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")"

if [ "$1" = "--compositor-only" ]; then
    MAIA_NESTED_APP=""
else
    MAIA_NESTED_APP="$(readlink -f "${1:-${SCRIPT_DIR}/appMaiaServer}")"
    if [ ! -x "${MAIA_NESTED_APP}" ]; then
        echo "[ERROR] Nie znaleziono pliku wykonywalnego: ${MAIA_NESTED_APP}" >&2
        exit 1
    fi
fi

if [ -z "${WAYLAND_DISPLAY}" ] && [ -z "${DISPLAY}" ]; then
    echo "[ERROR] Brak WAYLAND_DISPLAY i DISPLAY - zagnieżdżony KWin potrzebuje działającej sesji graficznej." >&2
    exit 1
fi

export MAIA_NESTED_APP
export MAIA_NESTED_STAGE=inside_kwin
export MAIA_LOG_PORT="${MAIA_LOG_PORT:-50003}"
export MAIA_QPA_PLATFORM="${MAIA_QPA_PLATFORM:-wayland}"

# Środowisko sesji wewnątrz zagnieżdżonego KWina (jak w run_maia_wayland.sh)
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=KDE
export KDE_FULL_SESSION=true
export KDE_SESSION_VERSION=6
export QT_QPA_PLATFORM="wayland;xcb"
export GDK_BACKEND="wayland,x11"
export GTK_USE_PORTAL=0
export KWIN_WAYLAND_NO_PERMISSION_CHECKS=1

echo "Uruchamianie zagnieżdżonego kwin_wayland (${MAIA_NESTED_WIDTH:-1280}x${MAIA_NESTED_HEIGHT:-720})..."

# dbus-run-session: osobna magistrala D-Bus, dzięki czemu org.kde.KWin i org.maia.*
# z sesji deweloperskiej nie kolidują z główną sesją.
# WAYLAND_DISPLAY/DISPLAY z bieżącej sesji zostają - KWin otworzy się jako okno.
dbus-run-session -- kwin_wayland \
    --width "${MAIA_NESTED_WIDTH:-1280}" \
    --height "${MAIA_NESTED_HEIGHT:-720}" \
    --socket "${MAIA_NESTED_SOCKET:-wayland-maia-dev}" \
    --xwayland \
    --exit-with-session="${SCRIPT_PATH}" &
DBUS_RUN_SESSION_PID=$!

# dbus-run-session nie przekazuje SIGTERM dalej, więc zatrzymanie samego skryptu
# (Stop w Qt Creatorze, kill, timeout) zostawiłoby KWina i Maię w tle.
# Zamykamy KWina jawnie - on z kolei kończy Maię i Xwayland.
trap 'pkill -TERM -P "${DBUS_RUN_SESSION_PID}"; wait "${DBUS_RUN_SESSION_PID}"' INT TERM
wait "${DBUS_RUN_SESSION_PID}"
