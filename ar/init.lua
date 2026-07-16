-- AR HUD manager.
--
-- Owns one panel per pair of glasses, decides what each shows (a pinned view,
-- or a rotation when `cycle` is on), and handles input from the glasses so the
-- source can be switched without walking back to the computer.
--
-- Input comes from OCGlasses signals (mod version 1.6.1-GTNH):
--   glasses_on(user, width, height)   -- player put the glasses on
--   glasses_off(user)
--   hud_click(user, x, y, button)     -- click in the free-cursor overlay
--   hud_keyboard(user, character, key)
--
-- IMPORTANT: hud_click/hud_keyboard only fire while the free-cursor overlay is
-- open, and the keybind that opens it ("Free Cursor (Toggle)", category
-- openGlasses) ships UNBOUND. Without binding it, none of this input exists —
-- which is why the README calls it out.
--
-- Panels are rebuilt only when the settings that affect their geometry change.
-- A rebuild tears down and recreates every glasses object, so doing it per
-- frame would both flicker and leak.

local component = require("component")
local computer = require("computer")

local ar = require("lib.graphics.ar")
local screen = require("lib.utils.screen")

local configuration = require("config")
local monitorLib = require("core.monitor")
local util = require("core.util")

local arPanel = require("ar.panel")

local hud = {}
hud.__index = hud

-- component.list() is a component call, and the HUD refreshes at ~10 Hz for the
-- bar animation. Rescanning every frame would be pure waste — glasses do not
-- come and go between frames.
local GLASSES_RESCAN_INTERVAL = 2

function hud.new(config)
    return setmetatable({
        config = config,
        panels = {},
        cleared = {},
        addresses = {},
        addressesAt = nil,
        -- ScaledResolution reported by glasses_on, per glasses address. This is
        -- authoritative: it is the space hud_click coordinates arrive in, so the
        -- hit boxes only line up if the card is laid out in the same one.
        viewport = {},
    }, hud)
end

-- Attached glasses, cached between rescans.
function hud:glassesList(now)
    now = now or computer.uptime()
    if self.addressesAt and (now - self.addressesAt) < GLASSES_RESCAN_INTERVAL then
        return self.addresses
    end
    local list = {}
    for address in component.list("glasses") do table.insert(list, address) end
    table.sort(list)
    self.addresses, self.addressesAt = list, now
    return list
end

-- Resolution to lay the card out in.
-- glasses_on gives the player's real ScaledResolution, which already accounts
-- for their GUI scale. Falling back to the configured resX/resY/scale only
-- matters before the player has put the glasses on.
function hud:resolution(address, settings)
    local reported = self.viewport[address]
    if settings.autoResolution ~= false and reported then
        return {reported.width, reported.height}
    end
    return screen.size({settings.resX, settings.resY}, settings.scale)
end

-- Any change here means the existing objects are wrong and must be recreated.
local function signature(settings, resolution)
    return table.concat({
        tostring(settings.enabled), tostring(settings.compact),
        tostring(settings.anchor), tostring(settings.offsetX), tostring(settings.offsetY),
        tostring(resolution[1]), tostring(resolution[2]),
    }, "|")
end

-- Remove leftovers from a previous run before drawing on a pair of glasses for
-- the first time. Objects from a crashed process cannot be removed individually
-- (their handles are gone), so this is the only way to reclaim them. Done once
-- per address per process — never on a rebuild, which would clear the panel we
-- are about to recreate anyway.
function hud:clearOnce(address, proxy)
    if self.cleared[address] or not self.config.clearGlassesOnStart then return end
    self.cleared[address] = true
    pcall(ar.clear, proxy)
end

function hud:drop(address)
    local panel = self.panels[address]
    if not panel then return end
    -- The glasses may already be gone; tearing down must not take the app with it.
    pcall(function() panel.instance:remove() end)
    self.panels[address] = nil
end

function hud:removeAll()
    for address in pairs(self.panels) do self:drop(address) end
end

-- Pick the view for one pair of glasses.
function hud:selectView(address, settings, monitor, now)
    if not settings.cycle then
        return monitor:resolve(settings.source)
    end

    local panel = self.panels[address]
    local views = monitor:list()
    if #views == 0 then return nil end

    panel.cycleIndex = panel.cycleIndex or 1
    panel.lastSwitch = panel.lastSwitch or now

    local interval = settings.cycleInterval or 8
    if (now - panel.lastSwitch) >= interval then
        panel.cycleIndex = panel.cycleIndex % #views + 1
        panel.lastSwitch = now
    end
    -- The view list can shrink between frames (a buffer went missing, wireless
    -- switched off), so clamp rather than index past the end.
    if panel.cycleIndex > #views then panel.cycleIndex = 1 end
    return views[panel.cycleIndex]
end

