# Mopidy: motore di riproduzione per la radio web. Espone l'API
# WebSocket/JSON-RPC (estensione "http", bundled nel pacchetto core) su cui
# l'app Flutter si collega direttamente (vedi lib/services/radio_service.dart)
# -- nessun ponte MQTT intermedio per questa funzione, a differenza di
# telefono/bluetooth/Android Auto che parlano con demoni di sistema senza
# un'API di rete pronta all'uso.
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    mopidy \
    glib-networking \
    && rm -rf /var/lib/apt/lists/*

COPY mopidy.conf /etc/mopidy/mopidy.conf

EXPOSE 6680

CMD ["mopidy"]
