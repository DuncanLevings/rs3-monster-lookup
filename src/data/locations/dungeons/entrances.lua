-- checked dungeon entrances, and for places inside other places the entry they go through
-- (parent). names must match exactly, quest copies of a dungeon can share its name or map
-- but be somewhere else entirely in game. a parent entry reuses the outer entrance, guiding
-- you on inside needs the location itself to convert to game coordinates, the entrance name
-- isnt enough. where each one came from: resources/DUNGEON_ENTRANCE_SOURCES.json
return {
    {
        pages = { "Taverley Dungeon" },
        x = 2885,
        z = 3397,
    },
    {
        pages = { "Brimhaven Dungeon" },
        x = 2744,
        z = 3155,
    },
    {
        pages = { "Fremennik Slayer Dungeon" },
        x = 2798,
        z = 3615,
    },
    {
        pages = { "Pollnivneach Slayer Dungeon" },
        x = 3359,
        z = 2972,
    },
    {
        pages = { "Ancient Cavern", "Kuradal's Dungeon" },
        via = "Ancient Cavern whirlpool",
        x = 2510,
        z = 3506,
    },
    {
        pages = { "Morytania Slayer Tower dungeon", "Slayer Tower Resource Dungeon" },
        x = 3434,
        z = 3532,
    },
    {
        pages = { "God Wars Dungeon" },
        x = 2915,
        z = 3741,
    },
    {
        pages = { "Polypore Dungeon" },
        x = 3409,
        z = 3330,
    },
    {
        pages = { "Polypore Dungeon resource dungeon" },
        via = "Polypore Dungeon entrance (access to resource dungeon)",
        x = 3409,
        z = 3330,
    },
    {
        pages = { "Lumbridge Catacombs" },
        x = 3246,
        z = 3198,
    },
    {
        pages = { "Chaos Tunnels" },
        via = "Chaos Tunnels level 6 Wilderness entrance",
        x = 3058,
        z = 3550,
    },
    {
        pages = { "Heart of Gielinor", "The Heart of Gielinor" },
        x = 3378,
        z = 2881,
    },
    {
        pages = { "Lair of Tarn Razorlor (dungeon)", "Lair of Tarn Razorlor", "Tarn's Lair" },
        via = "Abandoned Mine entrance",
        x = 3429,
        z = 3233,
    },
    {
        pages = { "Abandoned Mine" },
        x = 3429,
        z = 3233,
    },
    {
        pages = { "Al Kharid resource dungeon" },
        x = 3297,
        z = 3308,
    },
    {
        pages = { "Asgarnian Ice Dungeon", "Asgarnian Ice Caves" },
        x = 3008,
        z = 3150,
    },
    {
        pages = { "Waterfall Dungeon" },
        x = 2511,
        z = 3464,
    },
    {
        pages = { "Clock Tower Dungeon" },
        x = 2566,
        z = 3242,
        via = "Clock Tower Dungeon zone 1 entrance",
    },
    {
        pages = { "Daemonheim Peninsula Island" },
        x = 3514,
        z = 3668,
    },
    {
        pages = { "Dragontooth Island resource dungeon" },
        x = 3810,
        z = 3530,
    },
    {
        pages = { "Dwarven mines", "Dwarven Mine" },
        x = 3060,
        z = 3378,
        via = "Dwarven mines entrance in Falador",
    },
    {
        pages = { "Mining Guild" },
        x = 3020,
        z = 3339,
    },
    {
        pages = { "Edgeville Dungeon" },
        x = 3097,
        z = 3468,
    },
    {
        pages = { "Edimmu resource dungeon" },
        x = 4604,
        z = 2692,
        level = 1,
    },
    {
        pages = { "Elder God Wars Dungeon", "Senntisten" },
        x = 3332,
        z = 3452,
        via = "Senntisten ancient door",
    },
    {
        pages = { "Flesh-hatcher Mhekarnahz resource dungeon" },
        x = 3354,
        z = 3757,
    },
    {
        pages = { "Forinthry Dungeon" },
        x = 3071,
        z = 3649,
        via = "Forinthry Dungeon south entrance",
    },
    {
        pages = { "Glacor Cave", "Saradomin's hidden cave" },
        x = 2909,
        z = 3839,
    },
    {
        pages = { "Goblin Cave" },
        x = 2626,
        z = 3392,
    },
    {
        pages = { "Gorajo Hoardstalker Dungeon", "Gorajo resource dungeon" },
        x = 4604,
        z = 2719,
        level = 1,
    },
    {
        pages = { "Heroes' Guild Dungeon" },
        x = 2905,
        z = 3516,
        via = "Heroes' Guild access",
    },
    {
        pages = { "Jhallan's resting place" },
        x = 2866,
        z = 3927,
    },
    {
        pages = { "Kal'gerion resource dungeon" },
        x = 3401,
        z = 3665,
    },
    {
        pages = { "Elvarg's lair", "Crandor and Karamja Dungeon" },
        x = 2856,
        z = 3167,
        via = "Karamja Volcano entrance",
    },
    {
        pages = { "Lava Maze Dungeon" },
        x = 3069,
        z = 3857,
        via = "Lava Maze Dungeon entrance inside the maze",
    },
    {
        pages = { "Lumbridge Swamp Caves" },
        x = 3163,
        z = 3166,
    },
    {
        pages = { "Meiyerditch tunnels", "Meiyerditch Dungeon" },
        x = 3508,
        z = 3444,
        via = "Meiyerditch tunnels entrance from Mort Myre Swamp",
    },
    {
        pages = { "Mos Le'Harmless Caves", "Cave of Horrors" },
        x = 3747,
        z = 2973,
    },
    {
        pages = { "Mourner tunnels" },
        x = 2543,
        z = 3327,
    },
    {
        pages = { "Observatory Dungeon" },
        x = 2459,
        z = 3184,
    },
    {
        pages = { "Ogre Enclave" },
        x = 2504,
        z = 3037,
    },
    {
        pages = { "Ripper Demon cave" },
        x = 3353,
        z = 3148,
        via = "Dark Tunnel to the Ripper Demon cave",
    },
    {
        pages = { "Smoke Dungeon" },
        x = 3310,
        z = 2961,
    },
    {
        pages = { "Sophanem Slayer Dungeon" },
        x = 3291,
        z = 2709,
    },
    {
        pages = { "Underground Pass (dungeon)", "Underground Pass" },
        x = 2438,
        z = 3315,
        via = "Underground Pass entrance in West Ardougne",
    },
    {
        pages = { "Varrock Sewers" },
        x = 3237,
        z = 3458,
    },
    {
        pages = { "Waterbirth Island Dungeon" },
        x = 2522,
        z = 3740,
    },
    {
        pages = { "Witchaven Dungeon" },
        x = 2697,
        z = 3283,
    },
    {
        pages = { "Asgarnian Ice Dungeon resource dungeon" },
        parent = "Asgarnian Ice Dungeon",
    },
    {
        pages = { "Baxtorian Falls resource dungeon" },
        parent = "Waterfall Dungeon",
    },
    {
        pages = { "Brimhaven Dungeon resource dungeon" },
        parent = "Brimhaven Dungeon",
    },
    {
        pages = { "Chaos Tunnels resource dungeon" },
        parent = "Chaos Tunnels",
    },
    {
        pages = { "Dwarven Mine resource dungeon" },
        parent = "Dwarven mines",
    },
    {
        pages = { "Edgeville Dungeon chaos druids dungeon" },
        parent = "Edgeville Dungeon",
    },
    {
        pages = { "Edgeville Dungeon hill giant resource dungeon" },
        parent = "Edgeville Dungeon",
    },
    {
        pages = { "Karamja Volcano resource dungeon" },
        parent = "Elvarg's lair",
    },
    {
        pages = { "Mining Guild resource dungeon" },
        parent = "Mining Guild",
    },
    {
        pages = { "Nodon Front" },
        parent = "Elder God Wars Dungeon",
    },
    {
        pages = { "Senntisten Asylum" },
        parent = "Elder God Wars Dungeon",
    },
    {
        pages = { "Taverley blue dragon resource dungeon" },
        parent = "Taverley Dungeon",
    },
    {
        pages = { "Taverley hellhound resource dungeon" },
        parent = "Taverley Dungeon",
    },
    {
        pages = { "Varrock Sewers resource dungeon" },
        parent = "Varrock Sewers",
    },
    {
        pages = { "Fairy ring near Edgeville" },
        x = 3129,
        z = 3496,
        via = "Fairy ring near Edgeville",
        kind = "access",
    },
    {
        pages = { "Abyssal Area" },
        parent = "Fairy ring near Edgeville",
        via = "Fairy ring near Edgeville: use ALR for the Abyssal Area",
        kind = "access",
    },
    {
        pages = { "Dorgesh-Kaan South Dungeon" },
        parent = "Fairy ring near Edgeville",
        via = "Fairy ring near Edgeville: use AJQ for Dorgesh-Kaan South Dungeon",
        kind = "access",
    },
    {
        pages = { "Mazcab" },
        x = 3086,
        z = 2869,
        via = "World window to Mazcab at the desert goebie camp",
        kind = "access",
    },
    {
        pages = { "Braindeath Island 'Rum'-geon" },
        x = 3680,
        z = 3537,
        via = "Pirate Pete: travel to Braindeath Island for the 'Rum'-geon",
        kind = "access",
    },
    {
        pages = { "Brine Rat Cavern" },
        x = 2748,
        z = 3733,
    },
    {
        pages = { "Burthorpe Slayer Cave" },
        x = 2919,
        z = 3466,
    },
    {
        pages = { "Burthorpe Troll Cave" },
        x = 2878,
        z = 3575,
    },
    {
        pages = { "Borehole" },
        x = 2973,
        z = 3434,
    },
    {
        pages = { "Deep Wilderness Dungeon" },
        x = 3045,
        z = 3924,
    },
    {
        pages = { "Camdozaal" },
        x = 3010,
        z = 3498,
    },
    {
        pages = { "Chaos Temple Dungeon" },
        x = 3240,
        z = 3606,
    },
    {
        pages = { "Dragonkin Laboratory" },
        x = 3368,
        z = 3890,
    },
    {
        pages = { "Corporeal Beast's Lair" },
        x = 3212,
        z = 3783,
    },
    {
        pages = { "Crypt (Wilderness)" },
        x = 3286,
        z = 3610,
    },
    {
        pages = { "Elemental Workshop" },
        x = 2710,
        z = 3497,
    },
    {
        pages = { "Falador Mole Lair" },
        x = 2985,
        z = 3384,
    },
    {
        pages = { "Fenkenstrain's Dungeon", "Experiment Cave" },
        x = 3578,
        z = 3526,
    },
    {
        pages = { "Grotworm Lair" },
        x = 2993,
        z = 3238,
    },
    {
        pages = { "Exiled Kalphite Hive" },
        x = 3235,
        z = 2858,
    },
    {
        pages = { "Kalphite Hive" },
        x = 3226,
        z = 3109,
    },
    {
        pages = { "Jadinko Lair" },
        x = 2948,
        z = 2955,
    },
    {
        pages = { "Monastery of Ascension" },
        x = 2500,
        z = 2887,
    },
    {
        pages = { "Poison Waste Slayer Dungeon" },
        x = 2321,
        z = 3100,
    },
    {
        pages = { "Stronghold of Security" },
        x = 3082,
        z = 3421,
    },
    {
        pages = { "Morvran's Dungeon" },
        x = 4563,
        z = 2622,
    },
    {
        pages = { "Sophanem Dungeon" },
        x = 3315,
        z = 2797,
    },
    {
        pages = { "Temple of Ikov (dungeon)" },
        x = 2677,
        z = 3405,
    },
    {
        pages = { "Snake pit", "Crash Island Dungeon" },
        x = 2922,
        z = 2722,
    },
    {
        pages = { "The Skullery" },
        x = 3091,
        z = 3277,
    },
    {
        pages = { "The Empty Throne Room" },
        x = 3374,
        z = 3402,
    },
    {
        pages = { "The Shadow Reef" },
        x = 3511,
        z = 3693,
    },
    {
        pages = { "Shilo Village underground mine" },
        x = 2824,
        z = 3000,
    },
    {
        pages = { "Living Rock Caverns" },
        parent = "Dwarven mines",
    },
    {
        pages = { "Gemstone cavern" },
        parent = "Shilo Village underground mine",
    },
}
