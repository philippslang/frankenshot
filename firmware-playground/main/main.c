#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "controller.h"

void app_main(void)
{
    // these and only these is api
    elev_motors_init();
    vTaskDelay(pdMS_TO_TICKS(10));
    horz_home();
    vTaskDelay(pdMS_TO_TICKS(10));
    elev_stepper_home();
    vTaskDelay(pdMS_TO_TICKS(10));

    xTaskCreate(feed_task, "Feeder", 4*1024, NULL, 5, NULL);
    xTaskCreate(elev_task, "Elevation", 4*1024, NULL, 5, NULL);
    xTaskCreate(horz_task, "Horizontal", 4*1024, NULL, 5, NULL);

    vTaskDelay(pdMS_TO_TICKS(1000));
    horz_move_to_relative(7);
    vTaskDelay(pdMS_TO_TICKS(10));
    elev_motors_start(5, 5);
    vTaskDelay(pdMS_TO_TICKS(10000));
    elev_move_to_relative(5);
    vTaskDelay(pdMS_TO_TICKS(5000));
    request_feed();
    vTaskDelay(pdMS_TO_TICKS(10000));
    elev_motors_stop();
   return;
}
