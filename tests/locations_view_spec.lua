local lu = require("luaunit")
local fixture = require("tests/support/window_fixture")

return function(root)
    local suite = {}

    function suite:setUp()
        self.marker, self.extra_views = nil, {}
        self.context = fixture.new(root)
        self.context.subject.open({ name = "Goblin" })
        self.result = {
            title = "Goblin",
            info = {},
            sections = {},
            locations = {
                { name = "Lumbridge", levels = "2", requirements = "None", spawns = "30" },
                {
                    name = "Observatory Dungeon",
                    levels = "2, 5",
                    spawns = "33",
                    requirements = "Goblin Diplomacy and level 10 Agility",
                },
            },
        }
    end

    function suite:tearDown()
        for _, view in ipairs(self.extra_views) do
            view.destroy()
        end
        self.context.subject.destroy()
        if self.marker then
            self.marker.stop()
        end
    end

    local function location_root(context)
        return context:find_node_with_hook(2, "monster_lookup_locations_resize")
    end

    local function text_in(context, root, value)
        for _, label in ipairs(context.texts) do
            local parent = label.parent

            while parent do
                if parent == root and label.content == value then
                    return label
                end
                parent = parent.parent
            end
        end
    end

    local function background_in(context, button)
        for _, node in ipairs(context.nodes) do
            if node.parent == button.root.parent and node.fill == true then
                return node
            end
        end
    end

    local function mark_buttons(context, after)
        local buttons = {}
        for index = (after or 0) + 1, #context.simple_buttons do
            local button = context.simple_buttons[index]
            if not button.root.destroyed and button.content.content ~= "Clear marker" then
                buttons[#buttons + 1] = button
            end
        end
        return buttons
    end

    local function feedback_subscriptions(context)
        local count = 0
        for key in pairs(context.logic) do
            if key:find("monster_lookup_location_feedback_", 1, true) then
                count = count + 1
            end
        end
        return count
    end

    function suite:show_markable_locations()
        self.hints = require("tests/support/marker_fixture").enable(self.context)
        self.marker = self.context.load_module("src/game/location_marker")
        self.result.locations[1].map = { id = 28, plane = 0, x = 3225, z = 3439 }
        self.result.locations[2].name = "Varrock"
        self.result.locations[2].map = { id = 28, plane = 0, x = 3250, z = 3439 }
        self.context.subject.show_result(self.result)
        return mark_buttons(self.context)
    end

    function suite:test_click_marks_only_its_row_and_moving_the_marker_restores_the_old_row()
        local buttons = self:show_markable_locations()
        local theme = self.context.load_module("src/ui/theme")
        buttons[1].action()
        lu.assertEquals(buttons[1].content.content, "Marked")
        lu.assertEquals(background_in(self.context, buttons[1]).rgba, theme.ROW_MARKED)
        lu.assertEquals(buttons[2].content.content, "Mark")
        lu.assertEquals(background_in(self.context, buttons[2]).rgba, theme.row_colour(2))
        buttons[2].action()
        lu.assertEquals(buttons[1].content.content, "Mark")
        lu.assertEquals(background_in(self.context, buttons[1]).rgba, theme.row_colour(1))
        lu.assertEquals(buttons[2].content.content, "Marked")
        lu.assertEquals(background_in(self.context, buttons[2]).rgba, theme.ROW_MARKED)
        lu.assertEquals(feedback_subscriptions(self.context), 1)
    end

    function suite:test_clear_and_arrival_restore_the_row_and_cancel_click_feedback()
        local buttons = self:show_markable_locations()
        buttons[1].action()
        for _, button in ipairs(self.context.simple_buttons) do
            if button.content.content == "Clear marker" then
                button.action()
            end
        end
        lu.assertEquals(buttons[1].content.content, "Mark")
        lu.assertEquals(feedback_subscriptions(self.context), 0)
        buttons[1].action()
        self.marker.start()
        self.hints.player = { level = 0, x = 3225, z = 3439 }
        self.context:tick(1)
        lu.assertFalse(self.marker.has_target())
        lu.assertEquals(buttons[1].content.content, "Mark")
        lu.assertEquals(feedback_subscriptions(self.context), 0)
        lu.assertStrContains(self.marker.status(), "Arrived:")
    end

    function suite:test_second_view_with_the_same_coordinates_resets_the_first_monsters_row()
        local buttons = self:show_markable_locations()
        buttons[1].action()
        local before = #self.context.simple_buttons
        local view = self.context.load_module("src/ui/locations_view").render(
            self.context.tabs.pages[3],
            { title = "Guard", locations = self.result.locations }
        )
        self.extra_views[#self.extra_views + 1] = view
        local other = mark_buttons(self.context, before)
        lu.assertEquals(other[1].content.content, "Mark")
        other[1].action()
        lu.assertEquals(buttons[1].content.content, "Mark")
        lu.assertEquals(other[1].content.content, "Marked")
        lu.assertEquals(feedback_subscriptions(self.context), 1)
        self.marker.clear()
        lu.assertEquals(other[1].content.content, "Mark")
        lu.assertEquals(feedback_subscriptions(self.context), 0)
    end

    function suite:test_failed_click_stays_unmarked_and_shows_the_existing_warning()
        local buttons = self:show_markable_locations()
        self.hints.region = true
        buttons[1].action()
        local theme = self.context.load_module("src/ui/theme")
        lu.assertEquals(buttons[1].content.content, "Mark")
        lu.assertEquals(background_in(self.context, buttons[1]).rgba, theme.row_colour(1))
        lu.assertFalse(self.marker.has_target())
        lu.assertEquals(feedback_subscriptions(self.context), 0)
        local notice = text_in(
            self.context,
            location_root(self.context),
            "Location markers are available outside instances while logged in."
        )
        lu.assertNotNil(notice)
        lu.assertFalse(notice.hidden)
        lu.assertEquals(notice.options.colour, theme.TEXT_WARNING)
    end

    function suite:test_click_feedback_lasts_three_seconds_without_layout_work_between_endpoints()
        local buttons = self:show_markable_locations()
        buttons[1].action()
        local root = location_root(self.context)
        local notice = text_in(
            self.context,
            root,
            "Marked: Goblin - Lumbridge - open the world map to see it."
        )
        lu.assertNotNil(notice)
        lu.assertFalse(notice.hidden)
        lu.assertEquals(
            notice.options.font,
            self.context.environment.id.Font.MUSEO_SANS_15PT_REGULAR
        )
        local measurements = #self.context.text_measurements
        local positions = notice.position_updates
        self.context:tick(149)
        lu.assertFalse(notice.hidden)
        lu.assertEquals(#self.context.text_measurements, measurements)
        lu.assertEquals(notice.position_updates, positions)
        self.context:tick(1)
        lu.assertTrue(notice.hidden)
        lu.assertEquals(feedback_subscriptions(self.context), 0)
        local normal = text_in(self.context, root, self.marker.status())
        lu.assertFalse(normal.hidden)
        lu.assertEquals(normal.options.colour, self.context.load_module("src/ui/theme").TEXT_MUTED)
        lu.assertEquals(buttons[1].content.content, "Marked")
    end

    function suite:test_repeated_click_restarts_the_delay_and_destroy_stops_feedback()
        local buttons = self:show_markable_locations()
        buttons[1].action()
        self.context:tick(100)
        buttons[1].action()
        self.context:tick(100)
        lu.assertEquals(feedback_subscriptions(self.context), 1)
        local root = location_root(self.context)
        local notice = text_in(
            self.context,
            root,
            "Marked: Goblin - Lumbridge - open the world map to see it."
        )
        self.context.subject.destroy()
        lu.assertEquals(feedback_subscriptions(self.context), 0)
        local content = notice.content
        self.marker.mark(self.result.locations[2], "Guard")
        self.context:tick(150)
        lu.assertEquals(notice.content, content)
    end

    function suite:test_native_registration_failure_cancels_the_marked_row_and_success_notice()
        local buttons = self:show_markable_locations()
        self.hints.reject_arrow = true
        self.marker.start()
        buttons[1].action()
        self.context:tick(1)
        lu.assertEquals(buttons[1].content.content, "Mark")
        lu.assertEquals(feedback_subscriptions(self.context), 0)
        lu.assertNotNil(
            text_in(
                self.context,
                location_root(self.context),
                "The client could not create the location marker."
            )
        )
    end

    function suite:test_four_column_table_is_in_the_third_tab()
        self.context.subject.show_result(self.result)
        local root = location_root(self.context)
        local page = self.context.tabs.pages[3]

        lu.assertEquals(self.context.tabs.entries[3].text, "Locations")
        lu.assertIs(root.parent, page.content)
        for _, text in ipairs({
            "Location",
            "Levels",
            "Access requirements",
            "Spawns",
            "Lumbridge",
            "30",
            "Goblin Diplomacy and level 10 Agility",
        }) do
            lu.assertNotNil(text_in(self.context, root, text))
        end
        lu.assertNil(text_in(self.context, root, "Members"))
        lu.assertNotNil(text_in(self.context, root, "Map"))
    end

    function suite:test_rows_wrap_on_resize_and_only_remeasure_when_width_changes()
        self.result.locations[2].requirements = string.rep("A long access requirement. ", 8)
        self.context.subject.show_result(self.result)
        local root = location_root(self.context)
        local page = self.context.tabs.pages[3]
        local full_height = page.content_height
        local label = text_in(self.context, root, self.result.locations[2].requirements)
        local full_row_height = label.parent.height
        page.content.width = 420
        root.width = 420
        root.hooks[2](root)

        lu.assertTrue(page.content_height > full_height)
        lu.assertTrue(label.parent.height > full_row_height)
        local measurements = #self.context.text_measurements
        root.hooks[2](root)
        lu.assertEquals(#self.context.text_measurements, measurements)
    end

    function suite:test_empty_legacy_and_unsupported_results_have_distinct_messages()
        for _, scenario in ipairs({
            { locations = {}, no_locations = "none", message = "does not list" },
            { locations = {}, no_locations = "unreadable", message = "supported location table" },
            { message = "plugin settings" },
        }) do
            self.result.locations = scenario.locations
            self.result.no_locations = scenario.no_locations
            self.context.subject.show_result(self.result)
            local root = location_root(self.context)
            local found = false

            for _, label in ipairs(self.context.texts) do
                if label.parent == root and label.content:find(scenario.message, 1, true) then
                    found = true
                end
            end

            lu.assertTrue(found)
        end
    end

    function suite:test_switching_monsters_and_errors_dispose_of_the_old_locations()
        self.context.subject.show_result(self.result)
        local first = location_root(self.context)
        self.context.subject.open({ name = "Cow" })
        lu.assertTrue(first.destroyed)

        self.context.subject.show_result(self.result)
        local second = location_root(self.context)
        self.context.subject.show_error("Wiki unavailable")
        lu.assertTrue(second.destroyed)

        self.context.subject.show_result(self.result)
        local third = location_root(self.context)
        self.context.subject.destroy()
        lu.assertTrue(third.destroyed)
    end

    function suite:test_unknown_cached_spawn_values_are_blank_without_refreshing_the_wiki()
        self.result.locations[1].spawns = "? edit"
        self.result.locations[2].spawns = "12"
        self.context.subject.show_result(self.result)
        local root = location_root(self.context)
        lu.assertNil(text_in(self.context, root, "? edit"))
        lu.assertNotNil(text_in(self.context, root, ""))
        lu.assertNotNil(text_in(self.context, root, "12"))
    end

    function suite:test_mark_clear_and_browsing_another_monster_use_one_global_destination()
        local context = self.context
        require("tests/support/marker_fixture").enable(context)
        local marker = context.load_module("src/game/location_marker")
        self.result.locations[1].map = { id = 28, plane = 0, x = 3225, z = 3439 }
        self.result.locations[2].map = { id = 30, plane = 0, x = 109, z = 39 }
        self.result.locations[2].name = "Unknown dungeon"
        context.subject.show_result(self.result)
        local mark, unsupported, clear
        for _, button in ipairs(context.simple_buttons) do
            if button.content.content == "Mark" then
                if button.disabled then
                    unsupported = button
                else
                    mark = button
                end
            elseif button.content.content == "Clear marker" then
                clear = button
            end
        end
        lu.assertNotNil(mark)
        lu.assertTrue(unsupported.disabled)
        lu.assertTrue(clear.disabled)
        mark.action()
        lu.assertTrue(marker.has_target())
        lu.assertFalse(clear.disabled)
        lu.assertStrContains(marker.status(), "Goblin - Lumbridge")
        clear.action()
        lu.assertFalse(marker.has_target())
        lu.assertTrue(clear.disabled)
        mark.action()
        lu.assertTrue(marker.has_target())
        context.subject.open({ name = "Guard" })
        lu.assertTrue(marker.has_target())
        clear.action()
        lu.assertTrue(marker.has_target()) -- destroyed controls cannot change the active target
        marker.clear()
        lu.assertFalse(marker.has_target())
    end

    function suite:test_clear_marker_uses_the_buttons_fitted_width_for_layout()
        self.context.subject.show_result(self.result)
        local clear
        for _, button in ipairs(self.context.simple_buttons) do
            if button.content.content == "Clear marker" then
                clear = button
            end
        end
        lu.assertNotNil(clear)
        lu.assertNil(clear.options.width)
        lu.assertEquals(clear.root.x, -clear.root.width - 8)
        lu.assertEquals(clear.root.x_anchor, 1)
    end

    function suite:test_entrance_action_is_distinct_and_fits_the_map_column()
        require("tests/support/marker_fixture").enable(self.context)
        self.result.locations[1] =
            { name = "Kuradal's Dungeon", levels = "98", requirements = "None", spawns = "10" }
        self.context.subject.show_result(self.result)
        local found
        for _, button in ipairs(self.context.simple_buttons) do
            if button.content.content == "Entrance" then
                found = button
            end
        end
        lu.assertNotNil(found)
        lu.assertFalse(found.disabled)
        lu.assertEquals(found.options.tooltip, "Mark the entrance")
        lu.assertEquals(found.root.width, #"Entrance" * 8 + 24)
        found.action()
        lu.assertEquals(found.content.content, "Marked")
        lu.assertEquals(found.root.width, #"Entrance" * 8 + 24)
        local row = found.root.parent
        lu.assertTrue(found.root.x + found.root.width <= row.width)
        local root = location_root(self.context)
        root.width = 420
        self.context.tabs.pages[3].content.width = 420
        root.hooks[2](root)
        lu.assertTrue(found.root.x + found.root.width <= 420)
    end

    function suite:test_paused_guidance_is_larger_amber_and_returns_to_muted_after_resuming()
        local hints = require("tests/support/marker_fixture").enable(self.context)
        local marker = self.context.load_module("src/game/location_marker")
        local theme = self.context.load_module("src/ui/theme")
        hints.player = { level = 0, x = 7000, z = 7000 }
        self.result.locations[1].map = { id = 28, plane = 0, x = 3225, z = 3439 }
        self.context.subject.show_result(self.result)
        marker.start()
        marker.mark(self.result.locations[1], "Goblin")
        self.context:tick(1)
        local notice
        for _, label in ipairs(self.context.texts) do
            if
                label.visible ~= false and label.content:find("Return to the main world", 1, true)
            then
                notice = label
            end
        end
        lu.assertNotNil(notice)
        lu.assertEquals(notice.options.colour, theme.TEXT_WARNING)
        lu.assertEquals(
            notice.options.font,
            self.context.environment.id.Font.MUSEO_SANS_15PT_REGULAR
        )
        lu.assertStrContains(notice.content, "<br>Destination:")
        hints.player = { level = 0, x = 3220, z = 3220 }
        self.context:tick(53)
        lu.assertFalse(notice.visible)
        local normal
        for _, label in ipairs(self.context.texts) do
            if label.visible ~= false and label.content:find("Marked:", 1, true) then
                normal = label
            end
        end
        lu.assertNotNil(normal)
        lu.assertEquals(normal.options.colour, theme.TEXT_MUTED)
        marker.stop()
    end

    return suite
end
