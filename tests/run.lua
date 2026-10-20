local root = arg[0]:match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
package.path = root .. "/?.lua;" .. package.path

local lu = require("luaunit")
local create_npc_menu_suite = require("tests/npc_menu_spec")
local create_window_suite = require("tests/monster_window_spec")
local create_price_suite = require("tests/price_format_spec")
local create_wiki_suite = require("tests/wiki_spec")
local create_cache_suite = require("tests/cache_spec")
local create_rarity_suite = require("tests/rarity_format_spec")
local create_clock_suite = require("tests/cache_clock_spec")
local create_json_suite = require("tests/json_spec")
local create_info_suite = require("tests/monster_info_spec")
local create_icons_suite = require("tests/stat_icons_spec")
local create_search_suite = require("tests/item_search_spec")
local create_drop_search_suite = require("tests/drop_search_spec")
local create_drop_notes_suite = require("tests/drop_notes_spec")
local runner = lu.LuaUnit.new()

runner:runSuiteByInstances({
    { "TestDropNotes", create_drop_notes_suite(root) },
    { "TestItemSearch", create_search_suite() },
    { "TestDropSearch", create_drop_search_suite(root) },
    { "TestNpcMenu", create_npc_menu_suite(root) },
    { "TestMonsterWindow", create_window_suite(root) },
    { "TestPriceFormat", create_price_suite() },
    { "TestWiki", create_wiki_suite(root) },
    { "TestCache", create_cache_suite(root) },
    { "TestRarityFormat", create_rarity_suite() },
    { "TestCacheClock", create_clock_suite(root) },
    { "TestJson", create_json_suite() },
    { "TestMonsterInfo", create_info_suite() },
    { "TestStatIcons", create_icons_suite(root) },
})
os.exit(runner.result.notSuccessCount)
