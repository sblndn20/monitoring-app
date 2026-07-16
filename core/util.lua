local util = {}

-- Is this value callable?
--
-- This is not pedantry. OpenComputers does NOT expose component methods as
-- plain functions — machine.lua builds a proxy with
--     proxy[method] = setmetatable({address=..., name=...}, componentCallback)
-- where componentCallback supplies __call (and a __tostring that returns the
-- method's docstring, which is why `print(component.gpu.set)` prints docs).
--
-- So type(proxy.getSensorInformation) is "table", not "function". Testing for
-- "function" rejects every real component method and makes a perfectly healthy
-- machine look like it exposes nothing at all.
function util.callable(value)
    if type(value) == "function" then return true end
    if type(value) ~= "table" then return false end
    local mt = getmetatable(value)
    return type(mt) == "table" and mt.__call ~= nil
end

-- Call an optional component method. Component proxies raise on a broken or
-- unplugged block, and a monitor must never die because one adapter vanished.
function util.call(proxy, method, ...)
    if not proxy then return nil end
    local fn = proxy[method]
    if not util.callable(fn) then return nil end
    local ok, result = pcall(fn, ...)
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
