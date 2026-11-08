/*
  ESP8266 4-Channel WiFi Relay: Alexa (fauxmoESP) + Web page + Wall switches + Cycle mode
  Relay pins : D1=GPIO5, D2=GPIO4, D3=GPIO0, D4=GPIO2
  Switch pins: D5=GPIO14, D6=GPIO12, D7=GPIO13, RX=GPIO3 (switch between pin and GND)
  Libraries needed: fauxmoESP, ESPAsyncTCP, ESPAsyncWebServer
  Serial Monitor: 115200 baud
  Web page: http://<device-ip>/
*/

#include <ESP8266WiFi.h>
#include <EEPROM.h>
#include <ESPAsyncTCP.h>
#include <ESPAsyncWebServer.h>
#include "fauxmoESP.h"

// ---------- User settings ----------
const char* WIFI_SSID     = "whwc";
const char* WIFI_PASSWORD = "Access524";

#define RELAY_ACTIVE_LOW true   // set false if your relays turn on with HIGH

const uint8_t NUM_RELAYS = 4;
const uint8_t PINS[NUM_RELAYS]  = {5, 4, 0, 2};   // D1, D2, D3, D4
const char*   NAMES[NUM_RELAYS] = {"Switch 1", "Switch 2", "Switch 3", "Switch 4"};
const char*   DPINS[NUM_RELAYS] = {"D1", "D2", "D3", "D4"};

// Wall switches (one per relay, same order). Wire each between the pin and GND.
const uint8_t SW_PINS[NUM_RELAYS]  = {14, 12, 13, 3};   // D5, D6, D7, RX
const char*   SW_DPINS[NUM_RELAYS] = {"D5", "D6", "D7", "RX"};

// true  = normal latching rocker switch: every flip toggles the relay
// false = momentary push button: toggles on press only
#define SWITCH_LATCHING true
const unsigned long DEBOUNCE_MS = 50;

// Remember relay states and cycle settings across power cuts (stored in flash/EEPROM)
#define REMEMBER_STATE true
const unsigned long SAVE_DELAY_MS = 3000;   // wait this long after a change before writing (reduces flash wear)

// Cycle mode: relays run one after another, each ON for a set time, repeating forever
// true  = while cycling, Alexa commands and web relay buttons are ignored
// false = an Alexa / web command stops the cycle and is applied
// Wall switches always stop cycle mode, whatever this is set to (so you are never locked out)
#define CYCLE_BLOCKS_MANUAL false
const uint32_t CYCLE_DEFAULT_MS = 60000;        // 60 s
const uint32_t CYCLE_MIN_MS     = 100;          // shorter than this just wears out the relays
const uint32_t CYCLE_MAX_MS     = 86400000UL;   // 24 hours

const unsigned long STATUS_INTERVAL_MS = 30000;   // periodic status print
// -----------------------------------

fauxmoESP fauxmo;
AsyncWebServer server(80);

bool relayOn[NUM_RELAYS] = {false, false, false, false};
unsigned long lastStatus = 0;
unsigned long commandCount = 0;

bool swRaw[NUM_RELAYS];                 // latest raw reading
bool swStable[NUM_RELAYS];              // last debounced state
unsigned long swChangedAt[NUM_RELAYS];  // when the raw reading last changed

// Cycle mode state
bool cycleEnabled = false;
uint32_t cycleMs = CYCLE_DEFAULT_MS;    // ON time per relay, in milliseconds
int8_t cycleIndex = -1;                 // relay currently ON in the cycle
unsigned long cycleStepAt = 0;          // millis() when the current step started

// Persistence layout: 0 = magic, 1..4 = relay states, 5 = cycle enabled, 6..9 = cycle time in ms
// (magic was 0xA5 when the cycle time was stored in seconds; the change makes old data be ignored once)
const uint8_t EEPROM_MAGIC = 0xA6;
bool saveDirty = false;
unsigned long lastChangeAt = 0;

