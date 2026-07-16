-- Character-aware string helpers.
--
-- Lua's `#` counts BYTES, but gpu.set() advances by CHARACTERS. Every glyph
-- this UI uses outside ASCII — ● › • … ⚠ █ ▀ ▄ — is three bytes in UTF-8, so
-- measuring a label with `#` overstates its width by 2 per glyph and every
-- right-aligned or truncated string lands in the wrong place.
--
-- OpenOS ships a `unicode` library for exactly this. The fallback keeps the
-- module usable under a desktop interpreter so the UI can be tested outside
-- Minecraft.

local text = {}

local ok, unicode = pcall(require, "unicode")

if ok and type(unicode) == "table" and unicode.len then
    text.len = unicode.len
    text.sub = unicode.sub
    text.upper = unicode.upper
    text.char = unicode.char
else
    text.len = function(s)
        if utf8 and utf8.len then return utf8.len(s) or #s end
        return #s
    end
    text.sub = function(s, i, j)
        if not (utf8 and utf8.offset) then return s:sub(i, j) end
        local length = text.len(s)
        j = j or length
        if i < 1 then i = 1 end
        if j > length then j = length end
        if i > j then return "" end
        local from = utf8.offset(s, i)
        local to = utf8.offset(s, j + 1)
        return s:sub(from, to and (to - 1) or #s)
    end
    text.upper = string.upper
    text.char = function(code)
        if utf8 and utf8.char then return utf8.char(code) end
        return string.char(code)
    end
end

-- Pad to `width` characters, truncating with an ellipsis when too long.
function text.fit(s, width)
    local length = text.len(s)
    if length == width then return s end
    if length > width then
        if width <= 1 then return text.sub(s, 1, width) end
        return text.sub(s, 1, width - 1) .. "…"
    end
    return s .. string.rep(" ", width - length)
end

return text
