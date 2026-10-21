-- Keep page searches separate from clicked NPCs: one Wiki page can cover many NPC IDs.
local identity = {}

function identity.key(monster)
    if monster.wiki_title then
        return "page:" .. monster.wiki_title
    end

    return tostring(monster.npc_id) .. ":" .. monster.name
end

function identity.selection(key)
    local title = key:match("^page:(.+)$")

    if title then
        return { name = title, wiki_title = title }
    end

    local npc_id, name = key:match("^(%d+):(.+)$")

    if npc_id then
        return { npc_id = tonumber(npc_id), name = name }
    end
end

return identity
