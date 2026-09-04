"""
Launcher/wrapper per OpenAuto (autoapp), containerizzato.

Modalita' CABLATA (USB/AOAP): il telefono si collega via cavo USB al mini
PC. aasdk rileva il device, lo riconfigura in modalita' "accessory" (AOAP -
Android Open Accessory Protocol) e apre la sessione Android Auto su quel
canale. Non serve alcun handshake Bluetooth ne' WiFi Direct.

Pipeline video: Xvfb (X server virtuale in memoria, nessuna GPU richiesta)
-> autoapp disegna su quel display -> GStreamer (ximagesrc) cattura lo
schermo e lo trasmette via TCP in formato grezzo (nessuna codifica H.264:
loopback sulla stessa macchina, comprimere aggiungerebbe solo latenza).
Lato Flutter, il plugin mantenuto flutterpi_gstreamer_video_player riceve
questo stream e gestisce lui la registrazione texture -- nessun codice C
custom da parte nostra.

Pubblica su MQTT:
  car/androidauto/state     stopped | starting | active | error

Si sottoscrive a:
  car/androidauto/cmd/start
  car/androidauto/cmd/stop
"""

import json
import logging
import os
import subprocess
import threading
import time

import paho.mqtt.client as mqtt

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("androidauto-bridge")

MQTT_HOST = os.getenv("MQTT_HOST", "127.0.0.1")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
TOPIC_BASE = "car/androidauto"
X_DISPLAY = os.getenv("X_DISPLAY", ":1")
STREAM_PORT = os.getenv("STREAM_PORT", "5000")
SCREEN_GEOMETRY = os.getenv("SCREEN_GEOMETRY", "1280x720x24")

_xvfb_process = None
_gst_process = None
_autoapp_process = None
_lock = threading.Lock()

mqttc = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="androidauto-bridge")


def publish(state):
    mqttc.publish(f"{TOPIC_BASE}/state", state)
    log.info("stato -> %s", state)


def _start_xvfb():
    global _xvfb_process
    if _xvfb_process and _xvfb_process.poll() is None:
        return
    log.info("Avvio Xvfb su %s", X_DISPLAY)
    _xvfb_process = subprocess.Popen(
        ["Xvfb", X_DISPLAY, "-screen", "0", SCREEN_GEOMETRY, "-nolisten", "tcp"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    for _ in range(50):
        if os.path.exists(f"/tmp/.X11-unix/X{X_DISPLAY.lstrip(':')}"):
            return
        time.sleep(0.1)
    raise RuntimeError("Xvfb non pronto entro il timeout")


def _start_gstreamer_stream():
    global _gst_process
    if _gst_process and _gst_process.poll() is None:
        return
    log.info("Avvio pipeline GStreamer (cattura schermo -> TCP:%s)", STREAM_PORT)
    # Video grezzo (nessun encoder): ximagesrc cattura lo schermo Xvfb,
    # rtpvrawpay lo impacchetta, gdppay allega le caps cosi' il lato client
    # non deve negoziarle a mano, tcpserversink lo espone sulla porta.
    pipeline = (
        f"ximagesrc display-name={X_DISPLAY} use-damage=0 ! "
        "video/x-raw,framerate=30/1 ! videoconvert ! "
        "video/x-raw,format=I420 ! rtpvrawpay ! gdppay ! "
        f"tcpserversink host=0.0.0.0 port={STREAM_PORT}"
    )
    _gst_process = subprocess.Popen(
        ["gst-launch-1.0", "-e"] + pipeline.split(" "),
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )


def start_session():
    global _autoapp_process
    with _lock:
        if _autoapp_process and _autoapp_process.poll() is None:
            log.info("Sessione gia' attiva")
            return
        publish("starting")
        _start_xvfb()
        _start_gstreamer_stream()
        # autoapp in modalita' USB: rileva il telefono su /dev/bus/usb
        # (montato dal container) e gestisce lui stesso lo switch AOAP.
        # Il flag esatto per forzare la modalita' USB varia tra fork/versioni
        # di aasdk/openauto -- verifica con 'autoapp --help' nell'immagine.
        _autoapp_process = subprocess.Popen(
            ["/usr/local/bin/autoapp", "--usb"],
            env={**os.environ, "DISPLAY": X_DISPLAY, "QT_QPA_PLATFORM": "xcb"},
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        threading.Thread(target=_watch_process, daemon=True).start()


def _watch_process():
    global _autoapp_process
    proc = _autoapp_process
    if not proc:
        return
    publish("active")
    for line in proc.stdout:
        log.info("[autoapp] %s", line.rstrip())
    exit_code = proc.wait()
    with _lock:
        _autoapp_process = None
    publish("error" if exit_code != 0 else "stopped")


def stop_session():
    global _autoapp_process
    with _lock:
        if _autoapp_process and _autoapp_process.poll() is None:
            _autoapp_process.terminate()
            try:
                _autoapp_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                _autoapp_process.kill()
        _autoapp_process = None
    publish("stopped")
    # Xvfb e la pipeline GStreamer restano attivi tra una sessione e
    # l'altra: riavviarli ad ogni start/stop aggiungerebbe solo latenza.


def on_connect(client, userdata, flags, reason_code, properties=None):
    log.info("Connesso a MQTT")
    client.subscribe(f"{TOPIC_BASE}/cmd/#")
    publish("stopped")


def on_message(client, userdata, msg):
    cmd = msg.topic.split("/")[-1]
    if cmd == "start":
        start_session()
    elif cmd == "stop":
        stop_session()


def main():
    mqttc.on_connect = on_connect
    mqttc.on_message = on_message
    mqttc.connect(MQTT_HOST, MQTT_PORT, keepalive=30)
    mqttc.loop_forever()


if __name__ == "__main__":
    main()
