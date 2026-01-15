#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/gpio.h"
#include "driver/ledc.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "led_strip.h"
#include "sdkconfig.h"

static const char *TAG = "firmware";

/* ===== GPIO CONFIG ===== */
#define FEED_PWM_GPIO   6   // R_PWM
#define FEED_EN_GPIO    7   // R_EN + L_EN tied together
#define FEED_SWITCH_GPIO 16
#define RGB_LED_GPIO 38
#define FEED_TEST_GPIO 10

/* ===== PWM CONFIG ===== */
#define LEDC_TIMER       LEDC_TIMER_0
#define LEDC_MODE        LEDC_LOW_SPEED_MODE
#define LEDC_CHANNEL     LEDC_CHANNEL_0
#define LEDC_DUTY_RES    LEDC_TIMER_8_BIT   // 0–255
#define LEDC_FREQUENCY   20000               // 20 kHz
#define ONED_TEST_LOAD   90 // ~40%

#define DEBOUNCE_COUNT 3

#define FEED_TIMEOUT_MS     10000   // jam detection
#define FEED_POLL_MS        10

typedef enum {
    FEED_IDLE,
    FEED_CLEAR_SWITCH,
    FEED_RUNNING,
    FEED_WAIT_RELEASE,
    FEED_ERROR
} feed_state_t;

static uint8_t s_led_state = 0;

static led_strip_handle_t led_strip;

void led_on(void)
{
    /* Set the LED pixel using RGB from 0 (0% power) to 255 (100% power) for each color */
    led_strip_set_pixel(led_strip, 0, 0, 0, 10);
    /* Refresh the strip to send data */
    led_strip_refresh(led_strip);
}


static void led_off(void)
{
    /* Set all LED off to clear all pixels */
    led_strip_clear(led_strip);
}

static void blink_led(void)
{
    if (s_led_state) {
        led_on();
    } else {
        /* Set all LED off to clear all pixels */
        led_off();
    }
    s_led_state = !s_led_state;
}

static void configure_led(void)
{
    /* LED strip initialization with the GPIO and pixels number*/
    led_strip_config_t strip_config = {
        .strip_gpio_num = RGB_LED_GPIO,
        .max_leds = 1, // at least one LED on board
    };
    led_strip_rmt_config_t rmt_config = {
        .resolution_hz = 10 * 1000 * 1000, // 10MHz
        .flags.with_dma = false,
    };
    ESP_ERROR_CHECK(led_strip_new_rmt_device(&strip_config, &rmt_config, &led_strip));
    /* Set all LED off to clear all pixels */
    led_strip_clear(led_strip);
}

// NC connected to gpio, will return true if switch is triggered and wire disconnected
// which makes consumption for motor stop downstream safer
static bool feed_switch_triggered(void)
{
    return gpio_get_level(FEED_SWITCH_GPIO) == 1;
}

static inline bool feed_test_requested(void)
{
    return gpio_get_level(FEED_TEST_GPIO) != 0; // active low
}

static bool debounce_feed_switch(void)
{
    static bool last_raw = false;
    static bool stable = false;
    static uint8_t count = 0;

    bool raw = feed_switch_triggered();

    if (raw == last_raw) {
        if (count < DEBOUNCE_COUNT) {
            count++;
        }
    } else {
        count = 0;
    }

    if (count >= DEBOUNCE_COUNT) {
        stable = raw;
    }

    last_raw = raw;
    return stable;
}

static inline bool timed_out(int64_t start_us, int timeout_ms)
{
    return (esp_timer_get_time() - start_us) >
           ((int64_t)timeout_ms * 1000);
}


static void feed_switch_init(void)
{
    gpio_config_t io_conf = {
        .pin_bit_mask = 1ULL << FEED_SWITCH_GPIO,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
    };
    gpio_config(&io_conf);
}


static void motor_pwm_init(void)
{
    /* Enable pin */
    gpio_config_t en_cfg = {
        .pin_bit_mask = 1ULL << FEED_EN_GPIO,
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&en_cfg);
    gpio_set_level(FEED_EN_GPIO, 1); // Enable BTS7960

    /* LEDC timer config */
    ledc_timer_config_t timer_cfg = {
        .speed_mode       = LEDC_MODE,
        .timer_num        = LEDC_TIMER,
        .duty_resolution  = LEDC_DUTY_RES,
        .freq_hz          = LEDC_FREQUENCY,
        .clk_cfg          = LEDC_AUTO_CLK,
    };
    ESP_ERROR_CHECK(ledc_timer_config(&timer_cfg));

    /* LEDC channel config */
    ledc_channel_config_t channel_cfg = {
        .gpio_num   = FEED_PWM_GPIO,
        .speed_mode = LEDC_MODE,
        .channel    = LEDC_CHANNEL,
        .timer_sel  = LEDC_TIMER,
        .duty       = 0,
        .hpoint     = 0,
    };
    ESP_ERROR_CHECK(ledc_channel_config(&channel_cfg));

    ESP_LOGI(TAG, "Motor PWM initialized");
}

