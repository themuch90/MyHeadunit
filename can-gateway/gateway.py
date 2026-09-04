"""
Gateway CAN bus -> MQTT per head unit.
Legge frame dal bus SocketCAN (can0) e li pubblica su MQTT
in modo che l'app Flutter possa sottoscriverli in tempo reale.
"""

import os
import json
import time
import logging

import can
import paho.mqtt.client as mqtt

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("can-gateway")

MQTT_HOST = os.getenv("MQTT_HOST", "127.0.0.1")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
CAN_CHANNEL = os.getenv("CAN_CHANNEL", "can0")
CAN_BITRATE = int(os.getenv("CAN_BITRATE", "500000"))
MQTT_TOPIC_BASE = os.getenv("MQTT_TOPIC_BASE", "car/can")

# Mappa minima ID CAN -> nome segnale (esempio, da adattare al tuo veicolo/DBC)
SIGNAL_MAP = {
    0x100: "rpm",
    0x101: "speed",
    0x102: "coolant_temp",
    0x103: "fuel_level",
}


def connect_mqtt() -> mqtt.Client:
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="can-gateway")
    while True:
        try:
            client.connect(MQTT_HOST, MQTT_PORT, keepalive=30)
            client.loop_start()
            log.info("Connesso a MQTT su %s:%s", MQTT_HOST, MQTT_PORT)
            return client
        except Exception as exc:
            log.warning("MQTT non raggiungibile (%s), riprovo tra 3s...", exc)
            time.sleep(3)


def connect_can() -> can.BusABC:
    while True:
        try:
            bus = can.interface.Bus(channel=CAN_CHANNEL, bustype="socketcan")
            log.info("Bus CAN aperto su %s", CAN_CHANNEL)
            return bus
        except Exception as exc:
            log.warning("Impossibile aprire %s (%s), riprovo tra 3s...", CAN_CHANNEL, exc)
            time.sleep(3)


def decode_frame(msg: can.Message) -> dict | None:
    """Decodifica minima. Sostituisci con cantools + file .dbc per un mezzo reale."""
    name = SIGNAL_MAP.get(msg.arbitration_id)
    if not name:
        return None
    value = int.from_bytes(msg.data[:2], byteorder="big", signed=False)
    return {"signal": name, "value": value, "raw_id": hex(msg.arbitration_id)}


def main():
    mqtt_client = connect_mqtt()
    bus = connect_can()

    log.info("In ascolto sul bus CAN...")
    for msg in bus:
        decoded = decode_frame(msg)
        if decoded is None:
            continue
        topic = f"{MQTT_TOPIC_BASE}/{decoded['signal']}"
        mqtt_client.publish(topic, json.dumps(decoded), qos=0, retain=False)


if __name__ == "__main__":
    main()
