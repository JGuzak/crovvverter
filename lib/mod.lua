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
local cvOutputCallback = nil
local i2cOutputCallback = nil

-- Midi to CV components
local maxCvVoices = 1
local midiSourceNoteQueue = {}
local lastTriggeredVoice = 0

-- CV to Midi components
local cvNote = 1
local cvGate = false
local lastSentMidiNote = nil
local lastDestinationChannel = nil
local lastSentCcMessages = { 1, 1 }
local notesInScale = { 0 }

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
function SetCvInputMode() end
function SendMidiAllNoteAllChannelOff() end

function SetCvOutputState() end
function SetMidiSourceDevice() end
function SetCvAndI2cOutputCallbacks() end
function SetQuantizedScale() end
function SetGateMode() end
function CrowResetOutputs() end

function InitParams()
  params:add_separator("crovvverter", "Crovvverter")
  params:add {id = "crow_reconnect", name = "Reset Crow", type = "trigger", action = function(x) CrowInit() end}
  params:add {id = "refresh_midi_devices", name = "Refresh midi devices", type = "trigger", action = function(x) RefreshMidiDevices() end}

  -------------------------------------
  -- CV to Midi params
  params:add_group("cv_to_midi", "CV -> Midi", 8)
  params:add {id = "cv_to_midi_enabled", name = "Enabled", type = "option", options = { "Yes", "No" }, action = function(x) SetCvInputState() end}
  params:add {id = "cv_to_midi_destination", name = "Destination", type = "option", options = midiDeviceNames, default = 1, action = function(x) SetCvInputState() end}
  params:add {id = "cv_to_midi_channel", name = "Midi Channel", type = "number", min = 1, max = 16, default = 1, action = function(x) end}
  params:add {id = "cv_to_midi_mode", name = "CV Input Mode", type = "option", options = { "Pitch | Gate", "CC" }, action = function(x) SetCvInputState() end}
  params:add_control("cv_to_midi_gate_threshold", "Gate threshold", controlspec.new(-5, 10, "lin", 0.1, 5, "v"))
  params:add {id = "cv_to_midi_cc_1", name = "CC 1", type = "number", min = 0, max = 127, default = 0, action = function(x) end}
  params:add {id = "cv_to_midi_cc_2", name = "CC 2", type = "number", min = 0, max = 127, default = 1, action = function(x) end}
  params:add {id = "cv_to_midi_panic", name = "Panic", type = "trigger", action = function(x) SendMidiAllNoteAllChannelOff() end}

  -------------------------------------
  -- Midi to CV params
  params:add_group("midi_to_cv", "Midi -> CV", 15)
  params:add {id = "midi_to_cv_enabled", name = "Enabled", type = "option", options = { "Yes", "No" }, action = function(x) SetCvOutputState() end}
  params:add {id = "midi_to_cv_source", name = "Source", type = "option", options = midiDeviceNames, default = 1, action = function(x) SetCvOutputState() end}
  params:add {id = "midi_to_cv_channel", name = "Channel", type = "number", min = 1, max = 16, default = 1, action = function(x) end}
  params:add {id = "midi_to_cv_mode", name = "CV Output", type = "option", options = { "1 voice + cc 3 | 4", "2 voices", "4 pitches", "4 gates", "4 CCs", "None" }, action = function(x) SetCvOutputState() end}
  
  params:add {id = "midi_to_cv_cc_1", name = "CC 1", type = "number", min = 0, max = 127, default = 0, action = function(x) end}
  params:add {id = "midi_to_cv_cc_2", name = "CC 2", type = "number", min = 0, max = 127, default = 1, action = function(x) end}
  params:add {id = "midi_to_cv_cc_3", name = "CC 3", type = "number", min = 0, max = 127, default = 2, action = function(x) end}
  params:add {id = "midi_to_cv_cc_4", name = "CC 4", type = "number", min = 0, max = 127, default = 3, action = function(x) end}
  
  -- TODO: Add envelope class for gate outputs
  params:add {id = "midi_to_cv_gate_mode", name = "Gate mode", type = "option", options = { "Gate", "Trigger", "ADSR", "ADR" }, action = function(x) SetGateMode() end}
  params:add {id = "midi_to_cv_attack", name = "Attack", type = "control", controlspec = controlspec.new(0.5, 2000, "lin", 0.001, 1, "ms"), action = function(x) end}
  params:add {id = "midi_to_cv_decay", name = "Decay", type = "control", controlspec = controlspec.new(0.5, 2000, "lin", 0.001, 200, "ms"), action = function(x) end}
  params:add {id = "midi_to_cv_sustain", name = "Sustain", type = "control", controlspec = controlspec.new(-60, 0, "lin", 0.01, -20, "dB"), action = function(x) end}
  params:add {id = "midi_to_cv_release", name = "Release", type = "control", controlspec = controlspec.new(0.5, 2000, "lin", 0.001, 50, "ms"), action = function(x) end}

  params:add {id = "midi_to_cv_oct_offset", name = "Oct Offset", type = "control", controlspec = controlspec.new(-60, 0, "lin", 12, -48, "semitones"), action = function(x) end}
  params:add {id = "midi_to_cv_panic", name = "Panic", type = "trigger", action = function(x) CrowResetOutputs() end}

  -------------------------------------
  -- I^2C params
  params:add_group("i^2c", "I^2C", 1)
  params:add {id = "i2c_device", name = "Device", type = "option", options = { "None", "Just Friends", "W/" }, action = function(x) SetI2CMode() end}

  -------------------------------------
  -- Quantize Notes params
  params:add_group("crovvverter_quantize_notes", "Quantize Notes", 3)
  params:add {id = "crovvverter_quantizePitch", name = "Quantize Pitch to Scale", type = "option", options = { "No", "Yes" }, action = function(x) end}
  params:add {id = "crovvverter_root_note", name = "Root Note", type = "option", options = noteNames, action = function(x) SetQuantizedScale() end}
  params:add {id = "crovvverter_scale", name = "Scale", type = "option", options = { "major", "minor", "dorian" }, action = function(x) SetQuantizedScale() end}

  params:show("cv_to_midi")
  params:show("midi_to_cv")
  params:show("i^2c")
  params:show("crovvverter_quantize_notes")

  params:bang()
  params:print()
  _menu.rebuild_params()
