-- Pure waypoint planning. Authored map connections carry their own coordinates
-- or bounded scenery query; the engine never infers exits from object names.
local navigation = {}

function navigation.new(graph, coordinates)
    local planner = {}

    local function maps_at(position)
        local result = {}
        for id in pairs(graph.nodes) do
            if coordinates.contains(id, position) then
                result[#result + 1] = id
            end
        end
        -- Dedicated maps provide better area identity than a legacy diagram
        -- containing several unrelated caves. Keep shared maps only as fallback.
        if coordinates.is_shared then
            local dedicated = {}
            for _, id in ipairs(result) do
                if not coordinates.is_shared(id) then
                    dedicated[#dedicated + 1] = id
                end
            end
            if #dedicated > 0 then
                result = dedicated
            end
        end
        table.sort(result)
        return result
    end

    local function state_key(id, level, point)
        local region = point and coordinates.region and coordinates.region(id, point)
        return tostring(id) .. ":" .. tostring(level) .. ":" .. tostring(region or "unknown")
    end
    local function connected(id, first, second)
        return not coordinates.connected or coordinates.connected(id, first, second)
    end

    local function usable(edge, level, position, source)
        local from = edge.from_level or (edge.target and edge.target.level)
        if from ~= nil and from ~= level then
            return false
        end
        if edge.target and not coordinates.contains(source, edge.target) then
            return false
        end
        if position and edge.target and not connected(source, position, edge.target) then
            return false
        end
        if position and edge.region then
            local r = edge.region
            if position.x < r[1] or position.z < r[2] or position.x > r[3] or position.z > r[4] then
                return false
            end
        end
        return true
    end

    local function connections(
        sources,
        destination,
        destination_level,
        position,
        destination_point,
        require_arrival
    )
        local queue, visited, found = {}, {}, {}
        for _, id in ipairs(sources) do
            queue[#queue + 1] = { id = id, level = position.level, point = position, depth = 0 }
            visited[state_key(id, position.level, position)] = true
        end
        local cursor, depth = 1, nil
        while cursor <= #queue do
            local current = queue[cursor]
            cursor = cursor + 1
            if depth and current.depth >= depth then
                break
            end
            for _, edge in ipairs((graph.nodes[current.id] or {}).exits or {}) do
                if usable(edge, current.level, current.point, current.id) then
                    local level = edge.to_level or current.level
                    local first = current.first or edge
                    local source = current.source or current.id
                    local next_depth = current.depth + 1
                    local reaches = edge.to == destination
                    if destination_point and not reaches then
                        reaches = coordinates.contains(edge.to, destination_point)
                    end
                    if
                        reaches
                        and (not require_arrival or edge.arrival)
                        and (destination_level == nil or level == destination_level)
                        and (
                            not edge.arrival
                            or not destination_point
                            or connected(edge.to, edge.arrival, destination_point)
                        )
                    then
                        found[#found + 1] = {
                            edge = first,
                            source = source,
                            point = edge.arrival,
                            depth = next_depth,
                        }
                        depth = next_depth
                    else
                        local key = state_key(edge.to, level, edge.arrival)
                        if not visited[key] then
                            visited[key] = true
                            queue[#queue + 1] = {
                                id = edge.to,
                                level = level,
                                first = first,
                                source = source,
                                point = edge.arrival,
                                depth = next_depth,
                            }
                        end
                    end
                end
            end
        end
        -- Equal-hop exits can be physically far apart. Prefer the closest verified
        -- departure, while keeping unlocated queries after coordinate waypoints.
        table.sort(found, function(a, b)
            local function distance(candidate)
                local point = candidate.edge.target
                return point and ((point.x - position.x) ^ 2 + (point.z - position.z) ^ 2)
                    or math.huge
            end
            local da, db = distance(a), distance(b)
            if da ~= db then
                return da < db
            end
            return a.source < b.source
        end)
        return found
    end

    local function waypoint(target, label, final, map_level)
        return {
            target = target,
            label = label,
            final = final,
            map_level = map_level or target.level,
        }
    end

    function planner.next(goal, position, find_exit)
        if not position then
            return nil, "Waiting for your position"
        end
        if goal.interiors then
            local function reachable(spawn)
                return spawn
                    and spawn.target.level == position.level
                    and coordinates.contains(spawn.map_id, position)
                    and connected(spawn.map_id, position, spawn.target)
            end
            local selected = goal._selected_spawn
            if not reachable(selected) then
                local distance
                for _, spawn in ipairs(goal.interiors) do
                    if reachable(spawn) then
                        local point = spawn.target
                        local squared = (point.x - position.x) ^ 2 + (point.z - position.z) ^ 2
                        if not distance or squared < distance then
                            selected, distance = spawn, squared
                        end
                    end
                end
                goal._selected_spawn = selected
            end
            if selected then
                -- Keep a chosen pin stable while approaching it. This temporary
                -- goal copy does not change cached rows or the selection identity.
                local active = {}
                for key, value in pairs(goal) do
                    active[key] = value
                end
                active.interior, active.interior_map = selected.target, selected.map_id
                goal = active
            end
        end
        local at_interior = goal.interior and coordinates.contains(goal.interior_map, position)
        if
            at_interior
            and position.level == goal.interior.level
            and connected(goal.interior_map, position, goal.interior)
        then
            return waypoint(goal.interior, goal.destination_label, true)
        end
        local at_portal = goal.portal and coordinates.contains(goal.portal.map_id, position)
        if
            at_portal
            and (
                not goal.portal.target
                or (
                    position.level == goal.portal.target.level
                    and connected(goal.portal.map_id, position, goal.portal.target)
                )
            )
        then
            local point = goal.portal.target
                or (
                    goal.portal.query
                    and find_exit
                    and find_exit(goal.portal.query, position, goal.portal.map_id)
                )
            if point then
                return waypoint(point, goal.portal.label, false)
            end
            return nil, goal.portal.instruction or "Use the dungeon entrance to continue"
        end
        local sources = maps_at(position)
        if #sources == 0 then
            if goal.kind == "entrance" or goal.kind == "access" then
                return nil,
                    "Interior guidance is unavailable here. The selected destination is still saved"
            end
            return nil, "Return to the main world to show the marker"
        end
        -- A surface position can also be in an older diagram's footprint. The
        -- actual surface transform wins unless a verified destination matched above.
        local on_surface = false
        for _, id in ipairs(sources) do
            if id == graph.surface then
                on_surface = true
            end
        end
        if on_surface then
            return waypoint(
                goal.target,
                goal.label,
                goal.interior == nil and goal.kind ~= "entrance" and goal.kind ~= "access",
                0
            )
        end
        if not goal.interior and (goal.kind == "entrance" or goal.kind == "access") then
            -- Only an exact authored destination map confirms entry. An unknown
            -- area or the parent dungeon of a resource portal is not enough.
            for _, id in ipairs(goal.entry_maps or {}) do
                if coordinates.contains(id, position) then
                    return nil,
                        "No verified interior waypoint for this destination",
                        "interior_unavailable"
                end
            end
            return nil,
                "No verified interior waypoint for this destination. Entrance guidance remains saved"
        end
        local destination = goal.interior_map or graph.surface
        local level = goal.interior and goal.interior.level or nil
        local candidates =
            connections(sources, destination, level, position, goal.interior, at_interior)
        local fallback
        for _, candidate in ipairs(candidates) do
            local edge = candidate.edge
            local target = edge.target
                or (edge.query and find_exit and find_exit(edge.query, position, candidate.source))
            if target then
                return waypoint(target, edge.label or "Exit", false)
            end
            fallback = fallback or edge.instruction
        end
        if fallback then
            return nil, fallback
        end
        if at_interior then
            local destination_part = position.level == goal.interior.level and "destination chamber"
                or "destination floor"
            return nil,
                "Follow this area's passages, stairs or ladders to the "
                    .. destination_part
                    .. ". No verified transition waypoint is available",
                "interior_unavailable"
        end
        local node = graph.nodes[sources[1]]
        if node then
            local instruction = node.instruction
                or ("Leave " .. (node.name or "this dungeon") .. " to continue")
            return nil, instruction
        end
        return nil, "Return to the main world to show the marker"
    end

    return planner
end

return navigation
