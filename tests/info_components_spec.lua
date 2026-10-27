local lu = require("luaunit")
local fixture = require("tests/support/window_fixture")

-- the info components (src/ui/info/stat_blocks.lua) and the model viewer (model.lua) used on
-- their own, outside the standard window, the way another plugin would
return function(root)
    local suite = {}

    local INFO = {
        combat_level = 2,
        life_points = 50,
        weakness_text = { "water" },
        is_aggressive = true,
        susceptible_to = { "inquisitor" },
        susceptible_to_poison = true,
        susceptible_to_stun = false,
        slayer_level = 1,
        slayer_experience = 5,
        slayer_category = { "Goblins" },
    }

    function suite:setUp()
        self.context = fixture.new(root)
        self.components = self.context.load_module("src/ui/info/stat_blocks")
        self.parent = self.context.environment.ui.Layer.new(self.context.parent)
    end

    -- texts drawn under a component, by their content
    local function labels(context, from)
        local found = {}

        for index = from or 1, #context.texts do
            local text = context.texts[index]

            if not text.destroyed and text.content then
                found[text.content] = (found[text.content] or 0) + 1
            end
        end

        return found
    end

    function suite:test_stats_shows_the_summary()
        local start = #self.context.texts + 1
        local stats = self.components.stats(self.parent)
        stats.set_info(INFO, "Goblin")
        local all = labels(self.context, start)

        for _, field in ipairs(self.components.SUMMARY_FIELDS) do
            lu.assertNotNil(all[field], field)
        end

        lu.assertTrue(stats.layout(300, 0) > 0)
        lu.assertEquals(stats.height(), stats.layout(300, 0))
    end

    function suite:test_components_have_their_own_state()
        local first = self.components.stats(self.parent)
        local second = self.components.stats(self.parent)
        first.set_info(INFO, "Goblin")
        second.set_info({ weakness_text = { "fire" } }, "Imp")

        local first_height = first.layout(300, 0)
        second.destroy()

        lu.assertFalse(first.empty())
        lu.assertEquals(first.layout(300, 0), first_height)
        lu.assertTrue(second.empty())
    end

    function suite:test_slayer_is_empty_without_slayer_data()
        local slayer = self.components.slayer(self.parent)
        slayer.set_info({ combat_level = 5 }, "Not in the codex")

        lu.assertTrue(slayer.empty())
        lu.assertEquals(slayer.layout(300, 0), 0)

        slayer.set_info(INFO, "Goblin")
        lu.assertFalse(slayer.empty())
        lu.assertTrue(slayer.layout(300, 0) > 0)
    end

    function suite:test_groups_start_how_the_caller_says_and_report_toggles()
        local toggles = {}
        local detailed = self.components.detailed_stats(self.parent, {
            expanded = false,
            on_toggle = function(open)
                toggles[#toggles + 1] = open
            end,
        })
        detailed.set_info(INFO, "Goblin")
        local closed = detailed.layout(300, 0)

        local button = self.context.section_buttons[#self.context.section_buttons]
        lu.assertEquals(button.title, "Detailed stats")
        lu.assertFalse(button.expanded)

        button:SetExpanded(true)
        lu.assertEquals(toggles, { true })
        lu.assertTrue(detailed.layout(300, 0) > closed)

        -- nothing saved: the standard window does that, a component just reports
        lu.assertNil(self.context.storage.monster_lookup_settings)
    end

    function suite:test_destroy_removes_what_it_made_and_stops_updating()
        local start = #self.context.texts + 1
        local stats = self.components.stats(self.parent)
        stats.set_info(INFO, "Goblin")
        stats.destroy()

        for index = start, #self.context.texts do
            local text = self.context.texts[index]
            local node = text

            -- every label sits under the components block, which is destroyed
            while node and not node.destroyed do
                node = node.parent
            end

            lu.assertNotNil(node, tostring(text.content))
        end

        for _, tooltip in ipairs(self.context.tooltips) do
            lu.assertTrue(tooltip.destroyed)
        end

        local count = #self.context.texts
        stats.set_info(INFO, "Goblin")
        lu.assertEquals(#self.context.texts, count)
        lu.assertEquals(stats.layout(300, 0), 0)
        stats.destroy()
    end

    -- model viewer

    local function enable_models(context)
        context.environment.config.NPC = {
            FromID = function(npc_id)
                if npc_id == 1 then
                    return { visibleCombatLevel = 2, gridSize = 1 }
                end
            end,
        }
        context.stub_module(
            "src/data/library/api",
            require("tests/support/core_stub")({
                npc_ids = function()
                    return { 1 }
                end,
            })
        )
    end

    function suite:test_model_only_draws_while_active()
        enable_models(self.context)
        local model = self.context.load_module("src/ui/info/model")
        local viewer = model.new(self.parent, { width = 240, height = 180, x = 10, y = 20 })
        viewer.set_monster({ title = "Goblin", info = INFO })

        lu.assertEquals(#self.context.models, 0)
        lu.assertFalse(viewer.showing())

        viewer.set_active(true)
        lu.assertEquals(#self.context.models, 1)
        local drawn = self.context.models[1]
        lu.assertEquals(drawn.npc_id, 1)
        lu.assertEquals(drawn.width, 240)
        lu.assertEquals(drawn.parent.x, 10)
        lu.assertEquals(drawn.parent.y, 20)
        lu.assertEquals(drawn.parent.scroll_width, 240)

        viewer.resize(300, 200)
        lu.assertEquals(drawn.width, 300)

        viewer.set_active(false)
        lu.assertTrue(drawn.destroyed)
        lu.assertTrue(drawn.parent.destroyed)

        viewer.set_active(true)
        lu.assertEquals(#self.context.models, 2)
        viewer.destroy()
        lu.assertTrue(self.context.models[2].destroyed)

        -- destroyed stays destroyed
        viewer.set_active(true)
        lu.assertEquals(#self.context.models, 2)
    end

    function suite:test_model_zoom_limits_and_scroll_zoom_option()
        enable_models(self.context)
        local model = self.context.load_module("src/ui/info/model")
        local hook = self.context.environment.ui.Hook.ONSCROLLWHEEL

        local still = model.new(self.parent, { width = 240, height = 180, scroll_zoom = false })
        still.set_monster({ title = "Goblin", info = INFO })
        still.set_active(true)
        lu.assertNil(self.context.models[1].listeners[hook])
        still.destroy()

        local viewer = model.new(self.parent, { width = 240, height = 180, zoom_max = 1.1 })
        viewer.set_monster({ title = "Goblin", info = INFO })
        viewer.set_active(true)
        local drawn = self.context.models[2]
        local start = drawn.viewDistance
        local scroll = drawn.listeners[hook].handlers.monster_lookup_preview_zoom

        for _ = 1, 20 do
            scroll(drawn, 1)
        end

        lu.assertTrue(drawn.viewDistance > start)
        lu.assertTrue(drawn.viewDistance <= math.floor(start * 1.1) + 1)
        viewer.destroy()
    end

    function suite:test_model_without_an_npc_fails_once_until_another_monster()
        enable_models(self.context)
        local model = self.context.load_module("src/ui/info/model")
        local viewer = model.new(self.parent, { width = 240, height = 180 })
        viewer.set_monster({ title = "Goblin", info = { combat_level = 99 } })
        viewer.set_active(true)

        lu.assertTrue(viewer.failed())
        lu.assertFalse(viewer.showing())
        viewer.set_active(true)
        lu.assertEquals(#self.context.models, 0)

        viewer.set_monster({ title = "Goblin", info = INFO })
        lu.assertFalse(viewer.failed())
        lu.assertTrue(viewer.showing())
        viewer.destroy()
    end

    return suite
end
