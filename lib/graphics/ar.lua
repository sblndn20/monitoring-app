-- Thin wrapper over the OpenGlasses terminal component.
-- Derived from NIDAS (GPL-3.0). Changes: no implicit `legacyScaling` global,
-- no dependency on the colour palette, and colour conversion shared with
-- lib.utils.screen instead of being duplicated here.
--
-- Conventions:
--   * vertices are {x, y} tables; the first vertex is the top-left corner
--   * colours are 0xRRGGBB; alpha is 0.0..1.0 (defaults to 1.0)
--   * every function returns the live glasses object, so callers create an
--     object once and then mutate it each tick (setText/setVertex/setColor).
--     Recreating objects every frame will leak them.

local screen = require("lib.utils.screen")

local ar = {}

-- Older OpenGlasses builds scale text about the origin rather than the label's
-- own position, so the position has to be pre-divided. Opt in via ar.setLegacyScaling(true).
local legacyScaling = false

function ar.setLegacyScaling(enabled)
    legacyScaling = enabled and true or false
end

-- Vertices are laid out TL, BL, BR, TR — callers resize a bar by moving
-- vertices 3 and 4.
function ar.rectangle(glasses, v1, width, height, color, alpha)
    local rect = glasses.addQuad()
    rect.setColor(screen.toRGB(color))
    rect.setAlpha(alpha or 1.0)
    rect.setVertex(1, v1[1], v1[2])
    rect.setVertex(2, v1[1], v1[2] + height)
    rect.setVertex(3, v1[1] + width, v1[2] + height)
    rect.setVertex(4, v1[1] + width, v1[2])
    return rect
end

function ar.text(glasses, str, v1, color, scale, alpha)
    scale = scale or 1
    local text = glasses.addTextLabel()
    text.setText(str or "")
    text.setAlpha(alpha or 1.0)
    text.setPosition(v1[1], v1[2])
    text.setColor(screen.toRGB(color or 0xFFFFFF))
    if legacyScaling and scale ~= 1 then
        local oldX, oldY = text.getPosition()
        oldX = oldX * text.getScale()
        oldY = oldY * text.getScale()
        text.setScale(scale)
        text.setPosition(oldX / (scale * 2), oldY / (scale * 2))
    else
        text.setScale(scale)
    end
    return text
end

function ar.remove(glasses, objects)
    for i = 1, #objects do
        pcall(glasses.removeObject, objects[i].getID())
    end
end

function ar.clear(glasses)
    glasses.removeAll()
end

return ar
