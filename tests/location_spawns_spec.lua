local lu = require("luaunit")
return function(root)
    local suite = {}
    local context = require("tests/support/window_fixture").new(root)
    local parser = context.load_module("tools/wiki/monster_locations")
    local pins = context.load_module("tools/wiki/location_spawns")
    local maps = context.load_core("src/locations/resolve")
    local planner = context.load_module("src/data/locations/navigation").new(
        context.load_module("src/data/locations/routes"),
        context.load_core("src/locations/coordinates")
    )
    local function read(name)
        local file = assert(io.open(root .. "/tests/support/" .. name, "rb"))
        local content = file:read("*a")
        file:close()
        return content
    end
    local function rows()
        local result = parser.parse(read("infested_axe_locations.html"))
        pins.attach(result, read("infested_axe_locations.wiki"))
        return result
    end

    function suite:test_infested_axe_uses_real_spawn_on_the_entrance_floor_instead_of_map_centre()
        local locations = rows()
        lu.assertEquals(#locations[1].spawn_maps, 44)
        lu.assertEquals(#locations[2].spawn_maps, 18)
        local goal = assert(maps.resolve(locations[1]))
        lu.assertEquals(#goal.interiors, 44)
        local step = assert(planner.next(goal, { level = 3, x = 4645, z = 5400 }))
        lu.assertTrue(step.final)
        lu.assertEquals(step.target, { level = 3, x = 4661, z = 5405 })
        -- This is a known pin, not the HTML link's 3391,9535 viewport centre.
        local next_step = assert(planner.next(goal, { level = 3, x = 4650, z = 5400 }))
        lu.assertEquals(next_step.target, step.target)
    end

    function suite:test_floor_changes_choose_another_real_spawn_and_surface_still_points_to_entrance()
        local goal = assert(maps.resolve(rows()[1]))
        local top = assert(planner.next(goal, { level = 3, x = 4645, z = 5400 }))
        local lower = assert(planner.next(goal, { level = 1, x = 4645, z = 5400 }))
        lu.assertEquals(top.target.level, 3)
        lu.assertEquals(lower.target.level, 1)
        local surface = assert(planner.next(goal, { level = 0, x = 3410, z = 3330 }))
        lu.assertFalse(surface.final)
        lu.assertEquals(surface.target, goal.target)
    end

    function suite:test_resource_row_does_not_borrow_main_dungeon_spawns()
        local goal = assert(maps.resolve(rows()[2]))
        local step = assert(planner.next(goal, { level = 3, x = 4700, z = 5600 }))
        lu.assertEquals(step.target.level, 3)
        lu.assertTrue(step.target.z >= 5568)
        lu.assertEquals(goal._selected_spawn.map_id, 267)
    end

    return suite
end
