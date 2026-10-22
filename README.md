# Monster Lookup

View monster drops, stats and locations without leaving the game. Right-click a monster and choose **View drops**, or open Monster Lookup from the **Plugins** ribbon or **Plugin Hub > Manage** to search by name.

## Drops

Browse items, quantities, drop rates, GE guide prices and notes from the [RuneScape Wiki](https://runescape.wiki/). Search drops, collapse categories and choose a boss mode or enrage where available. The controls stay visible while you scroll. Expand **Notes** for drop conditions and hover over marked rarities for details.

Above the tables is the average value of one kill for the selected mode or enrage, worked out the same way as the Wiki: each drop's price times its average quantity, chance and rolls, added up. It uses live GE prices when the GE Price Library is installed, coins count as 1 gp each and untradeable items as 0. Drops with a rarity like Common or Varies, no price, or an Always chance that only happens in some cases are left out, and the total is then marked as an estimate.

## Monster info and locations

See weaknesses, behaviour and immunities at a glance. Expand **Slayer** for task and player-owned Slayer Dungeon details, or **Detailed stats** for combat information. Both sections remember your preference. Use the variant selector where available.

On wider windows a 3D model of the monster sits beside its stats. Drag to turn it round or tilt it, hold Shift and drag to move it up or down, and scroll to zoom.

The **Locations** tab lists spawn locations, levels, access requirements and spawn counts. Use **Mark** for world locations or **Entrance** for dungeon access. Supported routes continue through parent portals, known exits and floor transitions toward a spawn on your current floor when available. After entering a known dungeon, the marker clears if interior guidance is unavailable. Unknown areas pause guidance. Waypoints do not calculate a walking path. Only the final destination clears within 16 tiles on the matching floor.

## Search and settings

Choose **Search monsters** and enter at least three characters. Up to 50 results are shown. Search supports partial names, small typos, `*` and `?`. Include a location to distinguish variants, such as **Bloodveld God Wars**. Select a result to open its lookup. Search and lookup windows remember their position and size.

The dropdown beside the search box switches what you search:

- **Monsters** finds monsters by name or location.
- **Drops** finds a dropped item and lists the monsters that drop it, best chance first (up to 50). Selecting one opens its drops already filtered to that item, in the right boss mode.
- **Top stats** ranks monsters by combat XP, combat XP per life point, Slayer XP, life points, combat level or max hit. Bosses, their minions, elite dungeon and Sanctum fights and elite Slayer spawns are hidden unless you include them or choose bosses only. Optional maximum combat and Slayer levels and a name or Slayer category filter narrow the list. Selecting one opens its Monster info.

Drops and Top stats cover the bundled monsters only.

Choose **Customize** to change the View drops menu colour, display numeric drop rates as percentages, or refresh a saved monster. Saved data refreshes when opened after two weeks; manual refresh clears matching variants and fetches the selected monster, with a shared one-hour cooldown. Saved results remain available when the Wiki cannot be reached. With the optional [GE Price Library](https://github.com/CerenMD/ge-prices-library) plugin installed, GE prices are live traded prices; without it they are the Wiki's GE prices from when the bundled data was built.

## Requirements and data

Install [PrettyUI](https://prettyui.j3.gg/) from the Plugin Hub and allow HTTP access to the RuneScape Wiki when prompted. Typing a search stays on your device. Most monsters are bundled with the plugin and open without contacting the Wiki; only monsters added after the bundle date are looked up on the Wiki. Those lookups use the Wiki's structured Bucket data, which has no drop categories or location names, so they show one drop list per mode (plus the rare drop table) and one location row per map. Live prices come from the GE Price Library, which makes its own requests. Saved results, settings and window positions stay on your device. Slayer Dungeon information does not track your collected souls.
