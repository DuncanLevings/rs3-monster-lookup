-- how you get into a place: finds a location's entrance by its exact wiki page name, then
-- follows its parent entries outwards (cave inside a dungeon inside an area) to one on the
-- surface. only exact names, a similar looking name is never trusted for coordinates
local numbers = require("src/utils/numbers")
local wiki_text = require("src/utils/wiki_text")

local access = {}

function access.new(entries)
    local index, lookup = {}, {}

    for _, entry in ipairs(entries) do
        for _, page in ipairs(entry.pages) do
            index[wiki_text.page_key(page)] = entry
        end
    end

    function lookup.resolve(page, display_name)
        local entry = index[wiki_text.page_key(page)]
        if not entry then
            return nil
        end

        local root, visited = entry, {}

        while root.parent do
            if visited[root] then
                return nil, "The saved entrance path contains a cycle."
            end
            visited[root] = true
            root = index[wiki_text.page_key(root.parent)]
            if not root then
                return nil, "No verified parent entrance is available."
            end
        end

        local level = root.level or 0
        if
            not numbers.is_whole(root.x, 0, 16383)
            or not numbers.is_whole(root.z, 0, 16383)
            or not numbers.is_whole(level, 0, 3)
        then
            return nil, "The saved entrance coordinates are invalid."
        end

        local label = entry.via
        if not label and entry.parent then
            label = (root.via or root.pages[1] .. " entrance")
                .. " (access to "
                .. (display_name or entry.pages[1])
                .. ")"
        end

        return {
            entry = entry,
            target = { level = level, x = root.x, z = root.z },
            label = label or (display_name or entry.pages[1]) .. " entrance",
            kind = entry.kind == "access" and "access" or "entrance",
        }
    end

    return lookup
end

return access
