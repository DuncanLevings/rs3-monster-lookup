-- some wiki pages have a switcher with a copy of the drop tables per enrage, all with the
-- same headings. this keeps track of which switcher div each table is in so it keeps its
-- own label and intro text
local text = require("src/utils/wiki_text")

local switches = {}

local function has_class(attributes, name)
    local classes = " " .. text.attribute(attributes, "class"):gsub("%s+", " ") .. " "
    return classes:find(" " .. name .. " ", 1, true) ~= nil
end

local function threshold(label)
    if label:lower() == "normal mode" then
        return -1
    end

    if label:find("%%") then
        return tonumber(label:gsub(",", ""):match("^(%d+)"))
    end
end

local function read_labels(html)
    local labels, count, has_enrage = {}, 0, false

    for attributes, body in html:gmatch("<span([^>]*)>(.-)</span>") do
        if has_class(attributes, "trigger") then
            local name = text.plain(body)
            local minimum = threshold(name)
            local id = text.attribute(attributes, "data-id")

            if id ~= "" and minimum then
                labels[id] = { name = name, minimum = minimum }
                count = count + 1
                has_enrage = has_enrage or minimum >= 0
            end
        end
    end

    return count > 1 and has_enrage and labels or nil
end

local function finish_switch(frame, ranges, group_id)
    if not frame.labels then
        return
    end

    for _, range in ipairs(frame.items) do
        local label = frame.labels[range.id]

        if label then
            range.name = label.name
            range.minimum = label.minimum
            range.group = group_id
            ranges[#ranges + 1] = range
        end
    end
end

function switches.scan(html)
    local stack, ranges = {}, {}
    local group_id = 0

    for start, tag, attributes, content_start in html:gmatch("()<(/?div)([^>]*)>()") do
        if tag == "div" then
            local parent = stack[#stack]
            local frame = { context = parent and parent.context }

            if has_class(attributes, "switch-infobox") then
                frame.root = true
                frame.items = {}
                frame.context = frame
            elseif parent and parent.root then
                if has_class(attributes, "switch-infobox-triggers") then
                    frame.triggers_start = content_start
                elseif has_class(attributes, "item") then
                    frame.item =
                        { id = text.attribute(attributes, "data-id"), start = content_start }
                end
            end

            stack[#stack + 1] = frame
        else
            local frame = table.remove(stack)

            if frame then
                if frame.triggers_start then
                    frame.context.labels = read_labels(html:sub(frame.triggers_start, start - 1))
                elseif frame.item then
                    frame.item.finish = start - 1
                    table.insert(frame.context.items, frame.item)
                elseif frame.root then
                    group_id = group_id + 1
                    finish_switch(frame, ranges, group_id)
                end
            end
        end
    end

    table.sort(ranges, function(a, b)
        return a.start < b.start
    end)
    local position = 0

    return function(table_start)
        while ranges[position + 1] and ranges[position + 1].start <= table_start do
            position = position + 1
        end

        local range = ranges[position]
        return range and table_start <= range.finish and range or nil
    end
end

return switches