end

-------------------------------------------
-- Global Quantize param action callbacks
function SetQuantizedScale()
  local note = params:string("crovvverter_root_note")
  local scale = params:string("scale")

  notesInScale = MusicUtil.generate_scale(params:get("crovvverter_root_note") % 12, scale)
end

-------------------------------------------
-- CV to Midi param action callbacks
function SetCvInputState()
  if params:string("cv_to_midi_enabled") == "Yes" then
    SetMidiDestinationDevice()
    SetCvInputMode()
  else
    crow.input[1].mode("None")
    crow.input[2].mode("None")

    if midiDestinationDevice ~= nil then
      midiDestinationDevice.event = nil
    end

    midiDestinationDevice = nil
  end
end

function SetMidiDestinationDevice()
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
    end

    print("Failed to set "..destinationDeviceName.." midi source device")

    if midiDestinationDevice ~= nil then
      midiDestinationDevice.event = nil
    end

    midiDestinationDevice = nil
  end
end

function SetCvInputMode()
  if params:string("cv_to_midi_mode") == "Pitch | Gate" then
    crow.input[1].stream = ProcessPitchCv
    crow.input[2].stream = ProcessGateCv
    crow.input[1].mode("stream", 0.001, 0.01, "both")
    crow.input[2].mode("stream", 0.001, 0.01, "both")
  else
    crow.input[1].stream = ProcessCc1Cv
    crow.input[2].stream = ProcessCc2Cv
    crow.input[1].mode("stream", 0.01, 0.1, "both")
    crow.input[2].mode("stream", 0.01, 0.1, "both")
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
-- CV/Midi callbacks
-- TODO: add quantized scales
function QuantizeNoteToScale(note)
  return MusicUtil.snap_note_to_array(note, notesInScale)
