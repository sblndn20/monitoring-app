-- Generic fallback for any GregTech block that stores EU.
--
-- Any BaseMetaTileEntity gets Computronics' `gt_machine` environment merged
-- with OpenComputers' DriverEnergyContainer, so these getters are available on
-- a wide range of blocks: energy hatches, transformers, single-block machines,
-- and multiblocks this app has no dedicated adapter for.
--
-- Lowest detection priority: it only claims a component when nothing better does.

local sensor = require("core.sensor")
local states = require("core.states")
local util = require("core.util")

local energyContainer = {
    kind = "gt",
    label = "GregTech Energy Container",
    componentTypes = {"gt_machine", "gt_energyContainer"},
}

function energyContainer.detect(proxy)
    local capacity = util.callNumber(proxy, "getEUMaxStored")
    -- A block with no EU capacity is not an energy buffer.
    if capacity and capacity > 0 then return 10 end
    return 0
end

function energyContainer.read(proxy, lines)
    local reading = {
        stored = util.callNumber(proxy, "getEUStored") or 0,
        capacity = util.callNumber(proxy, "getEUMaxStored") or 0,
        euIn = util.callNumber(proxy, "getEUInputAverage") or 0,
        euOut = util.callNumber(proxy, "getEUOutputAverage") or 0,
        passiveLoss = (lines and sensor.value(lines, "^%s*Passive Loss")) or 0,
        problems = 0,
    }

    if lines then
        local maintenance = sensor.find(lines, "Maintenance Status") or sensor.find(lines, "Problems")
        if maintenance and not maintenance:find("Working perfectly") then
            local count = sensor.amount(maintenance)
            reading.problems = (count and count > 0) and count
                or (maintenance:find("[Hh]as [Pp]roblems") and 1 or 0)
        end
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

return energyContainer