static void feed_motor_start(void)
{
    ledc_set_duty(LEDC_MODE, LEDC_CHANNEL, ONED_TEST_LOAD); 
    ledc_update_duty(LEDC_MODE, LEDC_CHANNEL);
}

static void feed_motor_stop(void)
{
    ledc_set_duty(LEDC_MODE, LEDC_CHANNEL, 0);
    ledc_update_duty(LEDC_MODE, LEDC_CHANNEL);
}

void feed_task(void *arg)
{
    feed_state_t state = FEED_IDLE;
    feed_state_t last_state = -1;
    int64_t state_start_us = 0;

    while (1) {
        bool sw = debounce_feed_switch();

        // State entry diagnostics
        if (state != last_state) {
            switch (state) {
            case FEED_IDLE:
                ESP_LOGI("FEED", "State: IDLE");
                break;

            case FEED_CLEAR_SWITCH:
                ESP_LOGI("FEED", "State: CLEAR_SWITCH");
                break;

            case FEED_RUNNING:
                ESP_LOGI("FEED", "State: RUNNING");
                break;

            case FEED_WAIT_RELEASE:
                ESP_LOGI("FEED", "State: WAIT_RELEASE");
                break;

            case FEED_ERROR:
                ESP_LOGE("FEED", "State: ERROR");
                break;
            }
            last_state = state;
        }

        switch (state) {

        case FEED_IDLE:
            if (feed_test_requested()) {
                ESP_LOGI("FEED", "Feed requested");
                feed_motor_start();
                state_start_us = esp_timer_get_time();

                state = sw ? FEED_CLEAR_SWITCH : FEED_RUNNING;
            }
            break;

        case FEED_CLEAR_SWITCH:
            if (!sw) {
                ESP_LOGI("FEED", "Switch cleared");
                state = FEED_RUNNING;
            } else if (timed_out(state_start_us, FEED_TIMEOUT_MS)) {
                ESP_LOGE("FEED", "Timeout clearing switch");
                feed_motor_stop();
                state = FEED_ERROR;
            }
            break;

        case FEED_RUNNING:
            if (sw) {
                ESP_LOGI("FEED", "Switch hit");
                state = FEED_WAIT_RELEASE;
            } else if (timed_out(state_start_us, FEED_TIMEOUT_MS)) {
                ESP_LOGE("FEED", "Timeout waiting for switch");
                feed_motor_stop();
                state = FEED_ERROR;
            }
            break;

        case FEED_WAIT_RELEASE:
            if (!sw) {
                ESP_LOGI("FEED", "Switch released");
                feed_motor_stop();
                state = FEED_IDLE;
            }
            break;

        case FEED_ERROR:
            feed_motor_stop();
            // Stay here until reset / manual clear
            break;
        }

        vTaskDelay(pdMS_TO_TICKS(FEED_POLL_MS));
    }
}

// Led control
void _0_app_main(void)
{
    configure_led();

    while (1) {
        ESP_LOGI(TAG, "Turning the LED %s!", s_led_state == true ? "ON" : "OFF");
        blink_led();
        vTaskDelay(CONFIG_BLINK_PERIOD / portTICK_PERIOD_MS);
    }
}


// Unidirectional control (propulsino and feed)
void _1_app_main(void)
{
    configure_led();
    motor_pwm_init();

    while (1) {
        led_on();
        ESP_LOGI(TAG, "Motor ON");
        feed_motor_start();
        vTaskDelay(pdMS_TO_TICKS(8000));

        led_off();
        ESP_LOGI(TAG, "Motor OFF");
        feed_motor_stop();
        vTaskDelay(pdMS_TO_TICKS(4000));
    }
}

// Switch sensor test
void _2_app_main(void)
{
   feed_switch_init();

   while (1) {
        // ESP_LOGI(TAG, "feed switch = %s", feed_switch_triggered() ? "true" : "false");
        ESP_LOGI(TAG, "test switch = %s", feed_test_requested() ? "true" : "false");
        vTaskDelay(pdMS_TO_TICKS(10));
   }
}


// feed test
void app_main(void)
{
   feed_switch_init();
   motor_pwm_init();

   xTaskCreate(feed_task, "NimBLE Host", 4*1024, NULL, 5, NULL);
   return;
}