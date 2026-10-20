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

    return suite
end
