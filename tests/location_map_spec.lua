local lu = require("luaunit")

return function(root)
    local suite = {}
    local fixture = require("tests/support/window_fixture").new(root)
    local maps = fixture.load_module("src/data/locations/resolve")

    function suite:test_dungeon_diagrams_resolve_to_verified_surface_entrances()
        for _, entry in ipairs({
            {
                name = "Kuradal's Dungeon",
                id = 36,
                x = 100,
                z = 102,
                target = { level = 0, x = 2510, z = 3506 },
            },
            {
                name = "Morytania Slayer Tower dungeon",
                id = 717,
                x = 1182,
                z = 4620,
                target = { level = 0, x = 3434, z = 3532 },
            },
            {
                name = "Lair of Tarn Razorlor",
                id = 30,
                x = 109,
                z = 39,
                target = { level = 0, x = 3429, z = 3233 },
            },
            {
                name = "Fremennik Slayer Dungeon",
                id = 5,
                x = 2751,
                z = 10003,
                target = { level = 0, x = 2798, z = 3615 },
            },
            {
                name = "Chaos Tunnels",
                id = 23,
                x = 3182,
                z = 5470,
                target = { level = 0, x = 3058, z = 3550 },
            },
        }) do
            local resolution = maps.resolve({
                name = entry.name,
                map = { id = entry.id, plane = 2, x = entry.x, z = entry.z },
            })
            lu.assertEquals(resolution.target, entry.target)
            lu.assertEquals(resolution.kind, "entrance")
            lu.assertNotEquals(resolution.tooltip, "")
        end
    end

    function suite:test_verified_entrance_can_work_without_monster_map_coordinates()
        local resolution = maps.resolve({
            name = "Cave (Floor 2)",
            page = "Kuradal's Dungeon",
            requirements = "Quest required",
        })
        lu.assertEquals(resolution.target, { level = 0, x = 2510, z = 3506 })
        lu.assertEquals(resolution.tooltip, "Mark the entrance")
        lu.assertStrContains(resolution.label, "whirlpool")
    end

    function suite:test_shared_map_ids_and_similar_names_do_not_guess_an_entrance()
        for _, location in ipairs({
            { name = "Unknown cave", map = { id = 36, plane = 0, x = 100, z = 102 } },
            { name = "Taverley Dungeon annex" },
            { name = "Taverley Dungeon", page = "A different dungeon" },
            { name = "Unknown" },
        }) do
            local target, reason = maps.target(location)
            lu.assertNil(target)
            lu.assertNotNil(reason)
        end
    end

    function suite:test_quest_instances_and_unverified_coordinates_are_not_world_targets()
        for _, location in ipairs({
            { name = "Quest instance", map = { id = 28, plane = 0, x = 3200, z = 3400 } },
            { name = "Taverley Dungeon (during Test quest)", page = "Taverley Dungeon" },
            { name = "Unknown", map = { id = -1, plane = 0, x = 3169, z = 4589 } },
            { name = "Unknown", map = { id = 28, plane = 0, x = 109, z = 39 } },
            { name = "Unknown", map = { id = 28, plane = 0, x = 3200, z = 10000 } },
            { name = "Unknown", map = { id = 28, plane = 0, x = 8000, z = 3400 } },
            { name = "Unknown", map = { id = 28, plane = 0, x = 0 / 0, z = 3400 } },
        }) do
            local resolution, reason = maps.resolve(location)
            lu.assertNil(resolution)
            lu.assertNotNil(reason)
        end
    end

    function suite:test_bad_or_conflicting_map_metadata_cannot_fall_back_to_an_entrance()
        for _, issue in ipairs({ "invalid", "ambiguous" }) do
            lu.assertNil(maps.resolve({ name = "Taverley Dungeon", map_issue = issue }))
        end
        lu.assertNil(maps.resolve({
            name = "Taverley Dungeon",
            map = { id = 28, plane = 9, x = 2885, z = 3397 },
        }))
    end

    function suite:test_surface_and_tower_floors_keep_their_original_destination()
        local target = maps.target({
            name = "Slayer Tower (Floor 2)",
            map = { id = 28, plane = 2, x = 3407, z = 3546 },
        })
        lu.assertEquals(target, { level = 2, x = 3407, z = 3546 })
        lu.assertNil(maps.resolve(nil))
    end

    function suite:test_pollnivneach_continues_from_well_to_transformed_lower_floor()
        local resolution = maps.resolve({
            name = "Pollnivneach Slayer Dungeon",
            map = { id = 22, plane = 0, x = 142, z = 22 },
        })
        lu.assertEquals(resolution.target, { level = 0, x = 3359, z = 2972 })
        lu.assertEquals(resolution.kind, "entrance")
        lu.assertEquals(resolution.interior, { level = 0, x = 3310, z = 4310 })
        lu.assertEquals(resolution.interior_map, 22)
        lu.assertEquals(resolution.tooltip, "Mark the entrance")
    end

    function suite:test_polypore_resource_dungeon_resolves_shared_diagram_to_dedicated_native_region()
        local resolution = maps.resolve({
            name = "Polypore Dungeon resource dungeon",
            page = "Polypore Dungeon resource dungeon",
            map = { id = 41, plane = 0, x = 3291, z = 9518 },
        })
        lu.assertEquals(resolution.kind, "entrance")
        lu.assertEquals(resolution.target, { level = 0, x = 3409, z = 3330 })
        lu.assertStrContains(resolution.label, "access to resource dungeon")
        lu.assertEquals(resolution.interior, { level = 2, x = 4699, z = 5582 })
        lu.assertEquals(resolution.interior_map, 267)
        lu.assertEquals(resolution.tooltip, "Mark the entrance")
    end

    return suite
end
