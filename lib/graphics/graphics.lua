-- Half-block GPU renderer.
-- Derived from NIDAS (GPL-3.0), rewritten for correctness and to drop the
-- video-RAM buffer system, so a Tier 2 GPU is enough.
--
-- Only the foreground colour is ever set. Background colour changes break
-- shader setups, so every glyph is drawn as ▀ / ▄ / █ on the terminal's own
-- background. That doubles the vertical resolution and gives square pixels:
-- the drawing space is `width` x `2*height`, with y starting at 1.

local graphics = {}

local context = {gpu = nil, width = 0, height = 0}

function graphics.setContext(ctx)
    if ctx and ctx.gpu then
        context.gpu = ctx.gpu
        context.width = ctx.width
        context.height = ctx.height
    else
        local gpu = require("component").gpu
        local width, height = gpu.getResolution()
        context.gpu = gpu
        context.width = width
        context.height = height
    end
    return context
end

function graphics.context() return context end

-- Drawing-space size (vertical resolution is doubled).
function graphics.size() return context.width, context.height * 2 end

local function setFg(color)
    if context.fg ~= color then
        context.gpu.setForeground(color)
        context.fg = color
    end
end

-- A single half-height pixel. Odd y = upper half, even y = lower half.
local function pixel(x, y, color)
    if x < 1 or x > context.width or y < 1 or y > context.height * 2 then return end
    setFg(color)
    context.gpu.set(x, math.ceil(y / 2), (y % 2 == 1) and "▀" or "▄")
end

-- Filled rectangle in drawing space. Handles odd top/bottom edges by drawing
-- half-blocks and filling the whole-cell middle with █.
function graphics.rectangle(x, y, width, height, color)
    if width < 1 or height < 1 then return end
    x, y = math.floor(x), math.floor(y)
    width, height = math.floor(width), math.floor(height)

    local top, bottom = y, y + height - 1
    local firstFull, lastFull = top, bottom

    -- An even top edge only covers the lower half of its cell.
    if top % 2 == 0 then
        for i = x, x + width - 1 do pixel(i, top, color) end
        firstFull = top + 1
    end
    -- An odd bottom edge only covers the upper half of its cell.
    if bottom % 2 == 1 and bottom >= firstFull then
        for i = x, x + width - 1 do pixel(i, bottom, color) end
        lastFull = bottom - 1
    end

    if lastFull >= firstFull then
        local rows = (lastFull - firstFull + 1) / 2
        if rows >= 1 then
            setFg(color)
            context.gpu.fill(x, math.ceil(firstFull / 2), width, rows, "█")
        end
    end
end

-- Text sits on whole cells, so y must be odd in drawing space. Pass
-- `standardY` to address terminal rows directly instead.
function graphics.text(x, y, text, color, standardY)
    if not text or text == "" then return end
    local row
    if standardY then
        row = math.floor(y)
    else
        if y % 2 == 0 then
            error("graphics.text: y must be odd in drawing space (got " .. tostring(y) .. ")", 2)
        end
        row = math.ceil(y / 2)
    end
    if row < 1 or row > context.height then return end
    setFg(color or 0xFFFFFF)
    context.gpu.set(math.floor(x), row, text)
end

function graphics.clear()
    context.gpu.fill(1, 1, context.width, context.height, " ")
end

return graphics