// ---------- Web page ----------
const char PAGE[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Smart Relay</title>
<style>
  :root { --bg:#f4f5f7; --fg:#1b1f24; --card:#ffffff; --muted:#6b7280; --on:#16a34a; --off:#9ca3af; --accent:#2563eb; }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#111418; --fg:#e8eaed; --card:#1b2027; --muted:#9aa3ad; --on:#22c55e; --off:#4b5563; --accent:#60a5fa; }
  }
  * { box-sizing: border-box; }
  body { margin:0; padding:20px; font-family:system-ui,sans-serif; background:var(--bg); color:var(--fg); }
  h1 { font-size:1.3rem; margin:0 0 4px; }
  #info { color:var(--muted); font-size:.85rem; margin-bottom:16px; }
  #grid { display:grid; grid-template-columns:1fr 1fr; gap:12px; max-width:480px; }
  .card { background:var(--card); color:var(--fg); border:2px solid var(--off); border-radius:14px;
          padding:22px 10px; font-size:1rem; cursor:pointer; display:flex; flex-direction:column; gap:8px; align-items:center; }
  .card b { font-size:1.4rem; color:var(--off); }
  .card.on { border-color:var(--on); }
  .card.on b { color:var(--on); }
  .card:disabled, .row button:disabled { opacity:.5; cursor:not-allowed; }
  .row { display:flex; gap:12px; max-width:480px; margin-top:12px; }
  .row button { flex:1; padding:12px; border-radius:10px; border:1px solid var(--off);
                background:var(--card); color:var(--fg); font-size:.95rem; cursor:pointer; }
  .cyc { max-width:480px; margin-top:20px; background:var(--card); border:2px solid var(--off);
         border-radius:14px; padding:16px; }
  .cyc.active { border-color:var(--accent); }
  .cyc h2 { font-size:1.05rem; margin:0; }
  .cychead { display:flex; justify-content:space-between; align-items:center; }
  .cychead input { width:22px; height:22px; accent-color:var(--accent); }
  .cycrow { display:flex; gap:8px; align-items:center; margin-top:12px; flex-wrap:wrap; }
  .cycrow label { font-size:.9rem; color:var(--muted); flex:1 1 100%; }
  .cycrow input[type=number] { flex:1; padding:10px; border-radius:8px; border:1px solid var(--off);
                               background:var(--bg); color:var(--fg); font-size:1rem; min-width:0; }
  .cycrow button { padding:10px 18px; border-radius:8px; border:1px solid var(--accent);
                   background:var(--accent); color:#fff; font-size:.95rem; cursor:pointer; }
  #cycInfo { margin-top:12px; font-size:.9rem; color:var(--muted); }
</style>
</head>
<body>
  <h1>Smart Relay</h1>
  <div id="info">Connecting...</div>
  <div id="grid"></div>
  <div class="row">
    <button id="allOn" onclick="setAll(1)">All ON</button>
    <button id="allOff" onclick="setAll(0)">All OFF</button>
  </div>

  <div class="cyc" id="cycBox">
    <div class="cychead">
      <h2>Cycle mode</h2>
      <input type="checkbox" id="cycOn" onchange="cycToggle()">
    </div>
    <div class="cycrow">
      <label for="cycSec">ON time per relay (milliseconds)</label>
      <input type="number" id="cycSec" min="100" max="86400000" step="100" value="60000">
      <button onclick="cycApply()">Set</button>
    </div>
    <div id="cycInfo">Off</div>
  </div>
<script>
  const grid = document.getElementById('grid');
  const info = document.getElementById('info');
  const cycOn = document.getElementById('cycOn');
  const cycSec = document.getElementById('cycSec');
  const cycInfo = document.getElementById('cycInfo');
  const cycBox = document.getElementById('cycBox');
  const allOn = document.getElementById('allOn');
  const allOff = document.getElementById('allOff');

  function fmtMs(ms) {
    return ms < 1000 ? ms + ' ms' : (ms / 1000).toFixed(1) + ' s';
  }

  function render(d) {
    const c = d.cycle;
    grid.innerHTML = '';
    d.relays.forEach((x, i) => {
      const b = document.createElement('button');
      b.className = 'card' + (x.on ? ' on' : '');
      b.disabled = c.enabled;
      b.innerHTML = '<span>' + x.name + '</span><b>' + (x.on ? 'ON' : 'OFF') + '</b>';
      b.onclick = () => setRelay(i, !x.on);
      grid.appendChild(b);
    });
    allOn.disabled = allOff.disabled = c.enabled;

    cycOn.checked = c.enabled;
    cycBox.className = 'cyc' + (c.enabled ? ' active' : '');
    if (document.activeElement !== cycSec) cycSec.value = c.ms;
    if (c.enabled && c.active >= 0) {
      cycInfo.textContent = 'Running: ' + d.relays[c.active].name + ' (' + fmtMs(c.remaining) + ' left)';
    } else {
      cycInfo.textContent = 'Off';
    }
    info.textContent = 'WiFi ' + d.rssi + ' dBm \u00b7 uptime ' + d.uptime + 's';
  }

  async function load() {
    try {
      const r = await fetch('/api/state');
      render(await r.json());
    } catch (e) {
      info.textContent = 'Device not reachable';
    }
  }

  async function setRelay(id, on) {
    try { await fetch('/api/set?id=' + id + '&state=' + (on ? 1 : 0)); } catch (e) {}
    load();
  }

  function setAll(on) { setRelay('all', on); }

  async function cycSend(enabled, ms) {
    const q = [];
    if (enabled !== null) q.push('enabled=' + (enabled ? 1 : 0));
    if (ms !== null) q.push('ms=' + ms);
    try {
      const r = await fetch('/api/cycle?' + q.join('&'));
      if (r.ok) render(await r.json()); else load();
    } catch (e) {}
  }

  function cycMs() {
    const n = parseInt(cycSec.value, 10);
    return (n >= 100 && n <= 86400000) ? n : null;   // null = invalid, don't send
  }
  function cycToggle() { cycSend(cycOn.checked, cycMs()); }
  function cycApply() {
    const n = cycMs();
    if (n === null) { cycInfo.textContent = 'Enter a value from 100 to 86400000 ms'; return; }
    cycSend(null, n);
  }

  load();
  setInterval(load, 2000);
</script>
</body>
</html>
)rawliteral";

// ---------- Helpers ----------
void logTag(const char* tag) {
  Serial.printf("[%8lu ms] [%s] ", millis(), tag);
}

void markDirty() {
  saveDirty = true;
  lastChangeAt = millis();
}

void printStatus() {
  logTag("STATUS");
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("uptime=%lus  heap=%u B  RSSI=%d dBm  IP=%s\n",
                  millis() / 1000, ESP.getFreeHeap(), WiFi.RSSI(),
                  WiFi.localIP().toString().c_str());
  } else {
    Serial.printf("uptime=%lus  heap=%u B  WiFi=OFFLINE (wall switches active)\n",
                  millis() / 1000, ESP.getFreeHeap());
  }
  for (uint8_t i = 0; i < NUM_RELAYS; i++) {
    Serial.printf("             %-8s (%s / GPIO%u): %-3s   switch %s (GPIO%u) = %s\n",
                  NAMES[i], DPINS[i], PINS[i], relayOn[i] ? "ON" : "OFF",
                  SW_DPINS[i], SW_PINS[i], swStable[i] ? "open" : "closed");
  }
  Serial.printf("             Cycle mode: %s, %lu ms per relay\n",
                cycleEnabled ? "ON" : "OFF", (unsigned long)cycleMs);
}

