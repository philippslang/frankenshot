This is custom firmware for a spinshot tennis ball machine. It exposes motor controll via bluetooth.

The esp board only has current state and makes it happen. The state is split into current program and current state. The program is a list of configurations
- time between balls, e.g. seconds
- velocity, e.g. percentage
- spin, pos/neg factor
- height, e.g. percentage
- horizontal, pos/neg factor
The current state is 
- feeding, boolean, false is paused
- next configuration number, number
In terms of ble characterisitics, the program and current state are characteristics. Another characteristic is manual feed.
- current config (inidcation, read)
- program, multiple of five numbers to represent configs (read/write)
- feeding (indication, read/write)
- manual feed, boolean command (write)
On start-up some default state will be used, with feeding set to on. After ball fed the esp will start countdown of that config timer, move on to the next configuration in the list, get to this position, and after countdown expires move on again, or wrap back to the first one if last. On manual feed sets state to pause and triggers a ball feed, sets manual feed back to false.

CONFIG_ESP_TASK_WDT_TIMEOUT_S=45
CONFIG_BLINK_GPIO=38

