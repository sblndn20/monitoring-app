-- IC2 energy storage: BatBox, CESU, MFE, MFSU, AFSU.
-- OpenComputers' own ic2 DriverEnergyStorage exposes component `energy_storage`
-- with plain numeric getters — no sensor text involved.
--
-- Values are EU but the unit differs conceptually from GT's: IC2 storage
-- reports capacity/stored directly and only an output rate.

local states = require("core.states")
local util = require("core.util")

local ic2 = {
    kind = "ic2",
    label = "IC2 Energy Storage",
    componentTypes = {"energy_storage"},
}

function ic2.detect(proxy, lines, componentType)
    return componentType == "energy_storage" and 100 or 0
end

function ic2.read(proxy)
    local stored = util.callNumber(proxy, "getStored") or 0
    local capacity = util.callNumber(proxy, "getCapacity") or 0
    -- getOutput() is the configured output rate, not measured throughput, so
    -- there is no meaningful input figure to report here. The monitor derives
    -- the real net rate from how `stored` changes over time.
    local output = util.callNumber(proxy, "getOutput") or 0

    return {
        stored = stored,
        capacity = capacity,
        euIn = 0,
        euOut = output,
        passiveLoss = 0,
        problems = 0,
        state = (stored > 0) and states.ONLINE or states.IDLE,
        ratesUnavailable = true,
    }
end

return ic2
