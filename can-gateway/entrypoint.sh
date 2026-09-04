#!/bin/sh
set -e

# Configura l'interfaccia CAN sull'host (richiede network_mode: host + privileged)
# Adatta bitrate al tuo bus (es. 500000 per OBD-II standard)
if ip link show can0 > /dev/null 2>&1; then
    ip link set can0 down || true
    ip link set can0 type can bitrate 500000
    ip link set can0 up
else
    echo "ATTENZIONE: interfaccia can0 non trovata. Verifica overlay dtoverlay=mcp2515 in /boot/config.txt"
fi

exec python gateway.py
