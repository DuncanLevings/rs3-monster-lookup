-- turns a monsters infobox values from the wiki into the table sections the Monster info
-- tab draws. no ui code in here, the view just gets titles, headers, rows and icon keys
-- anything missing from the wiki shows as Unknown rather than being left out

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
    local rows = {
        {
            "Life points",
            format.text(info.life_points),
            "Attack style",
            format.title(info.attack_style_text),
        },
        {
            "Attack speed",
            attack_speed(info.attack_rate),
            "Aggressive",
            format.boolean(info.is_aggressive),
        },
        {
            "Poisonous",
            format.boolean(info.is_poisonous),
            "Combat XP",
            format.text(info.combat_experience),
        },
    }

    if info.is_members_only ~= nil or info.location_restriction ~= nil then
        rows[#rows + 1] = {
            "Members only",
            format.boolean(info.is_members_only),
            info.location_restriction ~= nil and "Location" or "",
            info.location_restriction ~= nil and format.title(info.location_restriction) or "",
        }
    end

    return facts("Combat info", rows)
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

local function defensive_section(info)
    return {
        title = "Defensive stats",
        widths = { 0.20, 0.20, 0.25, 0.35 },
        headers = { "Armour", "Defence level", "Weakness", "Susceptible to" },
        header_icons = { false, "defence", weakness_icon(info) or false, false },
        rows = {
            {
                format.text(info.armour),
                format.text(info.defence_level),
                weakness(info.weakness_text),
                format_susceptibilities(info.susceptible_to),
            },
        },
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
        widths = widths,
        headers = headers,
        header_icons = icons,
        rows = { values },
    }
end

-- the Wiki fields describe susceptibility, so true means Not immune in this section
local function immunity_section(info)
    local values = {}

    for _, field in ipairs({ "poison", "deflect", "stun", "drain" }) do
        values[#values + 1] =
            format.boolean(info["susceptible_to_" .. field], "Not immune", "Immune")
    end

    return {
        title = "Immunities",
        widths = { 0.25, 0.25, 0.25, 0.25 },
        headers = { "Poison", "Deflect", "Stun", "Stat drain" },
        header_icons = { "poison", "deflect", "stun", "drain" },
        rows = { values },
    }
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

function monster_info.build(info)
    if next(info) == nil then
        return { message = "Monster information is not available for this lookup.", sections = {} }
    end

    local sections = {
        combat_section(info),
        offensive_section(info),
        defensive_section(info),
        affinity_section(info),
        immunity_section(info),
    }
    local slayer = slayer_section(info)

    if slayer then
        sections[#sections + 1] = slayer
    end

    return {
        variant = anchor_name(info),
        sections = sections,
    }
end

return monster_info
