-- pulls drop tables out of a wiki page's rendered html
--
-- this isnt a general html parser, it only knows the markup the wiki uses for item-drops
-- tables right now (headings, rows, footnotes and the paragraphs around each table). if the
-- wiki changes that markup then an error is likely rather than a wrong table

local text = require("src/utils/wiki_text")
local json = require("src/utils/json")

---@class Drop
---@field name string item name as shown on the page
---@field wiki_name string item page name, used to look up the item id
---@field item_id integer? filled in later for the item icon
---@field quantity string
---@field rate string rarity text exactly as the wiki shows it eg "1/128" or "Rare"
---@field price number|{minimum: number, maximum: number}|"Not sold"|nil
---@field notes string footnote text for this row, "" if none
---@field note_marker string footnote numbers eg "1,3", "" if none

---@class DropSection
---@field title string headings above the table joined with " / "
---@field description string? paragraphs between the heading and the table
---@field afterword string? paragraphs after the table
---@field drops Drop[]
---@field notes string[] footnotes used in this table, numbered in order
---@field note_ids table<string, integer>

local wiki_page = {}

local function extract_notes(html)
    local notes = {}

    for attributes, content in html:gmatch("<li([^>]*)>(.-)</li>") do
        local id = text.attribute(attributes, "id")
        local body = content:match('<span class="reference%-text">(.*)')

        if id:match("^cite_note") and body then
            notes[id] = text.plain(body)
        end
    end

    return notes
end

local function row_notes(html, notes, section)
    local values = {}
    local seen = {}
    local numbers = {}

    for reference in html:gmatch('href="#([^"]+)"') do
        local id = text.decode(reference)
        local explanation = notes[id]

        if not explanation and id:match("^cite_note") then
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

        local average_value = value:lower():match("^the average .- is worth ")

        if value ~= "" and not average_value then
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
        state.introductions[deepest_heading(state.headings)] = paragraphs
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

local function add_drop_table(state, content, preceding_html)
    capture_paragraphs(state, preceding_html)
    local section = parse_table(content, state.headings, state.notes)

    if #section.drops == 0 then
        return
    end

    local descriptions = {}

    for level = 2, 6 do
        if state.introductions[level] then
            descriptions[#descriptions + 1] = state.introductions[level]
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
                add_drop_table(state, content, html:sub(position, ts - 1))
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

    local state = { headings = {}, sections = {}, introductions = {}, notes = extract_notes(html) }

    scan_tables(html, state)
    return state.sections
end

return wiki_page
