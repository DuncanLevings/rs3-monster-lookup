local lu = require("luaunit")
local fixture = require("tests/support/window_fixture")

return function(root)
    local suite = {}

    function suite:setUp()
        self.context = fixture.new(root)
    end

    function suite:test_ribbon_defaults_to_search_and_customize_reuses_the_settings_controls()
        local panel = self.context.load_module("src/ui/content_panel")
        local opened = 0
        panel.start(function()
            opened = opened + 1
        end, function() end)
        self.context.on_content_ready({ component = self.context.parent })
        local first = self.context.settings_views[1]
        local selector = self.context.dropdowns[1]
        lu.assertEquals(selector.selected, 0)
        lu.assertEquals(selector.entries[selector.selected + 1].text, "Search")
        lu.assertFalse(selector.selection_flags[1])
        lu.assertEquals(#self.context.radio_controls, 0)
        self.context.simple_buttons[1].action()
        lu.assertEquals(opened, 1)
        selector:pick(1)
        lu.assertTrue(first.root.destroyed)
        lu.assertEquals(#self.context.radio_controls, 1)
        self.context.on_content_ready({ component = self.context.parent })
        lu.assertEquals(self.context.dropdowns[2].selected, 0)
        lu.assertEquals(self.context.dropdowns[2].entries[1].text, "Search")
        panel.stop()
        lu.assertNil(self.context.on_content_ready)
    end

    function suite:test_hub_defaults_to_search_and_opens_the_same_monster_search_window()
        local context = self.context
        local opened = 0
        context.stub_module("src/ui/monster_search_window", {
            open = function()
                opened = opened + 1
            end,
        })
        context.settings_panel.start(function() end)
        context.on_settings_ready({ component = context.parent })
        local selector = context.dropdowns[1]
        lu.assertEquals(selector.selected, 0)
        lu.assertEquals(selector.entries[1].text, "Search")
        lu.assertEquals(#context.radio_controls, 0)
        context.simple_buttons[1].action()
        lu.assertEquals(opened, 1)
        selector:pick(1)
        lu.assertEquals(#context.radio_controls, 1)
        local customize = context.settings_views[#context.settings_views]
        context.on_settings_ready({ component = context.parent })
        lu.assertTrue(customize.root.destroyed)
        lu.assertEquals(context.dropdowns[2].selected, 0)
        context.settings_panel.stop()
        lu.assertTrue(context.settings_views[#context.settings_views].root.destroyed)
    end

    function suite:test_hub_and_ribbon_keep_independent_page_state_and_cleanup()
        local context = self.context
        local ribbon = context.load_module("src/ui/content_panel")
        context.settings_panel.start(function() end)
        ribbon.start(function() end, function() end)
        context.on_content_ready({ component = context.parent })
        local ribbon_selector = context.dropdowns[1]
        context.on_settings_ready({ component = context.parent })
        local hub_selector = context.dropdowns[2]
        hub_selector:pick(1)
        lu.assertEquals(ribbon_selector.selected, 0)
        lu.assertNotEquals(ribbon_selector.destroyed, true)
        context.settings_panel.stop()
        lu.assertTrue(hub_selector.destroyed)
        lu.assertNotEquals(ribbon_selector.destroyed, true)
        local count = #context.radio_controls
        hub_selector:pick(0)
        hub_selector:pick(1)
        lu.assertEquals(#context.radio_controls, count)
        ribbon_selector:pick(1)
        lu.assertEquals(#context.radio_controls, count + 1)
        ribbon.stop()
        lu.assertTrue(ribbon_selector.destroyed)
    end

    function suite:test_search_geometry_survives_window_recreation_without_changing_lookup_geometry()
        local context = self.context
        context.stub_module("src/data/monster_search", {
            new = function()
                return {
                    get_query = function()
                        return ""
                    end,
                    start = function() end,
                    stop = function() end,
                }
            end,
        })
        local view = context.load_module("src/ui/monster_search_window")
        view.start(function() end)
        view.open()
        local first = context.windows[1]
        first.root.x, first.root.y = 120, 180
        first:Close()
        lu.assertNil(context.saved)
        lu.assertNotNil(context.storage.monster_lookup_search_window)
        view.destroy()
        view.start(function() end)
        view.open()
        local restored = context.windows[2]
        lu.assertEquals(restored.root.x, 120)
        lu.assertEquals(restored.root.y, 180)
        lu.assertEquals(restored.root.width, 480)
        lu.assertEquals(restored.root.height, 360)
        view.destroy()
    end

    function suite:test_first_search_window_fits_a_small_viewport()
        local context = self.context
        context.parent.width, context.parent.height = 300, 200
        context.stub_module("src/data/monster_search", {
            new = function()
                return {
                    get_query = function()
                        return ""
                    end,
                    start = function() end,
                    stop = function() end,
                }
            end,
        })
        local view = context.load_module("src/ui/monster_search_window")
        view.start(function() end)
        view.open()
        local window = context.windows[1]
        lu.assertEquals(window.root.x, 0)
        lu.assertEquals(window.root.y, 0)
        lu.assertEquals(window.root.width, 300)
        lu.assertEquals(window.root.height, 200)
        view.destroy()
    end

    function suite:test_search_window_reuses_its_position_and_closes_after_one_selection()
        local context = self.context
        local started, stopped, active = 0, 0, false
        local query = ""
        local update
        context.stub_module("src/data/monster_search", {
            new = function(callback)
                update = callback
                return {
                    get_query = function()
                        return query
                    end,
                    start = function()
                        active = true
                        started = started + 1
                        update({}, "Type a name")
                    end,
                    stop = function()
                        active = false
                        stopped = stopped + 1
                    end,
                    set_query = function(text)
                        query = text
                    end,
                    choose = function(entry)
                        if active then
                            active = false
                            return entry.monster
                        end
                    end,
                }
            end,
        })
        local view = context.load_module("src/ui/monster_search_window")
        local selections = {}
        view.start(function(monster)
            selections[#selections + 1] = monster
        end)
        view.open()
        local window = context.windows[1]
        lu.assertTrue(window.options.resizable)
        lu.assertEquals(window.root.x, 400)
        lu.assertEquals(window.root.y, 220)
        window.root.x = 120
        context.text_fields[1].options.onChange(nil, nil, "guard")
        local entry = {
            label = "Guard (Varrock)",
            monster = { name = "Guard (Varrock)", wiki_title = "Guard (Varrock)" },
        }
        update({ entry }, "Select a monster")
        lu.assertEquals(#context.simple_buttons, 1)
        local button = context.simple_buttons[1]
        lu.assertEquals(button.content.content, "Guard (Varrock)")
        button.action()
        button.action()
        lu.assertEquals(#selections, 1)
        lu.assertFalse(window.visible)
        view.open()
        lu.assertEquals(#context.windows, 1)
        lu.assertEquals(window.root.x, 120)
        lu.assertEquals(started, 2)
        view.destroy()
        lu.assertTrue(stopped >= 2)
    end

    function suite:test_refresh_results_live_in_customize_and_stop_when_the_page_changes()
        local context = self.context
        local monster = { name = "Bloodveld", npc_id = 6215 }
        context.cache.put(
            monster,
            { title = "Bloodveld (God Wars Dungeon)", info = {}, sections = {}, no_drops = "none" }
        )
        local selected = 0
        context.settings_panel.start(function() end, function(choice)
            lu.assertEquals(choice, monster)
            selected = selected + 1
        end)
        context.on_settings_ready({ component = context.parent })
        local selector = context.dropdowns[1]
        selector:pick(1)
        local field = context.text_fields[1]
        context:tick(30)
        lu.assertEquals(#context.simple_buttons, 1)
        field:SetText("blodveld god wars", true)
        context:tick(30)
        local button = context.simple_buttons[#context.simple_buttons]
        lu.assertEquals(button.text, "Bloodveld (God Wars Dungeon)")
        lu.assertTrue(button.root.width > 0)
        lu.assertEquals(
            button.root.width,
            context.settings_views[#context.settings_views].content.width - 16
        )
        lu.assertNil(button.options.widthAnchor)
        lu.assertEquals(#context.windows, 0)
        button.action()
        button.action()
        lu.assertEquals(selected, 1)
        field:SetText("blood*god w?rs*", true)
        context:tick(30)
        local next_button = context.simple_buttons[#context.simple_buttons]
        selector:pick(0)
        lu.assertTrue(field.root.destroyed)
        lu.assertTrue(next_button.root.destroyed)
        lu.assertNil(next(context.logic))
        next_button.action()
        lu.assertEquals(selected, 1)
        context.settings_panel.stop()
    end

    function suite:test_inline_refresh_shows_cooldown_and_blocks_the_selection()
        local context = self.context
        local monster = { name = "Goblin", npc_id = 1 }
        context.cache.put(
            monster,
            { title = "Goblin", info = {}, sections = {}, no_drops = "none" }
        )
        context.cache.begin_manual_refresh(monster)
        local selected = 0
        context.settings_panel.start(function() end, function()
            selected = selected + 1
        end)
        context.on_settings_ready({ component = context.parent })
        context.dropdowns[1]:pick(1)
        context.text_fields[1]:SetText("gob", true)
        context:tick(30)
        local button = context.simple_buttons[#context.simple_buttons]
        lu.assertStrContains(button.text, "refresh in 60 min")
        button.action()
        lu.assertEquals(selected, 0)
        context.settings_panel.stop()
    end

    return suite
end
