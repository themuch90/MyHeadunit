# Head Unit su Mini PC + Docker + Flutter

## Architettura

```
┌─────────────────────────────────────────────┐
│  Host (Linux x86_64)                         │
│                                               │
│  ┌─────────────┐   Wayland    ┌────────────┐ │
│  │ Cage (kiosk)│──────────────│ flutter-pi │ │
│  └─────────────┘              └─────┬──────┘ │
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

L'interfaccia grafica (flutter-pi) gira **sull'host**, non in Docker: ha bisogno
di accesso diretto a `/dev/dri` e al compositor Wayland, e containerizzarla non
porta benefici per un singolo processo dedicato. I servizi headless (MQTT, lettura
CAN, GPS, API) sono invece in Docker: si aggiornano e si isolano facilmente.

## 1. Setup dell'host (una tantum)

```bash
chmod +x setup-host.sh
./setup-host.sh
sudo reboot
```

Questo installa Docker, Cage, le dipendenze di build per flutter-pi e compila
flutter-pi in `/usr/local/bin`. Per il bus CAN il target principale è un
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
flutter build linux --release   # produce l'asset bundle per flutter-pi
```

flutter-pi non usa l'eseguibile Linux desktop generato: usa la cartella
`build/flutter_assets` insieme al runtime engine. Verifica il percorso esatto
richiesto dalla versione di flutter-pi che hai compilato (vedi
https://github.com/ardera/flutter-pi per dettagli aggiornati, il progetto è
attivamente mantenuto e la sintassi CLI può evolvere).

Copia il bundle sul target:
```bash
scp -r build/flutter_assets headunit@<ip-host>:/opt/headunit/app/build/
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

## 6. Android Auto (cablato via USB/AOAP, video via GStreamer integrato in flutter-pi)

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

### Perché il video player GStreamer integrato invece di codice custom

Sono state esplorate due strade più complesse prima di arrivare a questa:

1. Scrivere un plugin nativo che registra una texture GL a mano tramite
   `texture_registry.h` di flutter-pi — funziona in linea di principio ma
   introduce codice C custom da mantenere e un punto irrisolto (come un
   plugin ottiene il puntatore al registry al proprio init).
2. Un pacchetto pub.dev di terze parti (`flutterpi_gstreamer_video_player`)
   — scartato perché immaturo (pochi download, nessuna piattaforma
   dichiarata support nell'analisi automatica di pub.dev).

La via scelta qui è quella **confermata dal README ufficiale di
[ardera/flutter-pi](https://github.com/ardera/flutter-pi)**: il supporto
GStreamer è integrato nel motore stesso, si abilita a compile-time con
un'opzione CMake, e poi — testuale dal README — *"non c'è nulla di
specifico da fare lato Dart"*: si usa il pacchetto ufficiale `video_player`
di Google così com'è.

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
  flutter-pi (ricompilato con BUILD_GSTREAMER_VIDEO_PLAYER_PLUGIN=ON)
    pacchetto ufficiale video_player → VideoPlayerController
```

### Cosa è containerizzato e cosa no

| Resta sull'host | Va in Docker |
|---|---|
| **Cage** (compositor) — accesso diretto a DRM/KMS | **`Xvfb` + `autoapp` + pipeline GStreamer di cattura** — nessuna GPU richiesta |
| **flutter-pi ricompilato** con supporto GStreamer — parte del motore, non un plugin separato | Logica di avvio/stop, wrappata da `launcher.py` |
| **regole udev** per i permessi USB del telefono | Rilevamento/gestione del device USB tramite `libusb` dentro aasdk |

### Setup

```bash
./setup-host.sh   # ricompila flutter-pi con GStreamer, installa Cage, regole udev USB

sudo cp systemd/headunit-ui.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now headunit-ui.service

docker compose build androidauto-bridge
docker compose up -d androidauto-bridge
```

Nell'app Flutter la dipendenza è il pacchetto ufficiale `video_player` (già
in `pubspec.yaml` di questo progetto), nessun pacchetto esotico. Collega il
telefono via cavo USB, poi avvia la sessione dal dashboard (tile "Android
Auto" → Avvia).

### Topic MQTT

| Topic | Direzione | Contenuto |
|---|---|---|
| `car/androidauto/state` | bridge → app | `stopped \| starting \| active \| error` |
| `car/androidauto/cmd/start` | app → bridge | avvia sessione |
| `car/androidauto/cmd/stop` | app → bridge | ferma sessione |

### Nell'app Flutter

- `pubspec.yaml` — dipendenza `video_player` (pacchetto ufficiale Google)
- `lib/widgets/androidauto_texture_view.dart` — `VideoPlayerController`
  puntato alla pipeline GStreamer del container
- `lib/services/androidauto_service.dart` — avvio/stop/stato via MQTT

### Limiti noti da adattare

- Il modo esatto in cui passare una pipeline GStreamer raw (invece di un
  URL http/file normale) a `VideoPlayerController` non è stato verificato
  parola per parola oltre la conferma del README ufficiale; se
  l'implementazione di flutter-pi si aspetta un prefisso URI specifico
  invece della stringa diretta, è un aggiustamento minore da fare guardando
  gli esempi nel repo clonato, non un cambio di architettura.
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
  (`eclipse-mosquitto:2.1.2`, `python:3.14-slim`, `debian:trixie-slim`,
  `node:24-alpine`) invece di tag mobili come `latest`; `gpsd` resta
  disabilitato per ora (vedi `compose.yaml`) e va ripinnato a un tag preciso
  quando lo riattivi. Ricontrolla periodicamente gli aggiornamenti a monte.
