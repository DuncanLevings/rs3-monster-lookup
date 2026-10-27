# Monster Lookup

Monster drops, stats and locations inside RuneScape 3. Right-click a monster and choose
**View drops**, or open Search from the plugin ribbon or Plugin Hub settings.

## Features

- **Drops:** categories, quantities, rarities, conditions, item icons and estimated kill value.
  Search within drops and choose the supported boss mode or enrage.
- **Monster info:** variant selection, weaknesses, susceptibilities, immunities and collapsible
  Slayer/detailed-stat groups. On wider windows, a model preview supports zoom and, where
  available, dragging to turn, tilt or shift its vertical framing.
- **Locations:** access requirements, spawn counts and manually selected markers. Supported
  dungeon connections guide through known entrances and floor transitions; these are waypoints,
  not calculated walking paths. Unsupported routes are explained instead of guessed.
- **Search:** monster names, dropped items and stat rankings. Name/item searches support partial
  words, small typos and wildcards. Drops and stat searches use the bundled reference dataset.
- **Preferences:** menu colour, rarity display, expanded groups and window placement persist locally.

## Installation and data

PrettyUI is required (Plugin Hub ID `6398181`). The static Monster Data Core code and records
are embedded in this plugin; **a separate Monster Data Core installation is not required**.
The standalone data-library repository remains available for developers interested in it.

Optional GE Price Library (`6414886`) supplies live traded prices where available. Without it,
prices come from the bundled dataset. The price library manages its own network access.
Coins count as 1 gp each; unknown rates, missing prices and conditional drops can make totals
incomplete, so estimates are labelled accordingly.

Monster Lookup makes no Wiki requests and requests no permissions. Unknown monsters are not
guessed: update the plugin or search for a more specific name. Reference data can become outdated;
quest/event-only encounters and other non-repeatable monsters may be deliberately excluded.

Closing the lookup hides it for reuse. Logging out or disabling the plugin destroys its owned
windows and clears its active marker. Monster models and imagery come from the client.
No collected Slayer souls are tracked.

## Data and privacy

Local settings and window placement are saved between sessions. Selected monsters and markers
are session state. Monster Lookup sends no player information to a server and never performs
gameplay actions. Static reference information is credited to RuneScape Wiki contributors;
see [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt).

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for the runtime flow, source layout, checks and packaging.
The public component/extension API and Wiki/cache implementation are maintained on separate
feature branches; this main version is a standalone player-facing plugin.
