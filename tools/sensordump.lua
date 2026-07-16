-- Sensor diagnostics.
--
--   cd /home/EMON && tools/sensordump.lua
--
-- Prints, for every attached energy component: its type, the raw
-- getSensorInformation() lines with their indices, which adapter claims it, and
-- what EMON parses out of it.
--
-- This exists because GregTech's sensor text is version- and addon-dependent.
-- If EMON shows a wrong figure on your pack, paste this output into an issue —
-- it is the whole picture needed to fix the parsing.

package.path = "/home/EMON/?.lua;/home/EMON/?/init.lua;" .. package.path

local component = require("component")

local parser = require("lib.utils.parser")
local sensor = require("core.sensor")
local sources = require("core.sources")
local util = require("core.util")

local function line(char)
    print(string.rep(char or "-", 60))
end

local GETTERS = {
    "getEUStored", "getEUMaxStored", "getEUInputAverage", "getEUOutputAverage",
    "getStoredEUString", "getEUCapacityString", "getName", "isWorkAllowed", "hasWork",
}

local candidates = {}
for address, componentType in component.list() do
    if componentType:find("^gt_") or componentType == "energy_storage" then
        table.insert(candidates, {address = address, type = componentType})
    end
end

if #candidates == 0 then
    print("No GregTech or IC2 energy components found.")
    print("Place an Adapter block against the machine and link it to this computer.")
    return
end

print("EMON sensor dump — " .. #candidates .. " component(s)")

for _, candidate in ipairs(candidates) do
    line("=")
    print("Address : " .. candidate.address)
    print("Type    : " .. candidate.type)

    local ok, proxy = pcall(component.proxy, candidate.address)
    if not ok or not proxy then
        print("  <cannot proxy this component>")
    else
        print("Name    : " .. tostring(util.call(proxy, "getName")))

        local adapter = sources.identify(proxy, candidate.type)
        print("Adapter : " .. (adapter and (adapter.kind .. " (" .. adapter.label .. ")") or "none"))

        line()
        print("Structured getters:")
        for _, method in ipairs(GETTERS) do
            if type(proxy[method]) == "function" then
                local value = util.call(proxy, method)
                print(string.format("  %-22s = %s", method, tostring(value)))
            else
                print(string.format("  %-22s   (absent)", method))
            end
        end

        line()
        local lines = sensor.lines(proxy)
        if not lines then
            print("getSensorInformation(): not available")
        else
            print("getSensorInformation(): " .. #lines .. " lines")
            for i = 1, #lines do
                -- Colour codes are stripped for readability; the value shown is
                -- what EMON's label matcher actually sees.
                print(string.format("  [%2d] %s", i, lines[i]))
            end
        end

        if adapter then
            line()
            print("Parsed reading:")
            local read, reading = pcall(adapter.read, proxy, lines)
            if not read then
                print("  read() failed: " .. tostring(reading))
            else
                for _, key in ipairs({"state", "stored", "storedText", "capacity",
                                      "capacityText", "euIn", "euOut", "passiveLoss",
                                      "problems", "avg5m", "avg1h"}) do
                    if reading[key] ~= nil then
                        print(string.format("  %-12s = %s", key, tostring(reading[key])))
                    end
                end
                if reading.storedText then
                    print("  exact stored = " .. parser.splitNumber(reading.storedText) .. " EU")
                end
                if reading.wireless then
                    print(string.format("  wireless     = enabled=%s stored=%s",
                        tostring(reading.wireless.enabled), tostring(reading.wireless.stored)))
                end
            end
        end
    end
end
line("=")
