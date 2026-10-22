local lu = require("luaunit")
local fixture = require("tests/support/window_fixture")

-- other plugins sections and tabs in the standard window (src/ui/extensions/), and the
-- export main.lua hands to plugins that depend on Monster Lookup (src/api.lua)
return function(root)
    local suite = {}

    local function result(title)
        return {
            title = title,
            sections = {},
            info = { combat_level = 2, weakness_text = { "water" } },
            variants = { { combat_level = 2 } },
            locations = {},
            no_locations = "none",
        }
    end

    function suite:setUp()
        self.context = fixture.new(root)
        self.registry = self.context.load_module("src/ui/extensions/registry")
        self.window = self.context.subject
    end

    function suite:tearDown()
        self.registry.clear()
    end

    -- a label with this text thats still on screen (it and everything above it alive).
    -- earlier renders leave destroyed copies behind, those dont count
    local function shows(context, text)
        for _, label in ipairs(context.texts) do
            if not label.destroyed and label.content == text then
                local node, alive = label.parent, true

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

    local function logged(context, pattern)
        local count = 0

        for _, message in ipairs(context.logs) do
            if message:find(pattern, 1, true) then
                count = count + 1
            end
        end

        return count
    end

    function suite:test_registration_checks_the_definition_and_copies_it()
        local registry = self.registry

        lu.assertNil(registry.register({ id = "no-dot", kind = "section", title = "A", content = print }))
        lu.assertNil(registry.register({ id = "me.plugin.a", kind = "box", title = "A", content = print }))
        lu.assertNil(registry.register({ id = "me.plugin.a", kind = "section", title = "A" }))
        lu.assertNil(registry.register({ id = "me.plugin.a", kind = "section", title = "A", create = print }))

        local definition = { id = "me.plugin.b", kind = "section", title = "B", order = 2, content = print }
        local b = assert(registry.register(definition))
        local a = assert(registry.register({ id = "me.plugin.a", kind = "section", title = "A", order = 2, content = print }))
        assert(registry.register({ id = "me.plugin.c", kind = "section", title = "C", order = 1, content = print }))
        local again, problem = registry.register({ id = "me.plugin.a", kind = "section", title = "A", content = print })

        lu.assertNil(again)
        lu.assertStrContains(problem, "already registered")

        definition.title = "changed"
        local ids = {}
        for _, entry in ipairs(registry.list("section")) do
            ids[#ids + 1] = entry.id
            lu.assertNotEquals(entry.title, "changed")
        end
        lu.assertEquals(ids, { "me.plugin.c", "me.plugin.a", "me.plugin.b" })

        b.dispose()
        b.dispose()
        a.dispose()
        lu.assertEquals(#registry.list("section"), 1)
    end

    function suite:test_sections_show_in_the_info_tab_and_go_when_disposed()
        local seen = {}
        local handle = assert(self.registry.register({
            id = "me.plugin.notes",
            kind = "section",
            title = "My notes",
            content = function(context)
                seen[#seen + 1] = context
                return { rows = { { "Kills", "12" } }, text = "Bring antipoison." }
            end,
        }))

        self.window.open({ name = "Goblin", npc_id = 1 })
        self.window.show_result(result("Goblin"), nil, { bundled = true, built = "2026-10-22" })

        lu.assertTrue(shows(self.context, "Kills"))
        lu.assertTrue(shows(self.context, "Bring antipoison."))
        local last = seen[#seen]
        lu.assertEquals(last.monster.title, "Goblin")
        lu.assertEquals(last.monster.npc_id, 1)
        lu.assertEquals(last.source, "bundle")

        handle.dispose()
        lu.assertFalse(shows(self.context, "Kills"))
        lu.assertTrue(shows(self.context, "Detailed stats") or #self.context.section_buttons > 0)
    end

    function suite:test_a_failing_section_shows_a_note_and_the_rest_still_works()
        assert(self.registry.register({
            id = "me.plugin.broken",
            kind = "section",
            title = "Broken",
            content = function()
                error("boom")
            end,
        }))

        self.window.open({ name = "Goblin", npc_id = 1 })
        self.window.show_result(result("Goblin"), nil, { bundled = true })
        self.window.show_result(result("Goblin"), nil, { bundled = true })

        lu.assertTrue(shows(self.context, "This section from another plugin could not be shown."))
        lu.assertEquals(logged(self.context, "me.plugin.broken failed in content"), 1)

        local titles = {}
        for _, button in ipairs(self.context.section_buttons) do
            titles[button.title] = true
        end
        lu.assertTrue(titles["Detailed stats"])
    end

    function suite:test_old_contexts_go_stale_and_refresh_only_works_while_current()
        local calls = 0
        ---@type table?
        local captured = nil
        assert(self.registry.register({
            id = "me.plugin.async",
            kind = "section",
            title = "Async",
            content = function(context)
                calls = calls + 1
                captured = captured or context
                return nil
            end,
        }))

        self.window.open({ name = "Goblin", npc_id = 1 })
        self.window.show_result(result("Goblin"), nil, { bundled = true })
        local current = assert(captured)
        captured = nil
        local before = calls

        lu.assertTrue(current.is_current())
        current.refresh()
        lu.assertEquals(calls, before + 1)

        self.window.open({ name = "Imp", npc_id = 2 })
        lu.assertFalse(current.is_current())
        current.refresh()
        lu.assertEquals(calls, before + 1)
    end

    local function recording_tab(registry, id)
        local calls = {}
        local handle = assert(registry.register({
            id = id,
            kind = "tab",
            title = "Helper",
            create = function(container)
                calls[#calls + 1] = { "create", container }
                container:SetHeight(120)
            end,
            update = function(context, container)
                calls[#calls + 1] = { "update", context.monster.title, container, context.mode }
            end,
            activate = function()
                calls[#calls + 1] = { "activate" }
            end,
            deactivate = function()
                calls[#calls + 1] = { "deactivate" }
            end,
            destroy = function(container)
                calls[#calls + 1] = { "destroy", container }
            end,
        }))
        return calls, handle
    end

    local function names(calls)
        local list = {}
        for _, call in ipairs(calls) do
            list[#list + 1] = call[1]
        end
        return list
    end

    function suite:test_custom_tabs_get_their_container_and_every_lifecycle_call()
        local calls = recording_tab(self.registry, "me.plugin.helper")

        self.window.open({ name = "Goblin", npc_id = 1 })
        self.window.show_result(result("Goblin"), nil, { bundled = true })
        local tabs = self.context.tabs

        lu.assertEquals(tabs.entries[4].text, "Helper")
        lu.assertEquals(calls[1][1], "create")
        local container = calls[1][2]
        lu.assertEquals(calls[#calls][2], "Goblin")
        lu.assertIs(calls[#calls][3], container)

        tabs:SetActive(4)
        tabs:SetActive(1)
        self.window.destroy()

        local list = names(calls)
        lu.assertEquals(list[#list - 2], "activate")
        lu.assertEquals(list[#list - 1], "deactivate")
        lu.assertEquals(list[#list], "destroy")
        lu.assertTrue(container.destroyed)
    end

    function suite:test_tabs_registered_later_rebuild_the_window_on_the_next_open()
        self.window.open({ name = "Goblin", npc_id = 1 })
        local windows = #self.context.windows
        local calls, handle = recording_tab(self.registry, "me.plugin.late")

        self.window.open({ name = "Imp", npc_id = 2 })
        lu.assertEquals(#self.context.windows, windows + 1)
        lu.assertEquals(self.context.windows[windows].destroy_count, 1)
        lu.assertEquals(calls[1][1], "create")

        -- disposed while showing: torn down now, the window is made again next time
        handle.dispose()
        lu.assertEquals(names(calls)[#calls], "destroy")
        lu.assertTrue(shows(self.context, "The plugin that added this tab was turned off."))
        self.window.open({ name = "Cow", npc_id = 3 })
        lu.assertEquals(#self.context.windows, windows + 2)
        lu.assertEquals(#self.context.tabs.entries, 3)
    end

    function suite:test_structured_tabs_and_opening_on_an_extension_tab()
        assert(self.registry.register({
            id = "me.plugin.table",
            kind = "tab",
            title = "Table",
            content = function(context)
                return { rows = { { "Monster", context.monster.title or "loading" } } }
            end,
        }))

        self.window.open({ name = "Goblin", npc_id = 1 }, nil, { tab = "me.plugin.table" })
        self.window.show_result(result("Goblin"), nil, { bundled = true })

        lu.assertEquals(self.context.tabs.active, 4)
        lu.assertTrue(shows(self.context, "Monster"))
        lu.assertTrue(shows(self.context, "Goblin"))
    end

    -- the export

    local function load_api(context, started)
        local opened = {}
        context.stub_module("src/app", {
            open = function(monster)
                opened[#opened + 1] = monster
                return started
            end,
        })
        return context.load_module("src/api"), opened
    end

    function suite:test_export_hands_out_fresh_tables_and_cleans_up_on_shutdown()
        local api, opened = load_api(self.context, true)
        local export = api.export

        lu.assertEquals(export.version().api.major, 1)

        lu.assertNil(export.data)

        lu.assertTrue(export.open("General Graardor", { tab = "info", item = 5 }))
        lu.assertEquals(opened[1], {
            name = "General Graardor",
            wiki_title = "General Graardor",
            focus = { tab = "info" },
        })
        lu.assertFalse(export.open(nil))

        local parent = self.context.environment.ui.Layer.new(self.context.parent)
        local components = export.components()
        local kept = components.stats(parent)
        local dropped = components.stats(parent)
        kept.set_info({ weakness_text = { "fire" } }, "Imp")
        dropped.set_info({ weakness_text = { "fire" } }, "Imp")
        dropped.destroy()

        api.shutdown()
        lu.assertTrue(kept.empty())
        lu.assertNil(export.shutdown)
    end

    return suite
end
