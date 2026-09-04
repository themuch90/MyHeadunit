// API gateway per la head unit.
// Espone:
//  - REST /health, /status
//  - WebSocket /ws  -> inoltra in tempo reale i messaggi MQTT (car/#) all'app Flutter
// L'app Flutter puo' cosi' usare un solo canale (WS) invece di parlare
// direttamente con MQTT, semplificando permessi di rete e debug.

import express from "express";
import { WebSocketServer } from "ws";
import mqtt from "mqtt";
import http from "http";

const MQTT_HOST = process.env.MQTT_HOST || "127.0.0.1";
const MQTT_PORT = process.env.MQTT_PORT || 1883;
const HTTP_PORT = process.env.HTTP_PORT || 8080;

const app = express();
app.use(express.json());

app.get("/health", (_req, res) => res.json({ status: "ok" }));

app.get("/status", (_req, res) => {
  res.json({
    mqtt_connected: mqttClient.connected,
    uptime_s: process.uptime(),
  });
});

const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: "/ws" });

const mqttClient = mqtt.connect(`mqtt://${MQTT_HOST}:${MQTT_PORT}`);

mqttClient.on("connect", () => {
  console.log(`Connesso a MQTT ${MQTT_HOST}:${MQTT_PORT}`);
  mqttClient.subscribe("car/#");
});

mqttClient.on("message", (topic, payload) => {
  const message = JSON.stringify({ topic, payload: payload.toString() });
  wss.clients.forEach((client) => {
    if (client.readyState === client.OPEN) {
      client.send(message);
    }
  });
});

wss.on("connection", (ws) => {
  console.log("Client Flutter connesso via WebSocket");
  ws.send(JSON.stringify({ topic: "system/connected", payload: "ok" }));

  // Comandi dall'app (es. accensione HVAC, richiesta media) rilanciati su MQTT
  ws.on("message", (data) => {
    try {
      const { topic, payload } = JSON.parse(data.toString());
      if (topic) mqttClient.publish(topic, payload ?? "");
    } catch (err) {
      console.warn("Messaggio WS non valido:", err.message);
    }
  });
});

server.listen(HTTP_PORT, () => {
  console.log(`API gateway in ascolto su :${HTTP_PORT}`);
});
