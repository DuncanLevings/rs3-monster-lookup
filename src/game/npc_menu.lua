-- adds "View drops" to the right click menu of anything attackable
-- familiars are skipped. identical stacked monsters share the first one's entry;
-- distinct configurations and levels stay separate. selections are plain snapshots.

local npc_menu = {}
local SUBSCRIPTION_ID = "monster_lookup_npc_menu"
local VIEW_DROPS = "View drops"
local active_session

local function get_valid_npc(entry)
    local npc = entry.npcData and entry.npcData.entity

    if npc and npc.isValid then
        return npc
    end

    return nil
end

local function create_candidate(npc)
    local npc_config = npc.config

    if not npc_config or npc_config.attackOpIndex < 1 or npc_config.isFamiliar then
        return nil
    end

    return {
        monster = {
            npc_id = npc.configID,
            entity_uid = npc.uid,
            name = npc_config.name,
            combat_level = npc_config.visibleCombatLevel,
            parent_npc_id = npc.isMultiNPC and npc.parentConfigID or nil,
        },
    }
end

local function capture_attack_subject(candidate, entry)
    if entry.actionVerbType == MiniMenuActionVerbType.ATTACK then
        if entry.subjectText and entry.subjectText ~= "" then
            candidate.subject = entry.subjectText
        end
    end
end

local function collect_candidates(entries)
    local seen = {}
    local groups = {}
    local candidates = {}

    for index, entry in ipairs(entries) do
        local npc = get_valid_npc(entry)

        if npc then
            local candidate = seen[npc.uid]

            if candidate == nil then
                candidate = create_candidate(npc)
                if candidate then
                    local monster = candidate.monster
                    local key = table.concat({
                        tostring(monster.npc_id),
                        tostring(monster.combat_level),
                        tostring(monster.parent_npc_id),
                        monster.name,
                    }, "\0")
                    if groups[key] then
                        candidate = nil
                    else
                        groups[key] = candidate
                        candidates[#candidates + 1] = candidate
                    end
                end

                -- remember npcs that were skipped too, so their other menu rows dont read
                -- the npc config again
                seen[npc.uid] = candidate or false
            end

            if candidate then
                capture_attack_subject(candidate, entry)
                if entry.actionVerbType == MiniMenuActionVerbType.EXAMINE then
                    candidate.examine_index = candidate.examine_index or index
                end
            end
        end
    end

    return candidates
end

-- puts each View drops row right after its monster's rows, keeping every other row in
-- the order it was. works out the final order first, then gets there with swaps instead of
-- moving rows one place at a time
local function position_lookup_entries(menu, original_count, candidates)
    local after, fallback = {}, {}
    local count = original_count + #candidates

    for index, candidate in ipairs(candidates) do
        local added_index = original_count + index
        if candidate.examine_index then
            after[candidate.examine_index] = added_index
        else
            fallback[#fallback + 1] = added_index
        end
    end

    if next(after) == nil then
        return
    end

    local wanted = {}

    for index = 1, original_count do
        wanted[#wanted + 1] = index
        if after[index] then
            wanted[#wanted + 1] = after[index]
        end
    end

    for _, index in ipairs(fallback) do
        wanted[#wanted + 1] = index
    end

    local current, positions = {}, {}

    for index = 1, count do
        current[index], positions[index] = index, index
    end

    for destination, item in ipairs(wanted) do
        local source = positions[item]
        if source ~= destination then
            -- on the beta client Swap counts rows from the bottom
            menu:Swap(count - destination + 1, count - source + 1)
            local displaced = current[destination]
            current[destination], current[source] = item, displaced
            positions[item], positions[displaced] = destination, source
        end
    end
end

-- the subject keeps the npcs own name and level colours from its Attack entry
local function view_drops_label(colour_hex)
    if colour_hex then
        return "<col=" .. colour_hex .. ">" .. VIEW_DROPS .. "</col> "
    end

    return VIEW_DROPS .. " "
end

local function add_lookup_entry(menu, candidate, label, on_select)
    local subject = candidate.subject or candidate.monster.name
    menu:Add(label .. subject, on_select, candidate.monster)
end

local function create_selection_handler(session, on_select)
    return function(monster)
        -- ignore callbacks left in a menu from an earlier session
        if active_session == session then
            on_select(monster)
        end
    end
end

local function create_menu_handler(session, on_select, get_colour)
    return function(event)
        if active_session ~= session then
            return
        end

        local menu = event.miniMenu
        local entries = menu.entries
        local original_count = #entries
        local candidates = collect_candidates(entries)
        if #candidates == 0 then
            return
        end

        -- read every time the menu opens so a settings change shows up straight away
        local label = view_drops_label(get_colour and get_colour())

        for _, candidate in ipairs(candidates) do
            add_lookup_entry(menu, candidate, label, on_select)
        end
        position_lookup_entries(menu, original_count, candidates)
    end
end

---@param on_select fun(monster: MonsterSelection)
---@param get_colour (fun(): string?)? hex colour for "View drops", nil for the default text
function npc_menu.start(on_select, get_colour)
    if active_session then
        return
    end

    local session = {}
    active_session = session
    local select_monster = create_selection_handler(session, on_select)
    Event.MiniMenuReady.Subscribe(
        SUBSCRIPTION_ID,
        create_menu_handler(session, select_monster, get_colour)
    )
end

function npc_menu.stop()
    if not active_session then
        return
    end

    active_session = nil
    Event.MiniMenuReady.Unsubscribe(SUBSCRIPTION_ID)
end

return npc_menu