// Per-step logging is skipped for very fast cycles so the serial port doesn't slow things down
bool quietCycleStep(const char* source) {
  return cycleEnabled && cycleMs < 500 && strcmp(source, "Cycle") == 0;
}

// source: "Alexa", "Web", "Switch" or "Cycle".
// Anything except Alexa is pushed to fauxmo so its state stays current.
// Cycle steps are not saved to flash (they would wear it out); only the cycle settings are.
void setRelay(uint8_t i, bool on, const char* source) {
  relayOn[i] = on;
  if (strcmp(source, "Cycle") != 0) markDirty();
  bool level = RELAY_ACTIVE_LOW ? !on : on;
  digitalWrite(PINS[i], level ? HIGH : LOW);
  if (!quietCycleStep(source)) {
    logTag("RELAY");
    Serial.printf("%s (%s / GPIO%u) -> %s  [pin %s, via %s]\n",
                  NAMES[i], DPINS[i], PINS[i], on ? "ON" : "OFF", level ? "HIGH" : "LOW", source);
  }
  if (strcmp(source, "Alexa") != 0) {
    fauxmo.setState(i, on, 255);
  }
}

// ---------- Cycle mode ----------
void startCycle() {
  cycleEnabled = true;
  for (uint8_t i = 0; i < NUM_RELAYS; i++) {
    if (relayOn[i]) setRelay(i, false, "Cycle");
  }
  cycleIndex = 0;
  cycleStepAt = millis();
  setRelay(cycleIndex, true, "Cycle");
  logTag("CYCLE");
  Serial.printf("Started: each relay ON for %lu ms, then the next, in a loop\n", (unsigned long)cycleMs);
}

