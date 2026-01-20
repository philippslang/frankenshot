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
#define ELEV_BOTTOM_PWM_GPIO    21
#define ELEV_BOTTOM_EN_GPIO     20
#define ELEV_TOP_PWM_GPIO       19
#define ELEV_TOP_EN_GPIO        18

#define FEED_SWITCH_GPIO        3    // NC switch input
#define HORZ_STEP_SWITCH_GPIO   2
#define ELEV_STEP_SWITCH_GPIO   11

#define MANUAL_TEST_GPIO        10

#define HORZ_STEP_EN_GPIO       6
#define HORZ_STEP_STEP_GPIO     4
#define HORZ_STEP_DIR_GPIO      5

  
/* ===== PWM CONFIG ===== */
#define PWM_LEDC_TIMER       LEDC_TIMER_0
#define PWM_LEDC_MODE        LEDC_LOW_SPEED_MODE
#define PWM_LEDC_DUTY_RES    LEDC_TIMER_8_BIT      // 0–255
#define PWM_LEDC_FREQUENCY   20000                 // 20 kHz

#define FEED_PWM_LOAD         90                    // ~40%
#define ELEV_PWM_LOAD         100   

#define FEED_LEDC_CHANNEL          LEDC_CHANNEL_0
#define ELEV_BOTTOM_LEDC_CHANNEL   LEDC_CHANNEL_1
#define ELEV_TOP_LEDC_CHANNEL      LEDC_CHANNEL_2

#define ELEV_MOTOR_MAX_DUTY   200   // max 255 for 8-bit resolution
#define ELEV_SPIN_DIVISOR     25   // higher = weaker effect

/* ===== STEPPER CONFIG ===== */
#define HORZ_STEP_DELAY_US     1000   // ping delay, smaller = faster, 1000 safe, limited by Hz

/* ===== SWITCH CONFIG ===== */
#define DEBOUNCE_COUNT    3
#define FEED_TIMEOUT_MS   10000   // jam detection
#define FEED_POLL_MS      10

static const char *HTAG = "HORZ";

# define MAIN 1

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
static int32_t horz_tmp_step_counter = 0;
// steps for full travel cycle
// find with iterations of horz_init only
static int32_t horz_total_steps = 2800; 
static int32_t horz_target_steps = 0;
static int32_t horz_dir = 0;

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


static void limit_switch_init(uint32_t gpio_num)
{
    gpio_config_t io_conf = {
        .pin_bit_mask = 1ULL << gpio_num,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
    };
    gpio_config(&io_conf);
}

static void feed_switch_init(void)
{
    limit_switch_init(FEED_SWITCH_GPIO);
}

static void pwm_init(gpio_num_t en_gpio, gpio_num_t pwm_gpio, gpio_num_t channel)
{
    /* Enable pin */
    gpio_config_t en_cfg = {
        .pin_bit_mask = 1ULL << en_gpio,
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&en_cfg);
    gpio_set_level(en_gpio, 1); // Enable BTS7960

    /* LEDC timer config */
    ledc_timer_config_t timer_cfg = {
        .speed_mode       = PWM_LEDC_MODE,
        .timer_num        = PWM_LEDC_TIMER,
        .duty_resolution  = PWM_LEDC_DUTY_RES,
        .freq_hz          = PWM_LEDC_FREQUENCY,
        .clk_cfg          = LEDC_AUTO_CLK,
    };
    ESP_ERROR_CHECK(ledc_timer_config(&timer_cfg));

    /* LEDC channel config */
    ledc_channel_config_t channel_cfg = {
        .gpio_num   = pwm_gpio,
        .speed_mode = PWM_LEDC_MODE,
        .channel    = channel,
        .timer_sel  = PWM_LEDC_MODE,
        .duty       = 0,
        .hpoint     = 0,
    };
    ESP_ERROR_CHECK(ledc_channel_config(&channel_cfg));

    ESP_LOGI(TAG, "PWM initialized");
}

static void pwm_start(gpio_num_t channel, uint32_t duty)
{
    esp_err_t ret;
    ret = ledc_set_duty(PWM_LEDC_MODE, channel, duty);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "pwm_start ledc_set_duty failed: %s", esp_err_to_name(ret));
    }
    ret = ledc_update_duty(PWM_LEDC_MODE, channel);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "pwm_start ledc_update_duty failed: %s", esp_err_to_name(ret));
    }
    ESP_LOGI(TAG, "pwm_start: duty=%d on channel %d", duty, channel);
}

