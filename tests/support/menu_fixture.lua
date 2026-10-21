local fixture = {}

function fixture.npc(options)
    options = options or {}
    return {
        isValid = options.valid ~= false,
        uid = options.uid or 10,
        configID = options.npc_id or 100,
        isMultiNPC = options.parent_npc_id ~= nil,
        parentConfigID = options.parent_npc_id,
        config = {
            name = options.name or "Goblin",
            attackOpIndex = options.attack_index or 1,
            visibleCombatLevel = options.combat_level or 2,
            isFamiliar = options.familiar or false,
        },
    }
end

function fixture.entry(npc, subject, verb)
    return {
        npcData = { entity = npc },
        subjectText = subject or npc.config.name,
        actionVerbType = verb or 0,
    }
end

function fixture.new(root)
    local context = {
        subscriptions = {},
        subscribe_count = 0,
        unsubscribe_count = 0,
        selections = {},
    }
    local environment = setmetatable({
        MiniMenuActionVerbType = { ATTACK = 0, EXAMINE = 1 },
        Event = {
            MiniMenuReady = {
                Subscribe = function(id, callback)
                    context.subscribe_count = context.subscribe_count + 1
                    context.subscriptions[id] = callback
                end,
                Unsubscribe = function(id)
                    context.unsubscribe_count = context.unsubscribe_count + 1
                    context.subscriptions[id] = nil
                end,
            },
        },
    }, { __index = _G })

    context.subject = assert(loadfile(root .. "/src/game/npc_menu.lua", "t", environment))()

    -- set context.colour to a hex string to colour the View drops text
    function context:start()
        self.subject.start(function(monster)
            self.selections[#self.selections + 1] = monster
        end, function()
            return self.colour
        end)
    end

    function context:open_menu(entries)
        local menu = { entries = entries, entryCount = #entries, added = {}, swaps = 0 }

        function menu:Add(label, callback, monster)
            local item = { label = label, callback = callback, monster = monster }
            self.added[#self.added + 1] = item
            self.entries[#self.entries + 1] = item
            self.entryCount = #self.entries
        end

        -- copies what the beta client did: Swap positions count from the bottom of entries
        -- if the client starts following the docs instead this and npc_menu both need changing
        function menu:Swap(a, b)
            self.swaps = self.swaps + 1
            local first = self.entryCount - a + 1
            local second = self.entryCount - b + 1
            self.entries[first], self.entries[second] = self.entries[second], self.entries[first]
        end

        for _, callback in pairs(self.subscriptions) do
            callback({ miniMenu = menu })
        end

        return menu
    end

    return context
end

return fixture
