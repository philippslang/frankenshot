# frankenshot

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

The app will send state updates via ble, with each state field being a ble characteristic. This means the app will run programs, pause and start etc. The main screen of the app shows the current state and let's user manually adjust every characteristic

## firmware


### Characteristics info

 Characteristic details:
  - Properties: Read
  - Descriptor: "Configuration"
  - UUID: 01544f48-534e-454b-4e41-524601000000
  
  typedef struct {
    uint8_t speed;
    uint8_t height;
    uint8_t time_between_balls;
    uint8_t spin;
    uint8_t horizontal;
} frankenshot_config_t;

 Characteristic details:
  - Properties: Write
  - Descriptor: "Manual Feed"
  - UUID: 01544f48-534e-454b-4e41-524603000000
  
  Characteristic details:
  - Properties: Read/Write
  - Descriptor: "Program"
  - UUID: 01544f48-534e-454b-4e41-524604000000
  
  typedef struct {
      uint8_t id;
      uint8_t count;  /* number of configs in use (max 8) */
      frankenshot_config_t configs[8];
  } frankenshot_program_t;

  Data format:
  ┌────────┬───────────┬─────────────────────────────────────────────────────────────────────┐
  │ Offset │   Size    │                                Field                                │
  ├────────┼───────────┼─────────────────────────────────────────────────────────────────────┤
  │ 0      │ 1         │ id                                                                  │
  ├────────┼───────────┼─────────────────────────────────────────────────────────────────────┤
  │ 1      │ 1         │ count (0-8)                                                         │
  ├────────┼───────────┼─────────────────────────────────────────────────────────────────────┤
  │ 2+     │ count × 5 │ configs (each: speed, height, time_between_balls, spin, horizontal) │
  └────────┴───────────┴─────────────────────────────────────────────────────────────────────┘
  When reading, only the configs in use are sent (2 + count×5 bytes). When writing, the size must match exactly.

## app

A Flutter App to control a custom controller for a Spinshot tennis ball machnine. The controller has as state 
- the current configuration of the machine
    - speed, an integer from 0 to 10
    - spin, an integer from -5 to 5
    - height, an integer from 0 to 10
    - horizontal, an integer from -5 to 5
    - time between balls, a float from 1 to 20
    - a boolean feeding state which if true goes through the configurations, and can be set to false to pause the machine
    - an integer which indicates which item we're currently processing
- the configuration plan, which is a list of configurations (so each item has speed, spin, height, horizontal, and time between balls)

The user should be able to create configuration plans. Each configuration plan can be saved under a name. Each plan has a list of items of the configuration set of speed, spin, height, horizontal, and time between balls. On the main page, the names of all configutaration plans are visible, and the user can select one to run. On the main page the users sees the feeding state, can pause it, and if paused can do a manual feed. Next the users sees the current configuration. Then they see all configuration lists, can create a new one and select an existing one to run. The user should be able to pause and resume at any time, no matter the plan selection.

To install on phone, just do flutter run --release

## machine
propulsion: two high velocity 12V DC motors, plus/minus thick wires, one direction, BTS7960

feed: smaller 12V motor geared, plus/minus thinner wires, says sgmada dc geared motor, type TT-5412500-394M, DC 12V, no switches, one direction, BTS7960

horizontal and elevation: 2GN 12.5K gear head, 12V, four thinner wires, Bipolar Stepper Motor with an integrated Planetary Gearbox (the "gear head").
pairs are blue/red phase a and gree/black phase b, DRV8833 controller
horizontal: one directions with crank and slider of sorts. needs manual precalculation how many steps to move from left to right, then move until switch and then
move to center point using pre-calc. cyclic axis with a single index switch.
elevation: motor in both directions, single switch to indicate stop (lowest angle). need to move until switch hit, and then use manual pre-calculation of
how many steps to max, then divide by range to make move to elevation function
 
sensors: mechanical clicks, three wire limit switch, black blue red. our trigger logic is com+nc and com (to gnd) is black and nc (to gpio) is blue. this way
if we check like this
static inline bool feed_switch_triggered(void)
{
    return gpio_get_level(FEED_SWITCH_GPIO) == 1;
}
we get true if the switch is triggered AND if the wire is broken/disconnected and stop in either case, which is safe in our use case

## order
- female logic wires all colors

## todo
- don't stop propulsion during pause
- detect bluetooth disconnect in app
