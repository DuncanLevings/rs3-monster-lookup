-- splits drop sections into the modes shown in the drop tabs mode picker, eg normal and hard
-- mode on bosses or the enrage tables on amascut

local drop_groups = {}

---@class DropGroup
---@field name string shown in the mode picker eg "Normal mode"
---@field sections DropSection[]
---@field titles string[] section titles without the group part eg "Unique"

-- "Drops (hard mode)" reads better as "Hard mode" in a dropdown
local function group_name(heading)
    local inside = heading:match("^Drops %((.+)%)$")

    if inside then
        return inside:sub(1, 1):upper() .. inside:sub(2)
    end

    return heading
end

local function enrage_choices(sections)
    local choices, seen = {}, {}

    for _, section in ipairs(sections) do
        if section.drop_mode and section.drop_threshold and not seen[section.drop_threshold] then
            seen[section.drop_threshold] = true
            choices[#choices + 1] = { name = section.drop_mode, minimum = section.drop_threshold }
        end
    end

    table.sort(choices, function(a, b)
        return a.minimum < b.minimum
    end)
    return choices
end

local function selected_thresholds(sections, enrage)
    local selected = {}

    -- categories can use different thresholds, or start at 100% with no normal table
    for _, section in ipairs(sections) do
        local switch, minimum = section.drop_switch, section.drop_threshold

        if
            switch
            and minimum <= enrage
            and (not selected[switch] or minimum > selected[switch])
        then
            selected[switch] = minimum
        end
    end

    return selected
end

local function enrage_groups(sections)
    local choices = enrage_choices(sections)

    if #choices < 2 then
        return nil
    end

    local groups = {}

    for _, choice in ipairs(choices) do
        local selected = selected_thresholds(sections, choice.minimum)
        local group = { name = choice.name, sections = {}, titles = {} }

        for _, section in ipairs(sections) do
            if
                not section.drop_switch
                or selected[section.drop_switch] == section.drop_threshold
            then
                group.sections[#group.sections + 1] = section
                group.titles[#group.titles + 1] = section.title
            end
        end

        groups[#groups + 1] = group
    end

    return groups
end

-- splits sections into modes using the first part of their title, eg normal and hard mode
-- on bosses. only when every section has a group part and theres more than one group,
-- otherwise a page with just a "Tertiary / Charms" subsection would get a pointless picker
---@param sections DropSection[]
---@return DropGroup[]? groups nil when the page shouldnt be split
function drop_groups.mode_groups(sections)
    local enrages = enrage_groups(sections)

    if enrages then
        return enrages
    end

    local groups = {}
    local by_heading = {}

    for _, section in ipairs(sections) do
        local heading, rest = section.title:match("^(.-) / (.+)$")

        if not heading then
            return nil
        end

        local group = by_heading[heading]

        if not group then
            group = { name = group_name(heading), sections = {}, titles = {} }
            by_heading[heading] = group
            groups[#groups + 1] = group
        end

        group.sections[#group.sections + 1] = section
        group.titles[#group.titles + 1] = rest
    end

    return #groups > 1 and groups or nil
end

return drop_groups
