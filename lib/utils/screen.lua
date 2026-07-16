-- Screen/colour maths helpers.
-- Derived from NIDAS (GPL-3.0), rewritten without Lua 5.3 bitwise operators so
-- the code also runs on Lua 5.2 OpenComputers architectures.

local screen = {}

local function channels(hex)
    local r = math.floor(hex / 65536) % 256
    local g = math.floor(hex / 256) % 256
    local b = hex % 256
    return r, g, b
end

screen.channels = channels

-- OpenGlasses wants each channel normalised to 0..1.
function screen.toRGB(hex)
    local r, g, b = channels(hex)
    return r / 255.0, g / 255.0, b / 255.0
end

-- Linear blend between two colours; t = 0 gives `from`, t = 1 gives `to`.
function screen.blend(from, to, t)
    t = math.min(1, math.max(0, t))
    local r1, g1, b1 = channels(from)
    local r2, g2, b2 = channels(to)
    local r = math.floor(r1 + (r2 - r1) * t)
    local g = math.floor(g1 + (g2 - g1) * t)
    local b = math.floor(b1 + (b2 - b1) * t)
    return r * 65536 + g * 256 + b
end

-- Minecraft GUI scale: Small = 1, Normal = 2, Large = 3, Auto = 4..10 (even).
-- Converts a window resolution into the glasses coordinate space.
function screen.size(resolution, scale)
    scale = scale or 3
    return {resolution[1] / scale, resolution[2] / scale}
end

return screen
