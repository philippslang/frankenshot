# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ESP32-S3 firmware for a modified tennis ball machine ("Frankenshot") that exposes motor control via Bluetooth Low Energy. The device controls ball feeding, elevation (speed/spin), and horizontal positioning through a mobile app.


## Architecture

### Task Structure (FreeRTOS)

The application runs multiple concurrent tasks:
- **nimble_host_task**: BLE stack operations
- **indication_task**: Periodic BLE characteristic updates (25s interval)
- **feed_task**: Ball feeder state machine with jam detection
- **elev_task**: Elevation stepper motor control
- **horz_task**: Horizontal stepper motor control

### BLE Services

Custom Frankenshot service UUID: `0x00000000-4652-414E-4b45-4e53484f5401`

| Characteristic | UUID Suffix | Access | Purpose |
|---------------|-------------|--------|---------|
| Config | 0x01 | read/indicate | Current active configuration |
| Feeding | 0x02 | read/write/indicate | Feeding state (paused/running) |
| Manual Feed | 0x03 | write | Trigger single ball feed |
| Program | 0x04 | read/write | Sequence of up to 8 configurations |

### Data Structures

```c
// 5 bytes per configuration
typedef struct {
    uint8_t speed;              // 0-10
    uint8_t height;             // 0-10
    uint8_t time_between_balls; // seconds
    uint8_t spin;               // 0-10 (5 = center)
    uint8_t horizontal;         // 0-10
} frankenshot_config_t;

// Program holds up to 8 configurations
typedef struct {
    uint8_t id;
    uint8_t count;
    frankenshot_config_t configs[8];
} frankenshot_program_t;
```

### Motor Control

| Motor | Type | Control | GPIO Pins |
|-------|------|---------|-----------|
| Feed | DC (BTS7960) | PWM 20kHz | PWM:19, EN:20, Switch:14 |
| Elev Bottom | DC (BTS7960) | PWM 20kHz | PWM:48, EN:45 |
| Elev Top | DC (BTS7960) | PWM 20kHz | PWM:36, EN:37 |
| Elev Stepper | Stepper | Step/Dir | Step:16, Dir:17, EN:15, Switch:13 |
| Horz Stepper | Stepper | Step/Dir | Step:46, Dir:9, EN:3 |

- Elevation uses differential top/bottom motor speeds for spin control
- Steppers auto-home on startup using limit switches
- Feed motor has 10-second jam detection timeout

### Source Organization

```
main/
├── main.c           # Entry point, task creation, init sequence
├── src/
│   ├── controller.c # All motor control (feed, elevation, horizontal)
│   ├── gap.c        # BLE advertising and connection management
│   ├── gatt_svc.c   # GATT services and characteristic handlers
│   └── led.c        # RGB LED strip control (GPIO 38)
└── include/         # Header files
```

### Key APIs

```c
// Motor control (controller.h)
void request_feed(void);                           // Trigger ball feed
void elev_motors_start(uint32_t speed, uint32_t spin);  // Start elevation motors
void elev_move_to_relative(uint32_t rel);          // Position 0-100
void horz_move_to_relative(uint32_t rel);          // Position 0-100

// State (gatt_svc.h)
const frankenshot_config_t *get_frankenshot_config(void);
bool get_frankenshot_feeding(void);
```
