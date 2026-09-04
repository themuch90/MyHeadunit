# Test dello stack in VM (senza hardware reale)

## Setup rapido

1. Crea una VM Debian 12 / Ubuntu 24.04 x86_64 (consigliato QEMU/KVM via
   `virt-manager`: gestisce meglio il passthrough USB rispetto a VirtualBox
   quando vorrai testare Bluetooth/WiFi reali in seguito)
2. Dentro la VM:

```bash
chmod +x vm-testing/setup-vm-host.sh
./vm-testing/setup-vm-host.sh
sudo reboot
```

3. Avvia lo stack con CAN virtuale invece di hardware:

```bash
docker compose -f docker-compose.yml -f vm-testing/docker-compose.override.yml up -d --build
```

Questo ti dà: Mosquitto, `can-gateway` che legge da `vcan0`, `can-simulator`
che genera RPM/velocità/temperatura/carburante plausibili, `api-gateway`,
`phone-bridge` e `androidauto-bridge` (questi ultimi due partono ma restano
in attesa di hardware BT/WiFi reale finché non fai il passthrough).

4. Verifica il flusso dati:

```bash
docker exec -it mosquitto mosquitto_sub -t 'car/#' -v
```

5. Compila e avvia l'app Flutter dentro la VM (stessa procedura del README
   principale, `flutter build linux --release` + `flutter-pi` sotto Cage) —
   il dashboard mostrerà i valori generati da `can-simulator`.

## Cosa stai validando in questo modo

- L'intera catena Docker → MQTT → WebSocket → Flutter, senza differenze
  rispetto al deploy reale
- La UI, la navigazione a schede, gli aggiornamenti in tempo reale
- La pipeline Xvnc + VNC (puoi avviare `androidauto-bridge` e collegarti al
  suo `127.0.0.1:5901` con un client VNC qualsiasi per vedere se `autoapp`
  disegna correttamente, anche senza una sessione Android Auto reale)

## Cosa NON stai validando (serve hardware reale prima o poi)

- Pairing Bluetooth vero, HFP con telefono reale, audio SCO
- Sessione Android Auto autentica via WiFi Direct
- Timing/latenza reali della pipeline VNC→texture su GPU vera

Quando sarai pronto per questi test, fai il passthrough USB di un dongle
Bluetooth (e, se vuoi validare AA via cavo invece che WiFi Direct, del
telefono stesso) nella VM — vedi le note in fondo a `setup-vm-host.sh`.
