-- Sparkline over a metrics ring.
--
-- Drawn as one-pixel-wide columns in graphics.lua's doubled-height space rather
-- than with ▁▂▃▄▅▆▇█ glyphs, which doubles the vertical resolution for free.
--
-- The Y axis auto-scales to the visible window instead of spanning 0..capacity.
-- A capacitor parked at 99.4% would otherwise render as a flat line and hide
-- exactly the drift you are watching for; the caller renders the min/max labels
-- so the scale stays honest.

local graphics = require("lib.graphics.graphics")
local screen = require("lib.utils.screen")

local graph = {}

-- Returns min, max of the plotted window (nil, nil when there is nothing yet).
function graph.draw(x, y, width, height, series, colors)
    if not series or series.count < 2 then
        graphics.text(x, y, "collecting data…", colors.muted)
        return nil, nil
    end

    local count = series.count
    local visible = math.min(count, width)
    local first = count - visible + 1

    local min, max
    for i = first, count do
        local _, value = series:get(i)
        if value then
            if not min or value < min then min = value end
            if not max or value > max then max = value end
        end
    end
    if not min then return nil, nil end

    local span = max - min
    -- A perfectly flat series has no span to normalise against; centre it.
    local flat = span <= 0

    -- Newest sample sits at the right edge, so a partially filled history grows
    -- leftwards instead of jumping around as it fills.
    local offset = width - visible

    for i = 0, visible - 1 do
        local _, value = series:get(first + i)
        if value then
            local fraction = flat and 0.5 or (value - min) / span
            local barHeight = math.max(1, math.floor(fraction * height + 0.5))
            local column = x + offset + i
            local color = screen.blend(colors.muted, colors.primary, fraction)
            graphics.rectangle(column, y + height - barHeight, 1, barHeight, color)
        end
    end

    return min, max
end

return graph
