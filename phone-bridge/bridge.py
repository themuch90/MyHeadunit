"""
Phone bridge per la head unit.

Ruolo: l'host si comporta da dispositivo "vivavoce" (HFP Hands-Free)
verso lo smartphone accoppiato via Bluetooth. Usa:
  - BlueZ (org.bluez.*)   -> scansione, pairing, trust, connessione
  - oFono (org.ofono.*)   -> stato chiamate, comporre/rispondere/chiudere, DTMF
  - BlueZ obexd (PBAP)    -> scarica la rubrica del telefono accoppiato

Questo script gira SULL'HOST (non in Docker) perche' ha bisogno di accesso
diretto al bus D-Bus di sistema dove vivono bluetoothd, ofonod e obexd.

Pubblica su MQTT:
  car/bluetooth/devices      lista dispositivi trovati/noti (JSON)
  car/bluetooth/pairing/request   passkey/pin da confermare in UI
  car/bluetooth/pairing/state     idle | pairing | paired | failed
  car/phone/state             connesso/scollegato, nome device
  car/phone/call/incoming     {number, name}
  car/phone/call/state        idle | ringing | active | dialing
  car/phone/contacts          lista contatti (JSON), pubblicata dopo la sync PBAP

Si sottoscrive a:
  car/bluetooth/cmd/make_discoverable   rende la head unit visibile/associabile
                                        dal telefono (es. bottone "Associa
                                        nuovo telefono" nell'app)
  car/bluetooth/cmd/scan_start
  car/bluetooth/cmd/scan_stop
  car/bluetooth/cmd/pair          {"mac": "AA:BB:CC:DD:EE:FF"}
  car/bluetooth/cmd/remove        {"mac": "AA:BB:CC:DD:EE:FF"}
  car/bluetooth/cmd/confirm       {"accept": true}   risposta a pairing/request
  car/phone/cmd/dial              {"number": "+391234567"}
  car/phone/cmd/answer
  car/phone/cmd/hangup
  car/phone/cmd/dtmf              {"digit": "5"}
  car/phone/cmd/sync_contacts
"""

import json
import logging
import os

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib
import paho.mqtt.client as mqtt

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("phone-bridge")

MQTT_HOST = os.getenv("MQTT_HOST", "127.0.0.1")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
TOPIC_BASE = "car/phone"
BT_TOPIC_BASE = "car/bluetooth"
AGENT_PATH = "/headunit/agent"
ADAPTER_PATH = "/org/bluez/hci0"  # adatta se il tuo adattatore ha un path diverso
ADAPTER_ALIAS = os.getenv("ADAPTER_ALIAS", "Autoradio Smart")
# obexd (PBAP/rubrica) vive solo sul bus di SESSIONE D-Bus, mai su quello
# di sistema -- su un host headless senza sessione desktop attiva questo
# bus non esiste di default, quindi setup-host.sh ne crea uno dedicato e
# persistente apposta per lui (vedi dbus-session-obex.service).
OBEX_SESSION_BUS_ADDRESS = os.getenv(
    "OBEX_SESSION_BUS_ADDRESS", "unix:path=/run/dbus-session-obex/bus"
)

dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SystemBus()
_obex_bus = None


def get_obex_bus():
    # Connessione creata al primo utilizzo (non all'avvio): se il socket
    # del bus di sessione dedicato a obexd non fosse ancora pronto, non
    # deve far crashare l'intero bridge, solo la sync rubrica che lo usa.
    global _obex_bus
    if _obex_bus is None:
        _obex_bus = dbus.bus.BusConnection(OBEX_SESSION_BUS_ADDRESS)
    return _obex_bus

mqttc = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="phone-bridge")


def publish(sub_topic, payload, base=TOPIC_BASE):
    topic = f"{base}/{sub_topic}"
    mqttc.publish(topic, json.dumps(payload) if not isinstance(payload, str) else payload)
    log.info("MQTT -> %s: %s", topic, payload)


# --- BlueZ: scansione e pairing ----------------------------------------------

