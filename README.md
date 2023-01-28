# Crovvverter

This mod is a CV to Midi and Midi to CV converter for Crow.

Route midi messages from external devices into your modular system via the 4 crow outputs. There are various modes for processing different sets of midi messages.

## Installing

1. From your shell of choice, navigate to `\\norns.local\dust\code\`
2. Run `git clone https://github.com/JGuzak/crovvverter.git`
3. On Norns, navigate to `System > Mods` and enable `Crovvverter`.
4. Restart Norns and the mod will load.

## How to use crovvverter

Load a script of your choice via `Select >`. By loading a script, the mod will load up and add parameters in the `Parameters > Edit` menu.

Parameter list

| Item | Description |
| ---- | ----------- |
| `Reset Crow` | reruns crow.init(), useful if crow gets into a funky state. |
| `Refresh midi devices` | manually refreshes the list of midi devices. |
| `CV -> Midi` | Settings for generating midi messages from CV inputs on crow. |
| `Midi -> CV` | Settings for generating CV from midi messages. |
| `I^2C` | Settings for controlling I^2C devices from midi messages. |

## Upcoming Plans/Ideas

### Alternative CV Output Modes

Plumbing for these modes is already complete. Next step is to implement midi callbacks for the following parameters:

* `Midi -> CV > CV Output = 2 voices`
* `Midi -> CV > CV Output = 4 pitches`
* `Midi -> CV > CV Output = 4 gates`
* `Midi -> CV > CV Output = 4 CCs`

### I^2C extensions

* Just Friends
* W/ maybe?

### Script Midi Loopback

Virtual midi device that exists in the normal midi device list. It would enable sending midi from the active script to the midi -> cv side of crovvverter

## Bugs

If you find a bug, please create an issue on github and include the things that happened right before the issue and a maiden log for troubleshooting purposes.

### Known Issues

* Parameter `CV -> Midi > CV Input Mode = CC` does not output midi.
* Parameter `Midi -> CV > CV Output = 1 voice + cc 3 | 4` does not produce CC messages.