static void pwm_stop(gpio_num_t channel)
{
    ledc_set_duty(PWM_LEDC_MODE, channel, 0);
    ledc_update_duty(PWM_LEDC_MODE, channel);
}


static void feed_motor_pwm_init(void)
{
    pwm_init(FEED_EN_GPIO, FEED_PWM_GPIO, FEED_LEDC_CHANNEL);
}

static void feed_motor_start(void)
{
    pwm_start(FEED_LEDC_CHANNEL, FEED_PWM_LOAD);
}

static void feed_motor_stop(void)
{
    pwm_stop(FEED_LEDC_CHANNEL);
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


static void elev_bottom_motor_pwm_init(void)
{
    pwm_init(ELEV_BOTTOM_EN_GPIO, ELEV_BOTTOM_PWM_GPIO, ELEV_BOTTOM_LEDC_CHANNEL);
}

static void elev_bottom_motor_start(uint32_t duty)
{
    pwm_start(ELEV_BOTTOM_LEDC_CHANNEL, duty);
}

static void elev_bottom_motor_stop(void)
{
    pwm_stop(ELEV_BOTTOM_LEDC_CHANNEL);
}

static void elev_top_motor_pwm_init(void)
{
    pwm_init(ELEV_TOP_EN_GPIO, ELEV_TOP_PWM_GPIO, ELEV_TOP_LEDC_CHANNEL);
}   

static void elev_top_motor_start(uint32_t duty)
{
    pwm_start(ELEV_TOP_LEDC_CHANNEL, duty);
}

static void elev_top_motor_stop(void)
{
    pwm_stop(ELEV_TOP_LEDC_CHANNEL);
}

// api
static void elev_motors_init(void)
{
    elev_top_motor_pwm_init();
    elev_bottom_motor_pwm_init();
}

// api
static void elev_motors_stop(void)
{
    elev_top_motor_stop();
    elev_bottom_motor_stop();
}

// api
static void elev_motors_start(uint32_t speed, uint32_t spin)
{
    if (spin < 0 || spin > 10) {
        ESP_LOGE(TAG, "elev_motors_start: invalid spin %d", spin);
        return;
    }
    if (speed < 1 || speed > 10) {
        ESP_LOGE(TAG, "elev_motors_start: invalid speed %d", speed);
        return;
    }

    
    int32_t base = (speed * ELEV_MOTOR_MAX_DUTY) / 10;

    /* Centered spin: -5 … +5 */
    int32_t spin_offset = (int32_t)spin - 5;

    int32_t delta = (base * spin_offset) / ELEV_SPIN_DIVISOR;

    int32_t top_duty    = base + delta;
    int32_t bottom_duty = base - delta;

    /* Clamp */
    if (top_duty > ELEV_MOTOR_MAX_DUTY) top_duty = ELEV_MOTOR_MAX_DUTY;
    if (top_duty < 0) top_duty = 0;

    if (bottom_duty > ELEV_MOTOR_MAX_DUTY) bottom_duty = ELEV_MOTOR_MAX_DUTY;
    if (bottom_duty < 0) bottom_duty = 0;

    ESP_LOGI(TAG,
        "Elev motors: speed=%lu spin=%lu base=%ld offset=%ld top=%ld bottom=%ld",
        speed, spin, base, spin_offset, top_duty, bottom_duty
    );

    elev_top_motor_start((uint32_t)top_duty);
    elev_bottom_motor_start((uint32_t)bottom_duty);
}


static bool horz_switch_pressed(void)
{
    return debounce_switch(HORZ_STEP_SWITCH_GPIO);
}

static void horz_switch_init(void)
{
    limit_switch_init(HORZ_STEP_SWITCH_GPIO);
}

static inline void horz_driver_enable(void)
{
    gpio_set_level(HORZ_STEP_EN_GPIO, 0); // active LOW
}

static inline void horz_driver_disable(void)
{
    gpio_set_level(HORZ_STEP_EN_GPIO, 1);
}

static void horz_clockwise(void)
{
    horz_dir = 0;
    gpio_set_level(HORZ_STEP_DIR_GPIO, horz_dir);
}

static void horz_counterclockwise(void)
{
    horz_dir = 1;
    gpio_set_level(HORZ_STEP_DIR_GPIO, horz_dir);
}

static void horz_count_step(void)
{
    if (horz_dir == 0) {
        horz_step_counter++;
    } else {
        horz_step_counter--;
    }
}

static void horz_stepper_init(void)
{
    gpio_config_t io_conf = {
        .mode = GPIO_MODE_OUTPUT,
        .pin_bit_mask =
            (1ULL << HORZ_STEP_STEP_GPIO) |
            (1ULL << HORZ_STEP_DIR_GPIO)  |
            (1ULL << HORZ_STEP_EN_GPIO),
    };
    gpio_config(&io_conf);

    horz_driver_disable();
    horz_clockwise();
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
    ESP_LOGI(HTAG, "Move to position %ld", pos);
    if (horz_axis_state != AXIS_READY) 
    {
        ESP_LOGI(HTAG, "Axis not ready, cannot move");
        return;
    }
    if (pos > horz_total_steps || pos < 0) {
        ESP_LOGI(HTAG, "Requested position %ld out of range (%ld)", pos, horz_total_steps);
        return;
    }
    if (pos < horz_step_counter) {
        horz_counterclockwise();
    } else {
        horz_clockwise();
    }

    horz_driver_enable();
    horz_target_steps = pos;
    horz_axis_state = AXIS_MOVING;
}

static void horz_moving(void) {
    horz_step_pulse();
    horz_count_step();

    if (horz_step_counter >= horz_total_steps){
        horz_step_counter = horz_total_steps;
        horz_axis_state = AXIS_READY;
        ESP_LOGI(HTAG, "Reached max limit");
        horz_driver_disable();
    }

    if (horz_step_counter <= 0){
        horz_step_counter = 0;
        horz_axis_state = AXIS_READY;
        ESP_LOGI(HTAG, "Reached min limit");
        horz_driver_disable();
    }

    if (horz_step_counter == horz_target_steps) {
        ESP_LOGI(HTAG, "Target reached");
        horz_driver_disable();
        horz_axis_state = AXIS_READY;
    }
}

static void horz_init(void *arg)
{
    horz_stepper_init();
    horz_switch_init();
    horz_driver_enable();
    ESP_LOGI(HTAG, "Horizontal startup");
    ESP_LOGI(HTAG, "Finding home");
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
                horz_axis_state = AXIS_READY;
                ESP_LOGI(HTAG, "Moving to center");
                horz_move_to(horz_total_steps/2);
            }
            break;
        
        case AXIS_MOVING:
            horz_moving();
            break;
        
        case AXIS_READY:
            ESP_LOGI(HTAG, "Horizontal startup done");
            return;

        default:
            ESP_LOGE(HTAG, "Unexpected state %d", horz_axis_state);
        }
    }
}

