local lu = require("luaunit")

return function(root)
    local suite = {}

    function suite:test_missing_os_library_uses_client_ticks_without_raising_an_error()
        local tick
        local environment = setmetatable({
            os = false,
            Event = {
                Logic = {
                    Subscribe = function(_, callback)
                        tick = callback
                    end,
                    Unsubscribe = function()
                        tick = nil
                    end,
                },
            },
        }, { __index = _G })
        local clock = assert(loadfile(root .. "/src/utils/cache_clock.lua", "t", environment))()

        lu.assertNil(clock.now())
        clock.start()
        for _ = 1, 50 do
            tick()
        end

        lu.assertAlmostEquals(clock.elapsed(), 1, 0.00001)
        clock.stop()
        lu.assertNil(tick)
    end

    return suite
end
