local lu = require("luaunit")
local fixture = require("tests/support/window_fixture")

return function(root)
    local suite = {}

    function suite:setUp()
        self.context = fixture.new(root)
        self.context.subject.open({ name = "Goblin" }, function() end)
        self.context.subject.show_result(self.context.sample)
        self.field = self.context.text_fields[1]
        self.page = self.context.tabs.pages[1]
    end

    function suite:tearDown()
        self.context.subject.destroy()
    end

    local function item_row(context, name)
        for _, text in ipairs(context.texts) do
            if text.content == name then
                return text.parent
            end
        end

        error("missing item: " .. name)
    end

    function suite:test_search_is_right_anchored_and_shares_the_button_row()
        lu.assertEquals(self.field.root.x_anchor, 1)
        lu.assertEquals(self.field.root.x, -248)
        lu.assertEquals(self.field.root.y, self.context.simple_buttons[1].root.y)
        lu.assertEquals(self.field.options.maxLength, 128)
    end

    function suite:test_live_search_reuses_rows_and_field_and_resets_scroll()
        local row = item_row(self.context, "Rune scimitar")
        self.page:SetScrollPosition(200)
        self.field:SetText("rune scim", true)

        lu.assertFalse(row.hidden)
        lu.assertEquals(row.y, 30)
        lu.assertTrue(item_row(self.context, "Bronze arrow").hidden)
        lu.assertTrue(self.context.section_buttons[1].root.hidden)
        lu.assertFalse(self.context.section_buttons[2].root.hidden)
        lu.assertEquals(self.page.scrollY, 0)
        lu.assertEquals(#self.context.text_fields, 1)
        lu.assertNil(self.field.root.destroyed)
        lu.assertEquals(#self.context.sample.sections[2].drops, 2)
    end

    function suite:test_clear_restores_rows_and_previous_category_states()
        self.context.section_buttons[2]:SetExpanded(false)
        self.field:SetText("scim", true)
        lu.assertTrue(self.context.section_buttons[2].expanded)

        self.field:SetText("", true)

        lu.assertFalse(self.context.section_buttons[2].expanded)
        lu.assertFalse(self.context.section_buttons[1].root.hidden)
        lu.assertFalse(item_row(self.context, "Bronze arrow").hidden)
        lu.assertEquals(item_row(self.context, "Rune scimitar").y, 70)
    end

    function suite:test_no_matches_message_disappears_after_clearing()
        local before = self.page.content_height
        self.field:SetText("nothing resembles this item", true)
        local message

        for _, text in ipairs(self.context.texts) do
            if text.content == "No drops match your search." then
                message = text
            end
        end

        lu.assertNotNil(message)
        lu.assertFalse(message.hidden)
        lu.assertTrue(self.page.content_height < before)

        self.field:SetText("", true)

        lu.assertTrue(message.hidden)
        lu.assertEquals(self.page.content_height, before)
    end

    function suite:test_query_survives_refresh_and_settings_then_resets_for_another_monster()
        self.field:SetText("scim", true)
        self.context.subject.show_result(self.context.sample)
        lu.assertEquals(self.context.text_fields[2]:GetText(), "scim")

        self.context.subject.refresh_settings()
        lu.assertEquals(self.context.text_fields[3]:GetText(), "scim")

        self.context.subject.open({ name = "Cow" })
        self.context.subject.show_result(self.context.sample)
        lu.assertEquals(self.context.text_fields[4]:GetText(), "")
        lu.assertTrue(self.field.root.destroyed)
    end

    function suite:test_filter_keeps_numbered_notes_and_their_tooltips()
        self.context.subject.show_result({
            title = "Goblin",
            info = {},
            sections = {
                {
                    title = "Other",
                    notes = { "Only in members worlds." },
                    drops = {
                        { name = "Coins", quantity = "1", rate = "1/2", price = 1 },
                        {
                            name = "Rune scimitar",
                            quantity = "1",
                            rate = "1/2",
                            price = 15000,
                            note_marker = "1",
                            notes = "Only in members worlds.",
                        },
                    },
                },
            },
        })
        local field = self.context.text_fields[#self.context.text_fields]
        local tooltip = self.context.tooltips[#self.context.tooltips]
        tooltip:Show()
        field:SetText("scim", true)

        lu.assertTrue(tooltip.hidden)
        lu.assertEquals(tooltip.options.text, "Only in members worlds.")
        lu.assertFalse(tooltip.component.parent.hidden)
        lu.assertNil(tooltip.destroyed)

        local note

        for _, text in ipairs(self.context.texts) do
            if text.content == "[1] Only in members worlds." then
                note = text
            end
        end

        lu.assertNotNil(note)
        lu.assertFalse(note.parent.hidden)
    end

    function suite:test_input_resizes_without_overlapping_toolbar_buttons()
        self.page.content.width = 420
        local body = self.context:find_node_with_hook(2, "monster_lookup_notes_resize")
        body.width = 420
        body.hooks[2](body)

        lu.assertEquals(self.field.root.width, 176)
        lu.assertEquals(420 + self.field.root.x, 236)
    end

    function suite:test_wheel_over_input_uses_the_same_page_scroll_step()
        self.field.root.hooks[1](self.field.root, 1)

        lu.assertEquals(self.page.scrollY, 32)
    end

    return suite
end
