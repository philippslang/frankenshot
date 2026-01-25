#include "common.h"
#include "driver/gpio.h"
#include "led_strip.h"

#define BLINK_GPIO 38

static uint8_t s_led_state = 0;

static led_strip_handle_t led_strip;


void led_off(void) {
    led_strip_clear(led_strip);
    s_led_state = 0;
    ESP_LOGI("LED", "led turned off");
}

void led_on(void) {
    led_strip_set_pixel(led_strip, 0, 0, 0, 10);
    led_strip_refresh(led_strip);
    s_led_state = 1;
    ESP_LOGI("LED", "led turned on");
}

void led_init(void)
{
    /* LED strip initialization with the GPIO and pixels number*/
    led_strip_config_t strip_config = {
        .strip_gpio_num = BLINK_GPIO,
        .max_leds = 1, // at least one LED on board
    };
    led_strip_rmt_config_t rmt_config = {
        .resolution_hz = 10 * 1000 * 1000, // 10MHz
        .flags.with_dma = false,
    };
    ESP_ERROR_CHECK(led_strip_new_rmt_device(&strip_config, &rmt_config, &led_strip));
    /* Set all LED off to clear all pixels */
    led_strip_clear(led_strip);
    ESP_LOGI("LED", "initialized LED strip on %d", BLINK_GPIO);
}

