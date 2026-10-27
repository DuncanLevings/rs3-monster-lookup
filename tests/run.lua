local root = arg[0]:match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
package.path = root .. "/?.lua;" .. package.path

-- the client gives plugins a global log, plain lua doesnt. specs that check messages pass
-- their own in, everything else just needs it to exist
log = function(...) end

MonsterDataCore = require("tests/support/core_loader").new().export

local lu = require("luaunit")
local create_npc_menu_suite = require("tests/npc_menu_spec")
local create_window_suite = require("tests/monster_window_spec")
local create_price_suite = require("tests/price_format_spec")
local create_wiki_suite = require("tests/wiki_spec")
local create_cache_suite = require("tests/cache_spec")
local create_rarity_suite = require("tests/rarity_format_spec")
local create_clock_suite = require("tests/cache_clock_spec")
local create_json_suite = require("tests/json_spec")
local create_icons_suite = require("tests/stat_icons_spec")
local create_drop_search_suite = require("tests/drop_search_spec")
local create_drop_notes_suite = require("tests/drop_notes_spec")
local create_drop_table_suite = require("tests/drop_table_spec")
local create_prices_suite = require("tests/prices_spec")
local create_bucket_data_suite = require("tests/bucket_data_spec")
local create_preview_suite = require("tests/monster_preview_spec")
local create_kill_value_suite = require("tests/kill_value_spec")
local create_lookup_suite = require("tests/wiki_lookup_spec")
local create_locations_view_suite = require("tests/locations_view_spec")
local create_monster_search_suite = require("tests/monster_search_spec")
local create_search_ui_suite = require("tests/search_ui_spec")
local create_marker_suite = require("tests/location_marker_spec")
local create_refresh_app_suite = require("tests/refresh_app_spec")
local create_navigation_suite = require("tests/location_navigation_spec")
local create_routing_suite = require("tests/dungeon_routing_spec")
local create_spawns_suite = require("tests/location_spawns_spec")
local create_info_components_suite = require("tests/info_components_spec")
local create_tab_components_suite = require("tests/tab_components_spec")
local runner = lu.LuaUnit.new()

runner:runSuiteByInstances({
    { "TestCoreDependency", require("tests/core_dependency_spec")(root) },
    { "TestInfoComponents", create_info_components_suite(root) },
    { "TestTabComponents", create_tab_components_suite(root) },
    { "TestLocationSpawns", create_spawns_suite(root) },
    { "TestDungeonRouting", create_routing_suite(root) },
    { "TestLocationNavigation", create_navigation_suite(root) },
    { "TestRefreshApp", create_refresh_app_suite(root) },
    { "TestLocationMarker", create_marker_suite(root) },
    { "TestMonsterSearch", create_monster_search_suite(root) },
    { "TestSearchUI", create_search_ui_suite(root) },
    { "TestLocationsView", create_locations_view_suite(root) },
    { "TestWikiLookup", create_lookup_suite(root) },
    { "TestDropNotes", create_drop_notes_suite(root) },
    { "TestDropTable", create_drop_table_suite(root) },
    { "TestPrices", create_prices_suite(root) },
    { "TestBucketData", create_bucket_data_suite() },
    { "TestMonsterPreview", create_preview_suite(root) },
    { "TestKillValue", create_kill_value_suite() },
    { "TestDropSearch", create_drop_search_suite(root) },
    { "TestNpcMenu", create_npc_menu_suite(root) },
    { "TestMonsterWindow", create_window_suite(root) },
    { "TestPriceFormat", create_price_suite() },
    { "TestWiki", create_wiki_suite(root) },
    { "TestCache", create_cache_suite(root) },
    { "TestRarityFormat", create_rarity_suite() },
    { "TestCacheClock", create_clock_suite(root) },
    { "TestJson", create_json_suite() },
    { "TestStatIcons", create_icons_suite(root) },
})
os.exit(runner.result.notSuccessCount)