end

-------------------------------------------
-- CV to Midi callbacks
function ProcessPitchCv(voltage)
  if cvNote < 0 then
    cvNote = 0
  end

  cvNote = util.round(voltage / 0.0833, 1.0)

  -- if params:string("crovvverter_quantizePitch") == "Yes" then
  --   cvNote = QuantizeNoteToScale(cvNote)
  -- end
end

function ProcessGateCv(voltage)
  if cvGate == false and voltage > params:get("cv_to_midi_gate_threshold") then
    print("note "..cvNote.." on")
    cvGate = true

    if midiDestinationDevice ~= nil then
      midiDestinationDevice:note_on(cvNote, 100, params:get("cv_to_midi_channel"))
    end

    lastSentMidiNote = cvNote
    lastDestinationChannel = params:get("cv_to_midi_channel")
  elseif cvGate == true and voltage <= params:get("cv_to_midi_gate_threshold") then
    print("note "..lastSentMidiNote.." off")
    cvGate = false

    if midiDestinationDevice ~= nil then
      midiDestinationDevice:note_off(lastSentMidiNote, 100, lastDestinationChannel)
    end

    lastSentMidiNote = nil
    lastDestinationChannel = nil
  end
end

-- TODO: Make this cleaner, condense into one ProcessCcCv function.
function ProcessCc1Cv(voltage)
  if midiDestinationDevice == nil then
    return
  end

  local inputVal = util.round(util.linlin(0.0, 10.0, 0, 127, voltage), 1)
  if lastSentCcMessages[1] ~= inputVal then
    midiDestinationDevice.cc(params:string("cv_to_midi_cc_1"), inputVal, params:string("cv_to_midi_channel"))
    lastSentCcMessages[1] = inputVal
  end
end

function ProcessCc2Cv(voltage)
  if midiDestinationDevice == nil then
    return
  end

  local inputVal = util.round(util.linlin(0.0, 10.0, 0, 127, voltage), 1)
  if lastSentCcMessages[2] ~= inputVal then
    midiDestinationDevice.cc(params:string("cv_to_midi_cc_2"), inputVal, params:string("cv_to_midi_channel"))
    lastSentCcMessages[2] = inputVal
  end
end

-------------------------------------------
-- Midi to CV callbacks
function SetCvOutputState()
  if params:string("midi_to_cv_enabled") == "Yes" then
    SetMidiSourceDevice()

    if midiSourceDevice == nil then
      print("Failed to set CV output state, midi source device is nil")
      return
    end
  
    SetCvOutputMode()
    -- SetI2CMode()
    CrowResetOutputs()

    -- not sure how to bind both cv and i2c output callbacks to midi source events
    -- midiSourceDevice.event = function(x)
    --   -- attach CV output callback
    --   if cvOutputCallback ~= nil then
    --     print("trigger cv output callback")
    --     cvOutputCallback(x)
    --   end
  
    --   -- attach i2c output callback
    --   if i2cOutputCallback ~= nil then
    --     i2cOutputCallback(x)
    --   end
    -- end
  else
    if midiSourceDevice ~= nil then
      midiSourceDevice.event = nil
    end

    midiSourceDevice = nil
  end
end

function SetMidiSourceDevice()
  -- RefreshMidiDevices()
  for i in pairs(midiDevices) do
    local formattedDeviceName = i..": "..util.trim_string_to_width(midiDevices[i].name, 55)
    local sourceDeviceName = params:string("midi_to_cv_source")
    if formattedDeviceName:find(sourceDeviceName) then

      -- TODO: Address dangling midi note on messages before switching source device
      if midiSourceDevice ~= nil then
      end

      print("switched midi source device to "..sourceDeviceName)
      midiSourceDevice = midi.connect(i)
      break
    end

    print("Failed to set "..sourceDeviceName.." midi source device")

    if midiSourceDevice ~= nil then
      midiSourceDevice.event = nil
    end

    midiSourceDevice = nil
  end
