-- Midi Croverter
--
-- Converts midi to cv and 
-- cv to midi
--
-- Author: Jordan Guzak

local midi = require "midi"
local mod = require 'core/mods'
local MusicUtil = require "musicutil"
local util = require 'util'
local tabUtil = require "tabutil"

local noteNames = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B", "B#" }

-- Crow components
function CrowInit()
  crow.reset()
end

function CrowResetOutputs()
  crow.output[1].volts = 0
  crow.output[2].volts = 0
  crow.output[3].volts = 0
  crow.output[4].volts = 0
end

-- Midi components
local midiDevices = {}
local midiDeviceNames = {}
local midiDestinationDevice = nil
local midiSourceDevice = nil

-- Midi to CV components
local lastTriggeredVoice = 6

-- CV to Midi components
local cvNote = 1
local cvGate = false
local lastSentMidiNote = nil
local lastDestinationChannel = nil


function RefreshMidiDevices()
  midiDeviceNames = {}
  midiDevices = {}
  for i = 1, #midi.vports do
    midiDevices[i] = midi.connect(i)
    table.insert(midiDeviceNames, i..": "..util.trim_string_to_width(midiDevices[i].name, 55))
  end
  params:bang()
end

midi.add = function(dev) RefreshMidiDevices() end
midi.remove = function(dev) RefreshMidiDevices() end

-- Predefine param callback functions
function CrowInit() end
function SetCvInputState() end
function SetMidiDestinationDevice() end
function SendMidiAllNoteAllChannelOff() end
function CrowResetOutputs() end

function InitParams()
  params:add_separator("crovvverter", "Crovvverter")
  params:add {id = "crow_reconnect", name = "Reset Crow", type = "trigger", action = function(x) CrowInit() end}
  params:add {id = "refresh_midi_devices", name = "Refresh midi devices", type = "trigger", action = function(x) RefreshMidiDevices() end}

  -------------------------------------
  -- CV to Midi params
  params:add_group("cv_to_midi", "CV -> Midi/I2C", 3)
  -- params:add_group("cv_to_midi", "CV -> Midi/I2C", 7)
  params:add {id = "cv_input_enabled", name = "Enabled", type = "option", options = { "Yes", "No" }, action = function(x) SetCvInputState() end}
  -- params:add {id = "cv_to_midi_enabled", name = "Midi Enabled", type = "option", options = { "No", "Yes" }, action = function(x) SetMidiDestinationDevice()() end}
  -- params:add {id = "cv_to_midi_destination", name = "Midi Destination", type = "option", options = midiDeviceNames, default = 1, action = function(x) SetMidiDestinationDevice()() end}
  -- params:add {id = "cv_to_midi_channel", name = "Midi Channel", type = "number", min = 1, max = 16, default = 1, action = function(x) end}
  -- params:add {id = "cv_to_midi_panic", name = "Panic", type = "trigger", action = function(x) SendMidiAllNoteAllChannelOff() end}
  params:add {id = "cv_to_i2c_destination", name = "I2C Destination", type = "option", options = { "Just Friends", "None" }, action = function(x) SetI2CMode() end}
  params:add_control("cv_to_midi_gate_threshold", "Gate threshold", controlspec.new(-5, 10, "lin", 0.1, 5, "v"))

  params:show("cv_to_midi")

  params:bang()
  params:print()
  _menu.rebuild_params()
end

-------------------------------------------
-- CV to Midi param action callbacks
function SetCvInputState()
  if params:string("cv_input_enabled") == "Yes" then
    -- attach callbacks
    crow.input[1].stream = ProcessPitchCv
    crow.input[2].stream = ProcessGateCv
    crow.input[1].mode("stream", 0.001, 0.01, "both")
    crow.input[2].mode("stream", 0.001, 0.01, "both")
  else
    crow.input[1].mode("None")
    crow.input[2].mode("None")
  end
end

