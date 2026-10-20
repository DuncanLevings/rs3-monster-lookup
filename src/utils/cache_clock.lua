-- time source for cache ages
-- now() is wall clock seconds if the sandbox gives us os.time, elapsed() is seconds since
-- the plugin started counted from logic ticks so it works either way

local clock = { TICKS_PER_SECOND = 50 }
local SUBSCRIPTION = "monster_lookup_cache_clock"
local elapsed = 0

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

    -- no wall clock means saved entries from older sessions have to be refreshed
    return nil
end

return clock
