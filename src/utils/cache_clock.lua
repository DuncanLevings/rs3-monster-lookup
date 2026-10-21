-- time source for cache ages
-- now() uses os.time when available, otherwise a Wiki UTC timestamp plus client ticks.
-- elapsed() is session time, independent of wall-clock adjustments.

local utc = require("src/utils/utc")

local clock = { TICKS_PER_SECOND = 50 }
local SUBSCRIPTION = "monster_lookup_cache_clock"
local elapsed = 0
local server_time
local synchronized_at

function clock.start()
    Event.Logic.Subscribe(SUBSCRIPTION, function()
        elapsed = elapsed + 1 / clock.TICKS_PER_SECOND
    end)
end

function clock.stop()
    Event.Logic.Unsubscribe(SUBSCRIPTION)
end

function clock.elapsed()
    return elapsed
end

function clock.now()
    if os and type(os.time) == "function" then
        return os.time()
    end

    if server_time then
        return server_time + elapsed - synchronized_at
    end

    return nil
end

-- One tiny API query establishes wall time when the client has no os library.
-- Only the anchor stays in memory; entry timestamps are persisted by the cache.
function clock.synchronize(timestamp)
    local seconds = utc.parse(timestamp)

    if not seconds then
        return false
    end

    server_time, synchronized_at = seconds, elapsed
    return true
end

return clock
