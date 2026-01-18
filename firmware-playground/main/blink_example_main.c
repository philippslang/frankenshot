#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/gpio.h"
#include "driver/ledc.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_rom_sys.h"
#include "led_strip.h"
#include "sdkconfig.h"

static const char *TAG = "firmware";

/* ===== GPIO CONFIG ===== */
#define RGB_LED_GPIO            38  // s3 on-board RGB LED
#define RGB_LED_GPIO            8   // c6 on-board RGB LED

#define FEED_PWM_GPIO           23   // R_PWM
#define FEED_EN_GPIO            22   // R_EN + L_EN tied together
#define FEED_SWITCH_GPIO        15   // NC switch input

#define MANUAL_TEST_GPIO        10

#define HORZ_STEP_ENABLE_GPIO   6
#define HORZ_STEP_STEP_GPIO     4
#define HORZ_STEP_DIR_GPIO      5
#define HORZ_STEP_SWITCH_GPIO   7
  
/* ===== PWM CONFIG ===== */
#define FEED_LEDC_TIMER       LEDC_TIMER_0
#define FEED_LEDC_MODE        LEDC_LOW_SPEED_MODE
#define FEED_LEDC_CHANNEL     LEDC_CHANNEL_0
#define FEED_LEDC_DUTY_RES    LEDC_TIMER_8_BIT      // 0–255
#define FEED_LEDC_FREQUENCY   20000                 // 20 kHz
#define FEED_PWM_LOAD         90                    // ~40%

/* ===== STEPPER CONFIG ===== */
#define HORZ_DIR            0
#define HORZ_STEP_DELAY_US     1000   // ping delay, smaller = faster, 1000 safe, limited by Hz

/* ===== SWITCH CONFIG ===== */
#define DEBOUNCE_COUNT    3
#define FEED_TIMEOUT_MS   10000   // jam detection
#define FEED_POLL_MS      10

# define MAIN 4

typedef enum {
    FEED_IDLE,
    FEED_CLEAR_SWITCH,
    FEED_RUNNING,
    FEED_WAIT_RELEASE,
    FEED_ERROR
} feed_state_t;

static uint8_t s_led_state = 0;
static led_strip_handle_t led_strip;

/* ===== HORZ ===== */
typedef enum {
    AXIS_CAL_SEEK_1,
    AXIS_CAL_WAIT_RELEASE_1,
    AXIS_CAL_SEEK_2,
    AXIS_CAL_WAIT_RELEASE_2,
    AXIS_READY,
    AXIS_MOVING
} horz_axis_state_t;

static horz_axis_state_t horz_axis_state;

static int32_t horz_step_counter = 0;
static int32_t horz_total_steps = 0;
static int32_t horz_target_steps = 0;

static inline bool timed_out(int64_t start_us, int timeout_ms)
{
    return (esp_timer_get_time() - start_us) >
           ((int64_t)timeout_ms * 1000);
}

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

static bool debounce_switch(gpio_num_t gpio_num)
{
    static bool last_raw = false;
    static bool stable = false;
    static uint8_t count = 0;

    // NC connected to gpio, will return true if switch is triggered and wire disconnected
    // which makes consumption for motor stop downstream safer
    bool raw = gpio_get_level(gpio_num) == 1;

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

static inline bool feed_test_requested(void)
{
    return gpio_get_level(MANUAL_TEST_GPIO) != 0; // active low
}

static bool feed_switch_pressed(void)
{
    return debounce_switch(FEED_SWITCH_GPIO);
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

static void feed_motor_pwm_init(void)
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
        .speed_mode       = FEED_LEDC_MODE,
        .timer_num        = FEED_LEDC_TIMER,
        .duty_resolution  = FEED_LEDC_DUTY_RES,
        .freq_hz          = FEED_LEDC_FREQUENCY,
        .clk_cfg          = LEDC_AUTO_CLK,
    };
    ESP_ERROR_CHECK(ledc_timer_config(&timer_cfg));

    /* LEDC channel config */
    ledc_channel_config_t channel_cfg = {
        .gpio_num   = FEED_PWM_GPIO,
        .speed_mode = FEED_LEDC_MODE,
        .channel    = FEED_LEDC_CHANNEL,
        .timer_sel  = FEED_LEDC_TIMER,
        .duty       = 0,
        .hpoint     = 0,
    };
    ESP_ERROR_CHECK(ledc_channel_config(&channel_cfg));

    ESP_LOGI(TAG, "Motor PWM initialized");
}

static void feed_motor_start(void)
{
    ledc_set_duty(FEED_LEDC_MODE, FEED_LEDC_CHANNEL, FEED_PWM_LOAD); 
    ledc_update_duty(FEED_LEDC_MODE, FEED_LEDC_CHANNEL);
}

static void feed_motor_stop(void)
{
    ledc_set_duty(FEED_LEDC_MODE, FEED_LEDC_CHANNEL, 0);
    ledc_update_duty(FEED_LEDC_MODE, FEED_LEDC_CHANNEL);
}

