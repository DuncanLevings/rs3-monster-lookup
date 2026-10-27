local lu = require("luaunit")
local fixture = require("tests/support/window_fixture")

-- another plugin replacing what the Locations tab buttons do (src/ui/locations/navigation.lua)
return function(root)
    local suite = {}

    local RECORD = {
        title = "Guard",
        info = {},
        variants = {},
        sections = {},
        no_locations = nil,
        locations = {
            {
                name = "Falador",
                levels = "21",
                requirements = "None",
                spawns = "6",
                page = "Falador",
            },
            {
                name = "Varrock",
                levels = "21",
                requirements = "None",
                spawns = "8",
                page = "Varrock",
            },
        },
    }

    function suite:setUp()
        self.context = fixture.new(root)
        self.navigation = self.context.load_module("src/ui/locations/navigation")
        self.locations = self.context.load_module("src/ui/locations/component")
        local window = self.context.environment.prettyui.Window.new(
            self.context.parent,
            { onClose = function() end }
        )
        self.page = window:AddTabs({ { text = "Locations" } }, {}):GetPage(1)
    end

    function suite:tearDown()
        self.navigation.clear()
    end

    -- a provider that records what it was asked and keeps one active location
    local function route_provider(log)
        local state = { listener = nil, active = nil }
        local provider = {
            id = "me.plugin.routes",
            column_title = "Go",
            stop_label = "Stop route",
            note = "Routes by my plugin.",
            action = function(location)
                return {
                    label = "Route",
                    active_label = "Routing",
                    tooltip = "Route to " .. location.name,
                }
            end,
            start = function(location, title)
                log[#log + 1] = { "start", location.name, title }
                state.active = location

                if state.listener then
                    state.listener()
                end

                return true
            end,
            confirmation = function(location)
                return "Routing to " .. location.name
            end,
            is_active = function(location)
                return state.active ~= nil and location.name == state.active.name
            end,
            status = function()
                return state.active and "On the way" or "Pick a location"
            end,
            can_stop = function()
                return state.active ~= nil
            end,
            stop = function()
                state.active = nil

                if state.listener then
                    state.listener()
                end
            end,
            subscribe = function(callback)
                state.listener = callback
                return function()
                    state.listener = nil
                end
            end,
        }
        return provider, state
    end

    -- the row background behind a button
    local function background_in(context, button)
        for _, node in ipairs(context.nodes) do
            if node.parent == button.root.parent and node.fill == true then
                return node
            end
        end
    end

    -- the live buttons, by their label
    local function buttons(context)
        local found = {}

        for _, button in ipairs(context.simple_buttons) do
            if not button.root.destroyed then
                found[#found + 1] = button
            end
        end

        return found
    end

    local function labels(context)
        local list = {}

        for _, button in ipairs(buttons(context)) do
            list[#list + 1] = button.content.content
        end

        return list
    end

    local function shows(context, text)
        for _, label in ipairs(context.texts) do
            if label.content == text then
                local node, alive = label, true

                while node do
                    if node.destroyed then
                        alive = false
                        break
                    end

                    node = node.parent
                end

                if alive then
                    return true
                end
            end
        end

        return false
    end

    function suite:test_a_registered_provider_replaces_the_marker_in_open_tabs_and_back()
        local view = self.locations.new(self.page)
        view.set_monster(RECORD)
        lu.assertEquals(labels(self.context)[1], "Clear marker")

        local provider, state = route_provider({})
        local handle = assert(self.navigation.register(provider))

        lu.assertEquals(labels(self.context), { "Stop route", "Route", "Route" })
        lu.assertTrue(shows(self.context, "Go"))
        lu.assertTrue(shows(self.context, "Pick a location"))
        lu.assertNotNil(state.listener)

        handle.dispose()
        lu.assertEquals(labels(self.context)[1], "Clear marker")
        lu.assertNil(state.listener)
        view.destroy()
    end

    function suite:test_clicks_highlight_and_stop_go_through_the_provider()
        local log = {}
        local provider = route_provider(log)
        assert(self.navigation.register(provider))
        local theme = self.context.load_module("src/ui/common/theme")
        local view = self.locations.new(self.page)
        view.set_monster(RECORD)

        local row_buttons = buttons(self.context)
        local stop = row_buttons[1]
        lu.assertTrue(stop.disabled)

        row_buttons[3].action()
        lu.assertEquals(log[1], { "start", "Varrock", "Guard" })
        lu.assertEquals(row_buttons[3].content.content, "Routing")
        lu.assertEquals(row_buttons[2].content.content, "Route")
        lu.assertEquals(background_in(self.context, row_buttons[3]).rgba, theme.ROW_ACTIVE)
        lu.assertNotEquals(background_in(self.context, row_buttons[2]).rgba, theme.ROW_ACTIVE)
        lu.assertTrue(shows(self.context, "Routing to Varrock"))
        lu.assertFalse(stop.disabled)

        stop.action()
        lu.assertEquals(row_buttons[3].content.content, "Route")
        view.destroy()
    end

    function suite:test_bad_providers_are_turned_away()
        local navigation = self.navigation

        lu.assertNil(navigation.register({ id = "me.plugin.nav", action = print }))
        lu.assertNil(navigation.register({ id = "nodot", action = print, start = print }))
        lu.assertNil(
            navigation.register({
                id = "me.plugin.nav",
                action = print,
                start = print,
                stop = print,
            })
        )
        lu.assertNil(navigation.register({ id = "me.plugin.nav", action = "Mark", start = print }))
        lu.assertEquals(navigation.current().id, "monster_lookup.marker")
    end

    function suite:test_a_failing_provider_doesnt_take_the_tab_down()
        assert(self.navigation.register({
            id = "me.plugin.broken",
            action = function()
                error("action broke")
            end,
            start = function() end,
            status = function()
                error("status broke")
            end,
        }))
        local view = self.locations.new(self.page)
        view.set_monster(RECORD)
        view.set_monster(RECORD)

        lu.assertEquals(labels(self.context), {})
        lu.assertTrue(shows(self.context, "Navigation from another plugin ran into a problem."))
        lu.assertTrue(shows(self.context, "Falador"))

        local count = 0
        for _, message in ipairs(self.context.logs) do
            if message:find("me.plugin.broken failed in action", 1, true) then
                count = count + 1
            end
        end
        lu.assertEquals(count, 1)
        view.destroy()
    end

    function suite:test_a_minimal_provider_gets_buttons_without_a_stop_button()
        local started = 0
        assert(self.navigation.register({
            id = "me.plugin.simple",
            action = function()
                return { label = "Go" }
            end,
            start = function()
                started = started + 1
            end,
        }))
        local view = self.locations.new(self.page)
        view.set_monster(RECORD)

        lu.assertEquals(labels(self.context), { "Go", "Go" })
        buttons(self.context)[1].action()
        lu.assertEquals(started, 1)
        view.destroy()
        lu.assertEquals(labels(self.context), {})
    end

    function suite:test_the_export_registers_navigation_too()
        self.context.stub_module("src/app", { open = function() end })
        local api = self.context.load_module("src/api")
        local handle = assert(api.export.register_navigation(route_provider({})))

        lu.assertEquals(self.navigation.current().id, "me.plugin.routes")
        handle.dispose()
        lu.assertEquals(self.navigation.current().id, "monster_lookup.marker")
    end

    return suite
end
