-- the key a monster is saved and looked up under. a search result is a wiki page
-- ("page:Goblin"), a clicked npc is its id and name ("3264:Goblin"). theyre kept apart
-- because one wiki page can cover lots of npc ids
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

-- the base name variants of a monster share, "Goblin (level 5)#Armed" -> "goblin". the
-- whole base name has to match, never part of it ("gob" mustnt clear every goblin)
function identity.family(name)
    name = (name or ""):gsub("_", " "):gsub("#.*$", "")
    name = name:gsub("%s+", " "):match("^%s*(.-)%s*$")

    while name:match("%b()$") do
        name = name:gsub("%s*%b()$", ""):match("^%s*(.-)%s*$")
    end

    return name:lower()
end

return identity