end

function SetGateMode()
end

-------------------------------------------
-- Callbacks for processing midi notes
function ProcessMidiToCv1Voice(data)
  local msg = midi.to_msg(data)
  if msg.ch ~= params:get("midi_to_cv_channel") then
    return
  end

  if msg.type:find("note") then
    local midiOctOffset = params:get("midi_to_cv_oct_offset")
    local noteCv = util.linlin(0, 120, 0, 10, msg.note + midiOctOffset)
    crow.output[1].volts = noteCv

    if msg.type:find("on") then
      crow.output[2].volts = 5
      print(msg.type.." "..msg.note.. " "..msg.ch)
    else
      crow.output[2].volts = 0
      print(msg.type.." "..msg.note.. " "..msg.ch)
    end
  elseif msg.type == "cc" then
    if msg.cc == params:get("midi_to_cv_cc_3") then
      print("cc: "..msg.cc.." val: "..msg.val)
      crow.output[3].volts = util.linlin(0, 127, 0, 5, 0.001, msg.val)
    elseif msg.cc == params:get("midi_to_cv_cc_4") then
      print("cc: "..msg.cc.." val: "..msg.val)
      crow.output[4].volts = util.linlin(0, 127, 0, 5, 0.001, msg.val)
    end
  end
end

-- TODO: Add 2 voices mode
function ProcessMidiToCv2Voices(data)
  local msg = midi.to_msg(data)
  if msg.ch ~= params:get("midi_to_cv_channel") then
    return
  end

  if msg.type:find("on") then
    table.insert(midiSourceNoteQueue, msg)
  elseif msg.type:find("off") then
    local siblingNoteMessage = msg
    siblingNoteMessage.type = "note_on"
    if tabUtil.contains(midiSourceNoteQueue, siblingNoteMessage) then
      table.remove(midiSourceNoteQueue, siblingNoteMessage)
      print("found and removed note from midiSourceNoteQueue")
    end
  end

  if lastTriggeredVoice <= maxCvVoices then
    lastTriggeredVoice = 0
  end
end

-- TODO: Add 4 pitches mode
function ProcessMidiToCv4Pitches(data)
end

-- TODO: Add 4 gates mode
function ProcessMidiToCv4Gates(data)
end

-- TODO: Add CC output mode
function ProcessMidiToCv4Ccs(data)
end

function SetCvOutputMode()
  -- identify cv output callback
  if midiSourceDevice == nil then
    print("Failed to set CV output mode midi source device is nil")
    return
  end

  local cvOutputMode = params:string("midi_to_cv_mode")
  cvOutputCallback = nil
  if cvOutputMode == "1 voice + cc 3 | 4" then
    maxCvVoices = 1
    midiSourceDevice.event = ProcessMidiToCv1Voice
    if midiSourceDevice.event == nil then
      print("failed to set cv output callback")
    end
  elseif cvOutputMode == "2 voices" then
    maxCvVoices = 2
    midiSourceDevice.event = ProcessMidiToCv2Voices
  elseif cvOutputMode == "4 pitches" then
    maxCvVoices = 4
    midiSourceDevice.event = ProcessMidiToCv4Pitches
  elseif cvOutputMode == "4 gates" then
    maxCvVoices = 4
    midiSourceDevice.event = ProcessMidiToCv4Gates
  elseif cvOutputMode == "4 CCs" then
    maxCvVoices = 4
    midiSourceDevice.event = ProcessMidiToCv4Ccs
  elseif cvOutputMode == "None" then
    midiSourceDevice.event = nil
  end
end

-------------------------------------------
-- I2C callbacks
function SetI2CMode()
  local i2cMode = params:string("i2c_device")
  i2cOutputCallback = nil
  if i2cMode == "Just Friends" then
    crow.ii.pullup(true)
    crow.ii.jf.mode(1)
  elseif i2cMode == "W/" then
    -- crow.ii.pullup(true)
    -- crow.ii.
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

  SetCvOutputState()
  SetCvInputState()
end)