-- adds "View drops" to the right click menu of anything attackable
-- familiars are skipped, and stacked npcs of the same type each get their own entry
-- (told apart by entity uid). selection hands back a plain snapshot, not the live npc

local npc_menu = {}
local SUBSCRIPTION_ID = "monster_lookup_npc_menu"
local VIEW_DROPS = "View drops"
local active_session

---@class MonsterSelection
---@field npc_id integer
---@field entity_uid integer
---@field name string
---@field combat_level integer
---@field parent_npc_id integer?

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
    local candidates = {}

    for _, entry in ipairs(entries) do
        local npc = get_valid_npc(entry)

        if npc then
            local candidate = seen[npc.uid]

            if not candidate then
                candidate = create_candidate(npc)

                if candidate then
                    seen[npc.uid] = candidate
                    candidates[#candidates + 1] = candidate
                end
            end

            if candidate then
                capture_attack_subject(candidate, entry)
            end
        end
    end

    return candidates
end

local function find_examine_index(entries, entity_uid)
    for index, entry in ipairs(entries) do
        if entry.actionVerbType == MiniMenuActionVerbType.EXAMINE then
            local npc = get_valid_npc(entry)

            if npc and npc.uid == entity_uid then
                return index
            end
        end
    end

    return nil
end

-- moves our new entry so it sits right under the npcs Examine option
local function position_lookup_entry(menu, examine_index)
    if not examine_index then
        return
    end

    local target = menu.entryCount - examine_index

    for position = 1, target - 1 do
        menu:Swap(position, position + 1)
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
    local examine_index = find_examine_index(menu.entries, candidate.monster.entity_uid)
    local subject = candidate.subject or candidate.monster.name
    menu:Add(label .. subject, on_select, candidate.monster)
    position_lookup_entry(menu, examine_index)
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
        -- read every time the menu opens so a settings change shows up straight away
        local label = view_drops_label(get_colour and get_colour())

        for _, candidate in ipairs(collect_candidates(menu.entries)) do
            add_lookup_entry(menu, candidate, label, on_select)
        end
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
