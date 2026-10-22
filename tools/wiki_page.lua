-- pulls drop tables out of a wiki pages rendered html. only the bundle build uses this now,
-- the plugin itself reads the saved bundle or the dropsline bucket instead
--
-- this isnt a general html parser, it only knows the markup the wiki uses for item-drops
-- tables right now (headings, rows, footnotes and the paragraphs around each table). if the
-- wiki changes that markup then an error is likely rather than a wrong table

local text = require("src/utils/wiki_text")
local json = require("src/utils/json")
local wiki_switches = require("tools/wiki_switches")
local wiki_notes = require("src/utils/wiki_notes")

local wiki_page = {}

local function extract_notes(html)
    local notes = {}

    for attributes, content in html:gmatch("<li([^>]*)>(.-)</li>") do
        local id = text.attribute(attributes, "id")
        local body = content:match('<span class="reference%-text">(.*)')

        if id:match("^cite_note") and body then
            local cleaned = wiki_notes.clean(text.plain(body))
            notes[id] = cleaned ~= "" and cleaned or false
        end
    end

    return notes
end

-- Wiki citation IDs are page-wide; give each drop table its own numbering in first-use order
local function row_notes(html, notes, section)
    local values = {}
    local seen = {}
    local numbers = {}

    for reference in html:gmatch('href="#([^"]+)"') do
        local id = text.decode(reference)
        local explanation = notes[id]

        if explanation == nil and id:match("^cite_note") then
            explanation =
                "This Wiki note could not be read. Check the source page for this condition."
        end

        if explanation and not seen[id] then
            seen[id] = true

            if not section.note_ids[id] then
                section.notes[#section.notes + 1] = explanation
                section.note_ids[id] = #section.notes
            end

            numbers[#numbers + 1] = tostring(section.note_ids[id])
            values[#values + 1] = explanation
        end
    end

    return table.concat(values, "\n\n"), table.concat(numbers, ",")
end

local function extract_cells(row)
    local cells = {}

    for attributes, content in row:gmatch("<td([^>]*)>(.-)</td>") do
        cells[#cells + 1] = { attributes = attributes, content = content }
    end

    return cells
end

local function extract_price(cell)
    if cell.content:find("dropsline%-gealch") or cell.content:find("dropsline%-altval") then
        return "Not sold"
    end

    local plain = text.plain(cell.content)

    if plain:lower():find("not sold", 1, true) then
        return "Not sold"
    end

    return text.price(cell.content)
end

local function parse_drop(row, notes, section)
    local cells = extract_cells(row)

    if #cells < 5 or not cells[2].attributes:find("item%-col") then
        return nil
    end

    local name = text.attribute(cells[1].attributes, "data-sort-value")

    if name == "" then
        return nil
    end

    local explanation, marker = row_notes(row, notes, section)
    return {
        name = text.plain(cells[2].content),
        wiki_name = name,
        quantity = text.plain(cells[3].content),
        rate = text.plain(cells[4].content),
        price = extract_price(cells[5]),
        notes = explanation,
        note_marker = marker,
    }
end

local function section_title(headings)
    local titles = {}

    for level = 2, 6 do
        if headings[level] and headings[level] ~= "Drops" then
            titles[#titles + 1] = headings[level]
        end
    end

    return #titles > 0 and table.concat(titles, " / ") or "Drops"
end

local function parse_table(content, headings, notes)
    local section = { title = section_title(headings), drops = {}, notes = {}, note_ids = {} }

    for row in content:gmatch("<tr[^>]*>(.-)</tr>") do
        local drop = parse_drop(row, notes, section)

        if drop then
            section.drops[#section.drops + 1] = drop
        end
    end

    return section
end

local function paragraph_notes(html)
    local values = {}

    for paragraph in html:gmatch("<p[^>]*>(.-)</p>") do
        local value = text.plain(paragraph)

        if value ~= "" then
            values[#values + 1] = value
        end
    end

    return table.concat(values, "\n\n")
end

local function update_heading(headings, level, content)
    headings[level] = text.plain(content)

    for deeper = level + 1, 6 do
        headings[deeper] = nil
    end
end

local function deepest_heading(headings)
    for level = 6, 2, -1 do
        if headings[level] then
            return level
        end
    end

    return 2
end

local function capture_paragraphs(state, html)
    local paragraphs = paragraph_notes(html)

    if paragraphs == "" then
        return
    end

    if state.last_section then
        state.last_section.afterword = paragraphs
    else
        local level = deepest_heading(state.headings)
        local existing = state.introductions[level]
        state.introductions[level] = existing and existing .. "\n\n" .. paragraphs or paragraphs
    end
end

local function start_heading(state, tag, heading, preceding_html)
    capture_paragraphs(state, preceding_html)
    local level = assert(tonumber(tag:sub(2)))
    update_heading(state.headings, level, heading)

    for deeper = level, 6 do
        state.introductions[deeper] = nil
    end

    state.last_section = nil
end

local function add_drop_table(state, content, preceding_html, variant)
    capture_paragraphs(state, preceding_html)
    local section = parse_table(content, state.headings, state.notes)

    if variant then
        section.drop_mode = variant.name
        section.drop_threshold = variant.minimum
        section.drop_switch = variant.group
    end

    if #section.drops == 0 then
        return
    end

    local descriptions = {}

    -- an intro under a heading like "Drops (normal mode)" goes above the first table under it
    -- only, otherwise it gets repeated above every category in that mode
    for level = 2, 6 do
        if state.introductions[level] then
            descriptions[#descriptions + 1] = state.introductions[level]
            state.introductions[level] = nil
        end
    end

    section.description = table.concat(descriptions, "\n\n")
    state.sections[#state.sections + 1] = section
    state.last_section = section
end

-- reuses the last search result while its still ahead of the scan position, otherwise a long
-- run of headings before a table means searching for that same table again every time
local function next_match(html, cached, pattern, position)
    if cached and (cached.done or cached[1] >= position) then
        return cached
    end

    local found = { html:find(pattern, position) }
    return found[1] and found or { done = true }
end

-- walks headings and tables in page order so each table knows which headings its under
local function scan_tables(html, state)
    local position = 1
    local heading_match, table_match

    while true do
        heading_match = next_match(html, heading_match, "<(h[2-6])[^>]*>(.-)</%1>", position)
        table_match = next_match(html, table_match, "<table([^>]*)>(.-)</table>", position)
        local hs, he, tag, heading = table.unpack(heading_match)
        local ts, te, attributes, content = table.unpack(table_match)

        if hs and (not ts or hs < ts) then
            start_heading(state, tag, heading, html:sub(position, hs - 1))
            position = he + 1
        elseif ts then
            if attributes:find("item%-drops") then
                local variant = state.find_switch(ts)
                local intro_start = position

                if variant and variant ~= state.last_variant then
                    if variant.start > position then
                        capture_paragraphs(state, html:sub(position, variant.start - 1))
                    end

                    state.last_section = nil
                    intro_start = math.max(position, variant.start)
                end

                add_drop_table(state, content, html:sub(intro_start, ts - 1), variant)
                state.last_variant = variant
            end

            position = te + 1
        else
            capture_paragraphs(state, html:sub(position))
            break
        end
    end
end

-- true if the page looks like it has drops (a Drops heading or an item-drops table) even
-- though parse() found none, so it can tell "no drops listed" apart from "cant read them"
---@param html string?
---@return boolean
function wiki_page.has_drop_markup(html)
    if type(html) ~= "string" then
        return false
    end

    return html:find('<h[2-6][^>]-id="Drops"') ~= nil or html:find("item%-drops") ~= nil
end

---@param html string? rendered page html from action=parse
---@return DropSection[]? sections
---@return string? problem
function wiki_page.parse(html)
    if type(html) ~= "string" or #html > json.MAX_BYTES then
        return nil, "The Wiki page is too large or invalid."
    end

    local state = {
        headings = {},
        sections = {},
        introductions = {},
        notes = extract_notes(html),
        find_switch = wiki_switches.scan(html),
    }

    scan_tables(html, state)
    return state.sections
end

return wiki_page