void stopCycle() {
  cycleEnabled = false;
  cycleIndex = -1;
  for (uint8_t i = 0; i < NUM_RELAYS; i++) {
    if (relayOn[i]) setRelay(i, false, "Cycle");
  }
  logTag("CYCLE");
  Serial.println("Stopped - all relays OFF");
}

void handleCycle() {
  if (!cycleEnabled || cycleIndex < 0) return;
  unsigned long now = millis();
  if (now - cycleStepAt >= cycleMs) {
    uint8_t prev = cycleIndex;
    cycleIndex = (cycleIndex + 1) % NUM_RELAYS;
    cycleStepAt += cycleMs;                                // advance by exactly one period: no drift
    if (now - cycleStepAt >= cycleMs) cycleStepAt = now;   // fell far behind: resync
    if (cycleMs >= 500) {
      logTag("CYCLE");
      Serial.printf("%s done -> next: %s\n", NAMES[prev], NAMES[cycleIndex]);
    }
    setRelay(prev, false, "Cycle");
    setRelay(cycleIndex, true, "Cycle");
  }
}

// Returns true if a remote command (Alexa / Web) may be applied right now.
bool manualAllowed(const char* source) {
  if (!cycleEnabled) return true;
  if (CYCLE_BLOCKS_MANUAL) {
    logTag("CYCLE");
    Serial.printf("Ignored %s command: cycle mode is active\n", source);
    return false;
  }
  logTag("CYCLE");
  Serial.printf("%s command stops cycle mode\n", source);
  stopCycle();
  markDirty();
  return true;
}

String stateJson() {
  String s = "{\"relays\":[";
  for (uint8_t i = 0; i < NUM_RELAYS; i++) {
    if (i) s += ",";
    s += "{\"name\":\"";
    s += NAMES[i];
    s += "\",\"on\":";
    s += relayOn[i] ? "true" : "false";
    s += "}";
  }
  s += "],\"cycle\":{\"enabled\":";
  s += cycleEnabled ? "true" : "false";
  s += ",\"ms\":";
  s += (unsigned long)cycleMs;
  s += ",\"active\":";
  s += (int)(cycleEnabled ? cycleIndex : -1);
  s += ",\"remaining\":";
  unsigned long remaining = 0;
  if (cycleEnabled) {
    unsigned long elapsed = millis() - cycleStepAt;
    remaining = (elapsed >= cycleMs) ? 0 : (cycleMs - elapsed);   // milliseconds
  }
  s += remaining;
  s += "},\"rssi\":";
  s += WiFi.RSSI();
  s += ",\"uptime\":";
  s += millis() / 1000;
  s += "}";
  return s;
}

// ---------- Persistence ----------
void loadState() {
  EEPROM.begin(16);
  if (EEPROM.read(0) == EEPROM_MAGIC) {
    for (uint8_t i = 0; i < NUM_RELAYS; i++) {
      relayOn[i] = (EEPROM.read(1 + i) == 1);
    }
    cycleEnabled = (EEPROM.read(5) == 1);
    uint32_t ms = 0;
    EEPROM.get(6, ms);
    if (ms >= CYCLE_MIN_MS && ms <= CYCLE_MAX_MS) cycleMs = ms;
    logTag("MEMORY");
    Serial.printf("Restored from flash: cycle mode %s, %lu ms per relay\n",
                  cycleEnabled ? "ON" : "OFF", (unsigned long)cycleMs);
  } else {
    logTag("MEMORY");
    Serial.println("No saved state found (first run) - all relays OFF");
  }
}

