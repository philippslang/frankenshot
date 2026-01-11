#ifndef GATT_SVR_H
#define GATT_SVR_H

#include <stdint.h>

/* NimBLE GATT APIs */
#include "host/ble_gatt.h"
#include "services/gatt/ble_svc_gatt.h"

/* NimBLE GAP APIs */
#include "host/ble_gap.h"

/* Frankenshot configuration structure */
typedef struct {
    uint8_t speed;
    uint8_t height;
} frankenshot_config_t;

/* Public function declarations */
void send_heart_rate_indication(void);
void gatt_svr_register_cb(struct ble_gatt_register_ctxt *ctxt, void *arg);
void gatt_svr_subscribe_cb(struct ble_gap_event *event);
int gatt_svc_init(void);
const frankenshot_config_t *get_frankenshot_config(void);

#endif // GATT_SVR_H