_known_devices = {}  # mac -> dict(name, rssi, paired, connected)
_pending_confirmation = {}  # tiene il callback in attesa della risposta UI


class PairingAgent(dbus.service.Object):
    """
    Agent BlueZ con capability 'DisplayYesNo': mostra un passkey che l'utente
    deve confermare sia sul telefono che sulla head unit (via UI Flutter).
    Le chiamate D-Bus sono asincrone (async_callbacks) perche' BlueZ resta in
    attesa della risposta finche' l'utente non conferma dall'app.
    """

    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Release(self):
        log.info("Agent rilasciato da BlueZ")

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="",
                          async_callbacks=("reply", "error"))
    def RequestConfirmation(self, device, passkey, reply, error):
        log.info("Richiesta conferma pairing: %s passkey=%06d", device, passkey)
        publish("pairing/request", {"device": str(device), "passkey": f"{passkey:06d}"},
                base=BT_TOPIC_BASE)
        publish("pairing/state", "pairing", base=BT_TOPIC_BASE)
        _pending_confirmation["callback"] = (reply, error)

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="")
    def RequestAuthorization(self, device):
        # Alcuni telefoni usano "Just Works" invece del passkey: qui si
        # autorizza direttamente. Per maggiore sicurezza puoi far passare
        # anche questo dalla UI come per RequestConfirmation.
        log.info("Autorizzazione pairing 'Just Works' per %s", device)
        return

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
    def AuthorizeService(self, device, uuid):
        # BlueZ chiama questo ogni volta che il telefono prova a connettere
        # un profilo (es. HFP Hands-Free, A2DP) verso un device gia'
        # accoppiato: senza un'implementazione, bluetoothd riceve
        # "UnknownMethod" e rifiuta la connessione del servizio, causando
        # un ciclo di connessione/disconnessione continuo lato telefono
        # (il device resta "paired" ma non riesce mai a restare connesso).
        log.info("Autorizzazione servizio %s per %s", uuid, device)
        return

    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Cancel(self):
        log.info("Pairing annullato da BlueZ")
        publish("pairing/state", "failed", base=BT_TOPIC_BASE)


def register_agent():
    agent = PairingAgent(bus, AGENT_PATH)
    manager = dbus.Interface(
        bus.get_object("org.bluez", "/org/bluez"), "org.bluez.AgentManager1"
    )
    manager.RegisterAgent(AGENT_PATH, "DisplayYesNo")
    manager.RequestDefaultAgent(AGENT_PATH)
    log.info("Agent di pairing registrato")


def confirm_pairing(accept: bool):
    pending = _pending_confirmation.pop("callback", None)
    if not pending:
        log.warning("Nessuna richiesta di pairing in sospeso")
        return
    reply, error = pending
    if accept:
        reply()
        publish("pairing/state", "paired", base=BT_TOPIC_BASE)
    else:
        error(dbus.DBusException("org.bluez.Error.Rejected: Rifiutato dall'utente"))
        publish("pairing/state", "failed", base=BT_TOPIC_BASE)


def _publish_devices():
    publish("devices", list(_known_devices.values()), base=BT_TOPIC_BASE)


def on_interfaces_added(path, interfaces):
    props = interfaces.get("org.bluez.Device1")
    if not props:
        return
    mac = str(props.get("Address", ""))
    _known_devices[mac] = {
        "mac": mac,
        "name": str(props.get("Name", "Dispositivo sconosciuto")),
        "rssi": int(props.get("RSSI", 0)) if props.get("RSSI") is not None else None,
        "paired": bool(props.get("Paired", False)),
        "connected": bool(props.get("Connected", False)),
    }
    _publish_devices()


def on_properties_changed(interface, changed, invalidated, path=None):
    if interface != "org.bluez.Device1" or not path:
        return
    # path tipico: /org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF
    mac = path.split("dev_")[-1].replace("_", ":")
    entry = _known_devices.get(mac)
    if not entry:
        return
    if "Paired" in changed:
        entry["paired"] = bool(changed["Paired"])
    if "Connected" in changed:
        entry["connected"] = bool(changed["Connected"])
    if "RSSI" in changed:
        entry["rssi"] = int(changed["RSSI"])
    _publish_devices()


