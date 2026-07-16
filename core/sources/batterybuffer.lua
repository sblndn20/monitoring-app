-- GregTech Battery Buffer (component type `gt_batterybuffer`).
--
-- MTEBasicBatteryBuffer.getInfoData() returns 4 lines in GTNH 2.8.3:
--   1  <localised machine name>
--   2  "Stored Items: X EU / Y EU"      <- both figures on one line
--   3  "Average input: X EU/t"
--   4  "Average output: X EU/t"
--
-- Charge stays far below 2^53 here, so the structured getters are safe and are
-- preferred; the sensor text is only a fallback.
--
-- NIDAS also handled this shape, but its detection was dead code: it looked up
-- `component.list()[address]` with a *partial* address while component.list()
-- is keyed by full UUID, so the lookup always returned nil.

local sensor = require("core.sensor")
local states = require("core.states")
local util = require("core.util")

local batteryBuffer = {
    kind = "batterybuffer",
    label = "Battery Buffer",
    componentTypes = {"gt_batterybuffer"},
}

function batteryBuffer.detect(proxy, lines, componentType)
    if componentType == "gt_batterybuffer" then return 100 end
    if lines and sensor.find(lines, "Stored Items:.*/") then return 70 end
    return 0
end

function batteryBuffer.read(proxy, lines)
    local stored = util.callNumber(proxy, "getEUStored")
    local capacity = util.callNumber(proxy, "getEUMaxStored")

    -- "X EU / Y EU" must be split before parsing: scraping digits from the whole
    -- line would concatenate both numbers into one meaningless value.
    if (not stored or not capacity) and lines then
        local line = sensor.find(lines, "Stored Items")
        if line then
            local left, right = line:match("Stored Items:%s*(.-)%s*/%s*(.*)$")
            if left and right then
                stored = stored or sensor.amount(left)
                capacity = capacity or sensor.amount(right)
            end
        end
    end

    local euIn = util.callNumber(proxy, "getEUInputAverage")
        or sensor.value(lines, "[Aa]verage input") or 0
    local euOut = util.callNumber(proxy, "getEUOutputAverage")
        or sensor.value(lines, "[Aa]verage output") or 0

    local reading = {
        stored = stored or 0,
        capacity = capacity or 0,
        euIn = euIn,
        euOut = euOut,
        passiveLoss = 0,
        problems = 0,
    }

    if util.call(proxy, "isWorkAllowed") == false then
        reading.state = states.OFF
    elseif euIn > 0 or euOut > 0 then
        reading.state = states.ONLINE
    else
        reading.state = states.IDLE
    end

    return reading
end

return batteryBuffer
