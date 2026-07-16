-- Duration formatting.
-- Derived from NIDAS (GPL-3.0); the NIDAS-specific realtime clock hack was
-- dropped since an energy monitor only needs relative durations.

local time = {}

-- Seconds -> a compact human duration. Scales the unit to the magnitude so a
-- nearly-idle buffer reads "3 Years 40 Days" rather than a wall of seconds.
function time.format(seconds)
    seconds = math.abs(math.floor(tonumber(seconds) or 0))
    if seconds == 0 then return "0s" end

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60

    if hours > 24 * 365 * 100 then
        return "∞"
    elseif hours > 17000 then
        local years = math.floor(hours / (24 * 365))
        local days = math.floor((hours - years * 24 * 365) / 24)
        return years .. "y " .. days .. "d"
    elseif hours > 48 then
        local days = math.floor(hours / 24)
        return days .. "d " .. (hours - days * 24) .. "h " .. minutes .. "m"
    elseif hours > 0 then
        return hours .. "h " .. minutes .. "m " .. secs .. "s"
    elseif minutes > 0 then
        return minutes .. "m " .. secs .. "s"
    end
    return secs .. "s"
end

return time
