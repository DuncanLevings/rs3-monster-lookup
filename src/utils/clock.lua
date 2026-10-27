-- elapsed client time for search delays and marker feedback; no wall clock or network.
local clock = { TICKS_PER_SECOND = 50 }
local tick = 0
local running = false

function clock.start()
    if running then
        return
    end

    running = true
    Event.Logic.Subscribe("monster_lookup_clock", function()
        tick = tick + 1
    end)
end

function clock.stop()
    Event.Logic.Unsubscribe("monster_lookup_clock")
    running = false
end

function clock.elapsed()
    return tick / clock.TICKS_PER_SECOND
end

return clock
