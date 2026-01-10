# frankenshot

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