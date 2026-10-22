-- builds the bundled monster data from what tools/fetch_wiki_data.py saved in work/wiki/
--
-- uses the page parsers in tools/ (wiki_page, monster_locations, location_spawns) that the
-- plugin used to run on every lookup, plus wiki_response for the stats. every page is decoded
-- again with src/data/bundle/codec.lua and compared, so a format bug fails the build instead
-- of showing up in game
--
-- usage, from the plugin folder, with any lua 5.4+:
--   lua tools/bundle/build.lua [--install] [--budget 1750000]
-- writes to work/bundle/ unless --install is given, then to src/data/bundle/generated/

local ROOT = (arg and arg[0] or ""):match("^(.*)[/\\]tools[/\\]bundle[/\\][^/\\]+$") or "."
package.path = ROOT .. "/?.lua;" .. package.path

local json = require("src/vendor/json")
local parser = require("tools/wiki/page")
local monster_locations = require("tools/wiki/monster_locations")
local wiki_response = require("src/data/wiki/response")
local codec = require("src/data/bundle/codec")
local shapes = require("src/data/bundle/shapes")
local encoder_module = require("tools/bundle/encoder")
local bundle_pack = require("tools/bundle/pack")
local search_index = require("tools/bundle/search_index")
local deep_equal = bundle_pack.deep_equal
local kill_value = require("src/data/drops/value")

local FORMAT_VERSION = 4
local SHARD_TARGET = 64 * 1024
-- the drop and stat search indexes took it from about 1.4 MB to 1.7 MB, the numbers for the
-- kill value (chance, rolls, quantity bounds per drop) to 1.8 MB. zipped its about 600 KB.
-- format 4 took it back to about 1.5 MB by working those out on load (shapes.DERIVED)
local install, budget = false, 1850000

for index = 1, #(arg or {}) do
    if arg[index] == "--install" then
        install = true
    elseif arg[index] == "--budget" then
        budget = assert(tonumber(arg[index + 1]), "--budget needs a number of bytes")
    end
end

-- infobox fields the Monster info tab reads, everything else is left out of the bundle
local INFO_FIELDS = {}
for _, field in ipairs({
    "armour",
    "assigned_by",
    "attack_level",
    "attack_rate",
    "attack_style_text",
    "combat_experience",
    "combat_level",
    "defence_level",
    "is_aggressive",
    "is_members_only",
    "is_poisonous",
    "life_points",
    "location_restriction",
    "magic_affinity",
    "magic_level",
    "melee_affinity",
    "necromancy_affinity",
    "necromancy_level",
    "ranged_affinity",
    "ranged_level",
    "slayer_category",
    "slayer_experience",
    "slayer_level",
    "special_max_hit",
    "susceptible_to",
    "version_anchor",
    "weakness",
    "weakness_affinity",
    "weakness_text",
}) do
    INFO_FIELDS[field] = true
end
for _, style in ipairs({ "melee", "ranged", "magic", "necromancy" }) do
    INFO_FIELDS[style .. "_max_hit"] = true
    INFO_FIELDS[style .. "_accuracy"] = true
end
for _, immunity in ipairs({ "poison", "deflect", "stun", "drain" }) do
    INFO_FIELDS["susceptible_to_" .. immunity] = true
end

-- location_restriction values (as the infobox json spells them) for repeatable versions
local REPEATABLE = { [""] = true, no = true, none = true, surface = true, minigame = true }
-- pages where no version matched REPEATABLE, kept whole and listed for a manual check
local dropped_all = {}

local function read(path)
    local file = assert(io.open(path, "rb"), "missing " .. path)
    local text = file:read("a")
    file:close()
    return text
end

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
    return #text
end

-- same file names as fetch_wiki_data.py's slug()
local function slug(title)
    local value = 0
    for index = 1, #title do
        value = (value * 131 + title:byte(index)) % 1000000007
    end
    local name = title:gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    return name:sub(1, 80) .. "-" .. value
