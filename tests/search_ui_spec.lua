local lu = require("luaunit")
local fixture = require("tests/support/window_fixture")

return function(root)
    local suite = {}

    function suite:setUp()
        self.context = fixture.new(root)
    end

    function suite:test_ribbon_defaults_to_search_and_customize_reuses_the_settings_controls()
        local panel = self.context.load_module("src/ui/settings/content")
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
        context.stub_module("src/ui/search/window", {
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
        local ribbon = context.load_module("src/ui/settings/content")
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

    -- a stand in for src/data/search/monsters that keeps every model it makes, by kind
    local function stub_search(context)
        local made = {}
        context.stub_module("src/data/search/monsters", {
            new = function(callback, kind)
                local model = { kind = kind or "monsters", update = callback, queries = {} }
                function model.get_query()
                    return model.queries[#model.queries] or ""
                end
                function model.start()
                    model.started = true
                    callback({}, "Type something")
                end
                function model.stop()
                    model.started = false
                end
                function model.set_query(text)
                    model.queries[#model.queries + 1] = text
                end
                function model.choose(entry)
                    if entry.item then
                        return { item = entry.item }
                    end
                    return { name = entry.title, wiki_title = entry.title, focus = entry.focus }
                end
                made[model.kind] = model
                return model
            end,
        })
        return made
    end

    local function shown_text(context, pattern)
        for index = #context.texts, 1, -1 do
            local text = context.texts[index]
            if type(text.content) == "string" and text.content:find(pattern) then
                return text.content
            end
        end
    end

    function suite:test_drops_mode_searches_items_and_a_picked_item_lists_its_droppers()
        local context = self.context
        local made = stub_search(context)
        local view = context.load_module("src/ui/search/window")
        local selections = {}
        view.start(function(monster)
            selections[#selections + 1] = monster
        end)
        view.open()
        local picker = context.dropdowns[1]
        lu.assertEquals(picker.entries[2].text, "Drops")
        lu.assertNil(made.items)

        picker:pick(1)
        local items = assert(made.items)
        local field = context.text_fields[#context.text_fields]
        lu.assertEquals(field.options.placeholder, "Search dropped items...")
        lu.assertTrue(items.started)
        lu.assertFalse(made.monsters.started)

        items.update({ { label = "Bones - 120 monsters", item = "Bones" } }, "Select an item")
        context.simple_buttons[#context.simple_buttons].action()
        lu.assertEquals(field.text, "Bones")
        lu.assertEquals(items.queries[#items.queries], "Bones")
        lu.assertTrue(context.windows[1].visible)

        items.update({
            {
                label = "Kerapac (Hard mode) - Always",
                title = "Kerapac",
                focus = { item = "Bones", mode = "Hard mode" },
            },
        }, "1 monster drops Bones")
        context.simple_buttons[#context.simple_buttons].action()
        lu.assertEquals(selections[1].focus, { item = "Bones", mode = "Hard mode" })
        lu.assertFalse(context.windows[1].visible)

        -- results from a mode thats not showing never reach the window
        local buttons = #context.simple_buttons
        made.monsters.update({ { label = "Goblin", title = "Goblin" } }, "Select a monster")
        lu.assertEquals(#context.simple_buttons, buttons)
        view.destroy()
    end

    function suite:test_stats_mode_ranks_with_filters_and_opens_the_info_tab()
        local context = self.context
        stub_search(context)
        local ranked = {}
        context.stub_module(
            "src/data/library/api",
            require("tests/support/core_stub")({
                stat_choices = function()
                    return { { id = 1, label = "Combat XP" }, { id = 2, label = "Slayer XP" } }
                end,
                stat_ranking = function(stat, filters)
                    ranked[#ranked + 1] = { stat = stat, filters = filters }
                    return {
                        { title = "Abyssal lord", label = "Abyssal lord - 1,000 XP" },
                        { title = "Goblin", label = "Goblin - 5 XP" },
                    },
                        120
                end,
            })
        )
        local view = context.load_module("src/ui/search/window")
        local selections = {}
        view.start(function(monster)
            selections[#selections + 1] = monster
        end)
        view.open()
        context.dropdowns[1]:pick(2)
        lu.assertEquals(context.dropdowns[1].entries[3].text, "Stats")
        -- These inputs use the host API that supplies clipping and wheel handling.
        for _, field in ipairs(context.text_fields) do
            lu.assertIs(field.managed_by, context.windows[1])
            lu.assertTrue(field.options.absolute)
        end

        local last = ranked[#ranked]
        lu.assertEquals(last.stat, 1)
        lu.assertEquals(last.filters.bosses, "hide")
        lu.assertEquals(
            shown_text(context, "^Top"),
            "Top 2 of 120 by Combat XP. Select one to open its Monster info."
        )
        lu.assertEquals(
            context.simple_buttons[#context.simple_buttons].content.content,
            "Goblin - 5 XP"
        )

        local stat_picker, boss_picker = context.dropdowns[2], context.dropdowns[3]
        lu.assertEquals(boss_picker.entries[1].text, "No bosses or instances")
        stat_picker:pick(1)
        boss_picker:pick(2)
        local fields = context.text_fields
        local search, combat, slayer = fields[#fields - 2], fields[#fields - 1], fields[#fields]
        combat.options.onChange(nil, nil, "85")
        slayer.options.onChange(nil, nil, "abc")
        search.options.onChange(nil, nil, "dragons")
        last = ranked[#ranked]
        lu.assertEquals(last.stat, 2)
        lu.assertEquals(last.filters, { bosses = "only", max_combat = 85, query = "dragons" })

        context.simple_buttons[#context.simple_buttons - 1].action()
        lu.assertEquals(selections[1], {
            name = "Abyssal lord",
            wiki_title = "Abyssal lord",
            focus = { tab = "info" },
        })

        -- reopening comes back to Stats with the same choices
        view.open()
        lu.assertEquals(ranked[#ranked].filters.max_combat, 85)
        lu.assertEquals(
            context.text_fields[#context.text_fields - 2].options.placeholder,
            "Filter by name or Slayer category..."
        )
        view.destroy()
    end

    function suite:test_search_geometry_survives_window_recreation_without_changing_lookup_geometry()
        local context = self.context
        context.stub_module("src/data/search/monsters", {
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
        local view = context.load_module("src/ui/search/window")
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
        context.stub_module("src/data/search/monsters", {
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
        local view = context.load_module("src/ui/search/window")
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
        context.stub_module("src/data/search/monsters", {
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
        local view = context.load_module("src/ui/search/window")
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

    function suite:test_stats_filters_fill_rows_and_reflow_without_reranking_on_resize()
        local context = self.context
        stub_search(context)
        local ranked = 0
        context.stub_module(
            "src/data/library/api",
            require("tests/support/core_stub")({
                stat_choices = function()
                    return { { id = 1, label = "Combat XP" } }
                end,
                stat_ranking = function()
                    ranked = ranked + 1
                    return {}, 0
                end,
            })
        )
        local view = context.load_module("src/ui/search/window")
        view.start(function() end)
        view.open()
        context.dropdowns[1]:pick(2)
        local window = context.windows[1]
        local stat, bosses = context.dropdowns[2], context.dropdowns[3]
        local fields = context.text_fields
        local query, combat, slayer = fields[#fields - 2], fields[#fields - 1], fields[#fields]
        combat:SetText("150")
        local calls = ranked
        local function resize(width)
            window.content.width = width
            window.content.hooks[2](window.content)
            lu.assertEquals(query.root.x + query.root.width, width - 8)
            lu.assertEquals(combat.root.x, 8)
            lu.assertEquals(slayer.root.x + slayer.root.width, width - 8)
            lu.assertEquals(slayer.root.x - combat.root.x - combat.root.width, 8)
            lu.assertEquals(combat.root.y, slayer.root.y)
            lu.assertEquals(ranked, calls)
            lu.assertEquals(combat:GetText(), "150")
        end
        resize(440)
        lu.assertEquals(stat.y, bosses.y)
        lu.assertEquals(bosses.x + bosses.width, 432)
        lu.assertEquals(bosses.x - stat.x - stat.width, 8)
        lu.assertEquals(combat.root.y - stat.y - stat.height, 6)
        lu.assertEquals(query.root.height, context.dropdowns[1].height)
        resize(320)
        lu.assertEquals(stat.width, 304)
        lu.assertEquals(bosses.width, 304)
        lu.assertEquals(bosses.y - stat.y - stat.height, 6)
        lu.assertEquals(combat.root.y - bosses.y - bosses.height, 6)
        resize(700)
        lu.assertEquals(stat.y, bosses.y)
        lu.assertEquals(bosses.x + bosses.width, 692)
        view.destroy()
    end

    -- Exercise search-view state and activation separately from window placement.

    local function own_page(context)
        local page =
            context.environment.prettyui.Window.new(context.parent, { onClose = function() end })
        page:Show()
        return page
    end

    function suite:test_two_searches_keep_their_own_queries_and_only_run_while_active()
        local context = self.context
        local runners = {}
        context.stub_module("src/data/search/monsters", {
            new = function(callback)
                local runner = { queries = {}, update = callback }
                function runner.get_query()
                    return runner.queries[#runner.queries] or ""
                end
                function runner.start()
                    runner.started = true
                end
                function runner.stop()
                    runner.started = false
                end
                function runner.set_query(text)
                    runner.queries[#runner.queries + 1] = text
                end
                runners[#runners + 1] = runner
                return runner
            end,
        })
        local search_view = context.load_module("src/ui/search/view")
        local first = search_view.new(own_page(context), { on_select = function() end })
        local first_field = context.text_fields[#context.text_fields]
        local second = search_view.new(own_page(context), { on_select = function() end })
        local second_field = context.text_fields[#context.text_fields]

        first.set_active(true)
        second.set_active(true)
        first_field:SetText("goblin", true)
        second_field:SetText("dragon", true)

        lu.assertEquals(#runners, 2)
        lu.assertEquals(runners[1].queries, { "goblin" })
        lu.assertEquals(runners[2].queries, { "dragon" })

        first.set_active(false)
        lu.assertFalse(runners[1].started)
        lu.assertTrue(runners[2].started)

        second.destroy()
        lu.assertFalse(runners[2].started)
        lu.assertTrue(second_field.root.destroyed)
        lu.assertNotEquals(first_field.root.destroyed, true)
        first.destroy()
    end

    function suite:test_a_later_search_starts_where_an_earlier_one_was()
        local context = self.context
        stub_search(context)
        context.stub_module(
            "src/data/library/api",
            require("tests/support/core_stub")({
                stat_choices = function()
                    return { { id = 1, label = "Combat XP" }, { id = 2, label = "Slayer XP" } }
                end,
                stat_ranking = function()
                    return {}, 0
                end,
            })
        )
        local search_view = context.load_module("src/ui/search/view")
        local first = search_view.new(own_page(context), { on_select = function() end })
        context.dropdowns[#context.dropdowns]:pick(2)
        context.dropdowns[#context.dropdowns - 1]:pick(1)
        local state = first.state()
        first.destroy()

        lu.assertEquals(state.mode, "stats")
        lu.assertEquals(state.stats.stat, 2)

        state.stats.stat = 1
        local second = search_view.new(
            own_page(context),
            { on_select = function() end, state = first.state() }
        )
        lu.assertEquals(second.state().mode, "stats")
        lu.assertEquals(second.state().stats.stat, 2)
        second.destroy()
    end

    return suite
end
