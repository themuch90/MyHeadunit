#!/bin/sh
set -e

# autoapp disegna su Xvfb (X server virtuale), GStreamer cattura quello
# schermo e lo trasmette via TCP: nessuna GPU, nessun VNC.
export DISPLAY=:1
export QT_QPA_PLATFORM=xcb

exec python3 /app/launcher.py
