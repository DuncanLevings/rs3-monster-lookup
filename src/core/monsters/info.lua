-- turns a monsters infobox values from the wiki into the table sections the Monster info
-- tab draws. no ui code in here, the view just gets titles, headers, rows and icon keys
-- anything missing from the wiki shows as Unknown rather than being left out

local codex = require("src/data/monsters/slayer_codex")
local format = require("src/utils/stat_format")

local monster_info = {}
local SUSCEPTIBILITIES = {
    inquisitor = "Inquisitor staff",
    hexhunter = "Hexhunter bow",
    terrasaur = "Terrasaur maul",
    ["hexhunter dungeoneering"] = "Hexhunter bow (Dungeoneering)",
    nopenopenope = "NopeNopeNope perk",
}
local STYLES = {
    { name = "Melee", prefix = "melee", level = "attack_level" },
    { name = "Ranged", prefix = "ranged", level = "ranged_level" },
    { name = "Magic", prefix = "magic", level = "magic_level" },
    { name = "Necromancy", prefix = "necromancy", level = "necromancy_level" },
}

local function attack_speed(value)
    if value == -1 then
        return "Random"
    elseif value == 0 then
        return "Not applicable"
    elseif type(value) == "number" and value > 0 then
        return format.number(value) .. " ticks (" .. format.number(value * 0.6) .. "s)"
    end

    return "Unknown"
end

local function weakness(value)
    local text = format.title(value)
    return (text:lower() == "nothing" or text:lower() == "none") and "None" or text
end

