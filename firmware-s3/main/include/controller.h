#ifndef CONTROLLER_H
#define CONTROLLER_H

void elev_motors_init(void);
void steppers_init(void);
void horz_home(void);
void elev_home(void);
void feed_task(void *arg);
void elev_task(void *arg);
void horz_task(void *arg);
void horz_move_to_relative(uint32_t rel);
void elev_move_to_relative(uint32_t rel);
void elev_motors_start(uint32_t speed, uint32_t spin);
void elev_motors_stop(void);
void request_feed(void);



#endif // CONTROLLER_H
