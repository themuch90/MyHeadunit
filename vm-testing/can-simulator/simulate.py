"""
Genera frame CAN sintetici ma plausibili su un'interfaccia virtuale (vcan0),
usando gli stessi ID che can-gateway/gateway.py si aspetta (vedi SIGNAL_MAP).
Serve a validare tutta la catena can-gateway -> MQTT -> Flutter senza un
veicolo reale o hardware CAN fisico.
"""

import math
import os
import time

import can

CAN_CHANNEL = os.getenv("CAN_CHANNEL", "vcan0")

# Deve combaciare con can-gateway/gateway.py::SIGNAL_MAP
SIGNAL_IDS = {
    "rpm": 0x100,
    "speed": 0x101,
    "coolant_temp": 0x102,
    "fuel_level": 0x103,
}


def main():
    bus = can.interface.Bus(channel=CAN_CHANNEL, bustype="socketcan")
    print(f"Simulatore CAN avviato su {CAN_CHANNEL}")

    t = 0.0
    while True:
        # Valori che oscillano in modo plausibile, non casuali a scatti
        rpm = int(1500 + 800 * math.sin(t / 3))
        speed = int(50 + 30 * math.sin(t / 7))
        coolant = int(88 + 3 * math.sin(t / 20))
        fuel = int(60 - (t % 600) / 10)  # scende lentamente, poi si "riempie"

        values = {
            "rpm": rpm,
            "speed": max(speed, 0),
            "coolant_temp": coolant,
            "fuel_level": max(fuel, 5),
        }

        for name, value in values.items():
            arb_id = SIGNAL_IDS[name]
            data = value.to_bytes(2, byteorder="big", signed=False)
            msg = can.Message(arbitration_id=arb_id, data=data.ljust(8, b"\x00"),
                               is_extended_id=False)
            bus.send(msg)

        t += 1
        time.sleep(1)


if __name__ == "__main__":
    main()
