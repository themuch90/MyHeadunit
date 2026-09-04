FROM python:3.12-slim

WORKDIR /app

# libdbus-1-dev e le dipendenze di build servono per compilare dbus-python;
# gobject-introspection per PyGObject (usato dal GLib.MainLoop); il
# metapackage "dbus" fornisce dbus-run-session, richiesto dal meson.build
# di dbus-python per configurare la sua test suite anche se non la
# eseguiamo mai (su alcune Debian il solo "dbus-bin" non basta).
RUN apt-get update && apt-get install -y --no-install-recommends \
    libdbus-1-dev \
    libglib2.0-dev \
    libgirepository1.0-dev \
    dbus \
    gcc \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --break-system-packages -r requirements.txt

COPY bridge.py .

CMD ["python3", "bridge.py"]