local function format_susceptibilities(values)
    if type(values) ~= "table" then
        return "Unknown"
    end

    local names = {}

    for _, value in ipairs(values) do
        names[#names + 1] = SUSCEPTIBILITIES[value] or format.title(value)
    end

    return #names > 0 and table.concat(names, "\n") or "None listed"
end

-- facts use alternating label/value columns. widths are fractions of the available
-- tab width; labels tells the renderer which cells need label styling
local function facts(title, rows)
    return {
        title = title,
        widths = { 0.20, 0.30, 0.20, 0.30 },
        labels = { true, false, true, false },
        rows = rows,
    }
end

local function combat_section(info)
    local section = facts("Combat info", {
        {
            "Life points",
            format.text(info.life_points),
            "Attack style",
            format.title(info.attack_style_text),
        },
        {
            "Attack speed",
            attack_speed(info.attack_rate),
            "Combat XP",
            format.text(info.combat_experience),
        },
        { "Poisonous", format.boolean(info.is_poisonous), "", "" },
    })
    if info.is_members_only ~= nil or info.location_restriction ~= nil then
        section.rows[#section.rows + 1] = {
            "Members only",
            format.boolean(info.is_members_only),
            info.location_restriction ~= nil and "Location" or "",
            info.location_restriction ~= nil and format.title(info.location_restriction) or "",
        }
    end

    section.detailed = true
    return section
end

local function offensive_section(info)
    local headers = { "Stat" }
    ---@type (string|boolean)[]
    local icons = { false }
    local max_hits, levels, accuracy = { "Max hit" }, { "Level" }, { "Accuracy" }

    for _, style in ipairs(STYLES) do
        headers[#headers + 1] = style.name
        icons[#icons + 1] = style.prefix
        max_hits[#max_hits + 1] = format.text(info[style.prefix .. "_max_hit"])
        levels[#levels + 1] = format.text(info[style.level])
        accuracy[#accuracy + 1] = format.text(info[style.prefix .. "_accuracy"])
    end

    if info.special_max_hit ~= nil then
        headers[#headers + 1] = "Special attack"
        icons[#icons + 1] = "special"
        max_hits[#max_hits + 1] = format.text(info.special_max_hit)
        levels[#levels + 1] = "-"
        accuracy[#accuracy + 1] = "-"
    end

    local widths = { 0.22 }

    for _ = 2, #headers do
        widths[#widths + 1] = 0.78 / (#headers - 1)
    end

    return {
        title = "Offensive stats",
        detailed = true,
        widths = widths,
        headers = headers,
        header_icons = icons,
        labels = { true },
        rows = { max_hits, levels, accuracy },
    }
end

local function weakness_icon(info)
    local text = type(info.weakness_text) == "table" and info.weakness_text[1] or info.weakness_text
    local keys = {
        air = "weak_air",
        water = "weak_water",
        earth = "weak_earth",
        fire = "weak_fire",
        crush = "weak_crush",
        slash = "weak_slash",
        stab = "weak_stab",
        nothing = "weak_none",
        none = "weak_none",
    }
    return type(text) == "string" and keys[text:lower()] or nil
end

local function overview_section(info)
    local section = facts("Overview", {
        {
            "Weakness",
            weakness(info.weakness_text),
            "Susceptible to",
            format_susceptibilities(info.susceptible_to),
        },
        {
            "Aggressive",
            format.boolean(info.is_aggressive),
            "",
            "",
        },
    })
    section.value_icons = { { [2] = weakness_icon(info) } }
    return section
end

local function defensive_section(info)
    return {
        title = "Defensive stats",
        detailed = true,
        widths = { 0.50, 0.50 },
        headers = { "Armour", "Defence level" },
        header_icons = { false, "defence" },
        rows = { { format.text(info.armour), format.text(info.defence_level) } },
    }
end

local function affinity_section(info)
    local headers = { "Weakness", "Melee", "Ranged", "Magic" }
    local icons = { weakness_icon(info) or false, "melee", "ranged", "magic" }
    local values = {
        format.text(info.weakness_affinity),
        format.text(info.melee_affinity),
        format.text(info.ranged_affinity),
        format.text(info.magic_affinity),
    }
    local widths = { 0.25, 0.25, 0.25, 0.25 }

    if info.necromancy_affinity ~= nil then
        headers[#headers + 1] = "Necromancy"
        icons[#icons + 1] = "necromancy"
        values[#values + 1] = format.text(info.necromancy_affinity)
        widths = { 0.20, 0.20, 0.20, 0.20, 0.20 }
    end

    return {
        title = "Base hit chance",
        detailed = true,
        widths = widths,
        headers = headers,
        header_icons = icons,
        rows = { values },
    }
end

-- the Wiki fields describe susceptibility, so true means Not immune in this section
local function immunity_section(info)
    local values = {}
    local tooltips = {}
    local fields = { "poison", "deflect", "stun", "drain" }
    local names = { "Poison", "Deflect", "Stun", "Stat drain" }

    for index, field in ipairs(fields) do
        values[index] = format.boolean(info["susceptible_to_" .. field], "Not immune", "Immune")
        tooltips[index] = names[index] .. ": " .. values[index]
    end

    local section = facts("Immunities", {
        { names[1], values[1], names[2], values[2] },
        { names[3], values[3], names[4], values[4] },
    })
    section.continuation = true
    section.value_icons = { { [2] = "poison", [4] = "deflect" }, { [2] = "stun", [4] = "drain" } }
    section.value_tooltips = {
        { [2] = tooltips[1], [4] = tooltips[2] },
        { [2] = tooltips[3], [4] = tooltips[4] },
    }
    return section
end

local function slayer_section(info)
    if
        info.slayer_level == nil
        and info.slayer_experience == nil
        and (type(info.slayer_category) ~= "table" or #info.slayer_category == 0)
    then
        return nil
    end

    return facts("Slayer", {
        {
            "Required level",
            format.text(info.slayer_level),
            "Slayer XP",
            format.text(info.slayer_experience),
        },
        {
            "Category",
            format.title(info.slayer_category),
            "Assigned by",
            format.text(info.assigned_by),
        },
    })
end

local function dungeon_section(title)
    local entry = codex.find(title or "")

    if not entry then
        return nil
    end

    local section = facts("Player-owned Slayer Dungeon", {
        { "Codex entry", tostring(entry.number), "Dungeon size", entry.size },
        { "Slayer level", entry.slayer_level, "Soul capture level", entry.altered_level },
        { "Soul XP (repeat)", entry.soul_xp, "Dungeon variants", entry.variants },
    })

    if entry.notes ~= "" then
        section.rows[#section.rows + 1] = { "Notes", entry.notes, "", "" }
    end

    section.note = "Soul capture level is the Wiki's altered Slayer level for capture chance and soul XP. "
        .. codex.source_note()
    return section
end

function monster_info.variants(result)
    local variants = {}

    for _, info in ipairs(type(result.variants) == "table" and result.variants or {}) do
        if type(info) == "table" then
            variants[#variants + 1] = info
        end
    end

    return #variants > 0 and variants or { type(result.info) == "table" and result.info or {} }
end

-- the wikis own name for a variant eg "Hard mode", nil if it doesnt give one
local function anchor_name(info)
    return info.version_anchor and format.text(info.version_anchor) or nil
end

function monster_info.variant_name(info, index)
    return anchor_name(info) or ("Variant " .. index)
end

function monster_info.build(info, title)
    if next(info) == nil then
        return { message = "Monster information is not available for this lookup.", sections = {} }
    end

    local sections = {
        overview_section(info),
        immunity_section(info),
    }
    local slayer = slayer_section(info)

    if slayer then
        sections[#sections + 1] = slayer
    end

    local dungeon = dungeon_section(title)

    if dungeon then
        sections[#sections + 1] = dungeon
    end

    sections[#sections + 1] = combat_section(info)
    sections[#sections + 1] = offensive_section(info)
    sections[#sections + 1] = defensive_section(info)
    sections[#sections + 1] = affinity_section(info)

    return {
        variant = anchor_name(info),
        sections = sections,
    }
end

return monster_info
