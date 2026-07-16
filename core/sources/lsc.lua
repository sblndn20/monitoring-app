-- Lapotronic Supercapacitor (kekztech multiblock, component type `gt_machine`).
--
-- Why this reads sensor text rather than the structured getters:
-- the LSC stores its charge as a BigInteger, but MTELapotronicSuperCapacitor's
-- getEUVar() returns `stored.longValue()` — BigInteger.longValue() *wraps*
-- instead of clamping. So getEUStored() (and getStoredEUString(), which is
-- built on it) return garbage once stored exceeds 2^63. The sensor lines are
-- rendered straight from the BigInteger and stay correct. Fixed upstream only
-- in GTNH 2.9 via a dedicated `LSC` component, which does not exist in 2.8.3.
--
-- Rates are small enough to be safe, so those come from the clean getters where
-- available and fall back to sensor text.

local sensor = require("core.sensor")
local states = require("core.states")
local util = require("core.util")

local lsc = {
    kind = "lsc",
    label = "Lapotronic Supercapacitor",
    componentTypes = {"gt_machine"},
}

function lsc.detect(proxy, lines)
    if not lines then return 0 end
    -- "Wireless mode:" and "Passive Loss:" together are unique to the LSC.
    if sensor.find(lines, "Wireless mode") then return 100 end
    if sensor.find(lines, "^%s*Passive Loss") and sensor.find(lines, "Capacity") then
        return 80
    end
    return 0
end

local function readWireless(lines)
    local modeLine = sensor.find(lines, "Wireless mode")
    if not modeLine then return nil end
    local enabled = modeLine:lower():find("enabled") ~= nil
    if not enabled then return {enabled = false} end

    -- In 2.8.3 there is no API for the wireless network balance; these two
    -- sensor lines are the only access. The value is a BigInteger and can
    -- exceed 2^63, which is why the scientific twin exists.
    local stored, exact = sensor.bestValue(lines, "[Tt]otal wireless EU")
    return {enabled = true, stored = stored or 0, storedText = exact}
end

local function readProblems(lines)
    local line = sensor.find(lines, "Maintenance Status") or sensor.find(lines, "Problems")
    if not line then return 0 end
    if line:find("Working perfectly") then return 0 end
    local count = sensor.amount(line)
    if count and count > 0 then return count end
    if line:find("[Hh]as [Pp]roblems") then return 1 end
    return 0
end

function lsc.read(proxy, lines)
    -- Prefer "EU Stored"; older builds printed the charge as "Used Capacity: NEU"
    -- instead. In 2.8.3 "Used Capacity" is a *percentage*, so it is only a valid
    -- fallback when the line actually carries an EU figure.
    local stored, storedText = sensor.bestValue(lines, "^%s*EU Stored")
    if not stored then
        stored, storedText = sensor.bestValue(lines, "^%s*Used Capacity.*EU")
    end
    local capacity, capacityText = sensor.bestValue(lines, "^%s*Total Capacity")

    local euIn = util.callNumber(proxy, "getEUInputAverage") or sensor.value(lines, "^%s*EU IN")
    local euOut = util.callNumber(proxy, "getEUOutputAverage") or sensor.value(lines, "^%s*EU OUT")

    local reading = {
        stored = stored or 0,
        storedText = storedText,
        capacity = capacity or 0,
        capacityText = capacityText,
        euIn = euIn or 0,
        euOut = euOut or 0,
        passiveLoss = sensor.value(lines, "^%s*Passive Loss") or 0,
        problems = readProblems(lines),
        wireless = readWireless(lines),
    }

    -- GTNH already tracks long-window averages, so use them instead of
    -- recomputing our own (NIDAS sampled these itself over a tick counter).
    local avg5m = sensor.find(lines, "Avg EU IN.*5 minutes")
    local avg5mOut = sensor.find(lines, "Avg EU OUT.*5 minutes")
    if avg5m and avg5mOut then
        reading.avg5m = (sensor.amount(avg5m) or 0) - (sensor.amount(avg5mOut) or 0)
    end
    local avg1h = sensor.find(lines, "Avg EU IN.*1 hour")
    local avg1hOut = sensor.find(lines, "Avg EU OUT.*1 hour")
    if avg1h and avg1hOut then
        reading.avg1h = (sensor.amount(avg1h) or 0) - (sensor.amount(avg1hOut) or 0)
    end

    if reading.problems > 0 then
        reading.state = states.PROBLEM
    elseif util.call(proxy, "isWorkAllowed") == false then
        reading.state = states.OFF
    elseif reading.euIn > 0 or reading.euOut > 0 then
        reading.state = states.ONLINE
    else
        reading.state = states.IDLE
    end

    return reading
end

return lsc
