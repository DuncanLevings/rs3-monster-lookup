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

    function suite:test_server_utc_anchor_keeps_time_without_os_and_rejects_bad_dates()
        local environment = setmetatable({ os = false }, { __index = _G })
        local clock = assert(loadfile(root .. "/src/utils/cache_clock.lua", "t", environment))()
        lu.assertTrue(clock.synchronize("2026-10-21T00:00:00Z"))
        lu.assertEquals(clock.now(), 1792540800)
        lu.assertFalse(clock.synchronize("2026-02-29T00:00:00Z"))
        lu.assertFalse(clock.synchronize("not a timestamp"))
        lu.assertEquals(clock.now(), 1792540800)
        lu.assertTrue(clock.synchronize("2024-02-29T12:30:00Z"))
        lu.assertEquals(clock.now(), 1709209800)
    end

    return suite
end
