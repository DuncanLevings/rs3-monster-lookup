-- reads the Wiki's standard spawn tables from the Location/Locations section
-- header names identify the columns so extra map or league columns cannot shift the data

local text = require("src/utils/wiki_text")
local location_map = require("src/data/location_map")

---@class MonsterLocation
---@field name string
---@field levels string
---@field requirements string
---@field spawns string
---@field map table? Wiki map space, not necessarily a game-world target

local locations = {}
local COLUMNS = {
    location = "name",
    level = "levels",
    levels = "levels",
    requirements = "requirements",
    ["access requirements"] = "requirements",
    spawns = "spawns",
}

local function location_section(html)
    local start, section_level

    for first, level, attributes, heading, last in html:gmatch("()<h([2-6])([^>]*)>(.-)</h%2>()") do
        local depth = tonumber(level)

        if start and depth <= section_level then
            return html:sub(start, first - 1)
        end

        local title = text.plain(heading):lower()
        local anchor = text.attribute(attributes, "id"):lower()

        if not start and (title == "location" or title == "locations" or anchor == "locations") then
            start, section_level = last, depth
        end
    end

    return start and html:sub(start) or nil
end

local function header_columns(row)
    local columns = {}
    local index = 0

    for heading in row:gmatch("<th[^>]*>(.-)</th>") do
        index = index + 1
        local key = COLUMNS[text.plain(heading):lower()]

        if key then
            columns[key] = index
        end
    end

    for _, key in ipairs({ "name", "levels", "requirements", "spawns" }) do
        if not columns[key] then
            return nil
        end
    end

    return columns
end

local function span_end(html, position)
    local depth = 1

    while true do
        local first, last, closing = html:find("<(/?)span[^>]*>", position)

        if not first then
            return nil
        end

        depth = depth + (closing == "/" and -1 or 1)

        if depth == 0 then
            return last + 1
        end

        position = last + 1
    end
end

local function cell_text(html)
    -- both floor conventions are present in rendered HTML; use the numeric floor once
    -- rather than displaying the hidden US and UK versions next to each other
    local parts = {}
    local position = 1

    while true do
        local first, last, attributes = html:find('<span([^>]-class="floornumber"[^>]*)>', position)

        if not first then
            parts[#parts + 1] = html:sub(position)
            break
        end

        local ending = span_end(html, last + 1)

        if not ending then
            parts[#parts + 1] = html:sub(position)
            break
        end

        parts[#parts + 1] = html:sub(position, first - 1)
        local floor = tonumber(text.attribute(attributes, "data-sort-value"))
        parts[#parts + 1] = floor and "Floor " .. floor or text.plain(html:sub(first, ending - 1))
        position = ending
    end

    return text.plain(table.concat(parts))
end

local function requirements_text(html)
    local visible = text.plain(html):lower()
    html = html:gsub("<img([^>]*)>", function(attributes)
        local alt = text.attribute(attributes, "alt"):gsub("%.png$", ""):gsub(" icon$", "")

        if alt == "" or visible:find(alt:lower(), 1, true) then
            return ""
        end

        return " " .. alt .. " "
    end)

    -- source-code newlines are formatting; list items and <br> are actual line breaks
    html = html:gsub("[\r\n]", " "):gsub("<br%s*/?>", "\n")
    html = html:gsub("</li%s*>", "\n"):gsub("</p%s*>", "\n")
    local lines = {}

    for line in html:gmatch("[^\n]+") do
        local value = cell_text(line)

        if value ~= "" then
            lines[#lines + 1] = value
        end
    end

    return table.concat(lines, "\n")
end

local function row_map(row)
    local found
    for attributes in row:gmatch("<a%s+([^>]*)>") do
        local classes = " " .. text.attribute(attributes, "class") .. " "
        if classes:find(" mw-kartographer-maplink ", 1, true) then
            local map = {
                id = tonumber(text.attribute(attributes, "data-mapid")),
                plane = tonumber(text.attribute(attributes, "data-plane")),
                x = tonumber(text.attribute(attributes, "data-lon")),
                z = tonumber(text.attribute(attributes, "data-lat")),
            }
            if not location_map.valid(map) then
                return nil
            end
            if
                found
                and (
                    found.id ~= map.id
                    or found.plane ~= map.plane
                    or found.x ~= map.x
                    or found.z ~= map.z
                )
            then
                return nil
            end
            found = map
        end
    end
    return found
end

local function parse_row(row, columns)
    local cells = {}

    for attributes, content in row:gmatch("<td([^>]*)>(.-)</td>") do
        -- merged cells need a grid parser. skip that table instead of assigning values
        -- to the wrong columns and presenting a misleading requirement or spawn count
        for _, attribute in ipairs({ "rowspan", "colspan" }) do
            local span = text.attribute(attributes, attribute)

            if span ~= "" and span ~= "1" then
                return nil
            end
        end

        cells[#cells + 1] = content
    end

    local result = {}

    for key, column in pairs(columns) do
        if not cells[column] then
            return nil
        end

        result[key] = key == "requirements" and requirements_text(cells[column])
            or cell_text(cells[column])
        if key == "spawns" then
            result[key] = result[key]:match("^%s*(%d+)%s*$") or ""
        else
            result[key] = result[key] ~= "" and result[key] or "Unknown"
        end
    end

    result.map = row_map(row)
    return result
end

local function parse_table(html)
    if html:find("<table[%s>]") then
        return nil
    end

    local columns
    local rows = {}

    for row in html:gmatch("<tr[^>]*>(.-)</tr>") do
        if row:find("<th[%s>]") then
            columns = header_columns(row)
        elseif columns and row:find("<td[%s>]") then
            local location = parse_row(row, columns)

            if not location then
                return nil
            end

            rows[#rows + 1] = location
        end
    end

    return columns and rows or nil
end

---@param html string rendered monster page, already checked by the response validator
---@return MonsterLocation[] rows
---@return "none"|"unreadable"? reason only set when no rows can be shown
function locations.parse(html)
    local section = location_section(html)

    if not section then
        return {}, "none"
    end

    local rows = {}

    for table_html in section:gmatch("<table[^>]*>(.-)</table>") do
        local parsed = parse_table(table_html)

        for _, row in ipairs(parsed or {}) do
            rows[#rows + 1] = row
        end
    end

    return rows, #rows == 0 and "unreadable" or nil
end

return locations
