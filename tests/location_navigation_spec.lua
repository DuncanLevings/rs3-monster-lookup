local lu = require("luaunit")
return function(root)
    local suite = {}
    local context = require("tests/support/window_fixture").new(root)
    local factory = context.load_module("src/data/locations/navigation")
    local coordinates = context.load_core("src/locations/coordinates")

    function suite:test_map_transforms_recover_dungeon_coordinates_and_floors()
        lu.assertEquals(
            coordinates.world({ id = 30, plane = 0, x = 45, z = 82 }),
            { level = 0, x = 3149, z = 4650 }
        )
        lu.assertEquals(
            coordinates.world({ id = 30, plane = 0, x = 109, z = 39 }),
            { level = 1, x = 3149, z = 4575 }
        )
        lu.assertNil(coordinates.world({ id = 30, plane = 0, x = 900, z = 900 }))
        lu.assertFalse(coordinates.contains(28, { level = 0, x = 3149, z = 4650 }))
        lu.assertTrue(coordinates.contains(30, { level = 0, x = 3149, z = 4650 }))
    end

    function suite:test_planner_uses_injected_connections_with_unrelated_map_ids()
        local graph = {
            surface = 800,
            nodes = {
                [800] = {},
                [801] = {
                    name = "First",
                    exits = { { to = 802, query = { name = "A gate" }, label = "First exit" } },
                },
                [802] = { name = "Second", exits = { { to = 801 }, { to = 800 } } },
            },
        }
        local planner = factory.new(graph, {
            contains = function(map, point)
                return point.map == map
            end,
        })
        local goal = { target = { level = 0, x = 10, z = 20 }, label = "Destination" }
        local calls = 0
        local exit = { level = 2, x = 30, z = 40 }
        local step = planner.next(goal, { map = 801, level = 2 }, function(query, _, source)
            calls = calls + 1
            lu.assertEquals(query.name, "A gate")
            lu.assertEquals(source, 801)
            return exit
        end)
        lu.assertEquals(calls, 1)
        lu.assertEquals(step.target, exit)
        lu.assertFalse(step.final)
        lu.assertEquals(step.map_level, 2)
        lu.assertEquals(step.label, "First exit")
        lu.assertEquals(planner.next(goal, { map = 800, level = 2 }).target, goal.target)
        lu.assertTrue(planner.next(goal, { map = 800, level = 2 }).final)
        goal.interior, goal.interior_map, goal.destination_label = exit, 802, "Monster room"
        lu.assertFalse(planner.next(goal, { map = 800, level = 2 }).final)
        lu.assertEquals(planner.next(goal, { map = 802, level = 2 }).target, exit)
        lu.assertTrue(planner.next(goal, { map = 802, level = 2 }).final)
    end

    function suite:test_unknown_ambiguous_and_cyclic_routes_pause_without_guessing()
        local planner = factory.new({
            surface = 800,
            nodes = {
                [801] = { exits = { { to = 802 } } },
                [802] = { exits = { { to = 801 } } },
            },
        }, {
            contains = function(id, point)
                return point.map == id or point.map == "overlap"
            end,
        })
        local goal = { target = { level = 0, x = 10, z = 20 }, label = "Destination" }
        lu.assertNil(planner.next(goal, { map = 801, level = 2 }))
        lu.assertNil(planner.next(goal, { map = "unknown" }))
        lu.assertNil(planner.next(goal, { map = "overlap" }))
        lu.assertNil(planner.next(goal, nil))
    end

    function suite:test_entrance_only_guidance_never_counts_as_final_arrival()
        local planner = factory.new({ surface = 28, nodes = { [28] = {} } }, {
            contains = function(id, position)
                return id == position.map
            end,
        })
        local goal = { kind = "entrance", target = { level = 0, x = 1, z = 2 }, label = "Entrance" }
        lu.assertFalse(planner.next(goal, { map = 28 }).final)
        local step, reason = planner.next(goal, { map = 999 })
        lu.assertNil(step)
        lu.assertStrContains(reason, "still saved")
    end

    function suite:test_parent_portal_is_nonfinal_and_destination_disambiguates_overlapping_maps()
        local planner = factory.new(
            { surface = 28, nodes = { [28] = {}, [10] = {}, [11] = {}, [12] = {} } },
            {
                contains = function(id, position)
                    return id == position.map or (id == 12 and position.map == 11)
                end,
            }
        )
        local goal = {
            kind = "entrance",
            target = { level = 0, x = 1, z = 2 },
            interior = { level = 0, x = 3, z = 4 },
            interior_map = 11,
            destination_label = "Spawn",
            portal = {
                map_id = 10,
                target = { level = 0, x = 5, z = 6 },
                label = "Resource portal",
            },
        }
        local step = planner.next(goal, { map = 10, level = 0 })
        lu.assertEquals(step.target, goal.portal.target)
        lu.assertFalse(step.final)
        step = planner.next(goal, { map = 11, level = 0 })
        lu.assertEquals(step.target, goal.interior)
        lu.assertTrue(step.final)
    end

    function suite:test_real_wiki_spawns_continue_after_entering_the_dungeon()
        local file = assert(io.open(root .. "/tests/support/dungeon_interior_spawns.json", "rb"))
        local cases = require("src/data/library/vendor/json").decode(file:read("*a"))
        file:close()
        local maps = context.load_core("src/locations/resolve")
        local planner = factory.new(context.load_module("src/data/locations/routes"), coordinates)
        lu.assertTrue(#cases >= 40)
        for _, case in ipairs(cases) do
            local goal = assert(maps.resolve({ name = case.name, map = case.map }))
            lu.assertEquals(goal.interior, case.target, case.monster .. " - " .. case.name)
            local step = assert(planner.next(goal, case.target))
            lu.assertTrue(step.final, case.name)
            lu.assertEquals(step.target, case.target, case.name)
        end
    end

    function suite:test_shared_diagrams_use_the_selected_cave_on_all_floors()
        local maps = context.load_core("src/locations/resolve")
        local planner = factory.new(context.load_module("src/data/locations/routes"), coordinates)
        local goal = assert(maps.resolve({
            name = "Polypore Dungeon",
            map = { id = 41, plane = 0, x = 3400, z = 9740 },
        }))
        lu.assertEquals(goal.interior, { level = 3, x = 4616, z = 5452 })
        lu.assertEquals(goal.interior_map, 266)
        local step, reason, outcome = planner.next(goal, { level = 0, x = 4616, z = 5452 })
        lu.assertNil(step)
        lu.assertStrContains(reason, "destination floor")
        lu.assertEquals(outcome, "interior_unavailable")
        lu.assertTrue(planner.next(goal, { level = 3, x = 4616, z = 5452 }).final)
        lu.assertFalse(coordinates.contains(266, { level = 0, x = 3500, z = 9800 }))
        goal = assert(maps.resolve({
            name = "Pollnivneach Slayer Dungeon",
            map = { id = 22, plane = 0, x = 110, z = 30 },
        }))
        lu.assertEquals(goal.interior, { level = 0, x = 3278, z = 4318 })
        lu.assertTrue(planner.next(goal, goal.interior).final)
    end

    function suite:test_native_coordinates_need_a_matching_authored_destination_region()
        local maps = context.load_core("src/locations/resolve")
        local goal = assert(maps.resolve({
            name = "Polypore Dungeon resource dungeon",
            map = { id = -1, plane = 3, x = 4700, z = 5600 },
        }))
        lu.assertEquals(goal.interior, { level = 3, x = 4700, z = 5600 })
        lu.assertEquals(goal.interior_map, 267)
        goal = assert(maps.resolve({
            name = "Polypore Dungeon resource dungeon",
            map = { id = -1, plane = 0, x = 100, z = 100 },
        }))
        lu.assertNil(goal.interior)
    end

    function suite:test_authored_resource_portals_belong_to_their_parent_map()
        for name, portal in pairs(context.load_core("src/locations/dungeons/portals")) do
            if portal.target then
                lu.assertTrue(coordinates.contains(portal.map_id, portal.target), name)
            else
                lu.assertTrue(portal.query.unique, name)
                lu.assertTrue(portal.query.range <= 64, name)
            end
        end
    end

    function suite:test_parent_resource_entrance_does_not_complete_an_entrance_only_goal()
        local maps = context.load_core("src/locations/resolve")
        local planner = factory.new(context.load_module("src/data/locations/routes"), coordinates)
        local goal = assert(maps.resolve({ name = "Taverley blue dragon resource dungeon" }))
        local step, _, outcome = planner.next(goal, { level = 0, x = 2911, z = 9811 })
        lu.assertNotNil(step)
        lu.assertNil(outcome)
        lu.assertFalse(step.final)
        step, _, outcome = planner.next(goal, { level = 0, x = 967, z = 4498 })
        lu.assertNil(step)
        lu.assertEquals(outcome, "interior_unavailable")
        step, _, outcome = planner.next(goal, { level = 0, x = 100, z = 100 })
        lu.assertNil(step)
        lu.assertNil(outcome)
    end

    return suite
end
