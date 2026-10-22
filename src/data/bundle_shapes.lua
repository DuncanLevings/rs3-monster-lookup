-- bundled pages store their tables as plain lists in a fixed field order instead of
-- name=value pairs, which is what keeps the bundle small (field names would otherwise repeat
-- on every drop row and stat block). these lists say what each position means.
-- tools/bundle_pack.lua packs against the same lists, and the build fails if it meets a field
-- thats not listed here, so nothing gets lost quietly
--
-- changing an order means rebuilding the bundle and bumping FORMAT in tools/build_bundle.lua

local shapes = {}

shapes.PAGE = { "title", "variants", "sections", "locations", "no_drops", "no_locations" }
shapes.SECTION = {
    "title",
    "description",
    "afterword",
    "drops",
    "notes",
    "note_ids",
    "drop_mode",
    "drop_switch",
    "drop_threshold",
}
-- the last four are the numbers for the kill value, see src/data/drops/odds.lua. theyre at the
-- end so rows that dont need them (Always, a plain quantity, one roll) store nothing extra
shapes.DROP = {
    "name",
    "quantity",
    "rate",
    "price",
    "notes",
    "note_marker",
    "item_id",
    "chance",
    "rolls",
    "quantity_low",
    "quantity_high",
}
shapes.LOCATION = { "name", "levels", "requirements", "spawns", "page", "map", "map_issue" }
shapes.MAP = { "id", "plane", "x", "z" }

-- the infobox fields the Monster info tab reads
shapes.INFO = {
    "version_anchor",
    "combat_level",
    "life_points",
    "armour",
    "defence_level",
    "attack_level",
    "ranged_level",
    "magic_level",
    "necromancy_level",
    "attack_rate",
    "attack_style_text",
    "combat_experience",
    "is_aggressive",
    "is_members_only",
    "is_poisonous",
    "location_restriction",
    "melee_max_hit",
    "ranged_max_hit",
    "magic_max_hit",
    "necromancy_max_hit",
    "special_max_hit",
    "melee_accuracy",
    "ranged_accuracy",
    "magic_accuracy",
    "necromancy_accuracy",
    "melee_affinity",
    "ranged_affinity",
    "magic_affinity",
    "necromancy_affinity",
    "weakness_affinity",
    "weakness",
    "weakness_text",
    "susceptible_to",
    "susceptible_to_poison",
    "susceptible_to_deflect",
    "susceptible_to_stun",
    "susceptible_to_drain",
    "slayer_category",
    "slayer_level",
    "slayer_experience",
    "assigned_by",
}

-- list -> table using a field order. nil slots stay nil
local function unpack_fields(list, fields)
    local result = {}

    for index, field in ipairs(fields) do
        result[field] = list[index]
    end

    return result
end

-- the first variant is stored in full, the others as only what differs from it (most
-- versions of a monster only differ a little): a position followed by its new value, or a
-- negative position on its own for a field this version doesnt have. no gaps, so # works
local function unpack_variants(list)
    local variants = {}
    local base = list[1] and unpack_fields(list[1], shapes.INFO)

    if not base then
        return variants
    end

    variants[1] = base

    for index = 2, #list do
        local variant = {}

        for key, value in pairs(base) do
            variant[key] = value
        end

        local changes = list[index]
        local cursor = 1

        while cursor <= #changes do
            local position = changes[cursor]

            if position < 0 then
                variant[shapes.INFO[-position]] = nil
                cursor = cursor + 1
            else
                variant[shapes.INFO[position]] = changes[cursor + 1]
                cursor = cursor + 2
            end
        end

        variants[index] = variant
    end

    return variants
end

-- a drop rows notes are its marked footnotes ("1,3") from the section, joined by blank lines.
-- the bundle leaves them out when they match this, which is nearly always
function shapes.notes_for(note_marker, section_notes)
    local texts = {}

    for number in (note_marker or ""):gmatch("%d+") do
        texts[#texts + 1] = section_notes[tonumber(number)]
    end

    return table.concat(texts, "\n\n")
end

local function unpack_section(list)
    local section = unpack_fields(list, shapes.SECTION)
    local drops = {}

    for index, drop in ipairs(section.drops or {}) do
        drop = unpack_fields(drop, shapes.DROP)

        if drop.notes == nil then
            drop.notes = shapes.notes_for(drop.note_marker, section.notes or {})
        end

        drops[index] = drop
    end

    section.drops = drops
    section.notes = section.notes or {}
    section.note_ids = section.note_ids or {}
    return section
end

local function unpack_location(list)
    local location = unpack_fields(list, shapes.LOCATION)

    if location.map then
        location.map = unpack_fields(location.map, shapes.MAP)
    end

    return location
end

---turns a decoded bundle page back into the MonsterResult shape a live lookup returns
---@param list table decoded page from bundle_codec
---@return MonsterResult
function shapes.unpack_page(list)
    local page = unpack_fields(list, shapes.PAGE)
    page.variants = unpack_variants(page.variants or {})
    page.info = page.variants[1] or {}

    local sections = {}

    for index, section in ipairs(page.sections or {}) do
        sections[index] = unpack_section(section)
    end

    page.sections = sections

    if page.locations then
        local locations = {}

        for index, location in ipairs(page.locations) do
            locations[index] = unpack_location(location)
        end

        page.locations = locations
    end

    return page
end

return shapes
