-- plans the next waypoint towards a location, no game calls in here so its easy to test.
-- each connection between maps (dungeons/connections.lua) says where it is, or what to
-- look for nearby. exits are never guessed from an object being called Ladder or Door
--
-- graph is routes.lua: nodes are maps, each with exits (edges) to other maps. coordinates is
-- coordinates.lua, which knows which map a tile is on. planner.next is called about once a
-- second by the marker and returns the waypoint to point at right now

local navigation = {}

function navigation.new(graph, coordinates)
    local planner = {}

    -- the maps the player is standing on, sorted so ties always go the same way
    local function maps_at(position)
        local result = {}

        for id in pairs(graph.nodes) do
            if coordinates.contains(id, position) then
                result[#result + 1] = id
            end
        end

        -- an areas own map says more about where you are than an old shared map with
        -- several unrelated caves on, so shared maps are only the fallback
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

    -- one search state per map, floor and connected region of that map
    local function state_key(id, level, point)
        local region = point and coordinates.region and coordinates.region(id, point)
        return tostring(id) .. ":" .. tostring(level) .. ":" .. tostring(region or "unknown")
    end

    local function connected(id, first, second)
        return not coordinates.connected or coordinates.connected(id, first, second)
    end

    -- whether an exit can be taken from where the search is: right floor, actually on
    -- this map, and reachable from the position without a teleport
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

    -- breadth first search from the maps the player is on to the destination map, one
    -- exit at a time. only the first exit of each route matters (thats the next waypoint),
    -- so it returns every first exit that reaches the destination in the fewest steps
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

            -- found routes this short already, anything left in the queue is longer
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

        -- routes the same number of steps long can start from exits far apart, so the
        -- nearest one goes first. exits found by searching scenery (no known spot) go last
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

    ---the waypoint to point at now, in order of what gets checked:
    ---  1. already in the right part of the dungeon: the spawn itself
    ---  2. at a resource dungeon portal: the portal
    ---  3. on the surface: the entrance (or the spawn when its on the surface)
    ---  4. in a dungeon: the next exit towards the destination
    ---returns nil, a reason for the status line, and "interior_unavailable" when the
    ---player got in but theres no guidance any further (the marker then clears itself)
    ---@param find_exit fun(query: table, position: table, map_id: integer): table? looks for
    ---an exit among the loaded scenery, for exits with no known spot (game/locations/route)
    function planner.next(goal, position, find_exit)
        if not position then
            return nil, "Waiting for your position"
        end

        local is_entrance = goal.kind == "entrance" or goal.kind == "access"

        -- a monster with several spawns inside: head for the nearest one you can walk to
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
                -- stick with the pin already picked while walking to it. this is a copy of
                -- the goal so the saved rows and what was selected dont change
                local active = {}

                for key, value in pairs(goal) do
                    active[key] = value
                end

                active.interior, active.interior_map = selected.target, selected.map_id
                goal = active
            end
        end

        -- 1. in the right part of the dungeon already
        local at_interior = goal.interior and coordinates.contains(goal.interior_map, position)

        if
            at_interior
            and position.level == goal.interior.level
            and connected(goal.interior_map, position, goal.interior)
        then
            return waypoint(goal.interior, goal.destination_label, true)
        end

        -- 2. at a resource dungeon portal
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
            if is_entrance then
                return nil,
                    "Interior guidance is unavailable here. The selected destination is still saved"
            end

            return nil, "Return to the main world to show the marker"
        end

        -- a spot on the surface can also fall inside an old dungeon maps area. the surface
        -- wins unless one of the checked destinations above already matched
        local on_surface = false

        for _, id in ipairs(sources) do
            if id == graph.surface then
                on_surface = true
            end
        end

        -- 3. on the surface, its the final step only when the spawn itself is up here
        if on_surface then
            return waypoint(goal.target, goal.label, goal.interior == nil and not is_entrance, 0)
        end

        if not goal.interior and is_entrance then
            -- only being on the exact map the connection leads to counts as getting in.
            -- an unknown area, or the dungeon a resource portal sits in, isnt enough
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

        -- 4. in a dungeon, find the next exit towards the destination (or back to the
        -- surface when the destination is somewhere else)
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

            -- no spot for this exit, the first written directions get shown instead
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
