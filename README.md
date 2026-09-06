# Head Unit su Mini PC + Docker + Flutter

## Architettura

```
┌─────────────────────────────────────────────┐
│  Host (Linux x86_64)                         │
│                                               │
│  ┌─────────────┐   Wayland    ┌────────────┐ │
│  │ Cage (kiosk)│──────────────│ App Flutter│ │
│  └─────────────┘              │  (linux,   │ │
│                                │  standard) │ │
│                                └─────┬──────┘ │
│                                      │ WS     │
│  ┌────────────────────────────────  ▼ ─────┐ │
│  │ Docker (network_mode: host)             │ │
│  │  mosquitto ── can-gateway ── api-gateway│ │
│  │              gpsd                       │ │
│  └──────────────────────────────────────────┘│
│         │can0 (SPI/MCP2515)   │ttyUSB0 (GPS) │
└─────────┼──────────────────────┼─────────────┘
      CAN bus veicolo         modulo GPS
```

L'interfaccia grafica è una normale **app Flutter Linux desktop** (target
ufficiale `linux`, `flutter build linux`), lanciata fullscreen come unico
client Wayland sotto Cage: gira **sull'host**, non in Docker, perché ha
bisogno di accesso diretto al compositor Wayland e containerizzarla non
porta benefici per un singolo processo dedicato. I servizi headless (MQTT, lettura
CAN, GPS, API) sono invece in Docker: si aggiornano e si isolano facilmente.

## 1. Setup dell'host (una tantum)

```bash
chmod +x setup-host.sh
./setup-host.sh
sudo reboot
```

Questo installa Docker, Cage e le dipendenze per compilare l'app Flutter
Linux desktop (`clang`, `cmake`, `ninja-build`, `libgtk-3-dev`...). Per il
bus CAN il target principale è un
adattatore USB-CAN (es. PCAN-USB, CANable), che appare come `can0` senza
bisogno di overlay; lo script include anche, come opzione, l'overlay del
modulo CAN via SPI (MCP2515 — **adatta al tuo hardware CAN**, es. Waveshare
RS485 CAN HAT o simili) per chi usa invece una scheda con HAT dedicato.

## 2. Servizi backend Docker

```bash
cd MyHeadunit
docker compose build
docker compose up -d
docker compose logs -f can-gateway   # verifica che legga frame dal bus
```

Verifica rapida MQTT:
```bash
docker exec -it mosquitto mosquitto_sub -t 'car/#' -v
```

## 3. App Flutter

```bash
cd flutter_app_stub
flutter pub get
flutter build linux --release
```

