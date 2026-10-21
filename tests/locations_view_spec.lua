local lu = require("luaunit")
local fixture = require("tests/support/window_fixture")

return function(root)
    local suite = {}

    function suite:setUp()
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
        self.context.subject.destroy()
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
        lu.assertNil(text_in(self.context, root, "Map"))
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

    return suite
end
