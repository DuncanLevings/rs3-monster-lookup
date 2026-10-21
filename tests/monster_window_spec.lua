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

    function suite:test_window_uses_the_game_area()
        self.context.subject.open(self.monster)

        lu.assertEquals(self.context.requested_parent_id, 1)
        lu.assertEquals(self.context.windows[1].parent, self.context.parent)
    end

    function suite:test_source_credit_identifies_the_resolved_wiki_page()
        self.context.subject.open(self.monster)
        self.context.subject.show_result({ title = "Guard (Varrock)", info = {}, sections = {} })
        local source

        for _, text in ipairs(self.context.texts) do
            if
                text.content
                == "Source: RuneScape Wiki - Guard (Varrock). Stats apply to the selected variant."
            then
                source = text
            end
        end

        lu.assertNotNil(source)
    end

    function suite:test_reuses_the_window_when_selecting_another_monster()
        self.context.subject.open(self.monster)

        self.context.subject.open({ name = "Cow", combat_level = 4 })

        lu.assertEquals(#self.context.windows, 1)
        lu.assertEquals(self.context.windows[1].title, "Cow")
    end

    function suite:test_close_saves_position_and_reopen_keeps_the_same_window()
        self.context.subject.open(self.monster)
        local window = self.context.windows[1]
        window.root.x = 100
        window.root.y = 90

        window:Close()
        self.context.subject.open(self.monster)

        lu.assertEquals(#self.context.windows, 1)
        lu.assertTrue(window.visible)
        lu.assertEquals(window.root.x, 100)
        lu.assertEquals(window.root.y, 90)
        lu.assertEquals(self.context.saved.version, 1)
        lu.assertAlmostEquals(self.context.saved.x_ratio, 100 / (1280 - 840), 0.0001)
    end

    function suite:test_closing_the_window_runs_the_close_action()
        local closed = 0
        self.context.subject.open({ name = "Goblin" }, function()
            closed = closed + 1
        end)

        self.context.windows[1]:Close()

        lu.assertEquals(closed, 1)
    end

    function suite:test_monster_without_drops_shows_a_note_and_still_fills_monster_info()
        self.context.subject.open({ name = "Duckling" }, function() end)
        self.context.subject.show_result({
            title = "Duckling",
            info = { life_points = 50 },
            sections = {},
            no_drops = "none",
        })

        local lines = {}
        for _, text in ipairs(self.context.texts) do
            if not text.hidden and type(text.content) == "string" then
                lines[#lines + 1] = text.content
            end
        end
        local shown = table.concat(lines, "\n")

        lu.assertStrContains(shown, "No drops to show")
        lu.assertStrContains(shown, "doesn't list any drops for Duckling")
        lu.assertFalse(shown:find("Couldn't load drops", 1, true) ~= nil)
        lu.assertStrContains(shown, "Life points")
        lu.assertStrContains(shown, "50")
    end

    function suite:test_recreating_restores_saved_position_and_size()
        self.context.subject.open(self.monster)
        local first = self.context.windows[1]
        first.root.x = 150
        first.root.y = 60
        first.root.width = 900
        first.root.height = 480
        self.context.subject.destroy()

        self.context.subject.open(self.monster)

        local restored = self.context.windows[2]
        lu.assertEquals(restored.root, { x = 150, y = 60, width = 900, height = 480 })
        lu.assertEquals(first.destroy_count, 1)
    end

    function suite:test_destroy_is_safe_to_repeat()
        self.context.subject.open(self.monster)

        self.context.subject.destroy()
        self.context.subject.destroy()

        lu.assertEquals(self.context.windows[1].destroy_count, 1)
    end

    function suite:test_does_not_create_a_window_when_the_game_area_is_missing()
        self.context.parent = nil

        local opened = self.context.subject.open(self.monster)

        lu.assertFalse(opened)
        lu.assertEquals(self.context.windows, {})
    end

    function suite:test_new_install_centres_the_window()
        local options = self.context.geometry.load(self.context.parent)

        lu.assertEquals(options.x, 220)
        lu.assertEquals(options.y, 140)
    end

    function suite:test_invalid_saved_values_use_safe_defaults()
        self.context.saved = { version = 1, width = "wide", height = 0 / 0, x_ratio = math.huge }

        local options = self.context.geometry.load(self.context.parent)

        lu.assertEquals(options.width, 840)
        lu.assertEquals(options.height, 520)
        lu.assertEquals(options.x, 220)
    end

    function suite:test_unknown_saved_versions_are_ignored()
        self.context.saved = { version = 99, width = 900, x_ratio = 0 }

        local options = self.context.geometry.load(self.context.parent)

        lu.assertEquals(options.width, 840)
        lu.assertEquals(options.x, 220)
    end

    function suite:test_restored_window_fits_a_smaller_game_area()
        self.context.saved = { version = 1, width = 900, height = 800, x_ratio = 1, y_ratio = 1 }
        self.context.parent = { width = 480, height = 320 }

        local options = self.context.geometry.load(self.context.parent)

        lu.assertEquals(options.width, 480)
        lu.assertEquals(options.height, 320)
        lu.assertEquals(options.x, 0)
        lu.assertEquals(options.y, 0)
    end

    function suite:test_drop_rows_do_not_create_nested_scroll_panels()
        self.context.subject.open(self.monster)

        lu.assertEquals(self.context.panels, 0)
        lu.assertTrue(self.context.tabs.pages[1].content_height > 0)
        lu.assertFalse(self.context.windows[1].options.scrollable)
    end

    function suite:test_older_narrow_windows_expand_to_the_readable_minimum()
        self.context.saved =
            { version = 1, width = 620, height = 520, x_ratio = 0.5, y_ratio = 0.5 }

        local options = self.context.geometry.load(self.context.parent)

        lu.assertEquals(options.width, 760)
    end

    function suite:test_collapsing_a_category_reflows_the_remaining_sections()
        self.context.subject.open(self.monster)
        self.context.subject.show_result(self.context.sample)
        local page = self.context.tabs.pages[1]
        local expanded_height = page.content_height
        local second_heading_y = self.context.section_buttons[2].root.y

        self.context.section_buttons[1]:SetExpanded(false)

        lu.assertEquals(page.content_height, expanded_height - 70)
        lu.assertEquals(self.context.section_buttons[2].root.y, second_heading_y - 70)

        self.context.section_buttons[1]:SetExpanded(true)

        lu.assertEquals(page.content_height, expanded_height)
        lu.assertEquals(self.context.section_buttons[2].root.y, second_heading_y)
    end

    function suite:test_toggle_all_collapses_and_expands_categories_with_one_reflow()
        self.context.subject.open(self.monster)
        lu.assertEquals(#self.context.simple_buttons, 0)

        self.context.subject.show_result(self.context.sample)
        local button = self.context.simple_buttons[1]
        local page = self.context.tabs:GetPage(1)
        local expanded_height = page.content_height
        local layouts = 0
        self.context.on_content_height = function()
            layouts = layouts + 1
        end

        lu.assertEquals(button.content.content, "Collapse all")
        lu.assertTrue(button.root.y < self.context.section_buttons[1].root.y)
        button.action()

        for _, section in ipairs(self.context.section_buttons) do
            lu.assertFalse(section.expanded)
        end

        lu.assertEquals(button.content.content, "Expand all")
        lu.assertTrue(page.content_height < expanded_height)
        lu.assertEquals(layouts, 1)
        button.action()

        for _, section in ipairs(self.context.section_buttons) do
            lu.assertTrue(section.expanded)
        end

        lu.assertEquals(button.content.content, "Collapse all")
        lu.assertEquals(page.content_height, expanded_height)
        lu.assertEquals(layouts, 2)
    end

    function suite:test_toggle_all_tracks_individual_categories_and_is_cleaned_up()
        self.context.subject.open(self.monster)
        self.context.subject.show_result(self.context.sample)
        local button = self.context.simple_buttons[1]

        for _, section in ipairs(self.context.section_buttons) do
            section:SetExpanded(false)
        end

        lu.assertEquals(button.content.content, "Expand all")
        self.context.section_buttons[1]:SetExpanded(true)
        lu.assertEquals(button.content.content, "Collapse all")

        local propagate = button.root.hooks[1](button.root, 1)
        lu.assertFalse(propagate)
        lu.assertEquals(self.context.tabs:GetPage(1).scroll_position, 32)

        self.context.subject.open({ name = "Cow" })
        lu.assertTrue(button.root.destroyed)
    end

    function suite:test_settings_switches_visible_rarity_without_changing_the_source_data()
        self.context.subject.open(self.monster)
        self.context.subject.show_result(self.context.sample)
        local rate = self.context.sample.sections[1].drops[1].rate

        lu.assertEquals(self.context.tabs.entries[3].text, "Locations")
        lu.assertNil(self.context.tabs:GetPage(4))
        lu.assertEquals(#self.context.radio_controls, 0)
        self.context.settings_panel.start(self.context.subject.refresh_settings)
        self.context.on_settings_ready({ component = self.context.parent })
        self.context.dropdowns[#self.context.dropdowns]:pick(1)
        lu.assertEquals(#self.context.radio_controls, 1)
        self.context.checkbox_controls[1].options.onChange(nil, nil, nil, true)

        local found_percentage = false
        for _, label in ipairs(self.context.texts) do
            if
                not label.destroyed
                and type(label.content) == "string"
                and label.content:find("%%")
            then
                found_percentage = true
            end
        end

        lu.assertTrue(found_percentage)
        lu.assertEquals(self.context.sample.sections[1].drops[1].rate, rate)
    end

    function suite:test_hub_settings_can_open_without_a_monster_and_clean_up_on_remount_and_stop()
        self.context.settings_panel.start(self.context.subject.refresh_settings)
        self.context.on_settings_ready({ component = self.context.parent })
        self.context.dropdowns[#self.context.dropdowns]:pick(1)
        local first = self.context.settings_views[#self.context.settings_views]

        lu.assertEquals(#self.context.windows, 0)
        lu.assertEquals(first.options.widthAnchor, 1)
        lu.assertEquals(first.options.heightAnchor, 1)
        self.context.checkbox_controls[1].options.onChange(nil, nil, nil, true)
        lu.assertEquals(self.context.radio_controls[1].options.selectedValue, "default")
        self.context.radio_controls[1].options.onChange(nil, "purple")
        self.context.on_settings_ready({ component = self.context.parent })
        self.context.dropdowns[#self.context.dropdowns]:pick(1)

        lu.assertTrue(first.root.destroyed)
        lu.assertEquals(self.context.radio_controls[2].options.selectedValue, "purple")
        lu.assertTrue(self.context.checkbox_controls[2].entries[1].selected)
        self.context.settings_panel.stop()

        lu.assertTrue(self.context.settings_views[#self.context.settings_views].root.destroyed)
        lu.assertNil(self.context.on_settings_ready)
    end

    function suite:test_saved_data_warning_remains_without_a_refresh_button()
        self.context.subject.open(self.monster)
        self.context.subject.show_result(
            self.context.sample,
            "Wiki unavailable",
            { saved_at = 1, stale = true }
        )
        local found_warning = false

        for _, label in ipairs(self.context.texts) do
            if
                type(label.content) == "string"
                and label.content:find("showing saved data", 1, true)
            then
                found_warning = true
            end
        end

        lu.assertTrue(found_warning)

        for _, button in ipairs(self.context.simple_buttons) do
            lu.assertNotEquals(button.content.content, "Refresh")
        end
    end

    function suite:test_wheel_over_a_category_scrolls_the_page_once()
        self.context.subject.open(self.monster)
        self.context.subject.show_result(self.context.sample)
        local header = self.context.section_buttons[1].root

        local propagate = header.hooks[1](header, 1)

        lu.assertFalse(propagate)
        lu.assertEquals(self.context.tabs.pages[1].scroll_position, 32)
    end

    function suite:test_table_labels_do_not_create_hover_or_wheel_targets()
        self.context.subject.open(self.monster)
        self.context.subject.show_result(self.context.sample)

        for _, text in ipairs(self.context.texts) do
            if text.options then
                lu.assertNil(text.options.tooltip)
                lu.assertTrue(text.clickthrough)
                lu.assertFalse(text.enabled)
            end
        end
    end

    function suite:test_loading_a_new_monster_clears_the_previous_drop_table()
        self.context.subject.open(self.monster)
        self.context.subject.show_result(self.context.sample)
        local first = self.context.section_buttons[1]

        self.context.subject.open({ name = "Cow", combat_level = 4 })

        lu.assertTrue(first.root.destroyed)
        lu.assertEquals(self.context.texts[1].content, "Loading RuneScape Wiki...")
        lu.assertFalse(self.context.texts[1].hidden)
    end

    function suite:test_conditional_rates_have_a_tooltip_and_numbered_notes_below_the_table()
        self.context.subject.open(self.monster)
        self.context.subject.show_result({
            title = "Goblin",
            info = {},
            sections = {
                {
                    title = "Common",
                    notes = { "Only after a relic roll." },
                    drops = {
                        {
                            name = "Relic",
                            quantity = "1",
                            rate = "2/39",
                            price = "Not sold",
                            notes = "Only after a relic roll.",
                            note_marker = "1",
                        },
                    },
                },
            },
        })

        lu.assertEquals(#self.context.tooltips, 1)
        lu.assertEquals(self.context.tooltips[1].options.text, "Only after a relic roll.")
        lu.assertEquals(self.context.tooltips[1].component.content, "2/39 [1]")
        lu.assertIs(self.context.tooltips[1].parent, self.context.parent)

        local target = self.context.tooltips[1].component
        target.xyGlobal = { x = 650, y = 320 }
        self.context.parent.xyGlobal = { x = 40, y = 25 }

        target.hooks[3](target)

        lu.assertFalse(self.context.tooltips[1].root.hidden)
        lu.assertEquals(self.context.tooltips[1].root.x, 610)
        lu.assertEquals(self.context.tooltips[1].root.y, 341)

        local page = self.context.tabs:GetPage(1)
        page:SetScrollPosition(600)
        target.xyGlobal = { x = 650, y = 920 }
        target.hooks[3](target)

        lu.assertEquals(self.context.tooltips[1].root.x, 610)
        lu.assertEquals(self.context.tooltips[1].root.y, 341)

        target.xyGlobal = { x = 1300, y = 1375 }
        target.hooks[3](target)

        lu.assertEquals(self.context.tooltips[1].root.x, 974)
        lu.assertEquals(self.context.tooltips[1].root.y, 664)

        self.context.tabs:SetActive(2)

        lu.assertTrue(self.context.tooltips[1].root.hidden)

        target.hooks[3](target)
        self.context.windows[1]:Close()

        lu.assertTrue(self.context.tooltips[1].root.hidden)

        local note

        for _, label in ipairs(self.context.texts) do
            if label.content == "[1] Only after a relic roll." then
                note = label
            end
        end

        lu.assertNotNil(note)
        lu.assertTrue(note.hidden)
        lu.assertTrue(note.clickthrough)

        self.context.subject.open(self.monster)
        lu.assertTrue(self.context.tooltips[1].destroyed)
    end

    function suite:test_wheel_over_a_note_tooltip_target_scrolls_the_page_once()
        self.context.subject.open(self.monster)
        self.context.subject.show_result({
            title = "Goblin",
            info = {},
            sections = {
                {
                    title = "Common",
                    drops = {
                        {
                            name = "Relic",
                            quantity = "1",
                            rate = "2/39",
                            notes = "Conditional rate",
                        },
                    },
                },
            },
        })
        local target = self.context.tooltips[1].component

        lu.assertFalse(target.hooks[1](target, 1))
        lu.assertEquals(self.context.tabs.pages[1].scroll_position, 32)
        lu.assertTrue(self.context.tooltips[1].hidden)
    end

    function suite:test_monster_info_groups_combat_stats_in_the_existing_scroll_page()
        self.context.subject.open(self.monster)
        self.context.subject.show_result({
            title = "Guard",
            sections = {},
            info = {
                life_points = 900,
                attack_level = 18,
                melee_accuracy = 292,
                melee_max_hit = 72,
                weakness_text = { "air" },
                susceptible_to_poison = "true",
            },
        })
        local found = {}

        for _, text in ipairs(self.context.texts) do
            found[text.content] = true
        end

        for _, button in ipairs(self.context.section_buttons) do
            found[button.title] = true
        end

        for _, title in ipairs({
            "Combat info",
            "Offensive stats",
            "Defensive stats",
            "Base hit chance",
        }) do
            lu.assertTrue(found[title])
        end

        lu.assertNil(found.Immunities)
        lu.assertTrue(found.Air)
        lu.assertTrue(found["Not immune"])
        lu.assertEquals(self.context.panels, 0)
        lu.assertTrue(self.context.tabs:GetPage(2).content_height > 100)
        lu.assertEquals(#self.context.dropdowns, 0)
    end

    function suite:test_monster_info_omits_examine_text_and_positions_icon_tooltips_after_scrolling()
        self.context.subject.open(self.monster)
        self.context.subject.show_result({
            title = "Guard",
            sections = {},
            info = {
                examine = "This examine text should not be repeated.",
                life_points = 900,
            },
        })

        for _, label in ipairs(self.context.texts) do
            lu.assertNotEquals(label.content, "This examine text should not be repeated.")
        end

        local tooltip

        for _, candidate in ipairs(self.context.tooltips) do
            if candidate.options.text == "Poison: Unknown" then
                tooltip = candidate
            end
        end

        lu.assertNotNil(tooltip)
        lu.assertEquals(tooltip.options.text, "Poison: Unknown")
        lu.assertEquals(tooltip.component.sprite, "test:poison")
        local poison_label

        for _, label in ipairs(self.context.texts) do
            if label.content == "Poison" and label.parent == tooltip.component.parent then
                poison_label = label
            end
        end

        lu.assertNotNil(poison_label)
        lu.assertFalse(poison_label.hidden)
        lu.assertTrue(poison_label.x + poison_label.width <= tooltip.component.x)
        tooltip.component.xyGlobal = { x = 650, y = 900 }
        self.context.parent.xyGlobal = { x = 40, y = 25 }
        local page = self.context.tabs:GetPage(2)
        page:SetScrollPosition(600)
        tooltip.component.hooks[3](tooltip.component)

        lu.assertFalse(tooltip.root.hidden)
        lu.assertEquals(tooltip.root.x, 610)
        lu.assertEquals(tooltip.root.y, 301)
        lu.assertFalse(tooltip.component.hooks[1](tooltip.component, 1))
        lu.assertEquals(page.scroll_position, 632)
        lu.assertTrue(tooltip.root.hidden)

        tooltip.component.hooks[3](tooltip.component)
        self.context.tabs:SetActive(1)
        lu.assertTrue(tooltip.root.hidden)
        self.context.subject.open({ name = "Cow" })
        lu.assertTrue(tooltip.destroyed)
    end

    function suite:test_weakness_icon_is_centred_when_susceptibility_values_wrap()
        self.context.subject.open(self.monster)
        self.context.subject.show_result({
            title = "Abyssal demon",
            sections = {},
            info = {
                weakness_text = { "slash" },
                susceptible_to = { "inquisitor", "Abyssal Bane", "Demon Slayer" },
            },
        })

        for _, tooltip in ipairs(self.context.tooltips) do
            if tooltip.component.sprite == "test:weak_slash" then
                local icon = tooltip.component
                lu.assertTrue(icon.parent.height > 24)
                lu.assertEquals(icon.y, math.floor((icon.parent.height - icon.height) / 2))
                return
            end
        end

        lu.fail("Missing weakness icon")
    end

    function suite:test_positive_flags_use_checkmarks_with_descriptive_tooltips()
        self.context.subject.open(self.monster)
        self.context.subject.show_result({
            title = "Bloodveld",
            sections = {},
            info = { is_aggressive = true },
        })
        local descriptions = {}

        for _, tooltip in ipairs(self.context.tooltips) do
            if tooltip.component.sprite == "test:yes" then
                descriptions[#descriptions + 1] = tooltip.options.text
            end
        end

        lu.assertEquals(descriptions, { "Aggressive: Yes" })
    end

    function suite:test_negative_combat_flags_use_crosses_while_unknown_flags_remain_text()
        self.context.subject.open(self.monster)
        self.context.subject.show_result({
            title = "Guard",
            sections = {},
            info = {
                is_aggressive = false,
                is_members_only = "No",
            },
        })
        local descriptions = {}

        for _, tooltip in ipairs(self.context.tooltips) do
            if tooltip.component.sprite == "test:no" then
                descriptions[#descriptions + 1] = tooltip.options.text
            end
        end

        lu.assertEquals(descriptions, { "Aggressive: No", "Members only: No" })
    end

    function suite:test_monster_info_variant_switches_stats_and_cleans_up_on_new_lookup()
        local hard = { version_anchor = "Hard mode", life_points = 450000 }
        local normal = { version_anchor = "Normal mode", life_points = 200000 }
        self.context.subject.open(self.monster)
        self.context.subject.show_result({
            title = "Kerapac",
            sections = {},
            info = hard,
            variants = { hard, normal },
        })
        local box = self.context.dropdowns[1]
        local root = self.context:find_node_with_hook(2, "monster_lookup_info_resize")
        local before = #self.context.texts
        box:pick(2)
        local found = false

        for index = before + 1, #self.context.texts do
            if self.context.texts[index].content == "200,000" then
                found = true
            end
        end

        lu.assertTrue(found)
        lu.assertEquals(self.context.tabs:GetPage(2).scroll_position, 0)
        self.context.subject.refresh_settings()
        lu.assertEquals(#self.context.dropdowns, 1)
        self.context.subject.open({ name = "Cow" })

        lu.assertTrue(box.destroyed)
        lu.assertTrue(root.destroyed)
    end

    function suite:test_monster_info_reflows_long_values_when_resized()
        self.context.subject.open(self.monster)
        self.context.subject.show_result({
            title = "Guard",
            sections = {},
            info = {
                susceptible_to = { string.rep("Long weapon name ", 30) },
            },
        })
        local page = self.context.tabs:GetPage(2)
        local root = self.context:find_node_with_hook(2, "monster_lookup_info_resize")
        local before = page.content_height
        root.width = 400
        root.hooks[2](root)

        lu.assertTrue(page.content_height > before)
    end

    function suite:test_monster_info_layout_does_not_reenter_when_the_scrollbar_changes_width()
        self.context.subject.open(self.monster)
        local page = self.context.tabs:GetPage(2)
        local passes = 0
        local context = self.context
        context.on_content_height = function(changed_page)
            local root = context:find_node_with_hook(2, "monster_lookup_info_resize")

            if changed_page ~= page or not root then
                return
            end

            passes = passes + 1
            if passes > 2 then
                error("monster info layout reentered recursively")
            end

            root.width = root.width - 1
            root.hooks[2](root)
        end
        context.subject.show_result({ title = "Guard", sections = {}, info = { life_points = 900 } })

        lu.assertEquals(passes, 2)
    end

    function suite:test_long_notes_reflow_when_the_table_width_changes()
        self.context.subject.open(self.monster)
        self.context.subject.show_result({
            title = "Goblin",
            info = {},
            sections = {
                {
                    title = "Common",
                    drops = {},
                    notes = { string.rep("Long note about drop conditions. ", 12) },
                },
            },
        })
        local body = self.context:find_node_with_hook(2, "monster_lookup_notes_resize")

        local before = self.context.tabs.pages[1].content_height

        self.context.tabs.pages[1].content.width = 400
        body.width = 400
        body.hooks[2](body)

        lu.assertTrue(self.context.tabs.pages[1].content_height > before)
    end

    function suite:test_resize_events_cannot_recursively_reenter_table_layout()
        self.context.subject.open(self.monster)
        local page = self.context.tabs.pages[1]
        local passes = 0
        local self_context = self.context

        self_context.on_content_height = function(changed_page)
            if changed_page ~= page then
                return
            end

            passes = passes + 1

            if passes > 4 then
                error("table layout reentered recursively")
            end

            page.content.width = page.content.width - 1
            local body = self_context:find_node_with_hook(2, "monster_lookup_notes_resize")

            body.width = page.content.width
            body.hooks[2](body)
        end

        self.context.subject.show_result({
            title = "Goblin",
            info = {},
            sections = { { title = "Common", drops = {} } },
        })

        lu.assertEquals(passes, 2)
    end

    function suite:test_settings_refreshes_only_the_selected_cached_npc()
        local result = { title = "Guard", info = {}, sections = {}, no_drops = "none" }
        self.context.cache.put({ npc_id = 1, name = "Guard" }, result)
        self.context.cache.put({ npc_id = 2, name = "Guard" }, result)
        local selected
        self.context.settings_panel.start(function() end, function(monster)
            selected = monster
        end)
        self.context.on_settings_ready({ component = self.context.parent })
        self.context.dropdowns[#self.context.dropdowns]:pick(1)
        self.context.text_fields[#self.context.text_fields]:SetText("guard", true)
        self.context:tick(30)
        lu.assertEquals(#self.context.combos, 0)
        local refresh_button = self.context.simple_buttons[#self.context.simple_buttons]
        lu.assertStrContains(refresh_button.text, "Guard")
        refresh_button.action()
        refresh_button.action()
        lu.assertEquals(selected, { npc_id = 2, name = "Guard" })
        self.context.settings_panel.stop()
    end

    function suite:test_details_group_collapses_and_keeps_the_choice_when_switching_variant()
        local first = { version_anchor = "First", life_points = 900 }
        local second = { version_anchor = "Second", life_points = 1000 }
        self.context.subject.open(self.monster)
        self.context.subject.show_result({
            title = "Guard",
            sections = {},
            info = first,
            variants = { first, second },
        })
        local combat

        for _, button in ipairs(self.context.section_buttons) do
            if button.title == "Detailed stats" then
                combat = button
            end
        end

        lu.assertNotNil(combat)
        lu.assertFalse(combat.expanded)
        local page = self.context.tabs:GetPage(2)
        local collapsed_height = page.content_height
        combat:SetExpanded(true)
        lu.assertTrue(page.content_height > collapsed_height)
        self.context.dropdowns[1]:pick(2)
        local last_combat

        for _, button in ipairs(self.context.section_buttons) do
            if button.title == "Detailed stats" then
                last_combat = button
            end
        end

        lu.assertTrue(last_combat.expanded)
    end

    function suite:test_overview_has_one_details_toggle_and_keeps_common_values_visible()
        self.context.subject.open(self.monster)
        self.context.subject.show_result({
            title = "Guard",
            sections = {},
            info = {
                weakness_text = { "air" },
                is_aggressive = false,
                is_poisonous = false,
                slayer_level = 1,
                slayer_experience = 19,
                susceptible_to_poison = true,
            },
        })
        lu.assertEquals(#self.context.section_buttons, 2)
        lu.assertEquals(self.context.section_buttons[1].title, "Slayer")
        lu.assertTrue(self.context.section_buttons[1].expanded)
        lu.assertEquals(self.context.section_buttons[2].title, "Detailed stats")
        lu.assertFalse(self.context.section_buttons[2].expanded)
        local page = self.context.tabs:GetPage(2)
        lu.assertTrue(page.content_height < 320)
        local air

        for _, text in ipairs(self.context.texts) do
            if text.content == "Air" then
                air = text
            end
        end

        lu.assertNotNil(air)
        lu.assertFalse(air.hidden)
        lu.assertTrue(air.x > 160)
        lu.assertTrue(air.width > 0)
        self.context.section_buttons[2]:SetExpanded(true)
        lu.assertTrue(page.content_height > 320)
    end

    function suite:test_slayer_and_dungeon_share_one_toggle_and_keep_it_across_variants()
        local first = { version_anchor = "First", life_points = 100, slayer_level = 85 }
        local second = { version_anchor = "Second", life_points = 200, slayer_level = 85 }
        self.context.subject.open(self.monster)
        self.context.subject.show_result({
            title = "Abyssal demon",
            sections = {},
            info = first,
            variants = { first, second },
        })
        local slayer = self.context.section_buttons[1]
        lu.assertEquals(slayer.title, "Slayer")
        lu.assertTrue(slayer.expanded)
        local page = self.context.tabs:GetPage(2)
        local expanded_height = page.content_height
        slayer:SetExpanded(false)
        lu.assertTrue(page.content_height < expanded_height)
        self.context.dropdowns[1]:pick(2)
        local latest
        for _, button in ipairs(self.context.section_buttons) do
            if button.title == "Slayer" then
                latest = button
            end
        end
        lu.assertFalse(latest.expanded)
        latest:SetExpanded(true)
        lu.assertTrue(page.content_height > expanded_height - 30)
    end

    function suite:test_info_group_choices_carry_over_to_another_monster()
        local function group(title)
            local found
            for _, button in ipairs(self.context.section_buttons) do
                if button.title == title then
                    found = button
                end
            end
            return found
        end
        self.context.subject.open(self.monster)
        self.context.subject.show_result({
            title = "Goblin",
            sections = {},
            info = { life_points = 100, slayer_level = 1 },
        })
        group("Slayer"):SetExpanded(false)
        group("Detailed stats"):SetExpanded(true)
        self.context.subject.open({ name = "Guard" })
        self.context.subject.show_result({
            title = "Guard",
            sections = {},
            info = { life_points = 200, slayer_level = 1 },
        })
        lu.assertFalse(group("Slayer").expanded)
        lu.assertTrue(group("Detailed stats").expanded)
        lu.assertFalse(self.context.storage.monster_lookup_settings.slayer_expanded)
        lu.assertTrue(self.context.storage.monster_lookup_settings.detailed_stats_expanded)
    end

    return suite
end
