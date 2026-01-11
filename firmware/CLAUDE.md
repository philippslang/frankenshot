# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ESP32-S3 BLE (Bluetooth Low Energy) GATT Server firmware built with ESP-IDF v5.5.2 and NimBLE stack. Implements a BLE peripheral with Heart Rate and LED control services.

## Build Commands

```bash
idf.py build                    # Build the project
idf.py flash                    # Flash to device (COM6)
idf.py monitor                  # Open serial monitor
idf.py build flash monitor      # Full workflow
idf.py menuconfig               # Interactive configuration
idf.py fullclean                # Clean build directory
```

## Architecture

**Event-driven design with two FreeRTOS tasks:**

1. **NimBLE Host Task** - Handles BLE stack, GAP events, GATT operations
2. **Heart Rate Task** - Updates mock heart rate value every 1 second, sends indications

**Initialization flow in `main.c`:**
- Hardware init (LED, NVS) → NimBLE stack init → GAP/GATT service init → Task creation

**BLE Services:**
- Heart Rate Service (0x180D): Read + Indicate heart rate measurement (0x2A37)
- Automation IO Service (0x1815): Write-only LED control (custom 128-bit UUID)

## Code Structure

```
main/
├── main.c              # Entry point (app_main), task creation
├── src/
│   ├── gap.c           # GAP advertising, connection event handling
│   ├── gatt_svc.c      # GATT services table, characteristic callbacks
│   ├── led.c           # LED driver (GPIO or LED strip backend)
│   └── heart_rate_mock.c  # Mock heart rate generator (60-80 BPM)
└── include/            # Header files
```

## Key Patterns

- GAP events flow through `gap_event_handler()` in `gap.c`
- GATT characteristic access uses callbacks: `led_chr_access()`, `heart_rate_chr_access()` in `gatt_svc.c`
- Subscribe events are forwarded from GAP to GATT via `gatt_svr_subscribe_cb()`
- LED type (GPIO vs LED strip) is configurable via `idf.py menuconfig` → Component config

## Hardware Configuration

- Target: ESP32-S3
- LED GPIO: Pin 8 (configurable in Kconfig)
- Debug port: COM6 (configured in `.vscode/settings.json`)

## Testing

Use nRF Connect mobile app to:
- Connect to device (advertised as "NimBLE_GATT")
- Write to LED characteristic under Automation IO service
- Read/subscribe to Heart Rate Measurement characteristic
