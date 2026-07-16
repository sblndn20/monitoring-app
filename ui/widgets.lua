-- Minimal touch-aware widgets.
--
-- NIDAS built its widgets on GPU video-RAM buffers (gpu.allocateBuffer), which
-- requires a Tier 3 GPU. An energy monitor should run on cheaper hardware, so
-- this draws straight to the screen and keeps only a flat list of hit boxes.
--
-- Hit boxes are in TERMINAL cell coordinates, because that is what OpenComputers
-- reports in a `touch` signal. Drawing uses graphics.lua's doubled-height space,
-- where drawing row y maps to terminal row ceil(y/2).

local event = require("event")

local graphics = require("lib.graphics.graphics")
local text = require("lib.utils.text")

local widgets = {}

-- LWJGL scan codes, as delivered by OpenComputers' key_down signal.
local KEY_ESCAPE, KEY_BACKSPACE, KEY_ENTER, KEY_NUMPAD_ENTER = 1, 14, 28, 156

-- Modal single-line input. Blocks until Enter (returns the text) or Escape
-- (returns nil).
--
-- Blocking is deliberate. The alternative — threading edit state through the
-- main loop — buys nothing here: the loop only polls components and redraws,
-- and pausing both for the seconds it takes to type a name is unnoticeable.
-- A keyboard attached to the screen is required, which is the same thing that
-- makes the rest of the UI usable.
function widgets.prompt(x, row, width, initial, colors, numeric)
    local value = tostring(initial or "")

    local function render()
        -- The trailing block is the caret; fit() keeps a long value from
        -- spilling past the field.
        graphics.text(x, row, text.fit("> " .. value .. "▏", width), colors.primary, true)
    end
    render()

    while true do
        local _, _, char, code = event.pull("key_down")
        if code == KEY_ENTER or code == KEY_NUMPAD_ENTER then
            return value
        elseif code == KEY_ESCAPE then
            return nil
        elseif code == KEY_BACKSPACE then
            value = text.sub(value, 1, math.max(0, text.len(value) - 1))
        elseif char and char >= 32 then
            local typed = text.char(char)
            -- A numeric field still has to accept a leading minus.
            if not numeric or typed:match("[%d%-]") then
                if text.len(value) < width - 4 then value = value .. typed end
            end
        end
        render()
    end
end

local regions = {}

-- Call once per frame, before drawing, so stale hit boxes cannot fire.
function widgets.reset()
    regions = {}
end

function widgets.region(x, row, width, height, onClick, arg)
    table.insert(regions, {
        x = x, row = row, width = width, height = height or 1,
        onClick = onClick, arg = arg,
    })
end

-- Returns true when a region consumed the click.
function widgets.dispatch(x, row)
    -- Iterate newest-first so a widget drawn on top of another wins.
    for i = #regions, 1, -1 do
        local r = regions[i]
        if x >= r.x and x < r.x + r.width and row >= r.row and row < r.row + r.height then
            if r.onClick then r.onClick(r.arg) end
            return true
        end
    end
    return false
end

-- One-row button rendered as "[ Label ]". Returns the width it occupied so
-- callers can lay buttons out in a row without measuring the label twice.
function widgets.button(x, row, label, colors, onClick, arg, active)
    local caption = "[ " .. label .. " ]"
    local width = text.len(caption)
    graphics.text(x, row, caption, active and colors.primary or colors.muted, true)
    widgets.region(x, row, width, 1, onClick, arg)
    return width
end

-- Left-aligned row in a list; `selected` draws a marker and uses the accent.
function widgets.listItem(x, row, width, label, colors, selected, onClick, arg, enabled)
    local marker = selected and "›" or " "
    local state = enabled == false and "·" or "•"
    local color = colors.text
    if selected then
        color = colors.primary
    elseif enabled == false then
        color = colors.muted
    end

    graphics.text(x, row, text.fit(marker .. " " .. state .. " " .. label, width), color, true)
    widgets.region(x, row, width, 1, onClick, arg)
    return row + 1
end

-- Horizontal progress bar in drawing space, drawn as a filled track.
function widgets.bar(x, y, width, height, fraction, fillColor, trackColor)
    fraction = math.min(1, math.max(0, fraction or 0))
    graphics.rectangle(x, y, width, height, trackColor)
    local filled = math.floor(width * fraction + 0.5)
    if filled > 0 then
        graphics.rectangle(x, y, filled, height, fillColor)
    end
end

return widgets
