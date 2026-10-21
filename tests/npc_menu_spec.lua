local lu = require("luaunit")
local fixture = require("tests/support/menu_fixture")

local VIEW_DROPS_LABEL = "View drops "

return function(root)
    local suite = {}

    function suite:setUp()
        self.context = fixture.new(root)
        self.context:start()
    end

    function suite:tearDown()
        self.context.subject.stop()
    end

    function suite:test_start_is_idempotent()
        self.context:start()

        lu.assertEquals(self.context.subscribe_count, 1)
    end

    function suite:test_view_drops_uses_the_chosen_colour_from_the_next_menu_on()
        local npc = fixture.npc()
        local first = self.context:open_menu({ fixture.entry(npc) })
        self.context.colour = "8fd3d3"
        local second = self.context:open_menu({ fixture.entry(npc) })

        lu.assertEquals(first.added[1].label, "View drops Goblin")
        lu.assertEquals(second.added[1].label, "<col=8fd3d3>View drops</col> Goblin")
    end

    function suite:test_adds_one_entry_for_multiple_actions_on_the_same_npc()
        local npc = fixture.npc()

        local menu = self.context:open_menu({ fixture.entry(npc), fixture.entry(npc) })

        lu.assertEquals(#menu.added, 1)
        lu.assertEquals(menu.added[1].label, VIEW_DROPS_LABEL .. "Goblin")
    end

    function suite:test_keeps_stacked_npcs_with_the_same_config_separate()
        local first = fixture.npc({ uid = 11 })
        local second = fixture.npc({ uid = 12 })

        local menu = self.context:open_menu({ fixture.entry(first), fixture.entry(second) })

        for _, item in ipairs(menu.added) do
            item.callback(item.monster)
        end

        lu.assertEquals(#menu.added, 2)
        lu.assertEquals(self.context.selections[1].entity_uid, 11)
        lu.assertEquals(self.context.selections[2].entity_uid, 12)
    end

    function suite:test_leaves_existing_entries_in_their_original_order()
        local npc = fixture.npc()
        local examine = fixture.entry(npc)
        local attack = fixture.entry(npc)
        local other_action = {}

        local menu = self.context:open_menu({ examine, other_action, attack })

        lu.assertIs(menu.entries[1], examine)
        lu.assertIs(menu.entries[2], other_action)
        lu.assertIs(menu.entries[3], attack)
        lu.assertEquals(menu.swaps, 0)
    end

    function suite:test_selects_a_snapshot_of_the_monster_details()
        local npc = fixture.npc({ combat_level = 5 })
        local menu = self.context:open_menu({ fixture.entry(npc) })
        local item = menu.added[1]

        item.callback(item.monster)

        lu.assertEquals(self.context.selections, {
            { npc_id = 100, entity_uid = 10, name = "Goblin", combat_level = 5 },
        })
    end

    function suite:test_selection_still_works_after_the_npc_despawns()
        local npc = fixture.npc()
        local menu = self.context:open_menu({ fixture.entry(npc) })
        local item = menu.added[1]
        npc.isValid = false
        npc.config = nil

        item.callback(item.monster)

        lu.assertEquals(#self.context.selections, 1)
        lu.assertEquals(self.context.selections[1].npc_id, 100)
    end

    function suite:test_ignores_non_attackable_npcs()
        local npc = fixture.npc({ name = "Banker", attack_index = -1 })

        local menu = self.context:open_menu({ fixture.entry(npc) })

        lu.assertEquals(menu.added, {})
    end

    function suite:test_ignores_familiars()
        local npc = fixture.npc({ familiar = true })

        local menu = self.context:open_menu({ fixture.entry(npc) })

        lu.assertEquals(menu.added, {})
    end

    function suite:test_ignores_invalid_entities_without_reading_their_config()
        local npc = fixture.npc({ valid = false })
        npc.config = nil

        local menu = self.context:open_menu({ { npcData = { entity = npc } } })

        lu.assertEquals(menu.added, {})
    end

    function suite:test_ignores_entries_without_an_npc()
        local menu = self.context:open_menu({ {}, { npcData = {} } })

        lu.assertEquals(menu.added, {})
    end

    function suite:test_handles_an_empty_menu()
        local menu = self.context:open_menu({})

        lu.assertEquals(menu.entries, {})
    end

    function suite:test_preserves_the_parent_config_for_variants()
        local npc = fixture.npc({ npc_id = 301, parent_npc_id = 300 })

        local menu = self.context:open_menu({ fixture.entry(npc) })

        lu.assertEquals(menu.added[1].monster.npc_id, 301)
        lu.assertEquals(menu.added[1].monster.parent_npc_id, 300)
    end

    function suite:test_stop_is_idempotent_and_removes_the_subscription()
        self.context.subject.stop()
        self.context.subject.stop()

        lu.assertEquals(self.context.unsubscribe_count, 1)
        lu.assertEquals(self.context.subscriptions, {})
    end

    function suite:test_stopped_sessions_ignore_existing_menu_callbacks()
        local menu = self.context:open_menu({ fixture.entry(fixture.npc()) })
        local item = menu.added[1]
        self.context.subject.stop()

        item.callback(item.monster)

        lu.assertEquals(self.context.selections, {})
    end

    function suite:test_restarting_does_not_reactivate_old_menu_callbacks()
        local menu = self.context:open_menu({ fixture.entry(fixture.npc()) })
        local item = menu.added[1]
        self.context.subject.stop()
        self.context:start()

        item.callback(item.monster)

        lu.assertEquals(self.context.selections, {})
    end

    function suite:test_restarted_sessions_handle_new_selections_once()
        self.context.subject.stop()
        self.context:start()
        local menu = self.context:open_menu({ fixture.entry(fixture.npc()) })
        local item = menu.added[1]

        item.callback(item.monster)

        lu.assertEquals(#menu.added, 1)
        lu.assertEquals(#self.context.selections, 1)
    end

    function suite:test_uses_the_attack_subject_formatting_even_when_examine_comes_first()
        local npc = fixture.npc()
        local subject = "<col=ffff00>Goblin</col>"
        local examine = fixture.entry(npc, "Goblin", 1)
        local attack = fixture.entry(npc, subject, 0)

        local menu = self.context:open_menu({ examine, attack })

        lu.assertEquals(#menu.added, 1)
        lu.assertEquals(menu.added[1].label, VIEW_DROPS_LABEL .. subject)
        lu.assertEquals(menu.added[1].monster.name, "Goblin")
    end

    function suite:test_keeps_each_stacked_monsters_attack_colour()
        local first = fixture.npc({ uid = 11 })
        local second = fixture.npc({ uid = 12 })
        local first_subject = "<col=ffff00>Goblin</col>"
        local second_subject = "<col=ff0000>Goblin</col>"

        local menu = self.context:open_menu({
            fixture.entry(first, first_subject),
            fixture.entry(second, second_subject),
        })

        lu.assertEquals(menu.added[1].label, VIEW_DROPS_LABEL .. first_subject)
        lu.assertEquals(menu.added[2].label, VIEW_DROPS_LABEL .. second_subject)
        lu.assertEquals(menu.swaps, 0)
    end

    function suite:test_falls_back_to_the_name_when_the_attack_subject_is_empty()
        local menu = self.context:open_menu({ fixture.entry(fixture.npc(), "") })

        lu.assertEquals(menu.added[1].label, VIEW_DROPS_LABEL .. "Goblin")
    end

    function suite:test_places_view_drops_after_examine_and_before_cancel()
        local npc = fixture.npc()
        local attack = fixture.entry(npc)
        local walk = { verbText = "Walk here" }
        local examine = fixture.entry(npc, "Goblin", 1)
        local cancel = { verbText = "Cancel" }

        local menu = self.context:open_menu({ attack, walk, examine, cancel })

        lu.assertIs(menu.entries[1], attack)
        lu.assertIs(menu.entries[2], walk)
        lu.assertIs(menu.entries[3], examine)
        lu.assertIs(menu.entries[4], menu.added[1])
        lu.assertIs(menu.entries[5], cancel)
    end

    function suite:test_places_each_lookup_after_its_own_examine_for_stacked_monsters()
        local first = fixture.npc({ uid = 11 })
        local second = fixture.npc({ uid = 12 })
        local first_attack = fixture.entry(first)
        local second_attack = fixture.entry(second)
        local first_examine = fixture.entry(first, "Goblin", 1)
        local second_examine = fixture.entry(second, "Goblin", 1)
        local cancel = { verbText = "Cancel" }

        local menu = self.context:open_menu({
            first_attack,
            second_attack,
            first_examine,
            second_examine,
            cancel,
        })

        lu.assertIs(menu.entries[1], first_attack)
        lu.assertIs(menu.entries[2], second_attack)
        lu.assertIs(menu.entries[3], first_examine)
        lu.assertEquals(menu.entries[4].monster.entity_uid, 11)
        lu.assertIs(menu.entries[5], second_examine)
        lu.assertEquals(menu.entries[6].monster.entity_uid, 12)
        lu.assertIs(menu.entries[7], cancel)
    end

    return suite
end
