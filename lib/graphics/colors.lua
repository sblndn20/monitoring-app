-- ARGUS palette.
-- Internally every colour is a hex literal (0xRRGGBB).
--
-- NOTE: OpenOS ships its own `colors` library. Always require this one by its
-- full path (`lib.graphics.colors`) so the two never collide.

local colors = {
    -- Neutrals / chrome
    black      = 0x000000,
    white      = 0xFFFFFF,
    background = 0x0B0E14,
    panel      = 0x151A23,
    line       = 0x2A3442,
    muted      = 0x6B7A8F,
    text       = 0xC8D3E0,

    -- Accents
    cyan       = 0x22D3EE,
    blue       = 0x3B82F6,
    violet     = 0x8B5CF6,
    magenta    = 0xD946EF,
    green      = 0x22C55E,
    lime       = 0x84CC16,
    amber      = 0xF59E0B,
    orange     = 0xFB923C,
    red        = 0xEF4444,
    maroon     = 0x7F1D1D,
    teal       = 0x14B8A6,
    slate      = 0x475569,
}

-- Reverse lookup (colors[0x22D3EE] == "cyan") so the settings UI can show a
-- name for a stored value. Iterate over a snapshot: mutating a table while
-- pairs() walks it is undefined behaviour in Lua.
local names = {}
for name, value in pairs(colors) do names[value] = name end
for value, name in pairs(names) do colors[value] = name end

return colors
