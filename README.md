# Smart Switch

A four-channel ESP8266 relay controller with a companion iOS app. The firmware also provides a small browser interface, Alexa device discovery through `fauxmoESP`, physical wall-switch inputs, and a repeating relay-cycle mode.

The app and device communicate directly over your local Wi-Fi network. No cloud service or account is required.

> **Electrical safety:** Relay boards can switch hazardous mains voltage. Disconnect power before wiring, use a properly rated and enclosed relay module, and have mains wiring done by a qualified person. Never connect mains voltage to ESP8266 pins.

## Repository contents

- `SmartSwitch.xcodeproj/ESP8266/alexa_4ch_relay.ino` — ESP8266 firmware
- `SmartSwitch/` — SwiftUI iPhone app source

## What you need

### Hardware

- ESP8266 development board (for example, a NodeMCU- or Wemos D1 mini-style board)
- Four-channel relay module compatible with the board's 3.3 V logic
- Optional four physical switches or momentary buttons
- USB cable and a computer for programming the ESP8266
- iPhone running iOS 17 or later for the companion app
- 2.4 GHz Wi-Fi network reachable by both the ESP8266 and iPhone

Check the pin labels and electrical ratings of your specific board and relay module before connecting anything. Board labels such as `D1` are not GPIO numbers.

### Software

- Arduino IDE with the ESP8266 board support package installed
- Arduino libraries: `fauxmoESP`, `ESPAsyncTCP`, and `ESPAsyncWebServer` (use versions compatible with the ESP8266 Arduino core)
- Xcode for building and installing the iOS app

The Swift app uses SwiftUI and targets iOS 17. The source does not require third-party Swift packages.

## 1. Configure and flash the ESP8266

1. Install the ESP8266 board support package in Arduino IDE's Boards Manager.
2. Install the three firmware libraries listed above.
3. Open `SmartSwitch.xcodeproj/ESP8266/alexa_4ch_relay.ino` in Arduino IDE.
4. In the **User settings** section near the top of the sketch, set `WIFI_SSID` and `WIFI_PASSWORD` to your 2.4 GHz network credentials. Keep credentials private; do not commit them to a public repository.
5. Check the relay polarity. `RELAY_ACTIVE_LOW` is `true` by default, which is common for relay modules; set it to `false` if your module activates on a HIGH signal.
6. Select the board and serial port that match your ESP8266, then upload the sketch.
7. Open Serial Monitor at **115200 baud**. Once Wi-Fi connects, note the printed IP address and open `http://<device-ip>/` in a browser on the same network.

The firmware connects to Wi-Fi in the background. Physical switches, relay outputs, and cycle mode remain usable even when Wi-Fi is unavailable; the browser, app, and Alexa controls require Wi-Fi.

### Default pin map

| Channel | Relay output | GPIO | Wall-switch input | GPIO |
|---|---|---:|---|---:|
| 1 | D1 | 5 | D5 | 14 |
| 2 | D2 | 4 | D6 | 12 |
| 3 | D3 | 0 | D7 | 13 |
| 4 | D4 | 2 | RX | 3 |

Each wall switch input uses `INPUT_PULLUP`; connect the switch between its listed input pin and **GND**. `SWITCH_LATCHING` defaults to `true` for rocker switches (each flip toggles the relay). Set it to `false` for momentary push buttons (press toggles; release does not).

**Boot and serial note:** GPIO0 (D3) and GPIO2 (D4) are ESP8266 boot-strapping pins. The attached relay board must not hold them at an invalid level during startup; check its input circuitry and the ESP8266 board documentation. RX/GPIO3 is used as the fourth switch input, so the firmware configures serial output as TX-only. Avoid relying on serial input while that switch is connected.

## 2. Build and connect the iOS app

1. Open the iOS project in Xcode, choose the `SmartSwitch` app target, select your iPhone (or a simulator), and build/run.
2. If installing on a physical phone, choose your development team in Signing & Capabilities if Xcode asks.
3. On first launch, open **Settings** when prompted and enter the ESP8266 IP address shown in Serial Monitor (for example, `192.168.1.50`).
4. Allow the app to access the local network if iOS prompts. The iPhone and ESP8266 must be on the same Wi-Fi/LAN.
5. Tap **Test connection**. A successful connection shows the online status. Channel names can also be changed in Settings; these names are saved on the iPhone.

