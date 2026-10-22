local lu = require("luaunit")
return function(root)
    local suite = {}
    local context = require("tests/support/window_fixture").new(root)
    local c = context.load_core("src/locations/coordinates")
    local graph = context.load_module("src/data/locations/routes")
    local planner = context.load_module("src/data/locations/navigation").new(graph, c)
    local maps = context.load_core("src/locations/resolve")

    function suite:test_authored_connections_have_bounded_departures_and_valid_arrival_floors()
        local count = 0
        for _, edge in ipairs(context.load_module("src/data/locations/dungeons/connections")) do
            count = count + 1
            lu.assertNotNil(graph.nodes[edge.from])
            lu.assertNotNil(graph.nodes[edge.to])
            if edge.target then
                lu.assertTrue(c.contains(edge.from, edge.target), edge.label)
            end
            if edge.arrival then
                lu.assertTrue(c.contains(edge.to, edge.arrival), edge.label)
                lu.assertEquals(edge.to_level, edge.arrival.level)
            end
            if edge.query then
                lu.assertTrue(edge.query.unique)
                lu.assertTrue(edge.query.range <= 64)
            end
        end
        lu.assertTrue(count >= 100)
    end

    function suite:test_resource_exit_then_main_dungeon_exit_then_surface_destination()
        local goal =
            { kind = "location", target = { level = 0, x = 3220, z = 3200 }, label = "Destination" }
        local step = assert(planner.next(goal, { level = 0, x = 1380, z = 4580 }))
        lu.assertFalse(step.final)
        lu.assertEquals(step.target, { level = 0, x = 1395, z = 4587 })
        step = assert(planner.next(goal, { level = 0, x = 2852, z = 9840 }))
        lu.assertFalse(step.final)
        lu.assertEquals(step.target, { level = 0, x = 2886, z = 9795 })
        step = assert(planner.next(goal, { level = 0, x = 2885, z = 3397 }))
        lu.assertTrue(step.final)
        lu.assertEquals(step.target, goal.target)
    end

    function suite:test_living_rock_parent_rope_and_asylum_elevator_are_waypoints()
        for _, case in ipairs({
            {
                name = "Living Rock Caverns",
                map = { id = 35, plane = 0, x = 3650, z = 5100 },
                position = { level = 0, x = 3015, z = 9835 },
                target = { level = 0, x = 3012, z = 9831 },
            },
            {
                name = "Senntisten Asylum",
                map = { id = 738, plane = 0, x = 1985, z = 1475 },
                position = { level = 0, x = 1790, z = 1340 },
                target = { level = 0, x = 1795, z = 1345 },
            },
        }) do
            local goal = assert(maps.resolve(case))
            local step = assert(planner.next(goal, case.position))
            lu.assertFalse(step.final)
            lu.assertEquals(step.target, case.target)
            step = assert(planner.next(goal, goal.interior))
            lu.assertTrue(step.final)
        end
    end

    function suite:test_pollnivneach_separate_chambers_use_stairs_on_the_same_native_floor()
        local goal = assert(maps.resolve({
            name = "Pollnivneach Slayer Dungeon",
            map = { id = 22, plane = 0, x = 142, z = 22 },
        }))
        local position = { level = 0, x = 3359, z = 9355 }
        lu.assertFalse(c.connected(22, position, goal.interior))
        local step = assert(planner.next(goal, position))
        lu.assertFalse(step.final)
        lu.assertTrue(step.target.z > 9300)
        step = assert(planner.next(goal, { level = 0, x = 3310, z = 4310 }))
        lu.assertTrue(step.final)
    end

    function suite:test_ancient_cavern_floor_changes_use_an_authored_ladder()
        local lower = assert(c.world({ id = 36, plane = 0, x = 42, z = 182 }))
        local upper = assert(c.world({ id = 36, plane = 0, x = 169, z = 118 }))
        local goal = {
            kind = "entrance",
            target = { level = 0, x = 2510, z = 3506 },
            interior = upper,
            interior_map = 36,
            destination_label = "Upper floor",
        }
        lu.assertNotEquals(lower.level, upper.level)
        local step = assert(planner.next(goal, lower))
        lu.assertFalse(step.final)
        lu.assertEquals(step.target.level, lower.level)
        lu.assertStrContains(step.label, "Ladder")
        lu.assertTrue(planner.next(goal, upper).final)
    end

    function suite:test_legacy_maps_do_not_override_a_dedicated_dungeon_exit()
        local goal =
            { kind = "location", target = { level = 0, x = 3200, z = 3200 }, label = "Outside" }
        local step = assert(planner.next(goal, { level = 0, x = 2700, z = 9560 }))
        lu.assertFalse(step.final)
        lu.assertStrContains(step.label, "Brimhaven")
    end

    function suite:test_prifddinas_resource_exits_return_to_the_city_platform()
        for _, name in ipairs({ "Gorajo Hoardstalker Dungeon", "Edimmu resource dungeon" }) do
            local goal = assert(maps.resolve({ name = name }))
            lu.assertEquals(goal.target.level, 1)
        end
        local outside =
            { kind = "location", target = { level = 0, x = 3220, z = 3200 }, label = "Outside" }
        local step = assert(planner.next(outside, { level = 0, x = 1373, z = 4609 }))
        lu.assertFalse(step.final)
        lu.assertStrContains(step.label, "Prifddinas")
    end

    function suite:test_placeholder_maps_never_accept_a_storage_coordinate()
        for _, id in ipairs({ 161, 570, 702, 703 }) do
            lu.assertFalse(c.contains(id, { level = 0, x = 100, z = 100 }))
            lu.assertNil(c.world({ id = id, plane = 0, x = 100, z = 100 }))
        end
    end

    function suite:test_unknown_floor_transitions_pause_without_routing_out_and_back_in()
        local goal = assert(maps.resolve({
            name = "Polypore Dungeon",
            map = { id = 41, plane = 0, x = 3400, z = 9740 },
        }))
        local step, reason = planner.next(goal, { level = 0, x = 4616, z = 5452 })
        lu.assertNil(step)
        lu.assertStrContains(reason, "destination floor")
    end

    function suite:test_native_resource_coordinates_resolve_through_exact_location_aliases()
        local file = assert(io.open(root .. "/tests/support/dungeon_interior_spawns.json", "rb"))
        local cases = require("src/vendor/json").decode(file:read("*a"))
        file:close()
        local count = 0
        for _, case in ipairs(cases) do
            if case.name:lower():find("resource dungeon", 1, true) then
                local goal = assert(maps.resolve({
                    name = case.name,
                    map = {
                        id = -1,
                        plane = case.target.level,
                        x = case.target.x,
                        z = case.target.z,
                    },
                }))
                lu.assertEquals(goal.interior, case.target, case.name)
                count = count + 1
            end
        end
        lu.assertTrue(count >= 8)
    end

    return suite
end
