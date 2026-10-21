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
            sections = {
                {
                    title = "Other",
                    notes = { "Only in members worlds.", "Requires a quest." },
                    afterword = "Luck boosts can affect these drops.",
                    drops = {
                        {
                            name = "Rune scimitar",
                            quantity = "1",
                            rate = "1/2",
                            price = 15000,
                            note_marker = "1,2",
                            notes = "Only in members worlds. Requires a quest.",
                        },
                    },
                },
            },
        }
    end

    function suite:tearDown()
        self.context.subject.destroy()
    end

    local function find_text(context, value)
        for _, text in ipairs(context.texts) do
            if text.content == value then
                return text
            end
        end

        error("missing text: " .. value)
    end

    local function notes_button(context)
        for _, button in ipairs(context.simple_buttons) do
            if button.content.content:find("drop notes", 1, true) then
                return button
            end
        end
    end

    local function toggle(context)
        local button = assert(notes_button(context))
        button.action(button)
        return button
    end

    function suite:test_notes_start_collapsed_and_expanding_leaves_plain_notes_visible()
        self.context.subject.show_result(self.result)
        local page = self.context.tabs.pages[1]
        local height = page.content_height
        local note = find_text(self.context, "[1] Only in members worlds.")
        local other_note = find_text(self.context, "[2] Requires a quest.")
        local afterword = find_text(self.context, "Luck boosts can affect these drops.")
        local afterword_y = afterword.y
        local button = notes_button(self.context)

        lu.assertEquals(button.content.content, "Show drop notes (2)")
        lu.assertTrue(note.hidden)
        lu.assertTrue(other_note.hidden)
        lu.assertFalse(afterword.hidden == true)

        toggle(self.context)

        lu.assertEquals(button.content.content, "Hide drop notes (2)")
        lu.assertFalse(note.hidden)
        lu.assertFalse(other_note.hidden)
        lu.assertTrue(page.content_height > height)
        lu.assertTrue(afterword.y > afterword_y)

        toggle(self.context)

        lu.assertEquals(button.content.content, "Show drop notes (2)")
        lu.assertTrue(note.hidden)
        lu.assertTrue(other_note.hidden)
        lu.assertEquals(page.content_height, height)
    end

    function suite:test_plain_notes_without_item_references_have_no_toggle()
        self.result.sections[1].drops[1].note_marker = nil
        self.context.subject.show_result(self.result)

        lu.assertNil(notes_button(self.context))
        lu.assertFalse(find_text(self.context, "[1] Only in members worlds.").hidden == true)
        lu.assertFalse(
            find_text(self.context, "Luck boosts can affect these drops.").hidden == true
        )
    end

    function suite:test_unreferenced_notes_remain_visible_beside_collapsible_references()
        self.result.sections[1].drops[1].note_marker = "1"
        self.context.subject.show_result(self.result)

        lu.assertTrue(find_text(self.context, "[1] Only in members worlds.").hidden)
        lu.assertFalse(find_text(self.context, "[2] Requires a quest.").hidden == true)
    end

    function suite:test_search_and_category_toggles_preserve_collapsed_note_state()
        self.context.subject.show_result(self.result)
        local button = notes_button(self.context)
        local field = self.context.text_fields[1]
        field:SetText("coins", true)
        field:SetText("scim", true)
        self.context.section_buttons[1]:SetExpanded(false)
        self.context.section_buttons[1]:SetExpanded(true)

        lu.assertEquals(button.content.content, "Show drop notes (2)")
        lu.assertTrue(find_text(self.context, "[1] Only in members worlds.").hidden)
        local tooltip = self.context.tooltips[1]
        tooltip:Show()
        lu.assertFalse(tooltip.hidden)
        lu.assertEquals(tooltip.options.text, "Only in members worlds. Requires a quest.")
    end

    function suite:test_toggle_forwards_wheel_and_is_destroyed_with_the_view()
        self.context.subject.show_result(self.result)
        local button = notes_button(self.context)
        button.root.hooks[1](button.root, 1)
        lu.assertEquals(self.context.tabs.pages[1].scrollY, 32)

        self.context.subject.destroy()

        lu.assertTrue(button.root.destroyed)
    end

    function suite:test_filtering_and_note_toggles_reuse_text_measurements()
        self.result.sections[1].description = "Some drops have extra conditions."
        self.result.sections[1].drops[2] =
            { name = "Coins", quantity = "1", rate = "1/2", price = 1 }
        self.context.subject.show_result(self.result)
        toggle(self.context)
        local measurements = #self.context.text_measurements
        local field = self.context.text_fields[1]
        local note = find_text(self.context, "[1] Only in members worlds.")
        local note_y = note.y

        field:SetText("scim", true)

        lu.assertEquals(note.y, note_y - 40)
        lu.assertEquals(#self.context.text_measurements, measurements)

        field:SetText("nothing matches", true)
        field:SetText("", true)
        toggle(self.context)
        toggle(self.context)

        lu.assertEquals(#self.context.text_measurements, measurements)
        lu.assertEquals(note.y, note_y)
    end

    function suite:test_resizing_remeasures_expanded_notes_and_updates_their_height()
        self.result.sections[1].notes[1] = string.rep("Additional drop condition. ", 8)
        self.context.subject.show_result(self.result)
        toggle(self.context)
        local note = find_text(self.context, "[1] " .. self.result.sections[1].notes[1])
        local height = note.height
        local measurements = #self.context.text_measurements
        local body = self.context:find_node_with_hook(2, "monster_lookup_notes_resize")
        self.context.tabs.pages[1].content.width = 420
        body.width = 420
        body.hooks[2](body)

        lu.assertTrue(#self.context.text_measurements > measurements)
        lu.assertTrue(note.height > height)

        measurements = #self.context.text_measurements
        self.context.text_fields[1]:SetText("scim", true)

        lu.assertEquals(#self.context.text_measurements, measurements)
    end

    local function explanation_button(context)
        for _, button in ipairs(context.simple_buttons) do
            if button.content.content == "Notes" then
                return button
            end
        end
    end

    function suite:test_long_explanations_start_collapsed_above_the_table_and_expand_independently()
        local description = string.rep("These drops replace the usual roll when successful. ", 12)
        self.result.sections[1].description = description
        self.context.subject.show_result(self.result)
        local page = self.context.tabs.pages[1]
        local collapsed_height = page.content_height
        local button = assert(explanation_button(self.context))
        local label = find_text(self.context, description)
        local footnote = find_text(self.context, "[1] Only in members worlds.")
        lu.assertEquals(button.content.content, "Notes")
        lu.assertTrue(label.hidden)
        lu.assertTrue(footnote.hidden)
        lu.assertEquals(label.options.font, 11)

        button.action()

        lu.assertFalse(label.hidden)
        lu.assertTrue(page.content_height > collapsed_height)
        lu.assertTrue(footnote.hidden)
        lu.assertEquals(notes_button(self.context).content.content, "Show drop notes (2)")

        button.action()

        lu.assertTrue(label.hidden)
        lu.assertEquals(page.content_height, collapsed_height)
        button.root.hooks[1](button.root, 1)
        lu.assertEquals(page.scrollY, 32)
        self.context.subject.destroy()
        lu.assertTrue(button.root.destroyed)
    end

    function suite:test_short_descriptions_stay_visible_without_an_explanation_button()
        local description = "These items are rolled before other drops."
        self.result.sections[1].description = description
        self.context.subject.show_result(self.result)
        lu.assertNil(explanation_button(self.context))
        lu.assertFalse(find_text(self.context, description).hidden == true)
    end

    function suite:test_expanded_explanation_survives_search_and_reflows_when_resized()
        local description =
            string.rep("Extra chances apply while on the appropriate Slayer task. ", 12)
        self.result.sections[1].description = description
        self.context.subject.show_result(self.result)
        local button = assert(explanation_button(self.context))
        button.action()
        local label = find_text(self.context, description)
        local height = label.height
        local field = self.context.text_fields[1]
        field:SetText("coins", true)
        field:SetText("scim", true)
        lu.assertEquals(button.content.content, "Hide notes")
        lu.assertFalse(label.hidden)
        local measured = #self.context.text_measurements
        button.action()
        button.action()
        lu.assertEquals(#self.context.text_measurements, measured)

        local body = self.context:find_node_with_hook(2, "monster_lookup_notes_resize")
        self.context.tabs.pages[1].content.width = 420
        body.width = 420
        body.hooks[2](body)
        lu.assertTrue(label.height > height)
    end

    function suite:test_cached_mod_citations_are_filtered_without_losing_conditions_or_mutating_the_source()
        local section = self.result.sections[1]
        section.notes = {
            "Mod Sponge. Drop rates from Discord.",
            "Only on a Slayer task.",
            "Only in the Wilderness.",
        }
        section.drops[1].note_marker = "1,2,3"
        section.drops[1].notes = table.concat(section.notes, "\n\n")
        self.context.subject.show_result(self.result)
        lu.assertEquals(notes_button(self.context).content.content, "Show drop notes (2)")
        lu.assertEquals(
            self.context.tooltips[1].options.text,
            "Only on a Slayer task.<br><br>Only in the Wilderness."
        )
        lu.assertNotNil(find_text(self.context, "[1] Only on a Slayer task."))
        lu.assertNotNil(find_text(self.context, "[2] Only in the Wilderness."))
        lu.assertEquals(section.drops[1].note_marker, "1,2,3")
        lu.assertEquals(section.notes[1], "Mod Sponge. Drop rates from Discord.")
    end

    function suite:test_source_only_cached_notes_do_not_leave_an_empty_toggle_or_rarity_tooltip()
        local section = self.result.sections[1]
        section.notes = { "Mod Timbo. Drop rate source." }
        section.drops[1].note_marker = "1"
        section.drops[1].notes = section.notes[1]
        self.context.subject.show_result(self.result)
        lu.assertNil(notes_button(self.context))
        lu.assertEquals(#self.context.tooltips, 0)
    end

    return suite
end