Produce un bundle Linux desktop standard e autocontenuto in
`build/linux/x64/release/bundle/` (l'eseguibile `headunit_app` più le sue
librerie e `data/`, incluso l'engine Flutter): nessun embedder custom da
compilare o versionare a parte, l'app si lancia direttamente.

Copia il bundle sul target:
```bash
scp -r build/linux/x64/release/bundle headunit@<ip-host>:/opt/headunit/app/bundle
```

## 4. Avvio automatico al boot

```bash
sudo cp systemd/headunit-docker.service /etc/systemd/system/
sudo cp systemd/headunit-ui.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now headunit-docker.service
sudo systemctl enable --now headunit-ui.service
```

## 5. Gestione chiamate (Bluetooth HFP + rubrica PBAP)

Il telefono si accoppia via Bluetooth con il Pi, che agisce da dispositivo
"vivavoce" (Hands-Free). Stack usato:

- **BlueZ** — pairing e trasporto Bluetooth
- **oFono** — ruolo HFP Hands-Free: stato chiamate, comporre, rispondere, DTMF
- **obexd (BlueZ)** — PBAP per scaricare la rubrica dal telefono

### Cosa è containerizzato e cosa no

`bluetoothd`, `ofonod` e `obexd` sono **demoni di sistema** legati al kernel e
all'hardware Bluetooth: restano gestiti da systemd sull'host, come qualunque
altro componente del sistema operativo (non sono servizi applicativi).

La **logica applicativa** che li orchestra (`phone-bridge/bridge.py` — agent
di pairing, gestione chiamate, sync rubrica, ponte verso MQTT) gira invece in
Docker come gli altri servizi. Il container monta il socket D-Bus dell'host
(`/var/run/dbus`) per parlare con quei demoni.

Questo ti dà comunque i benefici che contano per l'applicazione: immagine
versionata e riproducibile, `docker compose pull && docker compose up -d` per
aggiornare senza toccare l'host, rollback immediato a un tag precedente,
stesso comportamento su Pi diversi. Non ottieni invece isolamento di
rete/filesystem da bluetoothd — il container ha comunque accesso al bus D-Bus
di sistema, che è la superficie minima necessaria per controllare Bluetooth.

### Pairing (dalla UI Flutter, non serve terminale)

Il bridge registra un **Agent BlueZ** con capability `DisplayYesNo`: la scansione,
il pairing e la conferma del passkey avvengono tutti dalla schermata Bluetooth
dell'app.

1. Apri la scheda **Bluetooth** nell'app → "Cerca dispositivi"
2. Tocca il telefono nella lista → parte il pairing
3. Appare un dialogo con un codice a 6 cifre: verifica che sia identico a
   quello mostrato sul telefono, poi conferma su entrambi
4. Una volta abbinato, il bridge imposta `Trusted` e avvia la connessione
   automaticamente; la rubrica si può sincronizzare dalla scheda Rubrica

Il pairing manuale via `bluetoothctl` resta comunque disponibile come fallback
per debug, ma non è più necessario in condizioni normali.

### Configurazione ed avvio

Il bridge è ora un servizio Docker Compose come gli altri (vedi `compose.yaml`):

```bash
docker compose build phone-bridge
docker compose up -d phone-bridge
docker compose logs -f phone-bridge
```

Aggiornamenti successivi (dopo modifiche a `bridge.py` o `requirements.txt`):
```bash
docker compose build phone-bridge && docker compose up -d phone-bridge
```

Verifica su MQTT:
```bash
docker exec -it mosquitto mosquitto_sub -t 'car/phone/#' -v
```

### Topic MQTT esposti

| Topic | Direzione | Contenuto |
|---|---|---|
| `car/bluetooth/devices` | bridge → app | dispositivi noti/trovati (JSON) |
| `car/bluetooth/pairing/request` | bridge → app | `{device, passkey}` da confermare |
| `car/bluetooth/pairing/state` | bridge → app | `idle \| pairing \| paired \| failed` |
| `car/bluetooth/cmd/scan_start` | app → bridge | avvia scansione |
| `car/bluetooth/cmd/scan_stop` | app → bridge | ferma scansione |
| `car/bluetooth/cmd/pair` | app → bridge | `{"mac": "..."}` |
| `car/bluetooth/cmd/remove` | app → bridge | `{"mac": "..."}` rimuove abbinamento |
| `car/bluetooth/cmd/confirm` | app → bridge | `{"accept": true\|false}` risposta al passkey |
| `car/phone/state` | bridge → app | connessione telefono |
| `car/phone/call/incoming` | bridge → app | `{number, name}` |
| `car/phone/call/state` | bridge → app | `idle \| ringing \| dialing \| active` |
| `car/phone/contacts` | bridge → app | rubrica sincronizzata via PBAP |
| `car/phone/cmd/dial` | app → bridge | `{"number": "..."}` |
| `car/phone/cmd/answer` | app → bridge | — |
| `car/phone/cmd/hangup` | app → bridge | — |
| `car/phone/cmd/dtmf` | app → bridge | `{"digit": "5"}` |
| `car/phone/cmd/sync_contacts` | app → bridge | forza ri-sync rubrica |

### Nell'app Flutter

- `lib/services/bluetooth_service.dart` — scansione, pairing, conferma passkey
- `lib/services/phone_service.dart` — wrapper sul WebSocket condiviso, espone
  stream (`callState`, `incomingCall`, `contacts`) e comandi (`dial`, `answer`, ecc.)
- `lib/screens/bluetooth_pairing_screen.dart` — lista dispositivi, pairing, dialogo passkey
- `lib/screens/dialpad_screen.dart` — tastiera numerica
- `lib/screens/contacts_screen.dart` — rubrica con ricerca e chiamata rapida
- `lib/screens/call_screen.dart` — overlay chiamata in arrivo + schermata chiamata attiva (muto, tastiera DTMF)
- `lib/main.dart` — naviga a schede (Cruscotto / Tastiera / Rubrica / Bluetooth) e apre
  l'overlay chiamata in arrivo sopra qualunque schermata

### Limiti noti da adattare

- `RequestAuthorization` (pairing "Just Works", usato da alcuni telefoni senza
  passkey) autorizza automaticamente lato bridge: se vuoi farlo confermare
  comunque dall'utente, va instradato verso la UI come `RequestConfirmation`.
- Il "muto" nella UI è solo visuale: va collegato al sink audio reale
  (PipeWire/PulseAudio sul canale SCO), oFono non espone un comando muto diretto.
- `PullAll` scarica l'intera rubrica in un colpo: per rubriche molto grandi
  valuta paginazione con `List`/`Search` PBAP.
- Il path dell'adattatore Bluetooth (`/org/bluez/hci0`) è hardcoded: se il Pi
  ha più adattatori o un nome diverso, va reso configurabile.

## 6. Android Auto (cablato via USB/AOAP, video via GStreamer)

### Perché cablato invece che WiFi Direct

Il WiFi Direct per Android Auto wireless è la parte più fragile dello stack:
negoziazione Group Owner, dipendenza dal supporto P2P del driver WiFi,
compatibilità telefono-per-telefono incerta anche nelle implementazioni
"ufficiali". L'**USB/AOAP (Android Open Accessory Protocol)** è la via
originale e più matura di Android Auto: il telefono si collega via cavo, il
sistema lo rileva e lo commuta in modalità "accessory", la sessione parte su
quel canale USB. Zero negoziazione wireless.

**Conseguenza sull'hardware**: non serve una seconda scheda Bluetooth
dedicata né `wpa_supplicant` in modalità P2P.

### Stato attuale: da adattare al passaggio a Flutter Linux standard

Questo progetto è passato da un embedder custom (flutter-pi) a una normale
app **Flutter Linux desktop** (vedi sezione 3). Il pacchetto ufficiale
`video_player` di Google **non ha un'implementazione per Linux** (solo
Android/iOS/web/macOS): `androidauto_texture_view.dart` così com'è, basato
su `VideoPlayerController`, non riceve alcun video finché non si sceglie un
plugin video Linux-compatibile e si adatta il widget di conseguenza.
Candidato più maturo: `media_kit` + `media_kit_video` (supporto Linux
attivamente mantenuto, via libmpv).

