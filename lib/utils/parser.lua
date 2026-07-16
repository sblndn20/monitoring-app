-- String/number formatting helpers.
-- Derived from NIDAS (GPL-3.0) with fixes: sign handling in splitNumber,
-- signed parsing in getInteger, and a metricNumber that no longer skips the
-- 1000..1000.9 band.

local parser = {}

-- Strip Minecraft section-sign colour codes ("§a", "§r", ...).
function parser.stripColors(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("\194\167.", ""):gsub("§.", ""))
end

-- Format a number as XXX,XXX,XXX. Accepts a number or a decimal string, so
-- exact EU values beyond 2^53 can be formatted without going through a double.
function parser.splitNumber(number, delim)
    delim = delim or ","
    local str, negative
    if type(number) == "string" then
        negative = number:sub(1, 1) == "-"
        str = number:gsub("^[-+]", ""):gsub("%D", "")
        if str == "" then str = "0" end
    else
        number = math.floor(number or 0)
        negative = number < 0
        str = tostring(math.abs(number))
    end
    if delim == "" then return (negative and "-" or "") .. str end

    local out, count = {}, 0
    for i = #str, 1, -1 do
        table.insert(out, 1, str:sub(i, i))
        count = count + 1
        if count % 3 == 0 and i > 1 then table.insert(out, 1, delim) end
    end
    return (negative and "-" or "") .. table.concat(out)
end

-- Compact SI-style rendering: 1234567 -> "1.2M".
function parser.metricNumber(number, format)
    format = format or "%.1f"
    number = tonumber(number) or 0
    if math.abs(number) < 1000 then
        return tostring(math.floor(number))
    end
    local suffixes = {"k", "M", "G", "T", "P", "E", "Z", "Y"}
    local power = 1
    -- >= 1000, not > 1000: otherwise 1000k renders instead of 1.0M.
    while math.abs(number / 1000 ^ power) >= 1000 and power < #suffixes do
        power = power + 1
    end
    return string.format(format, number / 1000 ^ power) .. suffixes[power]
end

-- Pull an integer out of a GregTech sensor line, e.g. "EU IN: 32,768EU/t".
-- Keeps the sign, which NIDAS's version dropped.
function parser.getInteger(s)
    if type(s) == "number" then return math.floor(s) end
    if type(s) ~= "string" then return 0 end
    s = parser.stripColors(s)
    -- ASCII hyphen only; a multi-byte minus in a character class would match
    -- individual UTF-8 bytes.
    local negative = s:match("%-%s*[%d]") ~= nil
    local digits = s:gsub("%D", "")
    local value = tonumber(digits)
    if not value then return 0 end
    value = math.floor(value)
    return negative and -value or value
end

function parser.split(s, sep)
    sep = sep or "%s"
    local words = {}
    for str in string.gmatch(s, "([^" .. sep .. "]+)") do
        table.insert(words, str)
    end
    return words
end

-- Expects a 0..1 fraction, renders "62.4%".
function parser.percentage(number)
    return (math.floor((number or 0) * 1000) / 10) .. "%"
end

return parser
