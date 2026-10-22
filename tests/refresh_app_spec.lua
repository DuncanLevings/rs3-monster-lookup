local lu = require("luaunit")

return function(root)
    local suite = {}
    function suite:test_manual_refresh_never_opens_or_renders_the_lookup_window()
        local refresh, requested, receive
        local function noop() end
        local function unexpected()
            error("Settings refresh must not open or render a lookup")
        end
        local modules = {
            ["src/game/npc_menu"] = { start = noop, stop = noop },
            ["src/game/locations/marker"] = { start = noop, stop = noop },
            ["src/settings"] = { menu_colour_hex = noop },
            ["src/ui/monster_window"] = {
                open = unexpected,
                show_result = unexpected,
                show_error = unexpected,
                refresh_settings = noop,
                destroy = noop,
            },
            ["src/ui/search/window"] = { start = noop, destroy = noop },
            ["src/data/drops/prices"] = { stop = noop },
            ["src/ui/settings/content"] = { start = noop, stop = noop },
            ["src/ui/settings/panel"] = {
                start = function(_, callback)
                    refresh = callback
                end,
                stop = noop,
            },
            ["src/data/lookup_service"] = {
                start = noop,
                stop = noop,
                cancel = noop,
                fetch = function(monster, callback, force)
                    requested = { monster = monster, force = force }
                    receive = callback
                end,
            },
        }
        local environment = {
            require = function(name)
                return assert(modules[name], name)
            end,
            prettyui = { Window = {} },
            log = noop,
            assert = assert,
            Event = { GameStateChanged = { Subscribe = noop, Unsubscribe = noop } },
        }
        local app = assert(loadfile(root .. "/src/app.lua", "t", environment))()
        app.start()
        local monster = { name = "General Graardor", npc_id = 6260 }
        local messages = {}
        refresh(monster, function(ok, problem)
            messages[#messages + 1] = { ok = ok, problem = problem }
        end)
        lu.assertEquals(requested, { monster = monster, force = true })
        receive({}, nil, { refreshing = true })
        lu.assertEquals(#messages, 0)
        receive({}, nil, { stale = false })
        lu.assertTrue(messages[1].ok)
        receive(nil, "Wiki unavailable", {})
        lu.assertFalse(messages[2].ok)
        lu.assertEquals(messages[2].problem, "Wiki unavailable")
        app.stop()
    end
    return suite
end
