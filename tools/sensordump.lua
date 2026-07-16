-- Sensor diagnostics.
--
--   cd /home/ARGUS && tools/sensordump.lua
--
-- Prints, for every attached energy component: its type, the raw
-- getSensorInformation() lines with their indices, which adapter claims it, and
-- what ARGUS parses out of it.
--
-- This exists because GregTech's sensor text is version- and addon-dependent.
-- If ARGUS shows a wrong figure on your pack, paste this output into an issue —
-- it is the whole picture needed to fix the parsing.

package.path = "/home/ARGUS/?.lua;/home/ARGUS/?/init.lua;" .. package.path

-- Same reason as init.lua: OpenOS keeps one package.loaded for the whole boot
-- session, so require() would hand back modules loaded before the last update
-- and this tool would report on code that is no longer on disk.
for name in pairs(package.loaded) do
    if name:match("^lib%.") or name:match("^core$") or name:match("^core%.") then
        package.loaded[name] = nil
    end
end

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

-- Every component first, unfiltered. If ARGUS sees no buffers, the answer is
-- almost always here: either the machine's component never appeared at all
-- (adapter not touching the controller), or it appeared under a type ARGUS does
-- not recognise. Filtering this list would hide exactly the case being debugged.
local all, total = {}, 0
for address, componentType in component.list() do
    total = total + 1
    table.insert(all, {address = address, type = componentType})
end
table.sort(all, function(a, b) return a.type < b.type end)

print("ARGUS sensor dump")
line("=")
print("All components visible to this computer (" .. total .. "):")
for _, item in ipairs(all) do
    print(string.format("  %-22s %s", item.type, item.address))
end

local candidates = {}
for _, item in ipairs(all) do
    if item.type:find("^gt_") or item.type == "energy_storage" then
        table.insert(candidates, item)
    end
end

if #candidates == 0 then
    line("=")
    print("No GregTech or IC2 energy components among them.")
    print("")
    print("If the list above has no gt_* entry, the machine is not exposed at all:")
    print("  * the Adapter must touch the multiblock's CONTROLLER block,")
    print("    not a casing, capacitor or hatch;")
    print("  * the Adapter must be connected to this computer (adjacent or cabled);")
    print("  * an MFU inside the Adapter can link a controller up to 16 blocks away.")
    print("")
    print("If you DO see an unfamiliar type above, report it — ARGUS may just need")
    print("an adapter for it.")
    return
end

line("=")
print("Energy candidates: " .. #candidates)

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
            -- util.callable, not a "function" check: OpenComputers exposes proxy
            -- methods as tables with a __call metamethod.
            if util.callable(proxy[method]) then
                local value = util.call(proxy, method)
                print(string.format("  %-22s = %s", method, tostring(value)))
            else
                print(string.format("  %-22s   (absent)", method))
            end
        end

        -- Anything the proxy actually offers, in case a method has been renamed
        -- and the list above is simply looking for the wrong name.
        local available = {}
        for key, value in pairs(proxy) do
            if util.callable(value) then table.insert(available, key) end
        end
        table.sort(available)
        print("  all callable methods: " .. (#available > 0 and table.concat(available, ", ") or "(none)"))

        line()
        local lines = sensor.lines(proxy)
        if not lines then
            print("getSensorInformation(): not available")
        else
            print("getSensorInformation(): " .. #lines .. " lines")
            for i = 1, #lines do
                -- Colour codes are stripped for readability; the value shown is
                -- what ARGUS's label matcher actually sees.
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