The app polls the device approximately every 1.5 seconds while it is active. If your router changes the ESP8266's IP address, update the address in Settings. A DHCP reservation in your router can help keep it stable.

> **Project format:** This repository contains `SmartSwitch.xcodeproj/project.xcproj` rather than the standard `project.pbxproj` used by Xcode. If Xcode cannot open or build the project as-is, create a new iOS SwiftUI App project targeting iOS 17 or later, then add the Swift files and asset catalog from `SmartSwitch/`. Use `SmartSwitch/Info.plist` as a reference for the local-network permission settings.

## 3. Use the controls

- **Individual relays:** Toggle any of the four channels.
- **All ON / All OFF:** Set all four relays together.
- **Cycle mode:** Repeatedly switches on one relay at a time in channel order. Set the ON duration per relay from **100 to 86,400,000 milliseconds** (24 hours). Starting the cycle begins at channel 1; stopping it turns all relays off.
- **Physical switches:** Work without Wi-Fi. Using one while cycle mode is active stops the cycle and turns all relays off.
- **Saved state:** The firmware saves relay and cycle settings to flash after changes settle. If power is restored while cycle mode was enabled, cycling restarts from channel 1.

With the current firmware setting (`CYCLE_BLOCKS_MANUAL false`), an Alexa or browser relay command during cycle mode stops the cycle and applies the command. Physical switches always stop cycle mode.

## Browser and HTTP interface

Open `http://<device-ip>/` for the firmware's built-in browser control page. Its JSON API is also used by the iOS app:

| Request | Purpose |
|---|---|
| `GET /api/state` | Read relay and cycle state |
| `GET /api/set?id=0&state=1` | Turn relay 1 on (`id` is `0`–`3`, `state` is `1` for on and `0` for off) |
| `GET /api/set?id=all&state=0` | Turn all relays off |
| `GET /api/cycle?enabled=1&ms=60000` | Set the cycle duration and start cycle mode |
| `GET /api/cycle?enabled=0` | Stop cycle mode |

The HTTP interface has no authentication or encryption. Keep it on a trusted local network; do not expose the device or port 80 directly to the internet.

## Alexa setup

After the device joins Wi-Fi, ask the Alexa app or speaker to discover devices. The firmware advertises four devices named **Switch 1** through **Switch 4**. Alexa discovery and control require the Echo and ESP8266 to be on the same local network; discovery may not work across guest-network or client-isolation boundaries.

## Troubleshooting

- **No IP address in Serial Monitor:** Recheck the SSID and password, confirm the network is 2.4 GHz, and verify the ESP8266 is in range. The firmware retries Wi-Fi periodically.
- **App says offline:** Confirm the phone and ESP8266 are on the same network, the IP address is current, and iOS Local Network access is allowed. Try `http://<device-ip>/api/state` in the phone's browser.
- **Relay state is inverted:** Change `RELAY_ACTIVE_LOW` to match the relay module and upload again.
- **Board does not boot reliably:** Inspect relay input behavior on GPIO0/D3 and GPIO2/D4 during startup; these pins determine ESP8266 boot mode.
- **A physical switch does not respond as expected:** Confirm it connects the assigned input to GND and set `SWITCH_LATCHING` for your switch type.
- **Alexa does not find the channels:** Check that Wi-Fi is connected, both devices share the same LAN, and the router is not isolating wireless clients. Restart discovery after confirming the Serial Monitor reports a Wi-Fi connection.
- **Cycle duration is rejected:** Use an integer number of milliseconds from 100 through 86,400,000.

## Implementation notes

- The device hosts the web interface and JSON endpoints on port 80.
- Firmware relay indices in the HTTP API are zero-based; the UI presents channels as 1–4.
- The app stores the device address and custom channel names locally on the iPhone.
- Relay control is unauthenticated local HTTP; this project is intended for a trusted home LAN.