def get_adapter():
    return dbus.Interface(bus.get_object("org.bluez", ADAPTER_PATH), "org.bluez.Adapter1")


def get_adapter_props():
    return dbus.Interface(bus.get_object("org.bluez", ADAPTER_PATH), "org.freedesktop.DBus.Properties")


def make_discoverable():
    """
    Rende la head unit visibile e associabile dal telefono, come un
    normale speaker/auricolare BT: senza questo, l'adattatore resta
    "nascosto" e solo la head unit puo' trovare il telefono (via
    StartDiscovery), mai il contrario. Timeout=0 disabilita lo scadere
    automatico: la head unit resta sempre visibile, comportamento comune
    per dispositivi fissi come un'autoradio (a differenza di un telefono,
    che si rende visibile solo per una finestra di tempo limitata).
    """
    # variant_level=1 e' necessario perche' Properties.Set ha firma "ssv":
    # senza incapsulare esplicitamente il valore come Variant, dbus-python
    # a volte lo marshalla come tipo semplice (es. "sss" invece di "ssv")
    # a seconda che l'introspezione dell'interfaccia sia gia' in cache,
    # causando un errore intermittente "Method Set ... doesn't exist".
    props = get_adapter_props()
    props.Set("org.bluez.Adapter1", "Alias", dbus.String(ADAPTER_ALIAS, variant_level=1))
    props.Set("org.bluez.Adapter1", "DiscoverableTimeout", dbus.UInt32(0, variant_level=1))
    props.Set("org.bluez.Adapter1", "PairableTimeout", dbus.UInt32(0, variant_level=1))
    props.Set("org.bluez.Adapter1", "Discoverable", dbus.Boolean(True, variant_level=1))
    props.Set("org.bluez.Adapter1", "Pairable", dbus.Boolean(True, variant_level=1))
    log.info("Adattatore Bluetooth visibile come '%s' (discoverable+pairable, senza timeout)",
              ADAPTER_ALIAS)
    publish("discoverable", True, base=BT_TOPIC_BASE)


def start_scan():
    get_adapter().StartDiscovery()
    publish("pairing/state", "idle", base=BT_TOPIC_BASE)


def stop_scan():
    get_adapter().StopDiscovery()


def pair_device(mac: str):
    device_path = f"{ADAPTER_PATH}/dev_{mac.replace(':', '_')}"
    device = dbus.Interface(bus.get_object("org.bluez", device_path), "org.bluez.Device1")
    publish("pairing/state", "pairing", base=BT_TOPIC_BASE)

    def on_pair_done():
        log.info("Pairing completato con %s", mac)
        device.Trust() if hasattr(device, "Trust") else None
        dbus.Interface(device, "org.bluez.Device1").Set  # noop, per chiarezza
        _pair_trust_connect(device_path)
        publish("pairing/state", "paired", base=BT_TOPIC_BASE)

    def on_pair_error(err):
        log.error("Pairing fallito con %s: %s", mac, err)
        publish("pairing/state", "failed", base=BT_TOPIC_BASE)

    device.Pair(reply_handler=on_pair_done, error_handler=on_pair_error,
                dbus_interface="org.bluez.Device1")


def _pair_trust_connect(device_path):
    props = dbus.Interface(
        bus.get_object("org.bluez", device_path), "org.freedesktop.DBus.Properties"
    )
    props.Set("org.bluez.Device1", "Trusted", True)
    device = dbus.Interface(bus.get_object("org.bluez", device_path), "org.bluez.Device1")
    device.Connect(reply_handler=lambda: log.info("Connesso a %s", device_path),
                    error_handler=lambda e: log.error("Connessione fallita: %s", e))


def remove_device(mac: str):
    adapter_obj_path = ADAPTER_PATH
    device_path = f"{ADAPTER_PATH}/dev_{mac.replace(':', '_')}"
    get_adapter().RemoveDevice(device_path)
    _known_devices.pop(mac, None)
    _publish_devices()


