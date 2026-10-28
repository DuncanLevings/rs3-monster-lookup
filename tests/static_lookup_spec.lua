local lu = require("luaunit")

return function(root)
    local suite = {}
    local function lookup(status, record, can_open)
        local reads = 0
        local selected
        local shown, problem, built
        local function noop() end
        local library = {
            monster = function()
                reads = reads + 1
                return status == "covered" and record or nil, { status = status }
            end,
            info = function()
                return { built = "2026-10-21" }
            end,
        }
        local window = {
            open = function()
                return can_open ~= false
            end,
            show_result = function(result, built_date)
                shown, built = result, built_date
            end,
            show_error = function(message)
                problem = message
            end,
            refresh_settings = noop,
        }
        local passive = { start = noop }
        local modules = {
            ["src/data/library/api"] = library,
            ["src/ui/monster_window"] = window,
            ["src/game/npc_menu"] = {
                start = function(callback)
                    selected = callback
                end,
            },
            ["src/ui/settings/panel"] = passive,
            ["src/ui/search/window"] = passive,
            ["src/settings"] = {},
            ["src/game/locations/marker"] = passive,
            ["src/data/drops/prices"] = {},
        }
        -- Exercise the actual selection path without network, storage or native UI.
        local environment = setmetatable({
            require = function(name)
                return assert(modules[name], name)
            end,
            prettyui = { Window = {} },
            Event = { GameStateChanged = { Subscribe = noop } },
            log = noop,
        }, { __index = _G })
        local app = assert(loadfile(root .. "/src/app.lua", "t", environment))()
        app.start()
        return {
            get = function(monster)
                selected(monster)
                return shown, problem, built
            end,
        }, function()
            return reads
        end
    end

    function suite:test_covered_monster_comes_from_the_embedded_library()
        local record = { title = "Goblin", sections = {} }
        local service, reads = lookup("covered", record)
        local result, problem, built = service.get({ name = "Goblin" })
        lu.assertIs(result, record)
        lu.assertNil(problem)
        lu.assertEquals(built, "2026-10-21")
        lu.assertEquals(reads(), 1)
    end

    function suite:test_unknown_and_ambiguous_npcs_are_not_guessed_or_fetched()
        for _, status in ipairs({ "unknown", "ambiguous" }) do
            local service, reads = lookup(status, {})
            local result, problem = service.get({ name = "Unknown NPC" })
            lu.assertNil(result)
            lu.assertNotNil(problem)
            lu.assertEquals(reads(), 1)
        end
    end

    function suite:test_excluded_and_no_drop_records_have_distinct_notices()
        for _, status in ipairs({ "excluded", "no_drops" }) do
            local service, reads = lookup(status)
            local result = service.get({ name = "Reference NPC" })
            lu.assertEquals(result.no_drops, status == "excluded" and "not_covered" or "none")
            lu.assertEquals(result.locations, {})
            lu.assertEquals(reads(), 1)
        end
    end

    function suite:test_missing_static_record_is_reported_without_network_fallback()
        local service = lookup("covered")
        local result, problem = service.get({ name = "Missing shard" })
        lu.assertNil(result)
        lu.assertStrContains(problem, "Monster Data Core")
    end

    function suite:test_unavailable_window_does_not_read_the_library()
        local selection, reads = lookup("covered", { title = "Goblin" }, false)
        local result, problem = selection.get({ name = "Goblin" })
        lu.assertNil(result)
        lu.assertNil(problem)
        lu.assertEquals(reads(), 0)
    end

    return suite
end