end

local function trim_info(info)
    local trimmed = {}
    for key, value in pairs(info) do
        if INFO_FIELDS[key] then
            trimmed[key] = value
        end
    end
    return trimmed
end

-- where two tables first differ, eg "sections.3.drops.2.chance (0.13 vs 0.130)"
local function first_difference(a, b, path)
    path = path or ""
    if type(a) ~= "table" or type(b) ~= "table" then
        return a ~= b and path .. " (" .. tostring(a) .. " vs " .. tostring(b) .. ")" or nil
    end
    local keys = {}
    for key in pairs(a) do
        keys[key] = true
    end
    for key in pairs(b) do
        keys[key] = true
    end
    for key in pairs(keys) do
        local found = first_difference(a[key], b[key], path .. "." .. tostring(key))
        if found then
            return found
        end
    end
    return nil
end

local started = os.clock()
local selection = json.decode(read(ROOT .. "/work/wiki/selection.json"))
local item_ids = json.decode(read(ROOT .. "/work/wiki/item_ids.json"))
local npc_ids = json.decode(read(ROOT .. "/work/wiki/npc_ids.json"))

local pages, failures, missing_ids, drop_count = {}, {}, {}, 0
local naive_bytes, trimmed_bytes = 0, 0

for number, title in ipairs(selection.kept) do
    local ok, problem = pcall(function()
        local saved = json.decode(read(ROOT .. "/work/wiki/pages/" .. slug(title) .. ".json"))
        local sections = assert(parser.parse(saved.html), "drop tables could not be parsed")
        local locations, no_locations = monster_locations.parse(saved.html)
        require("tools/wiki/location_spawns").attach(locations, saved.wikitext)
        local variants, full_variants = {}, {}

        for _, row in ipairs(saved.infobox) do
            local info = assert(wiki_response.monster_info(row))
            full_variants[#full_variants + 1] = info
            -- only versions you can meet again and again. quest, dungeoneering, event, familiar
            -- and removed versions (eg Greater demon pyromancer's old Wilderness one) are left
            -- out. fetch_wiki_data.py already skipped monsters with no repeatable version
            if REPEATABLE[tostring(info.location_restriction or ""):lower()] then
                variants[#variants + 1] = trim_info(info)
            end
        end

        if #variants == 0 then
            dropped_all[#dropped_all + 1] = title
            for _, info in ipairs(full_variants) do
                variants[#variants + 1] = trim_info(info)
            end
        end

        for _, section in ipairs(sections) do
            for _, drop in ipairs(section.drops) do
                drop_count = drop_count + 1
                drop.item_id = item_ids[drop.wiki_name]
                if not drop.item_id then
                    missing_ids[drop.wiki_name] = true
                end
            end
        end

        local result = {
            title = title,
            variants = full_variants,
            sections = sections,
            locations = locations,
            no_locations = no_locations,
            no_drops = #sections == 0
                    and (parser.has_drop_markup(saved.html) and "unreadable" or "none")
                or nil,
        }
        naive_bytes = naive_bytes + #json.encode(result)

        -- the bundle copy: trimmed stats, no parser bookkeeping the ui never reads
        result.variants = variants
        for _, section in ipairs(sections) do
            for _, drop in ipairs(section.drops) do
                drop.wiki_name = nil
            end
            -- the wikis "average kill is worth" sentences are hidden by the drop table anyway
            -- (the kill value replaces them), no point shipping them
            section.description = kill_value.without_wiki_averages(section.description)
            section.afterword = kill_value.without_wiki_averages(section.afterword)
        end
        trimmed_bytes = trimmed_bytes + #json.encode(result)
        pages[#pages + 1] = result
    end)

    if not ok then
        failures[#failures + 1] = title .. ": " .. tostring(problem)
    end

    if number % 100 == 0 then
        io.write(string.format("  parsed %d/%d\n", number, #selection.kept))
        io.flush()
    end
end

-- pack: fixed-order lists first (src/data/bundle/shapes.lua), then strings and shared tables
-- one item id and unit price per item name, so drop rows dont each repeat them
local items = bundle_pack.items(pages)
local shaped = {}
for index, page in ipairs(pages) do
    shaped[index] = bundle_pack.page(page, items)
end

local encoder = encoder_module.new()
for _, page in ipairs(shaped) do
    encoder:collect(page)
end
encoder:finish()
local items_text = bundle_pack.items_text(items, encoder.string_index)
-- read back the same way the plugin does, for the round trip below
local read_items = shapes.read_items(items_text, encoder.strings)

local packed = {}
for index, page in ipairs(shaped) do
    packed[index] = encoder:emit(page)
end

-- round trip every page the way the plugin will read it, and time the slowest unpack
-- (it runs inside the client's per-call time limit)
local slowest, slowest_title = 0, nil
for index, page in ipairs(pages) do
    local start = os.clock()
    local unpacked =
        shapes.unpack_page(codec.decode(packed[index], encoder.strings, encoder.shared), read_items)
    local took = os.clock() - start
    if took > slowest then
        slowest, slowest_title = took, page.title
    end
    page.info = page.variants[1] or {}
    assert(
        deep_equal(unpacked, page),
        "round trip changed " .. page.title .. " at " .. tostring(first_difference(unpacked, page))
    )
    page.info = nil
end

-- index: page titles, npc id -> page number, and npc ids known to have no drops
local page_number, ambiguous = {}, 0
local npc_pairs, seen_npc = {}, {}
for index, page in ipairs(pages) do
    page_number[page.title] = index
end
for title, ids in pairs(npc_ids) do
    local index = page_number[title]
    if index then
        for _, npc in ipairs(ids) do
            if seen_npc[npc] and seen_npc[npc] ~= index then
                ambiguous = ambiguous + 1
                seen_npc[npc] = 0 -- several pages, the plugin asks the player to pick
            else
                seen_npc[npc] = index
            end
        end
    end
end
for npc, index in pairs(seen_npc) do
    npc_pairs[#npc_pairs + 1] = { npc, index }
end
table.sort(npc_pairs, function(a, b)
    return a[1] < b[1]
end)

local base36 = encoder_module.base36
local npc_text, previous = {}, 0
for _, pair in ipairs(npc_pairs) do
    -- ids are sorted so store the gap to the previous one, much shorter than the id
    npc_text[#npc_text + 1] = base36(pair[1] - previous) .. ":" .. base36(pair[2])
    previous = pair[1]
end

-- npc ids the plugin knows about but doesnt bundle, sorted and stored as gaps like npcs.
-- an id that also belongs to a bundled page stays with the bundled page
local function packed_ids(groups)
    local ids = {}
    for _, group in pairs(groups or {}) do
        for _, npc in ipairs(group) do
            if not seen_npc[npc] then
                ids[#ids + 1] = npc
            end
        end
    end
    table.sort(ids)
    local text, last, count = {}, 0, 0
    for _, npc in ipairs(ids) do
        if npc ~= last then
            text[#text + 1] = base36(npc - last)
            count = count + 1
        end
        last = npc
    end
    return table.concat(text, ","), count
end

local no_drop_text, no_drop_count = packed_ids(selection.no_drops)
local not_covered_text, not_covered_count = packed_ids(selection.not_covered)

-- shards: consecutive pages until about SHARD_TARGET bytes
local shards, shard_of = { {} }, {}
local shard_size = 0
for index, text in ipairs(packed) do
    if shard_size > 0 and shard_size + #text > SHARD_TARGET then
        shards[#shards + 1] = {}
        shard_size = 0
    end
    local shard = shards[#shards]
    shard[#shard + 1] = index
    shard_of[index] = #shards
    shard_size = shard_size + #text + 4
end

local output = install and (ROOT .. "/src/data/bundle/generated") or (ROOT .. "/work/bundle")
os.execute(
    (package.config:sub(1, 1) == "\\" and 'mkdir "' or 'mkdir -p "')
        .. output:gsub("/", package.config:sub(1, 1))
        .. '" 2>nul'
)

local header = "-- Generated by tools/bundle/build.lua from the RuneScape Wiki, "
    .. os.date("!%Y-%m-%d")
    .. ".\n"
    .. "-- RuneScape Wiki contributors, CC BY-NC-SA 3.0; see THIRD_PARTY_NOTICES.txt.\n"

local sizes = {}
local function lua_list(values, quote)
    local lines = {}
    for _, value in ipairs(values) do
        lines[#lines + 1] = (quote and string.format("%q", value) or '"' .. value .. '"') .. ","
    end
    return "return {\n" .. table.concat(lines, "\n") .. "\n}\n"
end

sizes.strings = write(output .. "/strings.lua", header .. lua_list(encoder.strings, true))
sizes.shared = write(output .. "/shared.lua", header .. lua_list(encoder.shared, false))
-- a table like every other bundle file, the clients require didnt hand back a plain string
sizes.items =
    write(output .. "/items.lua", header .. 'return {\nitems = "' .. items_text .. '",\n}\n')

-- clear shards from an earlier, bigger build, a stale one would be read with the wrong strings
local stale = 1
while os.remove(string.format("%s/shard_%02d.lua", output, stale)) do
    stale = stale + 1
end

sizes.shards = 0
for number, members in ipairs(shards) do
    local lines = { header, "return {" }
    for _, index in ipairs(members) do
        lines[#lines + 1] = "[" .. index .. ']="' .. packed[index] .. '",'
    end
    lines[#lines + 1] = "}\n"
    sizes.shards = sizes.shards
        + write(string.format("%s/shard_%02d.lua", output, number), table.concat(lines, "\n"))
end

local titles, shard_list = {}, {}
for index, page in ipairs(pages) do
    titles[index] = page.title
    shard_list[index] = base36(shard_of[index])
end
sizes.index = write(
    output .. "/index.lua",
    header
        .. "return {\n"
        .. "format = "
        .. FORMAT_VERSION
        .. ",\n"
        .. 'built = "'
        .. os.date("!%Y-%m-%d")
        .. '",\n'
        .. "titles = "
        .. lua_list(titles, true):gsub("^return ", ""):gsub("\n$", "")
        .. ",\n"
        .. 'shards = "'
        .. table.concat(shard_list, ",")
        .. '",\n'
        .. 'npcs = "'
        .. table.concat(npc_text, ",")
        .. '",\n'
        .. 'no_drops = "'
        .. no_drop_text
        .. '",\n'
        .. 'not_covered = "'
        .. not_covered_text
        .. '",\n'
        .. "}\n"
)

-- the drop search and top stats indexes, see tools/bundle/search_index.lua
local drops_source, drop_counts = search_index.drops(pages, header, encoder.string_index)
-- bosses, their minions, elite dungeon and sanctum fights, and elite slayer spawns that turn
-- up at random. none of them are something you can just go and farm, so top stats hides them
-- by default
local BOSS_CATEGORIES = {}
for _, category in ipairs({
    "Bosses",
    "Boss minions",
    "Elite spawns",
    "Temple of Aminishi",
    "Dragonkin Laboratory",
    "The Shadow Reef",
    "The Zamorakian Undercity",
    "Sanctum of Rebirth",
}) do
    BOSS_CATEGORIES["Category:" .. category] = true
end
local bosses = {}
for title, categories in pairs(json.decode(read(ROOT .. "/work/wiki/page_categories.json"))) do
    for _, category in ipairs(categories) do
        if BOSS_CATEGORIES[category] then
            bosses[title] = true
        end
    end
end
local stats_source, stat_rows = search_index.stats(pages, header, encoder.string_index, bosses)
sizes.drops = write(output .. "/drops.lua", drops_source)
sizes.stats = write(output .. "/stats.lua", stats_source)

local total = sizes.strings
    + sizes.shared
    + sizes.items
    + sizes.shards
    + sizes.index
    + sizes.drops
    + sizes.stats
local missing = 0
for _ in pairs(missing_ids) do
    missing = missing + 1
end

local function kb(bytes)
    return string.format("%7.1f KB", bytes / 1024)
end

print(string.format("\n%d pages bundled, %d failed, %d drop rows", #pages, #failures, drop_count))
print(
    string.format(
        "%d no-drop and %d not-covered NPC ids, %d NPC ids on several pages, "
            .. "%d dropped items without an id",
        no_drop_count,
        not_covered_count,
        ambiguous,
        missing
    )
)
for _, title in ipairs(dropped_all) do
    print("  check: no repeatable version found for " .. title .. ", kept every version")
end
print(
    string.format(
        "%d strings, %d shared tables, %d shards",
        #encoder.strings,
        #encoder.shared,
        #shards
    )
)
print("\nsize at each step")
print("  parsed results as json   " .. kb(naive_bytes))
print("  trimmed stats/fields     " .. kb(trimmed_bytes))
print("  packed bundle total      " .. kb(total))
print("    strings.lua            " .. kb(sizes.strings))
print("    shared.lua             " .. kb(sizes.shared))
print("    items.lua              " .. kb(sizes.items))
print("    shards                 " .. kb(sizes.shards))
print("    index.lua              " .. kb(sizes.index))
print(
    "    drops.lua              "
        .. kb(sizes.drops)
        .. string.format("  (%d items, %d dropper rows)", drop_counts.items, drop_counts.rows)
)
print(
    "    stats.lua              " .. kb(sizes.stats) .. string.format("  (%d variants)", stat_rows)
)
-- what takes the space inside pages (shared tables count as their reference only)
local parts = {}
local function add_part(name, value)
    if value ~= nil then
        parts[name] = (parts[name] or 0) + #encoder:emit(value)
    end
end
local SECTIONS = 3 -- position of sections in shapes.PAGE
for _, page in ipairs(shaped) do
    for position, field in ipairs(shapes.PAGE) do
        add_part(field, page[position])
    end
    for _, section in ipairs(page[SECTIONS] or {}) do
        for position, field in ipairs(shapes.SECTION) do
            add_part("sections." .. field, section[position])
        end
    end
end
local part_names = {}
for key in pairs(parts) do
    part_names[#part_names + 1] = key
end
table.sort(part_names, function(a, b)
    return parts[a] > parts[b]
end)
print("\nshard bytes by field")
for _, key in ipairs(part_names) do
    print(string.format("  %-24s %s", key, kb(parts[key])))
end

-- biggest strings, the dictionary is loaded whole on the first lookup
local string_bytes = {}
for _, text in ipairs(encoder.strings) do
    string_bytes[#string_bytes + 1] = text
end
table.sort(string_bytes, function(a, b)
    return #a > #b
end)
local long_total = 0
for _, text in ipairs(string_bytes) do
    if #text > 200 then
        long_total = long_total + #text
    end
end
print(
    string.format(
        "\nstrings over 200 chars: %s; longest %d chars",
        kb(long_total),
        #(string_bytes[1] or "")
    )
)

print(
    string.format(
        "\nslowest page unpack %.1f ms (%s), build took %.0f s",
        slowest * 1000,
        tostring(slowest_title),
        os.clock() - started
    )
)
print("written to " .. output)

for _, failure in ipairs(failures) do
    print("  failed: " .. failure)
end

if total > budget then
    print(string.format("\nover budget: %d bytes > %d", total, budget))
    os.exit(1)
end