def load_known_devices():
    """
    Popola _known_devices con lo stato ATTUALE all'avvio del bridge (es.
    dopo un restart del container mentre il telefono e' gia' accoppiato e
    connesso): senza questo, il bridge non sa nulla dei device finche' non
    arriva un futuro segnale InterfacesAdded/PropertiesChanged, quindi sia
    la UI (lista Bluetooth vuota) sia sync_contacts ("nessun telefono
    connesso") si comportano come se non ci fosse alcun dispositivo,
    anche quando in realta' e' gia' connesso a livello BlueZ.
    """
    manager = dbus.Interface(
        bus.get_object("org.bluez", "/"), "org.freedesktop.DBus.ObjectManager"
    )
    for path, interfaces in manager.GetManagedObjects().items():
        on_interfaces_added(path, interfaces)


def watch_bluez_signals():
    bus.add_signal_receiver(
        on_interfaces_added,
        dbus_interface="org.freedesktop.DBus.ObjectManager",
        signal_name="InterfacesAdded",
    )
    bus.add_signal_receiver(
        on_properties_changed,
        dbus_interface="org.freedesktop.DBus.Properties",
        signal_name="PropertiesChanged",
        path_keyword="path",
    )


# --- oFono: gestione chiamate ------------------------------------------------

def get_ofono_modem():
    """Trova il modem oFono che rappresenta il telefono accoppiato via HFP."""
    manager = dbus.Interface(
        bus.get_object("org.ofono", "/"), "org.ofono.Manager"
    )
    modems = manager.GetModems()
    for path, props in modems:
        if props.get("Powered") and "org.ofono.VoiceCallManager" in _modem_interfaces(path):
            return path
    return None


def _modem_interfaces(path):
    # In un modem HFP reale le interfacce disponibili dipendono dalle Features
    # esposte dal telefono; qui si assume VoiceCallManager sempre presente
    # quando il modem e' online.
    return ["org.ofono.VoiceCallManager"]


def call_manager():
    modem_path = get_ofono_modem()
    if not modem_path:
        raise RuntimeError("Nessun modem oFono/HFP disponibile: telefono non accoppiato?")
    obj = bus.get_object("org.ofono", modem_path)
    return dbus.Interface(obj, "org.ofono.VoiceCallManager")


def on_call_added(path, properties):
    state = str(properties.get("State", "unknown"))
    number = str(properties.get("LineIdentification", ""))
    name = str(properties.get("Name", ""))

    if state == "incoming":
        publish("call/incoming", {"number": number, "name": name})
        publish("call/state", "ringing")
    elif state == "active":
        publish("call/state", "active")
    elif state == "dialing" or state == "alerting":
        publish("call/state", "dialing")


def on_call_removed(path):
    publish("call/state", "idle")


def dial(number: str):
    call_manager().Dial(number, "")


def answer():
    calls = call_manager().GetCalls()
    for path, _props in calls:
        dbus.Interface(
            bus.get_object("org.ofono", path), "org.ofono.VoiceCall"
        ).Answer()


def hangup():
    call_manager().HangupAll()


def send_dtmf(digit: str):
    call_manager().SendTones(digit)


# --- BlueZ obexd: sync rubrica via PBAP --------------------------------------

def sync_contacts():
    """
    Avvia una sessione PBAP verso il telefono attualmente connesso e scarica
    la rubrica. Richiede che il pairing/trust sia gia' avvenuto (vedi UI di
    pairing) e che il telefono abbia concesso l'accesso al Phone Book Access
    Profile durante l'abbinamento.
    """
    try:
        device_mac = _first_connected_device_mac()
        if not device_mac:
            log.warning("Nessun telefono connesso, salto sync rubrica")
            publish("error", {"cmd": "sync_contacts", "message": "Nessun telefono connesso"})
            return

        obex_bus = get_obex_bus()
        client = dbus.Interface(
            obex_bus.get_object("org.bluez.obex", "/org/bluez/obex"),
            "org.bluez.obex.Client1",
        )
        session_path = client.CreateSession(
            device_mac, {"Target": "PBAP"}
        )
        pbap = dbus.Interface(
            obex_bus.get_object("org.bluez.obex", session_path),
            "org.bluez.obex.PhonebookAccess1",
        )
        pbap.Select("int", "pb")  # rubrica del telefono interno
        # PullAll scarica il vcard completo; in produzione preferisci Search/List
        # con paginazione per rubriche grandi.
        vcard_path, _transfer_props = pbap.PullAll("", {"Format": "vcard30"})

        contacts = _parse_vcard_file(vcard_path)
        publish("contacts", contacts)

        client.RemoveSession(session_path)
    except dbus.exceptions.DBusException as exc:
        log.error("Sync rubrica fallita: %s", exc)
        publish("error", {"cmd": "sync_contacts", "message": str(exc)})


