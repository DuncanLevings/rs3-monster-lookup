local lu = require("luaunit")
local fixture = require("tests/support/window_fixture")

return function(root)
    local suite = {}

    function suite:setUp()
        self.context = fixture.new(root)
        self.monster = { name = "Goblin", combat_level = 2 }
    end

    function suite:tearDown()
        self.context.subject.destroy()
    end

    -- the fake ui doesnt mark children destroyed when a table is rebuilt, so only look at text
    -- made since `from`
    local function visible_texts(context, from)
        local shown = {}

        for index = (from or 0) + 1, #context.texts do
            local text = context.texts[index]

            if not text.destroyed and type(text.content) == "string" then
                shown[text.content] = true
            end
        end

        return shown
    end

    local function section_titles(context)
        local titles = {}

        for _, button in ipairs(context.section_buttons) do
            if not button.root.destroyed then
                titles[#titles + 1] = button.title
            end
        end

        return titles
    end

    local function grouped_result()
        local drop = { name = "Bones", quantity = "1", rate = "Always", price = 250 }
        local hard = { name = "Dragon bones", quantity = "1", rate = "Always", price = 2000 }
        return {
            title = "General Graardor",
            info = {},
            sections = {
                { title = "Drops (normal mode) / 100%", drops = { drop } },
                { title = "Drops (normal mode) / Other", drops = { drop } },
                { title = "Drops (hard mode) / 100%", drops = { hard } },
            },
        }
    end

    local function single_section(drops)
        return { title = "Goblin", info = {}, sections = { { title = "Other", drops = drops } } }
    end

    function suite:test_modes_get_a_picker_and_short_category_titles()
        self.context.subject.open(self.monster, function() end)
        self.context.subject.show_result(grouped_result())

        local picker = self.context.dropdowns[#self.context.dropdowns]
        lu.assertEquals(picker.entries, {
            { text = "Normal mode", id = 0 },
            { text = "Hard mode", id = 1 },
        })
        lu.assertEquals(section_titles(self.context), { "100%", "Other" })

        local before = #self.context.texts
        picker:pick(1)

        lu.assertEquals(section_titles(self.context), { "100%" })
        lu.assertTrue(visible_texts(self.context, before)["Dragon bones"])
        lu.assertEquals(self.context.dropdowns[#self.context.dropdowns].selected, 1)
    end

    function suite:test_enrage_selector_renders_only_selected_tables_and_retains_shared_drops()
        local potion = { name = "Potion", quantity = "3", rate = "Common", price = 100 }
        local more = { name = "Potion", quantity = "9", rate = "Common", price = 300 }
        local pet = { name = "Pet", quantity = "1", rate = "Rare", price = "Not sold" }
        self.context.subject.open(self.monster)
        self.context.subject.show_result({
            title = "Amascut, the Devourer",
            info = {},
            sections = {
                {
                    title = "Commons / Potions",
                    drop_mode = "Normal mode",
                    drop_threshold = -1,
                    drop_switch = 1,
                    drops = { potion },
                },
                {
                    title = "Commons / Potions",
                    drop_mode = "2000%+",
                    drop_threshold = 2000,
                    drop_switch = 1,
                    drops = { more },
                },
                { title = "Tertiary", drops = { pet } },
            },
        })
        local picker = self.context.dropdowns[1]
        lu.assertEquals(
            picker.entries,
            { { text = "Normal mode", id = 0 }, { text = "2000%+", id = 1 } }
        )
        lu.assertEquals(section_titles(self.context), { "Commons / Potions", "Tertiary" })
        local before = #self.context.texts
        picker:pick(1)
        local shown = visible_texts(self.context, before)
        lu.assertTrue(shown["9"])
        lu.assertTrue(shown.Pet)
        lu.assertNil(shown["3"])
        lu.assertEquals(section_titles(self.context), { "Commons / Potions", "Tertiary" })
    end

    function suite:test_a_drop_search_pick_opens_on_its_mode_with_the_item_filled_in()
        self.context.subject.open(
            self.monster,
            function() end,
            { item = "Dragon", mode = "Hard mode" }
        )
        self.context.subject.show_result(grouped_result())

        local picker = self.context.dropdowns[#self.context.dropdowns]
        lu.assertEquals(picker.selected, 1)
        lu.assertEquals(self.context.text_fields[#self.context.text_fields].text, "Dragon")
        lu.assertEquals(self.context.tabs.active, 1)

        -- a refresh arriving later keeps what the player picked since
        picker:pick(0)
        self.context.subject.show_result(grouped_result())
        lu.assertEquals(self.context.dropdowns[#self.context.dropdowns].selected, 0)
    end

    function suite:test_a_top_stats_pick_opens_on_the_monster_info_tab()
        self.context.subject.open(self.monster, function() end, { tab = "info" })
        self.context.subject.show_result(single_section({}))

        lu.assertEquals(self.context.tabs.active, 2)
    end

    function suite:test_opening_another_monster_goes_back_to_the_first_mode()
        self.context.subject.open(self.monster, function() end)
        self.context.subject.show_result(grouped_result())
        self.context.dropdowns[#self.context.dropdowns]:pick(1)

        self.context.subject.open({ name = "Kree'arra" }, function() end)
        self.context.subject.show_result(grouped_result())

        lu.assertEquals(self.context.dropdowns[#self.context.dropdowns].selected, 0)
    end

    local function category(context, title)
        for _, button in ipairs(context.section_buttons) do
            if not button.root.destroyed and button.title == title then
                return button
            end
        end
        error("Missing category " .. title)
    end

    function suite:test_individual_category_choices_survive_mode_switches_in_both_directions()
        self.context.subject.open(self.monster)
        self.context.subject.show_result(grouped_result())
        category(self.context, "100%"):SetExpanded(false)
        self.context.dropdowns[#self.context.dropdowns]:pick(1)
        lu.assertFalse(category(self.context, "100%").expanded)
        category(self.context, "100%"):SetExpanded(true)
        self.context.dropdowns[#self.context.dropdowns]:pick(0)
        lu.assertTrue(category(self.context, "100%").expanded)
        lu.assertTrue(category(self.context, "Other").expanded)
    end

    function suite:test_collapse_all_applies_to_new_mode_categories_and_resets_for_another_monster()
        local result = grouped_result()
        result.sections[#result.sections + 1] =
            { title = "Drops (hard mode) / Unique", drops = result.sections[3].drops }
        self.context.subject.open(self.monster)
        self.context.subject.show_result(result)
        self.context.simple_buttons[1].action()
        self.context.dropdowns[#self.context.dropdowns]:pick(1)
        lu.assertFalse(category(self.context, "100%").expanded)
        lu.assertFalse(category(self.context, "Unique").expanded)
        self.context.subject.open({ name = "Cow" })
        self.context.subject.show_result(result)
        lu.assertTrue(category(self.context, "100%").expanded)
    end

    function suite:test_item_search_does_not_overwrite_category_choices_when_changing_mode()
        self.context.subject.open(self.monster)
        self.context.subject.show_result(grouped_result())
        category(self.context, "100%"):SetExpanded(false)
        self.context.text_fields[#self.context.text_fields]:SetText("bones", true)
        self.context.dropdowns[#self.context.dropdowns]:pick(1)
        lu.assertTrue(category(self.context, "100%").expanded)
        self.context.text_fields[#self.context.text_fields]:SetText("", true)
        lu.assertFalse(category(self.context, "100%").expanded)
    end

    function suite:test_variant_dropdown_can_switch_back_to_the_first_variant()
        local hard = { version_anchor = "Hard mode", life_points = 450000 }
        local normal = { version_anchor = "Normal mode", life_points = 200000 }
        self.context.subject.open(self.monster)
        self.context.subject.show_result({
            title = "Kerapac",
            sections = {},
            info = hard,
            variants = { hard, normal },
        })
        local dropdown = self.context.dropdowns[1]
        dropdown:pick(2)
        local before = #self.context.texts

        dropdown:pick(1)

        lu.assertEquals(dropdown.stylesheetID, "dropdown")
        lu.assertTrue(visible_texts(self.context, before)["450,000"])
    end

    function suite:test_dropdown_ignores_deselection_events()
        self.context.subject.open(self.monster, function() end)
        self.context.subject.show_result(grouped_result())
        local picker = self.context.dropdowns[1]
        local before = #self.context.dropdowns
        picker.hooks[6](picker, 2, 0)

        lu.assertEquals(#self.context.dropdowns, before)
        lu.assertEquals(section_titles(self.context), { "100%", "Other" })
    end

    function suite:test_narrow_mode_toolbar_moves_search_below_the_picker()
        self.context.subject.open(self.monster, function() end)
        self.context.subject.show_result(grouped_result())
        local page = self.context.tabs.pages[1]
        local field = self.context.text_fields[1].root
        local picker = self.context.dropdowns[1]
        local body = self.context:find_node_with_hook(2, "monster_lookup_notes_resize")
        local full_height = page.content_height
        page.content.width = 360
        body.width = 360
        body.hooks[2](body)

        lu.assertTrue(field.y >= picker.y + picker.height)
        lu.assertTrue(360 + field.x >= 8)
        lu.assertTrue(page.content_height > full_height)
        page.content.width = 800
        body.width = 800
        body.hooks[2](body)

        lu.assertEquals(field.y, 12)
        lu.assertEquals(page.content_height, full_height)
    end

    function suite:test_very_narrow_toolbar_wraps_the_mode_picker_too()
        self.context.subject.open(self.monster, function() end)
        self.context.tabs.pages[1].content.width = 260
        self.context.subject.show_result(grouped_result())
        local field = self.context.text_fields[1].root
        local picker = self.context.dropdowns[1]

        lu.assertTrue(picker.y >= 36)
        lu.assertTrue(picker.x + picker.width <= 252)
        lu.assertTrue(
            field.y >= picker.y + picker.height or 260 + field.x >= picker.x + picker.width
        )
    end

    function suite:test_left_out_monsters_explain_why_and_bundled_ones_show_the_bundle_date()
        self.context.subject.open({ name = "Bandit" }, function() end)
        self.context.subject.show_result({
            title = "Bandit",
            info = {},
            variants = {},
            sections = {},
            no_drops = "not_covered",
            locations = {},
            no_locations = "none",
            placeholder = true,
        })
        local before = #self.context.texts
        local shown = visible_texts(self.context)

        lu.assertTrue(shown["Not covered"])
        local explained = false
        for text in pairs(shown) do
            explained = explained or text:find("find and fight again and again", 1, true) ~= nil
        end
        lu.assertTrue(explained)

        self.context.subject.show_result(
            single_section({
                { name = "Bones", quantity = "1", rate = "Always", price = 1, item_id = 526 },
            }),
            nil,
            { bundled = true, built = "2026-10-21", stale = false }
        )
        -- no GE Price Library in the tests, so the prices are the bundled ones too
        lu.assertTrue(
            visible_texts(self.context, before)["Monster Data Core: 2026-10-21 | Bundled GE prices"]
        )
    end

    -- drops with the numbers the build keeps, see src/core/drops/odds.lua
    local function odds(fields)
        MonsterDataCore.fill_odds(fields, fields.rate)
        return fields
    end

    local function shown_starting(context, prefix, from)
        for index = #context.texts, (from or 0) + 1, -1 do
            local text = context.texts[index]
            if
                not text.destroyed
                and type(text.content) == "string"
                and text.content:find(prefix, 1, true) == 1
            then
                return text.content
            end
        end
    end

    function suite:test_the_average_kill_follows_the_mode_being_shown()
        local normal = odds({ name = "Bones", quantity = "1", rate = "Always", price = 250 })
        local hard = odds({ name = "Dragon bones", quantity = "2", rate = "1/2", price = 4000 })
        self.context.subject.open(self.monster, function() end)
        self.context.subject.show_result({
            title = "General Graardor",
            info = {},
            sections = {
                { title = "Drops (normal mode) / 100%", drops = { normal } },
                { title = "Drops (hard mode) / Other", drops = { hard } },
            },
        })

        -- normal mode only, never normal and hard added together
        lu.assertEquals(shown_starting(self.context, "Average kill"), "Average kill: 250 gp")
        local before = #self.context.texts
        self.context.dropdowns[#self.context.dropdowns]:pick(1)
        -- 2000 each x 2 x 1/2
        lu.assertEquals(
            shown_starting(self.context, "Average kill", before),
            "Average kill: 2,000 gp"
        )
    end

    function suite:test_the_average_kill_uses_live_prices_and_hides_the_wikis_saved_one()
        self.context.environment.gepl = {
            isReady = function()
                return true
            end,
            getOneHourAverage = function()
                error("gepl 0.2.5 averages throw")
            end,
            getLatest = function(id)
                return assert(({ [526] = { high = 120, low = 80 } })[id], "Price not found")
            end,
        }
        self.context.subject.open(self.monster, function() end)
        self.context.subject.show_result({
            title = "Goblin",
            info = {},
            sections = {
                {
                    title = "Other",
                    description = "Two rolls per kill. The average Goblin kill is worth 2,142 coins.",
                    drops = {
                        odds({
                            name = "Bones",
                            quantity = "2",
                            rate = "Always",
                            price = 180,
                            item_id = 526,
                        }),
                        odds({
                            name = "Coins",
                            quantity = "5–15",
                            rate = "1/2",
                            price = { minimum = 5, maximum = 15 },
                        }),
                    },
                },
            },
        }, nil, { bundled = true, built = "2026-10-21", stale = false })

        -- bones live at 100 each x 2, coins 10 x 1/2
        lu.assertEquals(shown_starting(self.context, "Average kill"), "Average kill: 205 gp")
        local shown = visible_texts(self.context)
        lu.assertTrue(shown["Two rolls per kill."])
        for text in pairs(shown) do
            lu.assertNotStrContains(text, "2,142")
        end
    end

    function suite:test_an_incomplete_average_is_labelled_an_estimate()
        self.context.subject.open(self.monster, function() end)
        self.context.subject.show_result(single_section({
            odds({ name = "Bones", quantity = "1", rate = "Always", price = 100 }),
            odds({ name = "Shiny", quantity = "1", rate = "Rare", price = 5000000 }),
        }))

        lu.assertEquals(
            shown_starting(self.context, "Estimated"),
            "Estimated average kill: about 100 gp"
        )
        lu.assertNil(shown_starting(self.context, "Leaves out"))
    end

    function suite:test_live_ge_prices_replace_the_saved_ones_when_the_library_is_there()
        self.context.environment.gepl = {
            isReady = function()
                return true
            end,
            getOneHourAverage = function()
                error("gepl 0.2.5 averages throw")
            end,
            getLatest = function(id)
                return assert(({ [526] = { high = 120, low = 80 } })[id], "Price not found")
            end,
        }
        self.context.subject.open(self.monster, function() end)
        self.context.subject.show_result(
            single_section({
                { name = "Bones", quantity = "2", rate = "Always", price = 180, item_id = 526 },
                { name = "Coins", quantity = "50", rate = "1/2", price = 50, item_id = 995 },
            }),
            nil,
            { bundled = true, built = "2026-10-21", stale = false }
        )

        local shown = visible_texts(self.context)
        lu.assertTrue(shown["200 gp"]) -- live: 100 each x 2
        lu.assertTrue(shown["50 gp"]) -- no live price for coins, saved one stays
        lu.assertTrue(shown["Monster Data Core: 2026-10-21 | Live GE prices"])
    end

    function suite:test_drops_without_an_item_id_get_a_placeholder_icon()
        self.context.subject.open(self.monster, function() end)
        self.context.subject.show_result(single_section({
            { name = "Cremation", quantity = "1", rate = "1/1,000", price = "Not sold" },
            { name = "Bones", quantity = "1", rate = "Always", price = 1, item_id = 526 },
        }))

        local marks, icons = 0, 0
        for _, node in ipairs(self.context.nodes) do
            if not node.destroyed and node.content == "?" then
                marks = marks + 1
            elseif not node.destroyed and node.item_id == 526 then
                icons = icons + 1
            end
        end

        lu.assertEquals(marks, 1)
        lu.assertEquals(icons, 1)
    end

    function suite:test_only_quantities_that_get_cut_off_have_a_tooltip()
        self.context.subject.open(self.monster, function() end)
        self.context.subject.show_result(single_section({
            { name = "Magic logs", quantity = "30-40 (noted)", rate = "8/128", price = 1 },
            { name = "Bones", quantity = "1", rate = "Always", price = 1 },
        }))

        local quantity_tips = {}
        for _, tooltip in ipairs(self.context.tooltips) do
            if tooltip.options.text:find("^Quantity: ") then
                quantity_tips[#quantity_tips + 1] = tooltip.options.text
            end
        end

        lu.assertEquals(quantity_tips, { "Quantity: 30-40 (noted)" })
    end

    return suite
end