void feed_task(void *arg)
{
    feed_state_t state = FEED_IDLE;
    feed_state_t last_state = -1;
    int64_t state_start_us = 0;

    feed_switch_init();
    feed_motor_pwm_init();

    while (1) {
        bool sw = feed_switch_pressed();

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

static bool horz_switch_pressed(void)
{
    return debounce_switch(HORZ_STEP_SWITCH_GPIO);
}


static void horz_switch_init(void)
{
    gpio_config_t io_conf = {
        .pin_bit_mask = 1ULL << HORZ_STEP_SWITCH_GPIO,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
    };
    gpio_config(&io_conf);
}

static inline void horz_driver_enable(void)
{
    gpio_set_level(HORZ_STEP_ENABLE_GPIO, 0); // active LOW
}

static inline void horz_driver_disable(void)
{
    gpio_set_level(HORZ_STEP_ENABLE_GPIO, 1);
}

static void horz_stepper_init(void)
{
    gpio_config_t io_conf = {
        .mode = GPIO_MODE_OUTPUT,
        .pin_bit_mask =
            (1ULL << HORZ_STEP_STEP_GPIO) |
            (1ULL << HORZ_STEP_DIR_GPIO)  |
            (1ULL << HORZ_STEP_ENABLE_GPIO),
    };
    gpio_config(&io_conf);

    horz_driver_disable();
    gpio_set_level(HORZ_STEP_DIR_GPIO, HORZ_DIR);
}

static void horz_step_pulse(void)
{
    gpio_set_level(HORZ_STEP_STEP_GPIO, 1);
    esp_rom_delay_us(HORZ_STEP_DELAY_US); 
    gpio_set_level(HORZ_STEP_STEP_GPIO, 0);
    esp_rom_delay_us(HORZ_STEP_DELAY_US);
}

void horz_move_to(int32_t pos)
{
    if (horz_axis_state != AXIS_READY) return;

    horz_driver_enable();
    horz_target_steps = pos;
    horz_axis_state = AXIS_MOVING;
}

static void horz_home_task(void *arg)
{
    horz_stepper_init();
    horz_switch_init();
    horz_driver_enable();
    static const char *HTAG = "HORZ";
    ESP_LOGI(HTAG, "Calibration starts");
    horz_axis_state = AXIS_CAL_SEEK_1;

    while (1) {
        bool sw = horz_switch_pressed();

        switch (horz_axis_state) {

        case AXIS_CAL_SEEK_1:
            horz_step_pulse();
            if (sw) {
                ESP_LOGI(HTAG, "First press");
                horz_axis_state = AXIS_CAL_WAIT_RELEASE_1;
            }
            break;

        case AXIS_CAL_WAIT_RELEASE_1:
            horz_step_pulse();
            if (!sw) {
                ESP_LOGI(HTAG, "First release → zero");
                horz_step_counter = 0;
                horz_axis_state = AXIS_CAL_SEEK_2;
            }
            break;

        case AXIS_CAL_SEEK_2:
            horz_step_pulse();
            horz_step_counter++;
            if (sw) {
                ESP_LOGI(HTAG, "Second press");
                horz_axis_state = AXIS_CAL_WAIT_RELEASE_2;
            }
            break;

        case AXIS_CAL_WAIT_RELEASE_2:
            horz_step_pulse();
            horz_step_counter++;
            if (!sw) {
                horz_total_steps = horz_step_counter;
                ESP_LOGI(HTAG, "Calibration done, total steps = %ld", horz_total_steps);
                horz_driver_disable();
                horz_axis_state = AXIS_READY;
            }
            break;

        case AXIS_MOVING:
            horz_step_pulse();
            horz_step_counter++;

            if (horz_step_counter >= horz_total_steps)
                horz_step_counter = 0;

            if (horz_step_counter == horz_target_steps) {
                ESP_LOGI(HTAG, "Target reached");
                horz_driver_disable();
                horz_axis_state = AXIS_READY;
            }
            break;

        case AXIS_READY:
            vTaskDelay(pdMS_TO_TICKS(100));
            break;
        }
    }
}


// Led control
#if MAIN == 0
void app_main(void)
{
    configure_led();

    while (1) {
        ESP_LOGI(TAG, "Turning the LED %s!", s_led_state == true ? "ON" : "OFF");
        blink_led();
        vTaskDelay(CONFIG_BLINK_PERIOD / portTICK_PERIOD_MS);
    }
}
#endif

// Unidirectional control (propulsino and feed)
#if MAIN == 1
void app_main(void)
{
    configure_led();
    feed_motor_pwm_init();

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
#endif

// Switch sensor test
#if MAIN == 2
void app_main(void)
{
   horz_switch_init();

   while (1) {
        bool sw = horz_switch_pressed();
        if (sw) {
            ESP_LOGI(TAG, "Feed switch PRESSED");
        }
        // ESP_LOGI(TAG, "test switch = %s", feed_test_requested() ? "true" : "false");
        vTaskDelay(pdMS_TO_TICKS(10));
   }
}
#endif

// feed test
#if MAIN == 3
void app_main(void)
{
   xTaskCreate(feed_task, "Feeder", 4*1024, NULL, 5, NULL);
   return;
}
#endif

#if MAIN == 4
void app_main(void)
{
   xTaskCreate(horz_home_task, "Horz Homing", 4*1024, NULL, 5, NULL);
   ESP_LOGI(TAG, "Horizontal homing done");
   return;
}
#endif

// Unidirectional control (propulsino and feed)
#if MAIN == 5
void app_main(void)
{
    horz_stepper_init();
    horz_driver_enable();
    int step_count = 0;
    uint32_t sleep = pdMS_TO_TICKS(1);
    ESP_LOGI(TAG, "Sleep is %d ticks", sleep);
    while (step_count < 6000) {
        ESP_LOGI(TAG, "Step %d", step_count);
        gpio_set_level(HORZ_STEP_STEP_GPIO, 1);
        esp_rom_delay_us(HORZ_STEP_DELAY_US); 
        gpio_set_level(HORZ_STEP_STEP_GPIO, 0);
        esp_rom_delay_us(HORZ_STEP_DELAY_US); 
        step_count++;
    }   
    horz_driver_disable();    
    ESP_LOGI(TAG, "Sleep was %d ticks", sleep);
}
#endif