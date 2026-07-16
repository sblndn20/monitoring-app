local util = {}

-- Call an optional component method. Component proxies raise on a broken or
-- unplugged block, and a monitor must never die because one adapter vanished.
function util.call(proxy, method, ...)
    if not proxy or type(proxy[method]) ~= "function" then return nil end
    local ok, result = pcall(proxy[method], ...)
    if not ok then return nil end
    return result
end

-- Same, but coerced to a number.
function util.callNumber(proxy, method, ...)
    local value = util.call(proxy, method, ...)
    return tonumber(value)
end

-- Shallow copy with defaults filled in.
function util.defaults(target, source)
    target = target or {}
    for key, value in pairs(source) do
        if target[key] == nil then target[key] = value end
    end
    return target
end

return util
