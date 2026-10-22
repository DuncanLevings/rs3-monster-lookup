local lu = require("luaunit")

return function(root)
    local suite = {}
    local entries = require("src/data/dungeon_entrances")
    local access = require("src/data/dungeon_access")
    local coordinates = require("src/data/map_coordinates")
    local maps = require("src/data/location_map")

    function suite:test_all_audited_missing_locations_resolve_without_guessing_an_interior()
        local file = assert(io.open(root .. "/tests/support/dungeon_coverage.json", "rb"))
        local cases = require("src/vendor/json").decode(file:read("*a"))
        file:close()
        lu.assertEquals(#cases, 47)
        for _, case in ipairs(cases) do
            -- Deliberately unrelated diagram coordinates must not become a spawn.
            local result = maps.resolve({
                name = case.name,
                map = { id = case.map_id, plane = 0, x = 10, z = 10 },
            })
            assert(result, case.name)
            lu.assertEquals(
                result.target,
                { level = case.level or 0, x = case.x, z = case.z },
                case.name
            )
            lu.assertEquals(result.kind, case.kind, case.name)
            lu.assertNil(result.interior, case.name)
            lu.assertEquals(
                result.tooltip,
                case.kind == "entrance" and "Mark the entrance" or "Mark access point"
            )
        end
    end

    function suite:test_reference_aliases_are_unique_and_every_chain_reaches_the_main_world()
        local seen, lookup = {}, access.new(entries)
        for _, entry in ipairs(entries) do
            lu.assertNil(entry.note)
            for _, page in ipairs(entry.pages) do
                local key = page:gsub("_", " "):gsub("%s+", " "):lower()
                lu.assertNil(seen[key], page)
                seen[key] = true
                local result, reason = lookup.resolve(page)
                assert(result, page .. ": " .. (reason or ""))
                lu.assertTrue(coordinates.contains(28, result.target), page)
            end
        end
    end

    function suite:test_nested_parent_chains_reuse_the_root_and_explain_the_access_point()
        local lookup = access.new({
            { pages = { "Outer" }, x = 3000, z = 3300 },
            { pages = { "Middle" }, parent = "Outer" },
            { pages = { "Inner", "Inner alias" }, parent = "Middle" },
        })
        local result = assert(lookup.resolve("INNER_ALIAS", "Inner chamber"))
        lu.assertEquals(result.target, { level = 0, x = 3000, z = 3300 })
        lu.assertEquals(result.label, "Outer entrance (access to Inner chamber)")
        lu.assertNil(lookup.resolve("Outer quest copy"))
    end

    function suite:test_broken_or_cyclic_parent_data_never_produces_a_marker()
        for _, entries_under_test in ipairs({
            { { pages = { "A" }, parent = "Missing" } },
            { { pages = { "A" }, parent = "B" }, { pages = { "B" }, parent = "A" } },
            { { pages = { "A" }, x = 3000.5, z = 3300 } },
            { { pages = { "A" }, x = 3000, z = 3300, level = 4 } },
        }) do
            local result, reason = access.new(entries_under_test).resolve("A")
            lu.assertNil(result)
            lu.assertNotNil(reason)
        end
    end

    function suite:test_travel_access_is_not_labelled_as_a_dungeon_entrance()
        local result = assert(maps.resolve({ name = "Abyssal Area" }))
        lu.assertEquals(result.kind, "access")
        lu.assertStrContains(result.label, "ALR")
        lu.assertEquals(result.tooltip, "Mark access point")
    end

    return suite
end