function SetMidiDestinationDevice()
  if params:string("cv_to_midi_enabled") == "Yes" then
    -- RefreshMidiDevices()
    for i in pairs(midiDevices) do
      local formattedDeviceName = i..": "..util.trim_string_to_width(midiDevices[i].name, 55)
      local destinationDeviceName = params:string("cv_to_midi_destination")
      if destinationDeviceName:find(formattedDeviceName) then

        if midiDestinationDevice ~= nil then
          -- kill any dangling note on messages before switching devices
          if lastSentMidiNote ~= nil and lastDestinationChannel ~= nil then
            midiDestinationDevice:note_off(lastSentMidiNote, 100, lastDestinationChannel)
            lastSentMidiNote = nil
            lastDestinationChannel = nil
          end
        end

        print("switched midi destination device to "..destinationDeviceName)
        midiDestinationDevice = midi.connect(i)
        break
      else
        print("Failed to set "..destinationDeviceName.." midi source device")

        if midiDestinationDevice ~= nil then
          midiDestinationDevice.event = nil
        end
  
        midiDestinationDevice = nil
      end
    end
  else
    if midiDestinationDevice ~= nil then
      midiDestinationDevice.event = nil
    end

    midiDestinationDevice = nil
  end
end

function SendMidiAllNoteOff(channel)
  for note = 1, 120, 1 do
    if midiDestinationDevice ~= nil then
      midiDestinationDevice:note_off(note, 127, channel)
    end
  end
end

function SendMidiAllNoteAllChannelOff()
  for i = 1, 16, 1 do
    SendMidiAllNoteOff(i)
  end
end

-------------------------------------------
-- CV to Midi callbacks
function ProcessPitchCv(voltage)
  if cvNote < 0 then
    cvNote = 0
  end

  cvNote = util.round(voltage / 0.0833, 1.0)
end

function ProcessGateCv(voltage)
  if cvGate == false and voltage > params:get("cv_to_midi_gate_threshold") then
    print("note "..cvNote.." on")
    cvGate = true

    -- if midiDestinationDevice ~= nil then
    --   midiDestinationDevice:note_on(cvNote, 100, params:get("cv_to_midi_channel"))
    -- end

    local i2cDestination = params:string("cv_to_i2c_destination")
    if i2cDestination == "Just Friends" then
      lastTriggeredVoice = (lastTriggeredVoice) % 6 + 1
      print("last triggered voice: "..lastTriggeredVoice)
      crow.ii.jf.play_voice(lastTriggeredVoice, (cvNote - 60) / 12 + 1, 90)
      -- crow.ii.jf.vtrigger(lastTriggeredVoice, 90)
    end

    lastSentMidiNote = cvNote
    -- lastDestinationChannel = params:get("cv_to_midi_channel")

  elseif cvGate == true and voltage <= params:get("cv_to_midi_gate_threshold") then
    if lastSentMidiNote ~= nil then
      print("note "..lastSentMidiNote.." off")
    end
    cvGate = false

    local i2cDestination = params:string("cv_to_i2c_destination")
    if i2cDestination == "Just Friends" then
      crow.ii.jf.trigger(lastTriggeredVoice, 0)
    end
    -- if midiDestinationDevice ~= nil then
    --   midiDestinationDevice:note_off(lastSentMidiNote, 100, lastDestinationChannel)
    -- end

    lastSentMidiNote = nil
    lastDestinationChannel = nil
  end
end

-------------------------------------------
-- I2C callbacks
function SetI2CMode()
  local i2cMode = params:string("cv_to_i2c_destination")
  i2cOutputCallback = nil
  if i2cMode == "Just Friends" then
    crow.ii.pullup(false)
    crow.ii.jf.mode(0)
    crow.ii.pullup(true)
    crow.ii.jf.mode(1)
  elseif i2cMode == "None" then
    crow.ii.pullup(false)
  end
end

-------------------------------------------
-- Attach mod
mod.hook.register("script_pre_init", "crovvverter_script_pre_init", function()
  RefreshMidiDevices()
  InitParams()
  params:bang()
  _menu.rebuild_params()

  -- SetCvOutputState()
  SetCvInputState()
end)