FROM python:3.14-slim

WORKDIR /app

# libdbus-1-dev e le dipendenze di build servono per compilare dbus-python;
# libgirepository-2.0-dev per PyGObject (usato dal GLib.MainLoop): dalla
# 3.50 in poi PyGObject richiede la nuova girepository-2.0, non piu' la
# 1.0 (il suo meson.build non ha fallback); gir1.2-glib-2.0 e' il
# pacchetto RUNTIME che fornisce i file .typelib (senza, "from gi.repository
# import GLib" fallisce con "introspection typelib not found" anche se
# PyGObject si e' installato correttamente); il metapackage "dbus" fornisce
# dbus-run-session, richiesto dal meson.build di dbus-python per
# configurare la sua test suite anche se non la eseguiamo mai (su alcune
# Debian il solo "dbus-bin" non basta); libcairo2-dev serve a compilare
# pycairo, dipendenza di build di PyGObject.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libdbus-1-dev \
    libglib2.0-dev \
    libgirepository-2.0-dev \
    gir1.2-glib-2.0 \
    libcairo2-dev \
    dbus \
    gcc \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --break-system-packages -r requirements.txt

COPY bridge.py .

CMD ["python3", "bridge.py"]
