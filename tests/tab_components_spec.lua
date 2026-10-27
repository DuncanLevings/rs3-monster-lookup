local lu = require("luaunit")
local fixture = require("tests/support/window_fixture")

-- the drops and locations components on their own, each in a page the test owns
return function(root)
    local suite = {}

    local function record(title)
        return {
            title = title,
            info = {},
            variants = {},
            sections = {
                {
                    title = "Drops",
                    drops = {
                        { name = "Bones", quantity = "1", rate = "Always", notes = "" },
                        { name = "Coins", quantity = "5", rate = "1/2", notes = "" },
                    },
                },
            },
            locations = {},
            no_locations = "none",
        }
    end

    function suite:setUp()
        self.context = fixture.new(root)
        self.drops = self.context.load_module("src/ui/drops/component")
    end

    local function page(context)
        local window =
            context.environment.prettyui.Window.new(context.parent, { onClose = function() end })
        return window:AddTabs({ { text = "Drops" } }, {}):GetPage(1)
    end

    -- the search field each drops component made last
    local function search_field(context, from)
        local found

        for index = from, #context.text_fields do
            local field = context.text_fields[index]

            if field.options.placeholder == "Search drops..." and not field.root.destroyed then
                found = field
            end
        end

        return found
    end

    function suite:test_drops_keep_their_own_search_and_reset_for_a_new_monster()
        local context = self.context
        local first_from = #context.text_fields + 1
        local first = self.drops.new(page(context))
        first.set_monster(record("Goblin"), { item = "Bones" })
        local first_field = assert(search_field(context, first_from))

        local second_from = #context.text_fields + 1
        local second = self.drops.new(page(context))
        second.set_monster(record("Imp"))
        local second_field = assert(search_field(context, second_from))

        lu.assertEquals(first_field.text, "Bones")
        lu.assertEquals(second_field.text, "")

        -- a refresh of the same monster keeps what was typed, a new monster starts empty
        first_field:SetText("Coins", true)
        first.update(record("Goblin"))
        lu.assertEquals(assert(search_field(context, first_from)).text, "Coins")

        first.set_monster(record("Cow"))
        lu.assertEquals(assert(search_field(context, first_from)).text, "")
        lu.assertEquals(assert(search_field(context, second_from)).text, "")

        first.destroy()
        second.destroy()
    end

    function suite:test_drops_can_leave_out_the_search_box()
        local context = self.context
        local from = #context.text_fields + 1
        local drops = self.drops.new(page(context), { search = false, kill_value = false })
        drops.set_monster(record("Goblin"))

        lu.assertNil(search_field(context, from))

        for _, text in ipairs(context.texts) do
            lu.assertNil(tostring(text.content):find("Average kill", 1, true))
        end

        drops.destroy()
    end

    function suite:test_destroyed_drops_ignore_later_calls()
        local context = self.context
        local from = #context.text_fields + 1
        local drops = self.drops.new(page(context))
        drops.set_monster(record("Goblin"))
        drops.destroy()

        lu.assertNil(search_field(context, from))
        local count = #context.text_fields
        drops.set_monster(record("Imp"))
        drops.update(record("Imp"))
        drops.refresh()
        lu.assertEquals(#context.text_fields, count)
        drops.destroy()
    end

    function suite:test_locations_show_and_clear_their_own_rows()
        local context = self.context
        local locations = context.load_module("src/ui/locations/component")
        local with_rows = record("Goblin")
        with_rows.locations = {
            { name = "Lumbridge", levels = "2", requirements = "None", spawns = "4" },
        }
        with_rows.no_locations = nil

        local first = locations.new(page(context))
        local second = locations.new(page(context))
        first.set_monster(with_rows)
        second.set_monster(with_rows)

        local before = #context.simple_buttons
        first.destroy()
        second.set_monster(nil)
        second.set_monster(with_rows)

        lu.assertTrue(#context.simple_buttons > before)
        second.destroy()
        first.set_monster(with_rows)
        lu.assertTrue(#context.simple_buttons > before)
    end

    return suite
end
