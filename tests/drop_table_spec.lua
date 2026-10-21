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
            { text = "Normal mode", id = 1 },
            { text = "Hard mode", id = 2 },
        })
        lu.assertEquals(section_titles(self.context), { "100%", "Other" })

        local before = #self.context.texts
        picker:pick(2)

        lu.assertEquals(section_titles(self.context), { "100%" })
        lu.assertTrue(visible_texts(self.context, before)["Dragon bones"])
        lu.assertEquals(self.context.dropdowns[#self.context.dropdowns].selected, 2)
    end

    function suite:test_opening_another_monster_goes_back_to_the_first_mode()
        self.context.subject.open(self.monster, function() end)
        self.context.subject.show_result(grouped_result())
        self.context.dropdowns[#self.context.dropdowns]:pick(2)

        self.context.subject.open({ name = "Kree'arra" }, function() end)
        self.context.subject.show_result(grouped_result())

        lu.assertEquals(self.context.dropdowns[#self.context.dropdowns].selected, 1)
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
        page.content.width = 420
        body.width = 420
        body.hooks[2](body)

        lu.assertTrue(field.y >= picker.y + picker.height)
        lu.assertTrue(420 + field.x >= 8)
        lu.assertTrue(page.content_height > full_height)
        local status = self.context.texts[1]

        for _, text in ipairs(self.context.texts) do
            if text.options and text.options.font == 11 and text.options.maxLines == 2 then
                status = text
            end
        end

        lu.assertTrue(status.y >= field.y + field.height)

        page.content.width = 800
        body.width = 800
        body.hooks[2](body)

        lu.assertEquals(field.y, 12)
        lu.assertEquals(page.content_height, full_height)
    end

    function suite:test_very_narrow_toolbar_wraps_the_mode_picker_too()
        self.context.subject.open(self.monster, function() end)
        self.context.tabs.pages[1].content.width = 300
        self.context.subject.show_result(grouped_result())
        local field = self.context.text_fields[1].root
        local picker = self.context.dropdowns[1]

        lu.assertTrue(picker.y >= 36)
        lu.assertTrue(picker.x + picker.width <= 292)
        lu.assertTrue(
            field.y >= picker.y + picker.height or 300 + field.x >= picker.x + picker.width
        )
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
