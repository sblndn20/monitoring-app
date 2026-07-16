-- Per-buffer rate tracking.
--
-- The net rate is measured from how `stored` actually changes over time rather
-- than from EU IN minus EU OUT. That works for every source (IC2 storage
-- exposes no throughput at all) and it accounts for passive loss automatically.
--
-- Three rings keep memory flat while covering three time scales. Each is a
-- fixed number of slots, so an hour of history costs the same as a minute:
--   fast   ~15s  — the live rate
--   medium ~10m  — the default graph scale
--   slow   ~65m  — the 1-hour average and the wide graph
--
-- Precision note: `stored` is a Lua double, so past 2^53 EU its ULP grows to
-- hundreds of EU. That is irrelevant for a rate — the delta over a multi-second
-- window dwarfs it — but it is why exact display uses the string variant.

local ring = require("core.ring")

local metrics = {}

local FAST_CAPACITY = 60      -- ~15s at 4 Hz
local MEDIUM_CAPACITY = 120   -- ~10min at 1 sample / 5s
local MEDIUM_INTERVAL = 5
local SLOW_CAPACITY = 130     -- ~65min at 1 sample / 30s
local SLOW_INTERVAL = 30

local TICKS_PER_SECOND = 20

function metrics.new()
    return {
        fast = ring.new(FAST_CAPACITY),
        medium = ring.new(MEDIUM_CAPACITY),
        slow = ring.new(SLOW_CAPACITY),
        lastMedium = nil,
        lastSlow = nil,
    }
end

function metrics.update(tracker, stored, now)
    tracker.fast:push(now, stored)
    if not tracker.lastMedium or (now - tracker.lastMedium) >= MEDIUM_INTERVAL then
        tracker.medium:push(now, stored)
        tracker.lastMedium = now
    end
    if not tracker.lastSlow or (now - tracker.lastSlow) >= SLOW_INTERVAL then
        tracker.slow:push(now, stored)
        tracker.lastSlow = now
    end
end

-- Reset after a source disappears or is swapped, so the rate is not computed
-- across a discontinuity in `stored`.
function metrics.reset(tracker)
    tracker.fast:clear()
    tracker.medium:clear()
    tracker.slow:clear()
    tracker.lastMedium, tracker.lastSlow = nil, nil
end

-- Ring backing a given graph scale, so the UI can plot history without the
-- monitor keeping a second copy of it.
function metrics.series(tracker, scale)
    if scale == "fast" then return tracker.fast end
    if scale == "slow" then return tracker.slow end
    return tracker.medium
end

local function slope(buffer, now, window)
    if buffer.count < 2 then return nil end
    local newT, newV = buffer:newest()
    local oldT, oldV = buffer:since(now, window)
    if not oldT or not newT then return nil end
    local dt = newT - oldT
    if dt <= 0 then return nil end
    return (newV - oldV) / (dt * TICKS_PER_SECOND)
end

-- Live net rate in EU/t (positive = charging).
function metrics.rate(tracker, now, window)
    return slope(tracker.fast, now, window or 5)
end

-- Long-window average in EU/t, or nil until enough history exists.
function metrics.average(tracker, now, window)
    local oldest = tracker.slow:oldest()
    if not oldest then return nil end
    -- Refuse to label a 2-minute sample as a 1-hour average.
    if (now - oldest) < math.min(window, 60) then return nil end
    return slope(tracker.slow, now, window)
end

-- Seconds until full (net > 0) or empty (net < 0).
-- Returns: seconds, direction ("full" | "empty"), or nil when static.
function metrics.projection(stored, capacity, net)
    if not net or net == 0 then return nil, nil end
    if net > 0 then
        if capacity <= 0 or stored >= capacity then return nil, nil end
        return (capacity - stored) / (net * TICKS_PER_SECOND), "full"
    end
    if stored <= 0 then return nil, nil end
    return stored / (-net * TICKS_PER_SECOND), "empty"
end

return metrics
