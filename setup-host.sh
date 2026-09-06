#!/bin/bash
# Setup host - mini PC x86_64 con 2 schede Bluetooth + 2 schede WiFi
# (su mini PC salta la sezione overlay CAN via SPI, opzionale per chi usa
# invece una scheda con HAT MCP2515: usa un adattatore USB-CAN al suo posto,
# vedi nota in fondo)
# Da eseguire UNA VOLTA sull'host, non dentro container.
set -e

echo "== Aggiornamento sistema =="
sudo apt-get update && sudo apt-get upgrade -y

echo "== Installazione Docker (metodo ufficiale get.docker.com) =="
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"

echo "== Docker Compose plugin =="
sudo apt-get install -y docker-compose-plugin

echo "== Cage (kiosk Wayland) e dipendenze di build per l'app Flutter Linux desktop =="
echo "   L'interfaccia gira come normale app Flutter Linux desktop (target"
echo "   'linux' ufficiale, 'flutter build linux'), lanciata fullscreen come"
echo "   unico client sotto Cage -- niente piu' embedder custom da compilare."
sudo apt-get install -y \
    cage \
    clang \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    liblzma-dev \
    can-utils

echo "== libvncclient: serve per compilare il plugin texture Android Auto =="
sudo apt-get install -y libvncclient-dev

echo "== Android Auto CABLATO (USB/AOAP): regole udev per il telefono =="
sudo cp androidauto-bridge/51-android-auto.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger
echo "   Collega il telefono via USB al mini PC per testare il rilevamento:"
echo "   lsusb   (dovresti vedere il device del telefono comparire/cambiare"
echo "            VID quando aasdk forza lo switch in modalita' accessory)"

echo "== Stack telefonia: BlueZ, oFono (HFP), obexd (PBAP rubrica) =="
echo "   Questi restano demoni di sistema gestiti da systemd (legati a"
echo "   kernel/hardware Bluetooth); il codice applicativo che li orchestra"
echo "   (phone-bridge) gira invece in Docker, vedi compose.yaml."
sudo apt-get install -y \
    bluez \
    bluez-obexd \
    ofono

# Abilita il ruolo Hands-Free (HF) di oFono verso BlueZ
sudo mkdir -p /etc/ofono
if ! grep -q "^\[hfp\]" /etc/ofono/main.conf 2>/dev/null; then
  printf "[hfp]\nEnable=true\n" | sudo tee -a /etc/ofono/main.conf > /dev/null
fi

sudo systemctl enable --now bluetooth.service ofono.service

echo "== Bus di sessione dedicato per obexd (rubrica via PBAP) =="
echo "   obexd si registra SOLO sul bus di sessione D-Bus, mai su quello"
echo "   di sistema; su un host headless (nessun utente con sessione"
echo "   desktop attiva) quel bus non esiste di default, quindi gliene"
echo "   creiamo uno dedicato e persistente. phone-bridge (in Docker) ci"
echo "   si connette tramite il socket montato, vedi compose.yaml."
cat <<'UNIT' | sudo tee /etc/systemd/system/dbus-session-obex.service > /dev/null
[Unit]
Description=Bus di sessione D-Bus dedicato a obexd (nessuna sessione desktop su un host headless)

[Service]
Type=simple
RuntimeDirectory=dbus-session-obex
ExecStart=/usr/bin/dbus-daemon --session --address=unix:path=/run/dbus-session-obex/bus --nofork --nopidfile

[Install]
WantedBy=multi-user.target
UNIT
cat <<'UNIT' | sudo tee /etc/systemd/system/obex.service > /dev/null
[Unit]
Description=Bluetooth OBEX service (bus di sessione dedicato, host headless)
After=dbus-session-obex.service
Requires=dbus-session-obex.service

[Service]
Type=simple
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/dbus-session-obex/bus
ExecStart=/usr/libexec/bluetooth/obexd -n

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable --now dbus-session-obex.service obex.service

echo "== Mopidy (motore radio web) =="
echo "   Demone di sistema come bluetoothd/ofonod/obexd sopra, non un"
echo "   container: ha bisogno di accesso diretto all'hardware audio ALSA,"
echo "   che un container Docker minimale non riesce a risolvere in modo"
echo "   affidabile (alsa-lib ha bisogno del database udev dell'host)."
echo "   L'app Flutter ci si collega direttamente via WebSocket/JSON-RPC su"
echo "   127.0.0.1:6680, vedi lib/services/radio_service.dart."
sudo apt-get install -y \
    mopidy \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-libav \
    glib-networking

# Bug reale in mopidy 3.4.2 (mopidy/audio/scan.py) con la versione di
# PyGObject/GStreamer di Debian trixie: nel ramo "have-type" del type-find,
# legge il MIME type con get_value("caps").get_name(). Ma li' get_value
# ritorna uno StructureWrapper -- un oggetto pensato per essere usato SOLO
# come context manager ("with ... as caps:"), che fuori da un blocco with
# non espone alcun metodo: ogni accesso diretto fallisce con AttributeError.
# Senza questa patch, core.tracklist.add fallisce silenziosamente su
# QUALSIASI stream (ritorna una lista vuota invece del brano aggiunto).
sudo python3 - <<'PYEOF'
path = "/usr/lib/python3/dist-packages/mopidy/audio/scan.py"
old = '                mime = msg.get_structure().get_value("caps").get_name()\n'
new = (
    '                with msg.get_structure().get_value("caps") as _caps_struct:\n'
    '                    mime = _caps_struct.get_name()\n'
)
with open(path) as f:
    content = f.read()
if new not in content:
    assert content.count(old) == 1, "riga attesa non trovata: mopidy si e' aggiornato?"
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
PYEOF

sudo cp mopidy/mopidy.conf /etc/mopidy/mopidy.conf
sudo systemctl enable --now mopidy.service

echo "== Abilita overlay CAN (SOLO Raspberry Pi con HAT SPI, es. MCP2515) =="
echo "   Su mini PC x86_64 salta questa sezione: usa un adattatore USB-CAN"
echo "   (es. PCAN-USB, CANable) che appare direttamente come can0 via"
echo "   gs_usb/socketcan senza bisogno di overlay device-tree."
if [ -f /boot/firmware/config.txt ]; then
  if ! grep -q "dtoverlay=mcp2515" /boot/firmware/config.txt 2>/dev/null; then
    echo "dtparam=spi=on" | sudo tee -a /boot/firmware/config.txt
    echo "dtoverlay=mcp2515-can0,oscillator=16000000,interrupt=25" | sudo tee -a /boot/firmware/config.txt
    echo "Overlay CAN aggiunto. Riavvio necessario."
  fi
fi

echo "== Fatto. Riavvia il sistema prima di procedere: sudo reboot =="