def _first_connected_device_mac():
    """Ricava il MAC del telefono attualmente connesso guardando i device noti."""
    for mac, info in _known_devices.items():
        if info.get("connected"):
            return mac
    return None


def _parse_vcard_file(path):
    """Parsing vCard minimale: estrae FN (nome) e TEL. Per uso reale valuta 'vobject'."""
    contacts = []
    current = {}
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if line == "BEGIN:VCARD":
                    current = {}
                elif line.startswith("FN:"):
                    current["name"] = line[3:]
                elif line.startswith("TEL"):
                    number = line.split(":", 1)[-1]
                    current.setdefault("numbers", []).append(number)
                elif line == "END:VCARD" and current:
                    contacts.append(current)
    except OSError as exc:
        log.error("Impossibile leggere il vcard scaricato: %s", exc)
    return contacts


# --- MQTT: comandi in ingresso dall'app Flutter ------------------------------

def on_mqtt_connect(client, userdata, flags, reason_code, properties=None):
    log.info("Connesso a MQTT, sottoscrivo comandi telefono e bluetooth")
    client.subscribe(f"{TOPIC_BASE}/cmd/#")
    client.subscribe(f"{BT_TOPIC_BASE}/cmd/#")
    publish("state", {"connected": True})


def on_mqtt_message(client, userdata, msg):
    cmd = msg.topic.split("/")[-1]
    try:
        payload = json.loads(msg.payload.decode()) if msg.payload else {}
    except json.JSONDecodeError:
        payload = {}

    try:
        if msg.topic.startswith(BT_TOPIC_BASE):
            if cmd == "make_discoverable":
                make_discoverable()
            elif cmd == "scan_start":
                start_scan()
            elif cmd == "scan_stop":
                stop_scan()
            elif cmd == "pair":
                pair_device(payload["mac"])
            elif cmd == "remove":
                remove_device(payload["mac"])
            elif cmd == "confirm":
                confirm_pairing(bool(payload.get("accept", False)))
            return

        if cmd == "dial":
            dial(payload["number"])
        elif cmd == "answer":
            answer()
        elif cmd == "hangup":
            hangup()
        elif cmd == "dtmf":
            send_dtmf(payload["digit"])
        elif cmd == "sync_contacts":
            sync_contacts()
    except Exception as exc:
        log.error("Errore eseguendo comando %s: %s", cmd, exc)
        publish("error", {"cmd": cmd, "message": str(exc)})


def watch_ofono_signals():
    bus.add_signal_receiver(
        on_call_added, dbus_interface="org.ofono.VoiceCallManager", signal_name="CallAdded"
    )
    bus.add_signal_receiver(
        on_call_removed, dbus_interface="org.ofono.VoiceCallManager", signal_name="CallRemoved"
    )


def main():
    mqttc.on_connect = on_mqtt_connect
    mqttc.on_message = on_mqtt_message
    mqttc.connect(MQTT_HOST, MQTT_PORT, keepalive=30)
    mqttc.loop_start()

    register_agent()
    load_known_devices()
    watch_bluez_signals()
    watch_ofono_signals()

    log.info("Phone bridge avviato, in ascolto su D-Bus/BlueZ/oFono...")
    loop = GLib.MainLoop()
    loop.run()


if __name__ == "__main__":
    main()