void saveState() {
  EEPROM.write(0, EEPROM_MAGIC);
  for (uint8_t i = 0; i < NUM_RELAYS; i++) {
    EEPROM.write(1 + i, relayOn[i] ? 1 : 0);
  }
  EEPROM.write(5, cycleEnabled ? 1 : 0);
  uint32_t ms = cycleMs;
  EEPROM.put(6, ms);
  bool ok = EEPROM.commit();   // only writes flash if something actually changed
  logTag("MEMORY");
  Serial.printf("Saved relays [%d %d %d %d], cycle %s, %lu ms -> %s\n",
                relayOn[0], relayOn[1], relayOn[2], relayOn[3],
                cycleEnabled ? "ON" : "OFF", (unsigned long)cycleMs, ok ? "OK" : "FAILED");
}

void handleSaving() {
  if (saveDirty && millis() - lastChangeAt >= SAVE_DELAY_MS) {
    saveDirty = false;
    saveState();
  }
}

// ---------- Wall switches ----------
void setupSwitches() {
  for (uint8_t i = 0; i < NUM_RELAYS; i++) {
    pinMode(SW_PINS[i], INPUT_PULLUP);
    swRaw[i] = swStable[i] = digitalRead(SW_PINS[i]);
    swChangedAt[i] = millis();
    logTag("SWITCH");
    Serial.printf("%s (GPIO%u) -> controls %s, currently %s, mode: %s\n",
                  SW_DPINS[i], SW_PINS[i], NAMES[i], swStable[i] ? "open" : "closed",
                  SWITCH_LATCHING ? "latching" : "momentary");
  }
}

void handleSwitches() {
  for (uint8_t i = 0; i < NUM_RELAYS; i++) {
    bool reading = digitalRead(SW_PINS[i]);

    if (reading != swRaw[i]) {            // reading moved: restart debounce timer
      swRaw[i] = reading;
      swChangedAt[i] = millis();
    }

    if (reading != swStable[i] && millis() - swChangedAt[i] >= DEBOUNCE_MS) {
      swStable[i] = reading;
      logTag("SWITCH");
      Serial.printf("%s (GPIO%u) changed -> %s\n",
                    SW_DPINS[i], SW_PINS[i], reading ? "open" : "closed");
      // Latching: any change toggles. Momentary: only the press (LOW) toggles.
      if (SWITCH_LATCHING || reading == LOW) {
        if (cycleEnabled) {
          // A physical switch always wins: it ends cycle mode (all relays OFF),
          // so you are never locked out, even when WiFi is down.
          logTag("CYCLE");
          Serial.println("Wall switch used - stopping cycle mode");
          stopCycle();
          markDirty();
        } else {
          setRelay(i, !relayOn[i], "Switch");
        }
      }
    }
  }
}

