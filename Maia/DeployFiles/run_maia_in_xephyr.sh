#!/bin/bash


export DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/maia-dev-dbus-3.sock
export MAIA_LOG_PORT=3
dbus-run-session Xephyr :3 -screen 1280x720 -ac &

sleep 0.5


# solve long gtk+ applications startup
export GTK_USE_PORTAL=0
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/Maia/Maia_0.1.0/lib
export DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/maia-dev-dbus-3.sock
export MAIA_LOG_PORT=3
export DISPLAY=:3
dbus-run-session ./appMaiaServer
