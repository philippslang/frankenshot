#ifndef HEART_RATE_H
#define HEART_RATE_H

/* ESP APIs */
#include "esp_random.h"

#define MOCK_RATE_TASK_PERIOD (10000 / portTICK_PERIOD_MS)

uint8_t get_heart_rate(void);
void update_heart_rate(void);

#endif // HEART_RATE_H
