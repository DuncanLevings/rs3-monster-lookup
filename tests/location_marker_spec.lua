local lu = require("luaunit")
local window_fixture = require("tests/support/window_fixture")
local marker_fixture = require("tests/support/marker_fixture")

return function(root)
    local suite = {}

    function suite:setUp()
        self.context = window_fixture.new(root)
        self.hints = marker_fixture.enable(self.context)
        self.marker = self.context.load_module("src/game/location_marker")
        self.location = { name = "Slayer Tower", map = { id = 28, plane = 2, x = 3407, z = 3546 } }
        self.marker.start()
    end

    function suite:tearDown()
        self.marker.stop()
    end

    function suite:test_surface_target_preserves_axes_floor_and_tile_centre()
        lu.assertTrue(self.marker.mark(self.location, "Abyssal demon"))
        self.context:tick(1)
        local arrow = self.hints.arrow
        local area = self.hints.area
        lu.assertEquals(area.coordGrid, { level = 0, x = 3407, z = 3546 })
        lu.assertTrue(area.drawOnWorldMap)
        lu.assertFalse(area.drawOnMiniMap)
        lu.assertEquals(arrow.coordFine.level, 2)
        lu.assertEquals(arrow.coordFine.x, 3407 * 512 + 256)
        lu.assertEquals(arrow.coordFine.z, 3546 * 512 + 256)
        lu.assertStrContains(self.marker.status(), "Abyssal demon - Slayer Tower")
    end

    function suite:test_repeated_selections_and_ticks_do_not_recreate_native_hints()
        for _ = 1, 100 do
            self.marker.mark(self.location, "Abyssal demon")
        end
        self.context:tick(100)
        lu.assertEquals(self.hints.adds, 3)
        lu.assertEquals(self.hints.removes, 0)
    end

    function suite:test_switching_destinations_replaces_only_our_hints()
        self.hints.arrows.other_plugin = { name = "other_plugin" }
        self.marker.mark(self.location, "Abyssal demon")
        self.context:tick(1)
        local first_name = self.hints.arrow.name
        self.location.map.x = 3225
        self.marker.mark(self.location, "Guard")
        lu.assertEquals(self.hints.adds, 3)
        self.context:tick(1)
        lu.assertNil(self.hints.arrow)
        self.context:tick(2)
        lu.assertNotEquals(self.hints.arrow.name, first_name)
        lu.assertEquals(self.hints.adds, 6)
        lu.assertEquals(self.hints.removes, 3)
        lu.assertNotNil(self.hints.arrows.other_plugin)
        lu.assertEquals(self.hints.area.coordGrid.x, 3225)
        self.marker.clear()
        self.context:tick(1)
        lu.assertNotNil(self.hints.arrows.other_plugin)
        lu.assertNil(self.hints.arrow)
    end

    function suite:test_partial_native_failure_rolls_back_both_hints()
        self.hints.reject_polygon = true
        local accepted, problem = self.marker.mark(self.location, "Abyssal demon")
        lu.assertTrue(accepted)
        lu.assertNil(problem)
        self.context:tick(1)
        lu.assertStrContains(self.marker.status(), "could not create")
        lu.assertNil(next(self.hints.arrows))
        lu.assertNil(next(self.hints.polygons))
        lu.assertFalse(self.marker.has_target())
    end

    function suite:test_native_exceptions_are_reported_without_escaping_the_action()
        self.hints.throw_arrow = true
        lu.assertTrue(self.marker.mark(self.location, "Abyssal demon"))
        self.context:tick(1)
        lu.assertFalse(self.marker.has_target())
        lu.assertStrContains(self.marker.status(), "could not create")
    end

    function suite:test_separate_maps_missing_coordinates_and_unavailable_apis_do_not_register()
        self.location.map.id = 30
        lu.assertFalse(self.marker.mark(self.location, "Skeleton"))
        self.location.map = nil
        lu.assertFalse(self.marker.mark(self.location, "Skeleton"))
        self.location.map = { id = 28, plane = 0, x = 3225, z = 3439 }
        self.context.environment.HintList = nil
        lu.assertStrContains(self.marker.reason(self.location), "unavailable")
        lu.assertFalse(self.marker.mark(self.location, "Guard"))
        lu.assertEquals(self.hints.adds, 0)
    end

    function suite:test_instance_transition_suspends_and_restores_the_surface_target()
        self.marker.mark(self.location, "Abyssal demon")
        self.context:tick(1)
        self.hints.region = true
        self.context:tick(50)
        lu.assertNil(next(self.hints.arrows))
        lu.assertTrue(self.marker.has_target())
        lu.assertStrContains(self.marker.status(), "Paused")
        self.context:tick(100)
        lu.assertEquals(self.hints.adds, 3)
        self.hints.region = false
        self.context:tick(50)
        lu.assertEquals(self.hints.adds, 6)
        lu.assertNotNil(next(self.hints.arrows))
    end

    function suite:test_logout_cleanup_and_unsubscribed_views_do_not_receive_later_updates()
        local notifications = 0
        local unsubscribe = self.marker.subscribe(function()
            notifications = notifications + 1
        end)
        self.marker.mark(self.location, "Abyssal demon")
        unsubscribe()
        self.marker.stop()
        lu.assertEquals(notifications, 1)
        lu.assertFalse(self.marker.has_target())
        lu.assertNil(next(self.hints.arrows))
        lu.assertNil(self.context.logic.monster_lookup_location_marker)
    end

    function suite:test_invalid_coordinate_values_and_instance_selection_are_rejected()
        for _, value in ipairs({ -1, 1.5, math.huge, 0 / 0, 12800 }) do
            self.location.map.x = value
            lu.assertFalse(self.marker.mark(self.location, "Guard"))
        end
        self.location.map.x = 3225
        self.hints.region = true
        lu.assertFalse(self.marker.mark(self.location, "Guard"))
        lu.assertEquals(self.hints.adds, 0)
    end

    function suite:test_tower_floor_to_varrock_is_deferred_and_uses_a_new_native_identity()
        self.marker.mark(self.location, "Abyssal demon")
        lu.assertEquals(self.hints.adds, 0)
        self.context:tick(1)
        local previous_name = self.hints.arrow.name
        lu.assertEquals(self.hints.arrow.coordFine.level, 2)
        local goblins = { name = "Near Varrock", map = { id = 28, plane = 0, x = 3122, z = 3436 } }
        self.marker.mark(goblins, "Goblin")
        lu.assertEquals(self.hints.removes, 0)
        lu.assertEquals(self.hints.adds, 3)
        self.context:tick(1)
        lu.assertNil(self.hints.arrow)
        lu.assertEquals(self.hints.adds, 3)
        self.context:tick(1)
        lu.assertNil(self.hints.arrow)
        self.context:tick(1)
        lu.assertNotEquals(self.hints.arrow.name, previous_name)
        lu.assertEquals(self.hints.arrow.coordFine.level, 0)
        lu.assertEquals(self.hints.area.coordGrid, { level = 0, x = 3122, z = 3436 })
    end

    function suite:test_spam_selections_only_install_the_latest_target_and_clear_cancels_the_queue()
        self.marker.mark(self.location, "Abyssal demon")
        self.context:tick(1)
        for index = 1, 100 do
            self.marker.mark(
                { name = "Destination", map = { id = 28, plane = 0, x = 3100 + index, z = 3436 } },
                "Goblin"
            )
        end
        lu.assertEquals(self.hints.adds, 3)
        self.context:tick(3)
        lu.assertEquals(self.hints.adds, 6)
        lu.assertEquals(self.hints.area.coordGrid.x, 3200)
        self.location.map.x = 3408
        self.marker.mark(self.location, "Abyssal demon")
        self.context:tick(1)
        self.marker.clear()
        self.context:tick(10)
        lu.assertEquals(self.hints.adds, 6)
        lu.assertFalse(self.marker.has_target())
        lu.assertNil(next(self.hints.arrows))
    end

    function suite:test_failed_polygon_only_removes_the_accepted_arrow()
        self.hints.reject_polygon = true
        self.marker.mark(self.location, "Abyssal demon")
        self.context:tick(1)
        lu.assertEquals(self.hints.removes, 1)
        lu.assertFalse(self.marker.has_target())
    end

    function suite:test_foreground_failure_removes_only_the_accepted_border_and_arrow()
        self.hints.reject_polygon_number = 2
        self.marker.mark(self.location, "Abyssal demon")
        self.context:tick(1)
        lu.assertFalse(self.marker.has_target())
        lu.assertNil(next(self.hints.polygons))
        lu.assertNil(next(self.hints.arrows))
        lu.assertEquals(self.hints.removes, 2)
    end

    function suite:test_arrival_requires_sixteen_tile_radius_and_matching_destination_floor()
        self.marker.mark(self.location, "Abyssal demon")
        self.context:tick(1)
        self.hints.player = { level = 0, x = 3407, z = 3546 }
        self.context:tick(50)
        lu.assertTrue(self.marker.has_target())
        self.hints.player = { level = 2, x = 3423, z = 3562 }
        self.context:tick(50)
        lu.assertTrue(self.marker.has_target()) -- Sixteen tiles on both axes is outside the radius.
        self.hints.player.z = 3546
        self.context:tick(50)
        lu.assertFalse(self.marker.has_target())
        lu.assertStrContains(self.marker.status(), "Arrived: Abyssal demon - Slayer Tower")
        lu.assertNil(next(self.hints.arrows))
        lu.assertNil(next(self.hints.polygons))
        lu.assertEquals(self.hints.removes, self.hints.adds)
    end

    function suite:test_marking_an_already_reached_location_does_not_install_hints()
        self.hints.player = { level = 2, x = 3407, z = 3546 }
        self.marker.mark(self.location, "Abyssal demon")
        self.context:tick(1)
        lu.assertFalse(self.marker.has_target())
        lu.assertEquals(self.hints.adds, 0)
        lu.assertStrContains(self.marker.status(), "Arrived")
        self.marker.clear()
        lu.assertNotStrContains(self.marker.status(), "Arrived")
    end

    function suite:test_unavailable_player_and_instances_do_not_trigger_arrival()
        self.marker.mark(self.location, "Abyssal demon")
        self.context:tick(1)
        self.hints.player = { level = 2, x = 3407, z = 3546 }
        self.hints.player_ready = false
        self.context:tick(50)
        lu.assertTrue(self.marker.has_target())
        self.hints.player_ready = true
        self.hints.region = true
        self.context:tick(50)
        lu.assertTrue(self.marker.has_target())
        lu.assertStrContains(self.marker.status(), "Paused")
        self.hints.region = false
        self.context:tick(50)
        lu.assertFalse(self.marker.has_target())
    end

    function suite:test_player_polling_is_bounded_and_stops_without_a_destination()
        self.context:tick(100)
        lu.assertEquals(self.hints.player_reads, 0)
        self.marker.mark(self.location, "Abyssal demon")
        self.context:tick(100)
        lu.assertTrue(self.hints.player_reads <= 3)
        lu.assertEquals(self.hints.adds, 3)
        self.marker.clear()
        self.context:tick(1)
        local reads = self.hints.player_reads
        self.context:tick(100)
        lu.assertEquals(self.hints.player_reads, reads)
    end

    local function span(polygon)
        local low, high = math.huge, -math.huge
        for _, point in ipairs(polygon) do
            low, high = math.min(low, point), math.max(high, point)
        end
        return high - low
    end

    function suite:test_wide_zoom_emphasizes_the_marker_without_recreating_the_navigation_arrow()
        self.marker.mark(self.location, "Abyssal demon")
        self.context:tick(1)
        local arrow = self.hints.arrow
        lu.assertEquals(self.hints.area.fillRGBA, 0xFF4040FF)
        lu.assertTrue(#self.hints.area.polygon > 8) -- An X rather than a solid diamond.
        for _, zoom in ipairs({ 25, 37, 50, 100, 200 }) do
            self.hints.zoom = zoom
            self.context:tick(50)
            local pixels_per_tile = zoom == 37 and 1.5 or zoom / 25
            local width = span(self.hints.area.polygon) * pixels_per_tile
            if zoom <= 50 then
                lu.assertTrue(width >= 56 and width <= 64)
            else
                lu.assertTrue(width >= 28 and width <= 44)
            end
            lu.assertIs(self.hints.arrow, arrow)
            local adds = self.hints.adds
            self.context:tick(50)
            lu.assertEquals(self.hints.adds, adds)
        end
        self.marker.clear()
        self.context:tick(1)
        lu.assertNil(next(self.hints.polygons))
    end

    function suite:test_closed_map_or_invalid_zoom_keeps_the_last_valid_symbol()
        self.hints.zoom = 37
        self.marker.mark(self.location, "Abyssal demon")
        self.context:tick(1)
        local polygon = self.hints.area.polygon
        for _, zoom in ipairs({ 0, -1, math.huge, 0 / 0 }) do
            self.hints.zoom = zoom
            self.context:tick(50)
            lu.assertIs(self.hints.area.polygon, polygon)
        end
        lu.assertEquals(self.hints.adds, 3)
    end

    function suite:test_symbol_redraw_failure_keeps_arrow_and_does_not_retry_every_tick()
        self.marker.mark(self.location, "Abyssal demon")
        self.context:tick(1)
        self.hints.reject_polygon = true
        self.hints.zoom = 25
        self.context:tick(50)
        lu.assertNotNil(self.hints.arrow)
        lu.assertNil(next(self.hints.polygons))
        lu.assertStrContains(self.marker.status(), "navigation arrow is still active")
        local adds = self.hints.adds
        self.context:tick(100)
        lu.assertEquals(self.hints.adds, adds)
        self.hints.reject_polygon = false
        self.hints.zoom = 50
        self.context:tick(50)
        lu.assertNotNil(next(self.hints.polygons))
        lu.assertStrContains(self.marker.status(), "Marked:")
    end

    function suite:test_arrow_keeps_a_relative_offset_when_destination_floor_height_is_loaded()
        self.hints.ground_height = 6200
        self.hints.height_available = true
        self.hints.player = { level = 0, x = 3222, z = 3218 } -- Lumbridge is unrelated to target height.
        self.marker.mark(self.location, "Abyssal demon")
        self.context:tick(1)
        lu.assertEquals(self.hints.arrow.coordFine.y, 900)
        lu.assertEquals(self.hints.arrow.coordFine.level, 2)
        lu.assertEquals(self.hints.height_query, {
            level = 2,
            x = 3407 * 512 + 256,
            z = 3546 * 512 + 256,
        })
    end

    function suite:test_distant_upper_floor_arrow_refreshes_when_destination_terrain_loads()
        self.hints.player = { level = 0, x = 3222, z = 3218 }
        self.marker.mark(self.location, "Abyssal demon")
        self.context:tick(1)
        local previous_name = self.hints.arrow.name
        lu.assertEquals(self.hints.arrow.coordFine.y, 900)
        self.hints.player = { level = 0, x = 3407, z = 3546 }
        self.hints.ground_height = 6200
        self.hints.height_available = true
        self.context:tick(49)
        lu.assertNil(self.hints.arrow)
        self.context:tick(2)
        lu.assertNotEquals(self.hints.arrow.name, previous_name)
        lu.assertEquals(self.hints.arrow.coordFine.y, 900)
        lu.assertEquals(self.hints.arrow.coordFine.level, 2)
        lu.assertTrue(self.marker.has_target()) -- Standing underneath does not count as arrival.
        lu.assertNotNil(self.hints.area)
        self.context:tick(100)
        lu.assertEquals(self.hints.adds, 6)
    end

    function suite:test_unloaded_or_invalid_terrain_does_not_replace_a_valid_arrow_height()
        self.hints.ground_height = 6200
        self.hints.height_available = true
        self.marker.mark(self.location, "Abyssal demon")
        self.context:tick(1)
        local arrow = self.hints.arrow
        self.hints.height_available = false
        self.context:tick(50)
        self.hints.height_available = true
        for _, height in ipairs({ -1, math.huge, 0 / 0 }) do
            self.hints.ground_height = height
            self.context:tick(50)
            lu.assertIs(self.hints.arrow, arrow)
        end
        lu.assertEquals(self.hints.arrow.coordFine.y, 900)
        lu.assertEquals(self.hints.adds, 3)
    end

    function suite:test_height_sampling_is_bounded_and_api_errors_leave_navigation_available()
        self.context:tick(100)
        lu.assertNil(self.hints.height_reads)
        self.hints.throw_height = true
        self.marker.mark(self.location, "Abyssal demon")
        self.context:tick(100)
        lu.assertNotNil(self.hints.arrow)
        lu.assertTrue(self.hints.height_reads <= 6) -- Destination and player terrain, at most once per check.
        lu.assertEquals(self.hints.adds, 3)
        self.marker.clear()
        self.context:tick(1)
        local reads = self.hints.height_reads
        self.context:tick(100)
        lu.assertEquals(self.hints.height_reads, reads)
    end

    function suite:test_climbing_refreshes_the_arrow_even_when_destination_height_is_unchanged()
        self.hints.ground_height = 6200
        self.hints.height_available = true
        self.hints.player = { level = 0, x = 3375, z = 3546 }
        self.marker.mark(self.location, "Abyssal demon")
        self.context:tick(1)
        local previous = self.hints.arrow.name
        for _, level in ipairs({ 1, 2 }) do
            self.hints.player.level = level
            self.context:tick(50)
            self.context:tick(2)
            lu.assertNotEquals(self.hints.arrow.name, previous)
            lu.assertEquals(self.hints.arrow.coordFine.y, 900)
            lu.assertEquals(self.hints.arrow.coordFine.level, 2)
            lu.assertTrue(self.marker.has_target())
            previous = self.hints.arrow.name
        end
        self.hints.player.x = 3391 -- Exactly 16 tiles away, now on the destination floor.
        self.context:tick(50)
        lu.assertFalse(self.marker.has_target())
    end

    function suite:test_elevation_changes_refresh_the_arrow_without_a_floor_change()
        self.hints.player = { level = 0, x = 3375, z = 3546 }
        local local_height = 1000
        self.context.environment.World.GetGroundHeight = function(level)
            return level == 2 and 6200 or local_height, true
        end
        self.marker.mark(self.location, "Abyssal demon")
        self.context:tick(1)
        local previous = self.hints.arrow.name
        local_height = 1600
        self.context:tick(49)
        self.context:tick(2)
        lu.assertNotEquals(self.hints.arrow.name, previous)
        lu.assertEquals(self.hints.arrow.coordFine.y, 900)
        local adds = self.hints.adds
        self.context:tick(100)
        lu.assertEquals(self.hints.adds, adds)
    end

    function suite:test_entrance_markers_use_surface_coordinates_and_explicit_access_labels()
        local location =
            { name = "Kuradal's Dungeon", map = { id = 36, plane = 0, x = 100, z = 102 } }
        local action, tooltip, reason = self.marker.action(location)
        lu.assertEquals(action, "Entrance")
        lu.assertNil(reason)
        lu.assertEquals(tooltip, "Mark the entrance")
        lu.assertTrue(self.marker.mark(location, "Abyssal demon"))
        self.context:tick(1)
        lu.assertEquals(self.hints.area.coordGrid, { level = 0, x = 2510, z = 3506 })
        lu.assertEquals(self.hints.arrow.coordFine.level, 0)
        lu.assertStrContains(self.marker.status(), "Ancient Cavern whirlpool")
        -- Unsupported selections leave a working destination intact and make no
        -- native calls, even when repeated rapidly.
        local adds = self.hints.adds
        for _ = 1, 100 do
            lu.assertFalse(
                self.marker.mark(
                    { name = "Quest instance", map = { id = 28, plane = 0, x = 3200, z = 3400 } },
                    "Test"
                )
            )
            lu.assertFalse(self.marker.mark({ name = "Unknown" }, "Test"))
        end
        self.context:tick(1)
        lu.assertEquals(self.hints.adds, adds)
        lu.assertTrue(self.marker.has_target())
        lu.assertStrContains(self.marker.status(), "whirlpool")
        self.hints.player = { level = 2, x = 2510, z = 3506 }
        self.context:tick(50)
        lu.assertTrue(self.marker.has_target())
        self.hints.player.level = 0
        self.context:tick(50)
        lu.assertTrue(self.marker.has_target()) -- An entrance is a waypoint, not the final arrival.
    end

    function suite:test_dungeon_goal_survives_parent_entrance_but_clears_at_an_unsupported_interior()
        local location = { name = "Tarn's Lair", map = { id = 30, plane = 0, x = 45, z = 82 } }
        self.hints.player = { level = 0, x = 3429, z = 3233 }
        lu.assertTrue(self.marker.mark(location, "Terror dog"))
        self.context:tick(1)
        lu.assertTrue(self.marker.has_target())
        lu.assertNotStrContains(self.marker.status(), "Arrived")
        self.hints.player = { level = 0, x = 3430, z = 9633 }
        self.context.environment.LocList = {
            Filter = function(query)
                lu.assertEquals(query.name, "Entrance")
                return { { coordGrid = { level = 0, x = 3436, z = 9658 } } }
            end,
        }
        self.context:tick(53)
        lu.assertTrue(self.marker.has_target())
        lu.assertNotNil(self.hints.arrow)
        lu.assertEquals(self.hints.arrow.coordFine.z, 9658 * 512 + 256)
        lu.assertStrContains(self.marker.status(), "Entrance to Tarn's Lair")
        self.hints.player = { level = 0, x = 3180, z = 4545 }
        self.context:tick(53)
        lu.assertFalse(self.marker.has_target())
        lu.assertNil(self.hints.arrow)
        lu.assertStrContains(self.marker.status(), "Interior guidance unavailable")
        -- A new selection in a supported region still marks the actual spawn.
        self.hints.player = { level = 0, x = 3140, z = 4670 }
        lu.assertTrue(self.marker.mark(location, "Terror dog"))
        self.context:tick(53)
        lu.assertNotNil(self.hints.arrow)
        lu.assertEquals(self.hints.arrow.coordFine.x, 3149 * 512 + 256)
        lu.assertEquals(self.hints.arrow.coordFine.z, 4650 * 512 + 256)
        self.hints.player = { level = 0, x = 3149, z = 4650 }
        self.context:tick(50)
        lu.assertFalse(self.marker.has_target())
        lu.assertStrContains(self.marker.status(), "Arrived")
    end

    function suite:test_new_destination_inside_mine_uses_a_loaded_exit_then_resumes_outside()
        self.hints.player = { level = 0, x = 3430, z = 9633 }
        local queries = 0
        self.context.environment.LocList = {
            Filter = function(query)
                queries = queries + 1
                lu.assertEquals(query.name, "Cart tunnel")
                lu.assertTrue(query.sameLevel)
                lu.assertEquals(query.range, 64)
                return {
                    { coordGrid = { level = 0, x = 3441, z = 9632 } },
                    { coordGrid = { level = 0, x = 3429, z = 9625 } },
                    { coordGrid = { level = 1, x = 3430, z = 9633 } },
                    { coordGrid = { level = 0, x = 3430, z = 3233 } },
                }
            end,
        }
        local location = { name = "Varrock", map = { id = 28, plane = 0, x = 3225, z = 3439 } }
        self.marker.mark(location, "Goblin")
        self.context:tick(100)
        lu.assertTrue(queries <= 3)
        lu.assertEquals(self.hints.arrow.coordFine.z, 9625 * 512 + 256)
        lu.assertStrContains(self.marker.status(), "Abandoned Mine exit")
        lu.assertTrue(self.marker.has_target()) -- Standing near a gate must not clear the destination.
        self.hints.player = { level = 0, x = 3429, z = 3233 }
        self.context:tick(53)
        lu.assertEquals(self.hints.arrow.coordFine.z, 3439 * 512 + 256)
        lu.assertStrContains(self.marker.status(), "Goblin - Varrock")
    end

    function suite:test_unknown_dungeon_or_missing_exit_keeps_goal_but_has_no_void_arrow()
        self.marker.mark(self.location, "Abyssal demon")
        self.context:tick(1)
        for _, point in ipairs({
            { level = 0, x = 3430, z = 9633 },
            { level = 0, x = 7000, z = 7000 },
        }) do
            self.hints.player = point
            self.context:tick(50)
            lu.assertNil(self.hints.arrow)
            lu.assertTrue(self.marker.has_target())
            lu.assertStrContains(self.marker.status(), "Paused")
        end
        self.hints.player = { level = 0, x = 3220, z = 3220 }
        self.context:tick(53)
        lu.assertNotNil(self.hints.arrow)
        lu.assertStrContains(self.marker.status(), "Marked")
    end

    function suite:test_doorway_guidance_pauses_if_the_loaded_entrance_is_missing_or_ambiguous()
        local location = { name = "Tarn's Lair", map = { id = 30, plane = 0, x = 45, z = 82 } }
        self.hints.player = { level = 0, x = 3430, z = 9633 }
        local entries = { { coordGrid = { level = 0, x = 3436, z = 9658 } } }
        self.context.environment.LocList = {
            Filter = function()
                return entries
            end,
        }
        self.marker.mark(location, "Terror dog")
        self.context:tick(1)
        lu.assertNotNil(self.hints.arrow)
        for _, candidates in ipairs({
            {},
            { { coordGrid = { level = 1, x = 3436, z = 9658 } } },
            { { coordGrid = { level = 0, x = 3436, z = 3258 } } },
            {
                { coordGrid = { level = 0, x = 3436, z = 9658 } },
                { coordGrid = { level = 0, x = 3438, z = 9658 } },
            },
        }) do
            entries = candidates
            self.context:tick(50)
            lu.assertNil(self.hints.arrow)
            lu.assertTrue(self.marker.has_target())
            lu.assertStrContains(self.marker.status(), "north of the mine")
        end
        entries = { { coordGrid = { level = 0, x = 3436, z = 9658 } } }
        self.context:tick(53)
        lu.assertNotNil(self.hints.arrow)
        lu.assertStrContains(self.marker.status(), "Entrance to Tarn's Lair")
    end

    function suite:test_new_dungeon_keeps_goal_at_entrance_then_guides_to_spawn()
        local location =
            { name = "Smoke Dungeon", map = { id = 591, plane = 0, x = 3213, z = 9361 } }
        self.hints.player = { level = 0, x = 3310, z = 2961 }
        lu.assertTrue(self.marker.mark(location, "Dust devil"))
        self.context:tick(1)
        lu.assertTrue(self.marker.has_target())
        self.hints.player = { level = 0, x = 3250, z = 9361 }
        self.context:tick(53)
        lu.assertNotNil(self.hints.arrow)
        lu.assertEquals(self.hints.arrow.coordFine.x, 3213 * 512 + 256)
        lu.assertEquals(self.hints.arrow.coordFine.z, 9361 * 512 + 256)
        self.hints.player = { level = 0, x = 3213, z = 9361 }
        self.context:tick(53)
        lu.assertFalse(self.marker.has_target())
    end

    function suite:test_resource_dungeon_guides_to_portal_then_spawn_without_completing_at_either_entrance()
        local location = {
            name = "Taverley blue dragon resource dungeon",
            map = { id = 379, plane = 0, x = 967, z = 4498 },
        }
        self.hints.player = { level = 0, x = 2885, z = 3397 }
        lu.assertTrue(self.marker.mark(location, "Blue dragon"))
        self.context:tick(1)
        lu.assertTrue(self.marker.has_target())
        self.hints.player = { level = 0, x = 2912, z = 9810 }
        self.context:tick(53)
        lu.assertTrue(self.marker.has_target())
        lu.assertEquals(self.hints.arrow.coordFine.x, 2911 * 512 + 256)
        lu.assertEquals(self.hints.arrow.coordFine.z, 9811 * 512 + 256)
        self.hints.player = { level = 0, x = 995, z = 4498 }
        self.context:tick(53)
        lu.assertEquals(self.hints.arrow.coordFine.x, 967 * 512 + 256)
        self.hints.player = { level = 0, x = 967, z = 4498 }
        self.context:tick(53)
        lu.assertFalse(self.marker.has_target())
    end

    function suite:test_entrance_without_spawn_coordinates_retains_selection_after_entering_unknown_interior()
        self.hints.player = { level = 0, x = 3359, z = 2972 }
        lu.assertTrue(self.marker.mark({ name = "Pollnivneach Slayer Dungeon" }, "Basilisk"))
        self.context:tick(1)
        lu.assertTrue(self.marker.has_target())
        self.hints.player = { level = 0, x = 100, z = 100 }
        self.context:tick(53)
        lu.assertTrue(self.marker.has_target())
        lu.assertStrContains(self.marker.status(), "still saved")
    end

    function suite:test_resource_return_route_keeps_hints_until_the_final_surface_destination()
        self.hints.player = { level = 0, x = 1380, z = 4580 }
        lu.assertTrue(self.marker.mark(self.location, "Abyssal demon"))
        self.context:tick(1)
        lu.assertEquals(self.hints.arrow.coordFine.x, 1395 * 512 + 256)
        self.hints.player = { level = 0, x = 1395, z = 4587 }
        self.context:tick(53)
        lu.assertTrue(self.marker.has_target())
        self.hints.player = { level = 0, x = 2852, z = 9840 }
        self.context:tick(53)
        lu.assertEquals(self.hints.arrow.coordFine.x, 2886 * 512 + 256)
        self.hints.player = { level = 0, x = 2885, z = 3397 }
        self.context:tick(53)
        lu.assertEquals(self.hints.arrow.coordFine.x, 3407 * 512 + 256)
        self.hints.player = { level = 2, x = 3407, z = 3546 }
        self.context:tick(53)
        lu.assertFalse(self.marker.has_target())
    end

    function suite:test_infested_axe_top_floor_pin_replaces_entrance_guidance()
        local function read(name)
            local file = assert(io.open(root .. "/tests/support/" .. name, "rb"))
            local content = file:read("*a")
            file:close()
            return content
        end
        local rows = self.context
            .load_module("tools/monster_locations")
            .parse(read("infested_axe_locations.html"))
        self.context
            .load_module("tools/location_spawns")
            .attach(rows, read("infested_axe_locations.wiki"))
        self.hints.player = { level = 0, x = 3410, z = 3330 }
        lu.assertTrue(self.marker.mark(rows[1], "Infested axe"))
        self.context:tick(1)
        lu.assertTrue(self.marker.has_target())
        self.hints.player = { level = 3, x = 4645, z = 5400 }
        self.context:tick(53)
        lu.assertNotNil(self.hints.arrow)
        lu.assertEquals(self.hints.arrow.coordFine.level, 3)
        lu.assertEquals(self.hints.arrow.coordFine.x, 4661 * 512 + 256)
        lu.assertEquals(self.hints.arrow.coordFine.z, 5405 * 512 + 256)
        self.hints.player = { level = 3, x = 4661, z = 5405 }
        self.context:tick(53)
        lu.assertFalse(self.marker.has_target())
    end

    function suite:test_unsupported_polypore_floor_clears_after_entry_and_does_not_return_outside()
        -- This is the old cached Infested axe map-centre record, with no spawn pins.
        local location =
            { name = "Polypore Dungeon", map = { id = 41, plane = 0, x = 3391, z = 9535 } }
        self.hints.player = { level = 0, x = 3410, z = 3330 }
        lu.assertTrue(self.marker.mark(location, "Infested axe"))
        self.context:tick(1)
        lu.assertTrue(self.marker.has_target())
        self.hints.player = { level = 3, x = 4645, z = 5400 }
        self.context:tick(53)
        lu.assertFalse(self.marker.has_target())
        lu.assertNil(self.hints.arrow)
        lu.assertNil(self.hints.area)
        lu.assertStrContains(self.marker.status(), "Dungeon entered")
        lu.assertNotStrContains(self.marker.status(), "Arrived")
        self.hints.player = { level = 0, x = 3410, z = 3330 }
        self.context:tick(53)
        lu.assertFalse(self.marker.has_target())
        lu.assertNil(self.hints.arrow)
        lu.assertTrue(self.marker.mark(location, "Infested axe"))
        lu.assertNotStrContains(self.marker.status(), "Dungeon entered")
    end

    function suite:test_entrance_only_goal_clears_in_its_authored_destination_area()
        self.hints.player = { level = 0, x = 3410, z = 3330 }
        lu.assertTrue(self.marker.mark({ name = "Polypore Dungeon" }, "Infested axe"))
        self.context:tick(1)
        lu.assertTrue(self.marker.has_target())
        self.hints.player = { level = 3, x = 4645, z = 5400 }
        self.context:tick(53)
        lu.assertFalse(self.marker.has_target())
        lu.assertStrContains(self.marker.status(), "marker cleared")
    end

    return suite
end