function hud:update(monitor)
    local now = computer.uptime()
    local seen = {}

    for _, address in ipairs(self:glassesList(now)) do
        seen[address] = true
        local settings = configuration.glassesFor(self.config, address)
        local resolution = self:resolution(address, settings)
        local current = self.panels[address]
        local wanted = signature(settings, resolution)

        if current and current.signature ~= wanted then
            self:drop(address)
            current = nil
        end

        if not settings.enabled then
            if current then self:drop(address) end
        else
            if not current then
                local ok, proxy = pcall(component.proxy, address)
                if ok and proxy then
                    self:clearOnce(address, proxy)
                    local built, instance =
                        pcall(arPanel.new, proxy, settings, self.config.theme, resolution)
                    if built then
                        self.panels[address] = {
                            instance = instance,
                            proxy = proxy,
                            signature = wanted,
                            cycleIndex = 1,
                            lastSwitch = now,
                        }
                        current = self.panels[address]
                    end
                end
            end

            if current then
                local view = self:selectView(address, settings, monitor, now)
                local ok = pcall(function() current.instance:update(view, settings.cycle) end)
                -- Glasses unplugged mid-frame: forget the panel and let the next
                -- pass rebuild it if they come back.
                if not ok then self:drop(address) end
            end
        end
    end

    -- Glasses that vanished from the component list.
    for address in pairs(self.panels) do
        if not seen[address] then self:drop(address) end
    end
end

-- Input ----------------------------------------------------------------------

-- OCGlasses signals identify the player, not the terminal. With one pair of
-- glasses that is unambiguous; with several, ask each terminal who is bound to
-- it. getBindPlayers() may return a single name or a list depending on version,
-- so both shapes are handled.
function hud:glassesFor(user)
    local addresses = self:glassesList()
    if #addresses == 1 then return addresses[1] end
    if not user then return addresses[1] end

    for _, address in ipairs(addresses) do
        local ok, proxy = pcall(component.proxy, address)
        if ok and proxy then
            local bound = util.call(proxy, "getBindPlayers")
            if type(bound) == "string" and bound:find(user, 1, true) then return address end
            if type(bound) == "table" then
                for _, name in pairs(bound) do
                    if name == user then return address end
                end
            end
        end
    end
    return addresses[1]
end

-- Step the pinned source by `step` views, skipping the cycling mode.
function hud:step(settings, monitor, step)
    local views = monitor:list()
    if #views == 0 then return nil end

    local index = 1
    for i, view in ipairs(views) do
        if view.id == (settings.source or monitorLib.AGGREGATE_ID) then index = i break end
    end
    local target = views[(index - 1 + step) % #views + 1]
    settings.cycle = false
    settings.source = (target.id ~= monitorLib.AGGREGATE_ID) and target.id or nil
    return target
end

function hud:selectIndex(settings, monitor, index)
    local views = monitor:list()
    local target = views[index]
    if not target then return nil end
    settings.cycle = false
    settings.source = (target.id ~= monitorLib.AGGREGATE_ID) and target.id or nil
    return target
end

function hud:applyAction(address, action, monitor)
    local settings = configuration.glassesFor(self.config, address)
    if action == "next" then
        return self:step(settings, monitor, 1)
    elseif action == "prev" then
        return self:step(settings, monitor, -1)
    elseif action == "cycle" then
        settings.cycle = not settings.cycle
        return monitor:resolve(settings.source)
    end
    return nil
end

-- Returns true when the click landed on the card.
function hud:onClick(user, x, y, monitor)
    local address = self:glassesFor(user)
    if not address then return false end
    local panel = self.panels[address]
    if not panel then return false end

    local action = panel.instance:hitTest(x, y)
    if not action then return false end
    self:applyAction(address, action, monitor)
    return true
end

-- Hotkeys inside the free-cursor overlay: ‹ / › arrows, digits pick the Nth
-- source, `c` toggles cycling. LWJGL reports 203/205 for the arrow keys, whose
-- `character` is 0 — so both the character and the key code are inspected.
function hud:onKey(user, character, key, monitor)
    local address = self:glassesFor(user)
    if not address or not self.panels[address] then return false end

    local settings = configuration.glassesFor(self.config, address)
    character = tonumber(character) or 0

    if key == 203 then
        self:step(settings, monitor, -1) return true
    elseif key == 205 then
        self:step(settings, monitor, 1) return true
    elseif character >= 49 and character <= 57 then -- '1'..'9'
        return self:selectIndex(settings, monitor, character - 48) ~= nil
    elseif character == 99 then -- 'c'
        settings.cycle = not settings.cycle
        return true
    end
    return false
end

-- The player's ScaledResolution. Storing it rebuilds the card at the size the
-- click coordinates actually use, so no manual GUI-scale setting is needed.
function hud:onGlassesOn(user, width, height)
    if not (tonumber(width) and tonumber(height)) then return end
    local address = self:glassesFor(user)
    if not address then return end
    self.viewport[address] = {width = tonumber(width), height = tonumber(height)}
end

-- Route an OpenComputers signal. Returns true when it was ours.
--
-- OCGlasses documents these signals as (user, ...), but some component signals
-- in OpenComputers lead with the component address instead. Rather than bet on
-- one shape, drop a leading UUID if it is there.
function hud:handleSignal(monitor, name, ...)
    local args = {...}
    if type(args[1]) == "string" and args[1]:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-") then
        table.remove(args, 1)
    end

    if name == "hud_click" then
        return self:onClick(args[1], tonumber(args[2]) or -1, tonumber(args[3]) or -1, monitor)
    elseif name == "hud_keyboard" then
        return self:onKey(args[1], args[2], tonumber(args[3]) or 0, monitor)
    elseif name == "glasses_on" then
        self:onGlassesOn(args[1], args[2], args[3])
        return true
    end
    return false
end

return hud
