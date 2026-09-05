# OpenAuto/aasdk: stack Android Auto host open source.
# Nota: e' un progetto Qt5/C++ mantenuto dalla community (fork di f1x-ing),
# i tag di versione cambiano nel tempo -- verifica gli ultimi rilasci prima
# del build in produzione: https://github.com/opencardev/openauto
#                          https://github.com/opencardev/aasdk

FROM debian:trixie-slim AS builder

# libabsl-dev: il sottomodulo protobuf vendorizzato da aasdk (v30.0,
# clonato via --recursive) richiede Abseil per compilare ("Could not find
# a package configuration file provided by absl"); librtaudio-dev serve a
# openauto per l'I/O audio ("Could not find rtaudio").
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake git pkg-config \
    qtbase5-dev qtdeclarative5-dev qtmultimedia5-dev libqt5svg5-dev \
    libqt5bluetooth5 qtconnectivity5-dev \
    libusb-1.0-0-dev libssl-dev libboost-all-dev \
    protobuf-compiler libprotobuf-dev libabsl-dev \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
    librtaudio-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone --depth 1 https://github.com/opencardev/aasdk.git aasdk && \
    git clone --depth 1 https://github.com/opencardev/openauto.git openauto

RUN cd aasdk && mkdir build && cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release .. && \
    make -j"$(nproc)" && make install

RUN cd openauto && mkdir build && cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release .. && \
    make -j"$(nproc)"

# --- immagine runtime ---------------------------------------------------
# Nessuna dipendenza GPU/DRM reale: autoapp disegna su Xvfb (X server
# virtuale in memoria), e GStreamer (ximagesrc) cattura quello schermo e lo
# trasmette via TCP in formato grezzo (nessuna codifica H.264: siamo in
# loopback sulla stessa macchina, comprimere aggiungerebbe solo latenza).
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    qtbase5-dev qtdeclarative5-dev qtmultimedia5-dev libqt5svg5-dev \
    libqt5bluetooth5 \
    libusb-1.0-0 libboost-system1.83.0 libboost-log1.83.0 \
    xvfb \
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/openauto/build/autoapp /usr/local/bin/autoapp
COPY --from=builder /usr/local/lib/libaasdk* /usr/local/lib/

RUN pip install --no-cache-dir --break-system-packages paho-mqtt==2.1.0

COPY launcher.py /app/launcher.py
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
