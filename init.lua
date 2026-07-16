-- EMON — GregTech energy monitor for OpenComputers.
-- Entry point: run from the OpenOS shell (`cd /home/EMON && init`).

-- Prepend rather than append so our own modules win against same-named OpenOS
-- libraries. `?/init.lua` is what makes require("core.sources") resolve to
-- core/sources/init.lua.
package.path = "/home/EMON/?.lua;/home/EMON/?/init.lua;" .. package.path

local component = require("component")
local computer = require("computer")
local event = require("event")
local term = require("term")

local ar = require("lib.graphics.ar")
local graphics = require("lib.graphics.graphics")

local configuration = require("config")
local monitorLib = require("core.monitor")
local sources = require("core.sources")

local app = require("ui.app")
local arHud = require("ar")

local function setupScreen(config)
    if not component.isAvailable("gpu") or not component.isAvailable("screen") then
        return false
    end
    local gpu = component.gpu
    local maxWidth, maxHeight = gpu.maxResolution()
    local width = math.min(config.resolution.x or maxWidth, maxWidth)
    local height = math.min(config.resolution.y or maxHeight, maxHeight)
    gpu.setResolution(width, height)
    gpu.setBackground(config.theme.background)
    gpu.fill(1, 1, width, height, " ")
    graphics.setContext(nil)
    return true
end

local function restoreScreen()
    if not component.isAvailable("gpu") then return end
    local gpu = component.gpu
    pcall(gpu.setBackground, 0x000000)
    pcall(gpu.setForeground, 0xFFFFFF)
    local width, height = gpu.getResolution()
    pcall(gpu.fill, 1, 1, width, height, " ")
    pcall(term.setCursor, 1, 1)
end

local function run()
    local config = configuration.load()
    ar.setLegacyScaling(config.legacyTextScaling)

    -- First run: adopt whatever is attached so the app is useful before the
    -- user has touched any settings.
    if #config.buffers == 0 then
        configuration.syncBuffers(config, sources.discover())
        configuration.save(config)
    end

    local hasScreen = setupScreen(config)
    local monitor = monitorLib.new(config)
    local hud = arHud.new(config)
    local application = app.new(monitor, config, hud)

    if not hasScreen then
        config.screen.enabled = false
    end

    while application.running do
        monitor:update()
        hud:update(monitor)

        if config.screen.enabled then
            application:draw()
        end

        -- The timeout doubles as the poll interval: the loop wakes either when
        -- the user touches the screen or when it is time to sample again.
        local signal = {event.pull(config.screen.pollInterval or 0.25)}
        local name = signal[1]
        if name == "touch" then
            application:onTouch(signal[3], signal[4])
        elseif name == "interrupted" then
            application.running = false
        elseif name == "component_added" or name == "component_removed" then
            -- A buffer was plugged in or pulled; refresh the known component list.
            configuration.syncBuffers(config, sources.discover())
        elseif name == "hud_click" or name == "hud_keyboard" or name == "glasses_on" then
            -- Input from the glasses themselves, so the wearer can switch source
            -- without walking back to the computer.
            hud:handleSignal(monitor, name, table.unpack(signal, 2))
            application.dirty = true
        end
    end

    hud:removeAll()
    restoreScreen()
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
    -- Leave the terminal usable, then surface the failure.
    restoreScreen()
    io.stderr:write("EMON crashed:\n" .. tostring(err) .. "\n")
    computer.beep(880, 0.2)
end
