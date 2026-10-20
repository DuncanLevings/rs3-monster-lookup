# Monster Lookup

Check monster drops without leaving the game. Right-click a monster and choose **View drops**
to see its loot, drop rates, quantities and GE guide prices from the RuneScape Wiki.

Collapse categories individually or use **Collapse all** above the tables. The window can be
moved and resized, and remembers where you left it. Hover over a rarity with a note marker for
the details, or read the numbered notes below the table.

The **Monster info** tab groups combat details, offensive and defensive stats, weaknesses,
base hit chance, immunities and Slayer requirements. If the Wiki lists several variants or
boss modes, use the variant selector to compare their stats. Missing values show as **Unknown**.

Monster Lookup shows all the drop tables listed on a monster's Wiki page, including other
variants or boss modes. Check the headings and notes for the conditions that apply to your fight.

## Settings

Open **Plugin Hub > Manage** and click Monster Lookup's settings cog to choose how often saved
data should be refreshed: 15 minutes, 1 hour, 6 hours or 24 hours. The default is 1 hour. This
checks for updates when you open a monster; it does not fetch pages in the background. You can
also switch numeric rarities from fractions to percentages.

## Requirements

- [PrettyUI](https://prettyui.j3.gg/), installed from the Plugin Hub.
- The **HTTP access** permission, used only to read the RuneScape Wiki at
  `https://runescape.wiki`. Without it the window opens and explains how to allow access.

## Data source

Information comes from the [RuneScape Wiki](https://runescape.wiki/). Prices reflect the values
on the Wiki page and may differ from what an item actually buys or sells for. Items that cannot
be traded on the GE show **Not sold**, rather than treating an alchemy value as a GE price.
