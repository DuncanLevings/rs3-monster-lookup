local lu = require("luaunit")
local fixture = require("tests/support/window_fixture")

return function(root)
    local suite = {}
    local configured_root = os.getenv("MONSTER_LOOKUP_EXAMPLE_ROOT")
    local example_root = configured_root or (root .. "/../monster-lookup-example")

    function suite:setUp()
        if not configured_root then
            local manifest = io.open(example_root .. "/plugin.json", "rb")

            if not manifest then
                lu.skip(
                    "consumer checkout missing; set MONSTER_LOOKUP_EXAMPLE_ROOT to run these tests"
                )
                return
            end

            manifest:close()
        end

        self.context = fixture.new(root)
        local context = self.context
        self.requests, self.opened, self.cancels, self.destroyed_handles = {}, {}, 0, 0
        self.immediate = true
        local owner = self
        context.stub_module("src/app", {
            open = function(selection)
                owner.opened[#owner.opened + 1] = selection
                return true
            end,
        })
        context.stub_module("src/data/lookup/service", {
            new_handle = function()
                return {
                    fetch = function(selection, complete)
                        owner.requests[#owner.requests + 1] =
                            { selection = selection, complete = complete }
                        if owner.immediate then
                            complete(MonsterDataCore.monster(selection), nil, { bundled = true })
                        end
                    end,
                    cancel = function()
                        owner.cancels = owner.cancels + 1
                    end,
                    destroy = function()
                        owner.destroyed_handles = owner.destroyed_handles + 1
                    end,
                }
            end,
        })
        local environment = setmetatable({
            MonsterDataCore = context.environment.MonsterDataCore,
            MonsterLookup = context.load_module("src/api").export,
            GameState = { LOBBY = 1, LOGINSCREEN = 2 },
        }, { __index = context.environment })
        self.game_state = {}
        environment.Event.GameStateChanged = {
            Subscribe = function(key, callback)
                owner.game_state[key] = callback
            end,
            Unsubscribe = function(key)
                owner.game_state[key] = nil
            end,
        }
        local modules = {}
        local function load_example(name)
            if modules[name] == nil then
                modules[name] =
                    assert(loadfile(example_root .. "/" .. name .. ".lua", "t", environment))()
            end
            return modules[name]
        end
        environment.require = load_example
        self.environment = environment
        self.example = load_example("src/example")
        self.example.start()
    end

    function suite:tearDown()
        if self.example then
            self.example.stop()
        end
    end

    function suite:button(text)
        for _, button in ipairs(self.context.simple_buttons) do
            if
                not button.root.destroyed
                and (button.content and button.content.content or button.text) == text
            then
                return button
            end
        end
        error("missing live button: " .. text)
    end

    function suite:test_search_selection_updates_custom_view_without_opening_standard_window()
        lu.assertTrue(self.example.open())
        local tabs = self.context.tabs
        tabs:SetActive(2)
        local field = self.context.text_fields[1]
        field:SetText("abyssal demon", true)
        self.context:tick(30)
        local found
        for _, button in ipairs(self.context.simple_buttons) do
            local text = button.content and button.content.content
            if not button.root.destroyed and text and text:find("Abyssal demon", 1, true) == 1 then
                found = button
                break
            end
        end
        lu.assertNotNil(found)
        found.action()
        lu.assertEquals(self.requests[#self.requests].selection.wiki_title, "Abyssal demon")
        lu.assertEquals(tabs.active, 1)
        lu.assertEquals(#self.opened, 0)
        self:button("Open Monster Lookup").action()
        lu.assertEquals(self.opened[1].wiki_title, "Abyssal demon")
    end

    function suite:test_item_and_stat_search_focus_reaches_the_standard_window()
        self.example.open()
        local tabs = self.context.tabs
        tabs:SetActive(3)
        self.context.text_fields[2]:SetText("abyssal whip", true)
        local selected
        for _, button in ipairs(self.context.simple_buttons) do
            local text = button.content and button.content.content
            if not button.root.destroyed and text and text:find("Abyssal demon", 1, true) == 1 then
                selected = button
                break
            end
        end
        lu.assertNotNil(selected)
        selected.action()
        lu.assertEquals(#self.opened, 0)
        self:button("Open Monster Lookup").action()
        lu.assertEquals(self.opened[1].focus.item, "Abyssal whip")

        tabs:SetActive(4)
        local stat_button
        for _, button in ipairs(self.context.simple_buttons) do
            local text = button.content and button.content.content
            if not button.root.destroyed and text and text:find(" XP | ", 1, true) then
                stat_button = button
                break
            end
        end
        lu.assertNotNil(stat_button)
        stat_button.action()
        self:button("Open Monster Lookup").action()
        lu.assertEquals(self.opened[2].focus.tab, "info")
        lu.assertNil(self.opened[2].focus.item)
    end

    function suite:test_failed_lookup_stays_in_the_example_and_variant_button_is_available()
        self.immediate = false
        self.example.open()
        self.requests[1].complete(nil, "Example lookup failure")
        lu.assertTrue(self:button("Open Monster Lookup").disabled)
        lu.assertTrue(self:button("Next variant").disabled)
        self.requests[1].complete((MonsterDataCore.monster("General Graardor")))
        local variant = self:button("Next variant")
        lu.assertFalse(variant.disabled)
        variant.action()
        lu.assertEquals(#self.opened, 0)
    end

    function suite:test_only_active_search_runs_and_closing_stops_search_subscriptions()
        self.example.open()
        local tabs = self.context.tabs
        local function searches()
            local count = 0
            for key in pairs(self.context.logic) do
                if key:match("^monster_lookup_search_") then
                    count = count + 1
                end
            end
            return count
        end
        lu.assertEquals(searches(), 0)
        for index = 2, 5 do
            tabs:SetActive(index)
            lu.assertEquals(searches(), index == 4 and 0 or 1)
        end
        local window = self.context.windows[#self.context.windows]
        window:Close()
        lu.assertEquals(searches(), 0)
    end

    function suite:test_extensions_and_standard_window_focus_are_owned_by_the_example()
        local registry = self.context.load_module("src/ui/extensions/registry")
        lu.assertEquals(#registry.list("section"), 1)
        lu.assertEquals(#registry.list("tab"), 1)
        self.example.open()
        self:button("Open example tab").action()
        lu.assertEquals(self.opened[1].focus.tab, "example.monster_lookup.tab")
        self.example.stop()
        lu.assertEquals(registry.list("section"), {})
        lu.assertEquals(registry.list("tab"), {})
        lu.assertEquals(self.destroyed_handles, 1)
    end

    function suite:test_stale_results_cannot_touch_closed_or_rebuilt_windows()
        self.immediate = false
        self.example.open()
        local first = self.requests[1]
        local window = self.context.windows[#self.context.windows]
        window:Close()
        first.complete((MonsterDataCore.monster("Goblin")))
        lu.assertTrue(self:button("Open Monster Lookup").disabled)
        self.example.open()
        lu.assertEquals(#self.requests, 2)
        local current = self.requests[2]
        current.complete((MonsterDataCore.monster("Goblin")))
        lu.assertFalse(self:button("Open Monster Lookup").disabled)
        self.game_state.monster_lookup_example({ newState = self.environment.GameState.LOBBY })
        lu.assertEquals(window.destroy_count, 1)
        lu.assertEquals(self.context.logic, {})
        first.complete((MonsterDataCore.monster("Abyssal demon")))
        self.example.open()
        lu.assertEquals(#self.requests, 3)
    end

    function suite:test_shutdown_destroys_every_component_before_its_window()
        self.example.open()
        local window = self.context.windows[#self.context.windows]
        local page = self.context.tabs:GetPage(1)
        self.example.stop()
        lu.assertEquals(window.destroy_count, 1)
        local old_height = page.content_height
        page.content.width = page.content.width + 20
        page.content.hooks[self.environment.ui.Hook.ONRESIZE]()
        lu.assertEquals(page.content_height, old_height)
        lu.assertEquals(self.context.logic, {})
        lu.assertNil(self.context.on_content_ready)
        lu.assertNil(self.context.on_settings_ready)
        lu.assertEquals(self.game_state, {})
        lu.assertEquals(self.destroyed_handles, 1)
        self.example.stop()
        lu.assertEquals(window.destroy_count, 1)
    end

    function suite:test_ribbon_and_settings_panels_open_the_example()
        local content = self.environment.ui.Layer.new(self.context.parent)
        self.context.on_content_ready({ component = content })
        local old = self.context.settings_views[#self.context.settings_views]
        self:button("Open example").action()
        lu.assertEquals(#self.requests, 1)
        self.context.on_content_ready({ component = content })
        lu.assertTrue(old.root.destroyed)
        self.context.on_settings_ready({ component = content })
        self.example.stop()
        for _, panel in ipairs(self.context.settings_views) do
            lu.assertTrue(panel.root.destroyed)
        end
    end

    return suite
end
