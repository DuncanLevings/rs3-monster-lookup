-- monster data that ships with the plugin (src/data/bundle/, built by tools/build_bundle.lua)
--
-- most lookups never touch the Wiki: the index says which page an NPC ID belongs to, and
-- only that page's shard is loaded and unpacked. NPC IDs the build knew about but left out
-- (no drops, or not a monster you can meet repeatedly) are answered from the index too.
-- anything the index doesnt know is new content, so the caller falls back to a live lookup
--
-- if the bundle is missing or from a different format, every find returns nil and the
-- plugin works exactly as it did before the bundle existed

local codec = require("src/data/bundle_codec")
local shapes = require("src/data/bundle_shapes")

local bundle = {}
-- must match FORMAT_VERSION in tools/build_bundle.lua
local FORMAT = 3

local index
local strings, shared
local unavailable = false

local function report(problem)
    if not unavailable then
        unavailable = true
        log("Monster Lookup: bundled data unavailable, using the Wiki instead. " .. problem)
    end
end

-- gap-encoded sorted ids ("2a,5,1b" -> 90, 95, 142), see packed_ids in the build
local function each_id(text, callback)
    local id = 0

    for gap, rest in (text or ""):gmatch("([%w%-]+)(:?[%w]*)") do
        id = id + tonumber(gap, 36)
        callback(id, rest ~= "" and tonumber(rest:sub(2), 36) or nil)
    end
end

local function load_index()
    if index or unavailable then
        return index
    end

    local ok, raw = pcall(require, "src/data/bundle/index")

    if not ok or type(raw) ~= "table" then
        report(tostring(raw))
        return nil
    end

    if raw.format ~= FORMAT then
        report("Expected format " .. FORMAT .. ", found " .. tostring(raw.format) .. ".")
        return nil
    end

    local loaded = {
        built = raw.built,
        titles = raw.titles,
        by_title = {},
        shards = {},
        npcs = {},
        page_npcs = {},
        no_drops = {},
        not_covered = {},
    }

    for page, title in ipairs(raw.titles) do
        loaded.by_title[title] = page
    end

    for shard in (raw.shards or ""):gmatch("[^,]+") do
        loaded.shards[#loaded.shards + 1] = tonumber(shard, 36)
    end

    -- page 0 means the id is on several pages, the live lookup asks the player to pick
    each_id(raw.npcs, function(id, page)
        loaded.npcs[id] = page
        if page and page > 0 then
            local ids = loaded.page_npcs[page] or {}
            ids[#ids + 1] = id
            loaded.page_npcs[page] = ids
        end
    end)
    each_id(raw.no_drops, function(id)
        loaded.no_drops[id] = true
    end)
    each_id(raw.not_covered, function(id)
        loaded.not_covered[id] = true
    end)

    index = loaded
    return index
end

---@class BundleMatch
---@field kind "bundled"|"no_drops"|"not_covered"
---@field page integer? page number, only for "bundled"

---where the bundle stands on a clicked or searched monster, nil when it doesnt know it
---@param monster MonsterSelection
---@return BundleMatch?
function bundle.find(monster)
    local loaded = load_index()

    if not loaded then
        return nil
    end

    if monster.wiki_title then
        local page = loaded.by_title[monster.wiki_title]
        return page and { kind = "bundled", page = page } or nil
    end

    local id = monster.npc_id
    local page = id and loaded.npcs[id]

    if page and page > 0 then
        return { kind = "bundled", page = page }
    elseif page == 0 then
        return nil
    elseif id and loaded.no_drops[id] then
        return { kind = "no_drops" }
    elseif id and loaded.not_covered[id] then
        return { kind = "not_covered" }
    end

    -- same order as the live lookup: the NPC ID first, then the exact name
    page = monster.name and loaded.by_title[monster.name]
    return page and { kind = "bundled", page = page } or nil
end

---unpacks one bundled page
---@param page integer
---@return MonsterResult? result
---@return string? built date the bundle was built, for the status line
function bundle.load(page)
    local loaded = load_index()

    if not loaded or not loaded.shards[page] then
        return nil
    end

    local ok, result = pcall(function()
        -- loaded once on the first lookup, then kept by require
        strings = strings or require("src/data/bundle/strings")
        shared = shared or require("src/data/bundle/shared")
        local shard = require(string.format("src/data/bundle/shard_%02d", loaded.shards[page]))
        return shapes.unpack_page(codec.decode(assert(shard[page]), strings, shared))
    end)

    if not ok then
        log("Monster Lookup: bundled page " .. page .. " could not be read. " .. tostring(result))
        return nil
    end

    result.source = "bundle"
    return result, loaded.built
end

---stand-in result for monsters the bundle knows about but left out, so the window can say
---why without asking the Wiki. no stats or locations were bundled for these
---@param monster MonsterSelection
---@param kind string a BundleMatch kind other than "bundled"
---@return MonsterResult
function bundle.placeholder(monster, kind)
    return {
        title = monster.name,
        info = {},
        variants = {},
        sections = {},
        no_drops = kind == "not_covered" and "not_covered" or "none",
        locations = {},
        no_locations = "none",
        source = "bundle",
        placeholder = true,
    }
end

function bundle.titles()
    local loaded = load_index()
    return loaded and loaded.titles or {}
end

-- The IDs are already decoded for lookups; keep the reverse mapping too so an
-- info preview can resolve a page without scanning every NPC in the game.
function bundle.npc_ids(title)
    local loaded = load_index()
    if not loaded then
        return {}
    end

    local page = loaded.by_title[title]
    return page and loaded.page_npcs[page] or {}
end

return bundle