### Architettura

```
Container androidauto-bridge (nessuna GPU, nessun /dev/dri)
  Xvfb :1 (X server virtuale)  ←── autoapp (Qt/xcb) disegna qui
       │
       ▼ GStreamer: ximagesrc → rtpvrawpay → gdppay → tcpserversink :5000
       │  (video GREZZO, nessuna codifica H.264: loopback, comprimere
       │   aggiungerebbe solo latenza senza risparmiare banda che qui è
       │   comunque gratis)
Host: Cage (mono-client)
  App Flutter Linux desktop
    plugin video Linux-compatibile (da scegliere, vedi sopra) → widget texture
```

### Cosa è containerizzato e cosa no

| Resta sull'host | Va in Docker |
|---|---|
| **Cage** (compositor) — accesso diretto a DRM/KMS | **`Xvfb` + `autoapp` + pipeline GStreamer di cattura** — nessuna GPU richiesta |
| **App Flutter Linux desktop** — riceve lo stream e lo mostra in un widget texture | Logica di avvio/stop, wrappata da `launcher.py` |
| **regole udev** per i permessi USB del telefono | Rilevamento/gestione del device USB tramite `libusb` dentro aasdk |

### Setup

```bash
./setup-host.sh   # installa Cage, le dipendenze di build Flutter, regole udev USB

sudo cp systemd/headunit-ui.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now headunit-ui.service

docker compose build androidauto-bridge
docker compose up -d androidauto-bridge
```