static void horz_task(void *arg)
{
    ESP_LOGI(HTAG, "Waiting for horizontal request");

    while (1) {
        bool sw = horz_switch_pressed();

        switch (horz_axis_state) {
        case AXIS_MOVING:
            horz_moving();
            break;

        case AXIS_READY:
            vTaskDelay(pdMS_TO_TICKS(100));
            break;
        
        default:
            vTaskDelay(pdMS_TO_TICKS(100));
            ESP_LOGI(HTAG, "Unexpected state %d", horz_axis_state);
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
    elev_motors_init();
    // feed_motor_pwm_init();

    while (1) {
        ESP_LOGI(TAG, "Motor ON");
        elev_motors_start(5, 7);
        // feed_motor_start();
        vTaskDelay(pdMS_TO_TICKS(8000));

        ESP_LOGI(TAG, "Motor OFF");
        elev_motors_stop();
        // feed_motor_stop();
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

// Find horizontal range
#if MAIN == 4
void app_main(void)
{
   horz_init(NULL);
   vTaskDelay(pdMS_TO_TICKS(10));
   ESP_LOGI(TAG, "Horizontal homing done");
   xTaskCreate(horz_task, "Horz direction", 4*1024, NULL, 5, NULL);
//    horz_move_to(2200);
   horz_move_to(600);
   return;
}
#endif

