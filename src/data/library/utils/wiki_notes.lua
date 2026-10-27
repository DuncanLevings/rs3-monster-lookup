-- remove citation-only footnotes and keep visible note numbers/tooltips in sync.

local wiki_notes = {}

function wiki_notes.clean(value)
    local source = value:find("Mod%s+[%w_%-']+%.")
    return source and value:sub(1, source - 1):gsub("%s+$", "") or value
end

local function copy_table(value)
    local copy = {}

    for key, field in pairs(value) do
        copy[key] = field
    end

    return copy
end

local function remap_drop(drop, numbers, notes)
    local copy = copy_table(drop)
    local markers, explanations = {}, {}

    for number in (drop.note_marker or ""):gmatch("%d+") do
        local mapped = numbers[tonumber(number)]

        if mapped then
            markers[#markers + 1] = tostring(mapped)
            explanations[#explanations + 1] = notes[mapped]
        end
    end

    copy.note_marker = table.concat(markers, ",")
    copy.notes = (drop.note_marker or "") ~= "" and table.concat(explanations, "\n\n")
        or wiki_notes.clean(drop.notes or "")
    return copy
end

-- takes the wikis source citations out of a section, saved lookups from older versions
-- still have them. returns a copy, and renumbers the notes left and the markers pointing
-- at them together
function wiki_notes.without_sources(section)
    local notes, numbers = {}, {}
    local changed = false

    for number, value in ipairs(section.notes or {}) do
        local cleaned = wiki_notes.clean(value)
        changed = changed or cleaned ~= value

        if cleaned ~= "" then
            notes[#notes + 1] = cleaned
            numbers[number] = #notes
        end
    end

    if not changed then
        for _, drop in ipairs(section.drops) do
            if wiki_notes.clean(drop.notes or "") ~= (drop.notes or "") then
                changed = true
                break
            end
        end
    end

    if not changed then
        return section
    end

    local copy = copy_table(section)
    copy.notes, copy.drops, copy.note_ids = notes, {}, {}

    for _, drop in ipairs(section.drops) do
        copy.drops[#copy.drops + 1] = remap_drop(drop, numbers, notes)
    end

    for id, number in pairs(section.note_ids or {}) do
        copy.note_ids[id] = numbers[number]
    end

    return copy
end

return wiki_notes
