-- Fixed-capacity ring buffer of (time, value) pairs.
--
-- Values live in two flat numeric arrays rather than an array of {t, v} tables:
-- an OpenComputers machine has very little RAM, and a table per sample costs
-- roughly an order of magnitude more than a pair of array slots.

local ring = {}
ring.__index = ring

function ring.new(capacity)
    return setmetatable({
        capacity = capacity,
        count = 0,
        head = 0, -- index of the newest sample
        times = {},
        values = {},
    }, ring)
end

function ring:push(time, value)
    self.head = self.head % self.capacity + 1
    self.times[self.head] = time
    self.values[self.head] = value
    if self.count < self.capacity then self.count = self.count + 1 end
end

-- i = 1 is the oldest retained sample, i = count the newest.
function ring:get(i)
    if i < 1 or i > self.count then return nil end
    local index = (self.head - self.count + i - 1) % self.capacity + 1
    return self.times[index], self.values[index]
end

function ring:newest()
    if self.count == 0 then return nil end
    return self.times[self.head], self.values[self.head]
end

function ring:oldest()
    return self:get(1)
end

function ring:clear()
    self.count, self.head = 0, 0
    self.times, self.values = {}, {}
end

-- Oldest sample no older than `window` seconds before `now`. Falls back to the
-- oldest sample we still have, so a short history degrades to a wider window
-- rather than to no answer at all.
function ring:since(now, window)
    if self.count == 0 then return nil end
    local cutoff = now - window
    local bestT, bestV = self:get(1)
    for i = 1, self.count do
        local t, v = self:get(i)
        if t >= cutoff then return t, v end
        bestT, bestV = t, v
    end
    return bestT, bestV
end

return ring
