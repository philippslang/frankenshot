The esp board only has current state and makes it happen. The state is split into current program and current state. The program is a list of configurations
- time between balls, e.g. seconds
- velocity, e.g. percentage
- spin, pos/neg factor
- height, e.g. percentage
- horizontal, pos/neg factor
After ball fed the esp will move on to the next configuration in the list, or wrap back to the first one if last. The current state is 
- feeding, boolean, false is paused. if this is on it will automatically go through the program with feeds, if off it will stay at last config
- next configuration number
In terms of ble characterisitics, the program and current state are characteristics. Another characteristic is manual feed, which sets state to pause and triggers a ball feed. So the characteristics are
- program, multiple of five numbers to represent configs (read/write)
- state, bool and number, can be two numbers (read/write)
- manual feed, bool (write)
On start-up some default state will be used, with feeding set to on.

The app will send state updates via ble, with each state field being a ble characteristic. This means the app will run programs, pause and start etc. The main screen of the app shows the current state and let's user manually adjust every characteristic