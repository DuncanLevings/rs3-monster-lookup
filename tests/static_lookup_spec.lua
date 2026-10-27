local lu = require("luaunit")

return function(root)
    local suite = {}
    local function lookup(status, record)
        local reads = 0
        local environment = {
            require = function(name)
                lu.assertEquals(name, "src/data/core")
                return {
                    coverage = function()
                        return { status = status }
                    end,
                    monster = function()
                        reads = reads + 1
                        return record
                    end,
                    info = function()
                        return { built = "2026-10-21" }
                    end,
                }
            end,
        }
        -- No client globals, HTTP or PersistentDB: lookup must be purely static.
        local service = assert(loadfile(root .. "/src/data/lookup/service.lua", "t", environment))()
        return service, function()
            return reads
        end
    end

    function suite:test_covered_monster_comes_from_the_embedded_library()
        local record = { title = "Goblin", sections = {} }
        local service, reads = lookup("covered", record)
        local result, problem, metadata = service.get({ name = "Goblin" })
        lu.assertIs(result, record)
        lu.assertNil(problem)
        lu.assertEquals(metadata.built, "2026-10-21")
        lu.assertEquals(reads(), 1)
    end

    function suite:test_unknown_and_ambiguous_npcs_are_not_guessed_or_fetched()
        for _, status in ipairs({ "unknown", "ambiguous" }) do
            local service, reads = lookup(status, {})
            local result, problem = service.get({ name = "Unknown NPC" })
            lu.assertNil(result)
            lu.assertNotNil(problem)
            lu.assertEquals(reads(), 0)
        end
    end

    function suite:test_excluded_and_no_drop_records_have_distinct_notices()
        for _, status in ipairs({ "excluded", "no_drops" }) do
            local service, reads = lookup(status)
            local result = service.get({ name = "Reference NPC" })
            lu.assertEquals(result.no_drops, status == "excluded" and "not_covered" or "none")
            lu.assertEquals(result.locations, {})
            lu.assertEquals(reads(), 0)
        end
    end

    function suite:test_missing_static_record_is_reported_without_network_fallback()
        local service = lookup("covered")
        local result, problem = service.get({ name = "Missing shard" })
        lu.assertNil(result)
        lu.assertStrContains(problem, "Monster Data Core")
    end

    return suite
end
