#include "common.h"
#include "gap.h"
#include "gatt_svc.h"
#include "heart_rate.h"
#include "controller.h"
#include "led.h"

#include "host/ble_hs.h"
#include "nimble/nimble_port.h"


void ble_store_config_init(void);

static void on_stack_reset(int reason);
static void on_stack_sync(void);
static void nimble_host_config_init(void);
static void nimble_host_task(void *param);

/*
 *  Stack event callback functions
 *      - on_stack_reset is called when host resets BLE stack due to errors
 *      - on_stack_sync is called when host has synced with controller
 */
static void on_stack_reset(int reason) {
    /* On reset, print reset reason to console */
    ESP_LOGI(TAG, "nimble stack reset, reset reason: %d", reason);
}

static void on_stack_sync(void) {
    /* On stack sync, do advertising initialization */
    adv_init();
}

static void nimble_host_config_init(void) {
    ble_hs_cfg.reset_cb = on_stack_reset;
    ble_hs_cfg.sync_cb = on_stack_sync;
    ble_hs_cfg.gatts_register_cb = gatt_svr_register_cb;
    ble_hs_cfg.store_status_cb = ble_store_util_status_rr;

    ble_store_config_init();
}

static void nimble_host_task(void *param) {
    ESP_LOGI(TAG, "nimble host task has been started!");

    /* This function won't return until nimble_port_stop() is executed */
    nimble_port_run();

    /* Clean up at exit */
    vTaskDelete(NULL);
}

static void indication_task(void *param) {
    ESP_LOGI(TAG, "indication task has been started!");

    while (1) {
        update_heart_rate();

        send_heart_rate_indication();
        send_frankenshot_config_indication();
        send_frankenshot_feeding_indication();

        vTaskDelay(MOCK_RATE_TASK_PERIOD);
    }

    /* Clean up at exit */
    vTaskDelete(NULL);
}

static void program_task(void *param) {
    ESP_LOGI(TAG, "program task started");

    while (1) {
        const frankenshot_program_t *prog = get_frankenshot_program();

        /* Wait for feeding enabled and valid program */
        if (!get_frankenshot_feeding() || prog->count == 0) {
            elev_motors_stop();  /* Stop motors when paused */
            vTaskDelay(pdMS_TO_TICKS(100));
            continue;
        }

        uint8_t idx = get_current_config_index();
        const frankenshot_config_t *cfg = &prog->configs[idx];
        ESP_LOGI(TAG, "executing config[%d]: speed=%d height=%d time=%d spin=%d horiz=%d",
                 idx, cfg->speed, cfg->height, cfg->time_between_balls,
                 cfg->spin, cfg->horizontal);

        /* 1. Position motors (parallel) */
        horz_move_to_relative(cfg->horizontal);
        elev_move_to_relative(cfg->height);

        /* 2. Start elevation motors */
        elev_motors_start(cfg->speed, cfg->spin);

        /* 3. Wait for positioning */
        while (!is_horz_ready() || !is_elev_ready()) {
            if (!get_frankenshot_feeding()) break;
            vTaskDelay(pdMS_TO_TICKS(10));
        }
        if (!get_frankenshot_feeding()) continue;

        /* 4. Feed ball */
        request_feed();

        /* 5. Wait for feed complete */
        while (is_feed_pending()) {
            vTaskDelay(pdMS_TO_TICKS(10));
        }

        /* 6. Update current config for BLE indication */
        set_current_config_index(idx);
        send_frankenshot_config_indication();

        /* 7. Wait time_between_balls */
        for (int i = 0; i < cfg->time_between_balls * 10; i++) {
            if (!get_frankenshot_feeding()) break;
            vTaskDelay(pdMS_TO_TICKS(100));
        }

        /* 8. Advance to next config */
        uint8_t next = (idx + 1) % prog->count;
        set_current_config_index(next);
    }
}

void app_main(void) {
    int rc = 0;
    esp_err_t ret;

    led_init();

    /* Initialize motors and home steppers */
    elev_motors_init();
    horz_home();   /* Blocking - homes horizontal axis */
    vTaskDelay(pdMS_TO_TICKS(10));
    elev_home();   /* Blocking - homes elevation axis */
    vTaskDelay(pdMS_TO_TICKS(10));

    /*
     * NVS flash initialization
     * Dependency of BLE stack to store configurations
     */
    ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES ||
        ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "failed to initialize nvs flash, error code: %d ", ret);
        return;
    }

    /* NimBLE stack initialization */
    ret = nimble_port_init();
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "failed to initialize nimble stack, error code: %d ",
                 ret);
        return;
    }

#if CONFIG_BT_NIMBLE_GAP_SERVICE
    /* GAP service initialization */
    rc = gap_init();
    if (rc != 0) {
        ESP_LOGE(TAG, "failed to initialize GAP service, error code: %d", rc);
        return;
    }
#endif

    /* GATT server initialization */
    rc = gatt_svc_init();
    if (rc != 0) {
        ESP_LOGE(TAG, "failed to initialize GATT server, error code: %d", rc);
        return;
    }

    /* NimBLE host configuration initialization */
    nimble_host_config_init();

    vTaskDelay(pdMS_TO_TICKS(10));

    /* Start NimBLE host task thread and return */
    xTaskCreate(nimble_host_task, "NimBLE Host", 4*1024, NULL, 5, NULL);
    xTaskCreate(indication_task, "Indicators", 4*1024, NULL, 5, NULL);

    /* Start controller tasks */
    xTaskCreate(horz_task, "Horizontal", 4*1024, NULL, 5, NULL);
    xTaskCreate(elev_task, "Elevation", 4*1024, NULL, 5, NULL);
    xTaskCreate(feed_task, "Feeder", 4*1024, NULL, 5, NULL);
    xTaskCreate(program_task, "Program", 4*1024, NULL, 5, NULL);

    return;
}