// ---------- Web server ----------
void setupWebServer() {
  // Web UI
  server.on("/", HTTP_GET, [](AsyncWebServerRequest* request) {
    logTag("WEB");
    Serial.printf("GET / from %s\n", request->client()->remoteIP().toString().c_str());
    request->send_P(200, "text/html", PAGE);
  });

  // JSON state
  server.on("/api/state", HTTP_GET, [](AsyncWebServerRequest* request) {
    request->send(200, "application/json", stateJson());
  });

  // Control: /api/set?id=0&state=1   or   /api/set?id=all&state=0
  server.on("/api/set", HTTP_GET, [](AsyncWebServerRequest* request) {
    if (!request->hasParam("id") || !request->hasParam("state")) {
      request->send(400, "text/plain", "Missing id or state");
      return;
    }
    String id = request->getParam("id")->value();
    bool on = request->getParam("state")->value().toInt() != 0;

    logTag("WEB");
    Serial.printf("Command from %s: id=%s state=%s\n",
                  request->client()->remoteIP().toString().c_str(), id.c_str(), on ? "ON" : "OFF");

    if (!manualAllowed("Web")) {
      request->send(409, "application/json", stateJson());   // cycle mode is running
      return;
    }

    if (id == "all") {
      for (uint8_t i = 0; i < NUM_RELAYS; i++) setRelay(i, on, "Web");
    } else {
      int n = id.toInt();
      if (n < 0 || n >= NUM_RELAYS) {
        request->send(400, "text/plain", "Bad relay id");
        return;
      }
      setRelay(n, on, "Web");
    }
    request->send(200, "application/json", stateJson());
  });

  // Cycle control: /api/cycle?enabled=1&ms=500   (both parameters optional)
  server.on("/api/cycle", HTTP_GET, [](AsyncWebServerRequest* request) {
    logTag("WEB");
    Serial.printf("Cycle request from %s\n", request->client()->remoteIP().toString().c_str());

    if (request->hasParam("ms")) {
      long n = request->getParam("ms")->value().toInt();
      if (n < (long)CYCLE_MIN_MS || n > (long)CYCLE_MAX_MS) {
        request->send(400, "text/plain", "ms must be between 100 and 86400000");
        return;
      }
      if ((uint32_t)n != cycleMs) {
        cycleMs = (uint32_t)n;
        logTag("CYCLE");
        Serial.printf("ON time per relay set to %lu ms\n", (unsigned long)cycleMs);
      }
      markDirty();
    }

    if (request->hasParam("enabled")) {
      bool en = request->getParam("enabled")->value().toInt() != 0;
      if (en && !cycleEnabled) startCycle();
      else if (!en && cycleEnabled) stopCycle();
      markDirty();
    }
    request->send(200, "application/json", stateJson());
  });

  // Alexa traffic shares port 80: pass anything else to fauxmo
  server.onRequestBody([](AsyncWebServerRequest* request, uint8_t* data, size_t len, size_t index, size_t total) {
    String body;                       // the buffer is not NUL-terminated, so copy exactly len bytes
    body.reserve(len);
    for (size_t i = 0; i < len; i++) body += (char)data[i];
    if (fauxmo.process(request->client(), request->method() == HTTP_GET, request->url(), body)) return;
  });

  server.onNotFound([](AsyncWebServerRequest* request) {
    String body = (request->hasParam("body", true)) ? request->getParam("body", true)->value()
                                                     : String((char*)request->_tempObject);
    if (fauxmo.process(request->client(), request->method() == HTTP_GET, request->url(), body)) return;
    request->send(404, "text/plain", "Not found");
  });

  server.begin();
  logTag("WEB");
  Serial.println("Web server started on port 80");
}

// ---------- WiFi (non-blocking) ----------
bool wifiWasUp = false;
bool webStarted = false;
unsigned long lastWifiAttempt = 0;
const unsigned long WIFI_RETRY_MS = 30000;

void startWiFi() {
  WiFi.persistent(false);        // don't write credentials to flash on every begin()
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  lastWifiAttempt = millis();
  logTag("WIFI");
  Serial.printf("Connecting to \"%s\" in the background (wall switches work meanwhile)\n", WIFI_SSID);
}

// Called every loop(): reacts to WiFi coming up / going down without ever blocking.
void handleWiFi() {
  bool up = (WiFi.status() == WL_CONNECTED);

  if (up && !wifiWasUp) {
    wifiWasUp = true;
    logTag("WIFI");
    Serial.println("Connected!");
    Serial.printf("             SSID    : %s\n", WiFi.SSID().c_str());
    Serial.printf("             IP      : %s\n", WiFi.localIP().toString().c_str());
    Serial.printf("             Gateway : %s\n", WiFi.gatewayIP().toString().c_str());
    Serial.printf("             MAC     : %s\n", WiFi.macAddress().c_str());
    Serial.printf("             RSSI    : %d dBm\n", WiFi.RSSI());

    if (!webStarted) {
      setupWebServer();
      webStarted = true;
    }
    fauxmo.enable(false);   // restart the Alexa discovery listener on the new connection
    fauxmo.enable(true);
    logTag("ALEXA");
    Serial.println("fauxmo (re)enabled");
    logTag("READY");
    Serial.printf("Web control: http://%s/\n", WiFi.localIP().toString().c_str());

  } else if (!up && wifiWasUp) {
    wifiWasUp = false;
    lastWifiAttempt = millis();
    logTag("WIFI");
    Serial.println("Connection LOST - wall switches, cycle mode and relays keep working");
    fauxmo.enable(false);

  } else if (!up && millis() - lastWifiAttempt >= WIFI_RETRY_MS) {
    lastWifiAttempt = millis();
    logTag("WIFI");
    Serial.printf("Still offline (status=%d). Retrying...\n", WiFi.status());
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  }
}

