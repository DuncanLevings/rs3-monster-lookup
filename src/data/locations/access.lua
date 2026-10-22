-- Resolve exact location aliases and authored parent chains. This describes
-- access to a place; it never derives world coordinates from a similar name.
local access = {}

local function key(value)
    return (type(value) == "string" and value or "")
        :gsub("_", " ")
        :gsub("%s+", " ")
        :match("^%s*(.-)%s*$")
        :lower()
end

local function whole(value, maximum)
    return type(value) == "number"
        and value == value
        and value % 1 == 0
        and value >= 0
        and value <= maximum
end

function access.new(entries)
    local index, lookup = {}, {}

    for _, entry in ipairs(entries) do
        for _, page in ipairs(entry.pages) do
            index[key(page)] = entry
        end
    end

    function lookup.resolve(page, display_name)
        local entry = index[key(page)]
        if not entry then
            return nil
        end

        local root, visited = entry, {}

        while root.parent do
            if visited[root] then
                return nil, "The saved entrance path contains a cycle."
            end
            visited[root] = true
            root = index[key(root.parent)]
            if not root then
                return nil, "No verified parent entrance is available."
            end
        end

        local level = root.level or 0
        if not whole(root.x, 16383) or not whole(root.z, 16383) or not whole(level, 3) then
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
