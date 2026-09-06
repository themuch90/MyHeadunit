#!/bin/bash
# Setup DENTRO la VM (Debian/Ubuntu x86_64) per testare lo stack head unit
# senza hardware reale. Copre CAN virtuale, Docker, e le note su cosa
# richiede passthrough dall'hypervisor (Bluetooth, WiFi, GPU).
set -e

echo "== Aggiornamento sistema =="
sudo apt-get update && sudo apt-get upgrade -y

echo "== Docker =="
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
sudo apt-get install -y docker-compose-plugin

echo "== CAN virtuale (vcan) - nessun hardware richiesto =="
sudo modprobe vcan
if ! ip link show vcan0 > /dev/null 2>&1; then
  sudo ip link add dev vcan0 type vcan
  sudo ip link set up vcan0
fi
# Rendilo persistente al riavvio della VM:
echo "vcan" | sudo tee -a /etc/modules > /dev/null
cat << 'EOF' | sudo tee /etc/systemd/network/vcan0.netdev > /dev/null
[NetDev]
Name=vcan0
Kind=vcan
EOF
echo "vcan0 creata e attiva. Verifica con: ip link show vcan0"

echo "== Cage/app Flutter Linux desktop: dipendenze (funzionano anche su GPU virtuale/llvmpipe) =="
sudo apt-get install -y \
    cage \
    clang \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    liblzma-dev \
    mesa-utils

echo "== libvncclient per il plugin texture Android Auto =="
sudo apt-get install -y libvncclient-dev

echo ""
echo "=================================================================="
echo "NOTE IMPORTANTI - cosa questa VM NON puo' simulare via software:"
echo ""
echo "1. Bluetooth reale (pairing, HFP, PBAP con un telefono vero):"
echo "   serve passthrough USB di un vero dongle BT dall'hypervisor."
echo "   - virt-manager/QEMU: Dettagli VM -> Aggiungi hardware -> USB Host"
echo "     Device, seleziona il dongle. Oppure CLI:"
echo "     virsh attach-device <vm> usb-device.xml"
echo "   - VirtualBox: Impostazioni -> USB -> aggiungi filtro per il dongle"
echo "   Per test PURAMENTE software del codice D-Bus/agent (senza audio"
echo "   ne' telefono vero), BlueZ include 'btvirt' che crea controller"
echo "   Bluetooth virtuali via vhci: utile solo per validare pairing/"
echo "   D-Bus a basso livello, non per HFP/PBAP funzionanti con un telefono."
echo ""
echo "2. WiFi Direct reale (sessione video Android Auto autentica):"
echo "   serve passthrough di un adattatore WiFi USB con supporto P2P."
echo "   Alternativa piu' semplice per validare SOLO la pipeline video"
echo "   (Xvnc -> VNC -> texture Flutter) senza WiFi Direct: usa Android"
echo "   Auto via USB (autoapp lo supporta) passando il telefono stesso"
echo "   come USB device alla VM -- valida tutto tranne l'handshake BT/WiFi."
echo ""
echo "3. GPU: se la VM ha solo rendering software (llvmpipe), Flutter"
echo "   funziona ma con framerate piu' basso. Per test seri di fluidita'"
echo "   dell'interfaccia, valuta virtio-gpu con accelerazione 3D (QEMU"
echo "   con -device virtio-vga-gl e Spice/GTK display, oppure VirtIO-GPU"
echo "   Venus su host con GPU Vulkan) prima di scartare risultati di lag."
echo "=================================================================="