Collega il telefono via cavo USB, poi avvia la sessione dal dashboard (tile
"Android Auto" → Avvia) -- una volta scelto e integrato un plugin video
Linux-compatibile (vedi sopra).

### Topic MQTT

| Topic | Direzione | Contenuto |
|---|---|---|
| `car/androidauto/state` | bridge → app | `stopped \| starting \| active \| error` |
| `car/androidauto/cmd/start` | app → bridge | avvia sessione |
| `car/androidauto/cmd/stop` | app → bridge | ferma sessione |

### Nell'app Flutter

- `pubspec.yaml` — dipendenza `video_player` (pacchetto ufficiale Google,
  **da sostituire**: nessuna implementazione Linux, vedi sopra)
- `lib/widgets/androidauto_texture_view.dart` — `VideoPlayerController`
  puntato alla pipeline GStreamer del container (**non funzionante** finché
  non si integra un plugin video Linux-compatibile)
- `lib/services/androidauto_service.dart` — avvio/stop/stato via MQTT

### Limiti noti da adattare

- **Video non funzionante**: vedi "Stato attuale" sopra -- serve scegliere
  e integrare un plugin video con supporto Linux prima di poter verificare
  il resto della pipeline.
- La pipeline GStreamer lato container (`rtpvrawpay`/`gdppay`) e quella
  lato client (`rtpvrawdepay`/`gdpdepay`) devono restare in sincrono.
- Il flag `--usb` di `autoapp` è indicativo: verifica `autoapp --help`
  nell'immagine costruita.
- Il Dockerfile clona aasdk/OpenAuto dai repo della community
  (`opencardev/aasdk`, `opencardev/openauto`): verifica l'ultima release.
- `cap_add: SYS_ADMIN` serve per lo switch AOAP via `libusb`; se vuoi
  restringerlo, valuta `--device-cgroup-rule` sul VID/PID specifico del tuo
  telefono invece del generico `/dev/bus/usb`.
## 7. Testare tutto in VM prima dell'hardware definitivo

Puoi validare l'intero stack software (Docker, MQTT, Flutter, pipeline VNC)
in una VM, senza hardware reale — vedi `vm-testing/README.md`. Bluetooth e
WiFi Direct reali restano fuori portata senza passthrough USB di periferiche
fisiche, ma tutto il resto è testabile identico al deploy finale.

## Note importanti

- **Hardware CAN**: questo esempio assume un HAT MCP2515 su SPI. Se usi un
  adattatore USB-CAN, cambia `network_mode` e `devices` di conseguenza e rimuovi
  l'overlay dtoverlay dal boot config.
- **Decodifica segnali reale**: `gateway.py` ha una mappa segnali giocattolo.
  Per un veicolo reale usa un file `.dbc` con la libreria `cantools` per
  decodificare correttamente i frame.
- **Sicurezza**: Mosquitto qui è configurato con `allow_anonymous true` per
  semplicità di sviluppo. In produzione attiva autenticazione/TLS.
- **Alternative a Cage**: se in futuro serve multi-finestra (es. Android Auto
  proiettato + UI nativa), valuta Weston invece di Cage.
- **Versioni**: le immagini sono fissate a versioni specifiche
  (`eclipse-mosquitto:2.1.2-alpine`, `python:3.14-slim`, `debian:trixie-slim`,
  `node:24-alpine`) invece di tag mobili come `latest`; `gpsd` resta
  disabilitato per ora (vedi `compose.yaml`) e va ripinnato a un tag preciso
  quando lo riattivi. Ricontrolla periodicamente gli aggiornamenti a monte.