// ---------- Arduino ----------
void setup() {
  // TX-only serial frees the RX pin (GPIO3) for use as a switch input
  Serial.begin(115200, SERIAL_8N1, SERIAL_TX_ONLY);
  delay(200);
  Serial.println();
  Serial.println("==========================================");
  Serial.println("  ESP8266 4-Channel Alexa + Web Relay");
  Serial.println("==========================================");
  logTag("BOOT");
  Serial.printf("Reset reason: %s\n", ESP.getResetReason().c_str());
  logTag("BOOT");
  Serial.printf("Chip ID: %08X  CPU: %u MHz  Flash: %u KB  Free heap: %u B\n",
                ESP.getChipId(), ESP.getCpuFreqMHz(),
                ESP.getFlashChipSize() / 1024, ESP.getFreeHeap());
  logTag("BOOT");
  Serial.printf("Relay logic: %s\n", RELAY_ACTIVE_LOW ? "active-LOW" : "active-HIGH");

  // Restore the last saved states (or all OFF on first run / if disabled)
  if (REMEMBER_STATE) {
    loadState();
  } else {
    logTag("MEMORY");
    Serial.println("State memory disabled - all relays OFF at boot");
  }

  // If cycle mode was running before the power cut, the cycle restarts from Relay 1
  if (cycleEnabled) {
    for (uint8_t i = 0; i < NUM_RELAYS; i++) relayOn[i] = false;
  }

  // Set the output level first, then switch to OUTPUT, so there is no glitch at boot
  for (uint8_t i = 0; i < NUM_RELAYS; i++) {
    bool level = RELAY_ACTIVE_LOW ? !relayOn[i] : relayOn[i];
    digitalWrite(PINS[i], level ? HIGH : LOW);
    pinMode(PINS[i], OUTPUT);
    logTag("GPIO");
    Serial.printf("%s -> %s (GPIO%u) initialised %s\n",
                  NAMES[i], DPINS[i], PINS[i], relayOn[i] ? "ON" : "OFF");
  }

  setupSwitches();

  // WiFi starts in the background: relays, wall switches and cycle mode work even if it never connects
  startWiFi();

  // fauxmo uses our own web server (shared port 80); it is enabled once WiFi connects
  fauxmo.createServer(false);
  fauxmo.setPort(80);   // required for Alexa gen3 devices

  for (uint8_t i = 0; i < NUM_RELAYS; i++) {
    unsigned char id = fauxmo.addDevice(NAMES[i]);
    fauxmo.setState(id, relayOn[i], 255);   // report restored state to Alexa
    logTag("ALEXA");
    Serial.printf("Registered device #%u: \"%s\"\n", id, NAMES[i]);
  }

  fauxmo.onSetState([](unsigned char id, const char* name, bool state, unsigned char value) {
    commandCount++;
    logTag("ALEXA");
    Serial.printf("Command #%lu: id=%u name=\"%s\" state=%s value=%u\n",
                  commandCount, id, name, state ? "ON" : "OFF", value);
    if (id < NUM_RELAYS) {
      if (manualAllowed("Alexa")) {
        setRelay(id, state, "Alexa");
      } else {
        fauxmo.setState(id, relayOn[id], 255);   // keep Alexa's view correct
      }
    } else {
      logTag("ERROR");
      Serial.printf("Unknown device id %u, ignored\n", id);
    }
  });

  if (cycleEnabled) startCycle();   // resume cycle mode after a power cut

  logTag("READY");
  Serial.println("Wall switches are active now. Web page and Alexa start once WiFi connects.");
  printStatus();
  lastStatus = millis();
}

void loop() {
  handleSwitches();   // always first: works with or without WiFi
  handleCycle();
  if (REMEMBER_STATE) handleSaving();

  handleWiFi();
  if (WiFi.status() == WL_CONNECTED) fauxmo.handle();

  if (millis() - lastStatus >= STATUS_INTERVAL_MS) {
    lastStatus = millis();
    printStatus();
  }
}
