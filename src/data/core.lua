-- the client loads this dependency first and shares its static export; never modify it
assert(
    type(MonsterDataCore) == "table" and type(MonsterDataCore.monster) == "function",
    "Monster Lookup requires Monster Data Core. Enable monster-data-core before Monster Lookup."
)
return MonsterDataCore
