-- Connections describe transitions, not walking paths. A gate may be discovered
-- from loaded scenery or explained in text when its position is not verified.
-- Keep dungeon-specific names and access rules out of the navigation engine.
local graph = {
    surface = 28,
    nodes = {
        [28] = { name = "Surface" },
        [5] = { name = "Fremennik Slayer Dungeon" },
        [13] = { name = "Brimhaven Dungeon" },
        [15] = { name = "God Wars Dungeon" },
        [17] = { name = "Taverley Dungeon" },
        [23] = { name = "Chaos Tunnels" },
        [30] = {
            name = "Tarn's Lair",
            exits = {
                { to = 569, instruction = "Leave Tarn's Lair through its entrance to continue" },
            },
        },
        [36] = { name = "Ancient Cavern" },
        [164] = { name = "Lumbridge Catacombs" },
        [165] = { name = "Lumbridge Catacombs" },
        [266] = { name = "Polypore Dungeon" },
        [267] = { name = "Polypore Dungeon" },
        [569] = {
            name = "Abandoned Mine",
            exits = {
                {
                    to = 28,
                    query = { name = "Cart tunnel", range = 64 },
                    label = "Abandoned Mine exit (Cart tunnel)",
                    instruction = "Leave the Abandoned Mine to continue; no reliable exit is loaded",
                },
                {
                    to = 30,
                    query = { name = "Entrance", range = 64, unique = true },
                    label = "Entrance to Tarn's Lair",
                    instruction = "Enter Tarn's Lair from the north of the mine to continue",
                },
            },
        },
        [717] = { name = "Slayer Tower Resource Dungeon" },
    },
}

for id, name in pairs(require("src/data/dungeon_map_names")) do
    graph.nodes[id] = graph.nodes[id] or { name = name }
end
for _, connection in ipairs(require("src/data/dungeon_connections")) do
    local node = graph.nodes[connection.from]
    if node then
        node.exits = node.exits or {}
        node.exits[#node.exits + 1] = connection
    end
end
for id, instruction in pairs(require("src/data/dungeon_route_instructions")) do
    if graph.nodes[id] then
        graph.nodes[id].instruction = instruction
    end
end
return graph
