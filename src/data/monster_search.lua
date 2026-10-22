-- Local name search: typing never sends a request. Result selection uses the normal lookup.
-- the "items" kind searches dropped item names instead, and an exact item name lists the
-- monsters that drop it (src/data/drop_index.lua)
local names = require("src/data/monster_names")
local drop_index = require("src/data/drop_index")
local cache = require("src/data/monster_cache")
local identity = require("src/utils/monster_identity")
local matcher = require("src/utils/item_search")
local clock = require("src/utils/cache_clock")

local search = {}
local next_subscription = 0
local DEBOUNCE_TICKS = math.ceil(0.15 * clock.TICKS_PER_SECOND)
local ROWS_PER_TICK = 250
local MAX_RESULTS = 50
local LEGACY_READS_PER_TICK = 3

local function normalize(text)
	return tostring(text or ""):sub(1, 80):gsub("[%c]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
end

local function plural(count, word)
	return count .. " " .. word .. (count == 1 and "" or "s")
end

local function build_item_index()
	local entries, exact = {}, {}

	for position, item in ipairs(drop_index.items()) do
		local entry = {
			item = position,
			item_name = item.name,
			label = item.name .. " - " .. plural(item.count, "monster"),
			key = item.name:lower(),
			saved = false,
			resolved = true,
			monster = { name = item.name },
		}
		entries[#entries + 1] = entry
		exact[entry.key] = entry
	end

	return entries, exact
end

-- results for an exact item name: who drops it, best chance first
local function dropper_results(entry)
	local count = drop_index.items()[entry.item].count
	local results = {}

	for _, dropper in ipairs(drop_index.droppers(entry.item)) do
		local name = dropper.mode and (dropper.title .. " (" .. dropper.mode .. ")") or dropper.title
		local quantity = dropper.quantity ~= "1" and (" | x" .. dropper.quantity) or ""
		results[#results + 1] = {
			label = name .. " - " .. dropper.rate .. quantity,
			key = dropper.title:lower(),
			monster = { name = dropper.title, wiki_title = dropper.title },
			-- opens the monster on this item, in the mode the chance is for
			focus = { item = entry.item_name, mode = dropper.mode },
		}
	end

	local name = entry.item_name

	-- only if the index and the bundle titles dont agree, eg a half updated install
	if #results == 0 then
		return results, "No monsters in the saved data drop " .. name .. "."
	end

	if #results < count then
		return results,
			"Showing the " .. #results .. " best chances of the " .. count .. " monsters that drop " .. name .. "."
	end

	local verb = count == 1 and " drops " or " drop "
	return results, plural(count, "monster") .. verb .. name .. ", best chance first."
end

local function build_index(saved_only)
	local entries, seen = {}, {}
	local function add(monster, saved)
		local key = identity.key(monster)

		if seen[key] then
			seen[key].saved = seen[key].saved or saved
		else
			local entry = {
				monster = monster,
				label = monster.name,
				key = key,
				saved = saved,
				summary = monster.summary,
				resolved = monster.summary ~= nil,
			}
			seen[key] = entry
			entries[#entries + 1] = entry
		end
	end

	if not saved_only then
		for _, title in ipairs(names) do
			add({ name = title, wiki_title = title }, false)
		end
	end

	for _, monster in ipairs(cache.list(saved_only)) do
		-- NPC names and levels do not identify their Wiki page (eg Bloodveld).
		-- Keep the picker page-based; clicked NPCs retain their separate cache identity.
		if saved_only then
			if not require("src/data/bundle").find(monster) then
				add(monster, true)
			end
		elseif monster.wiki_title and seen[identity.key(monster)] then
			add({ name = monster.wiki_title, wiki_title = monster.wiki_title }, true)
		end
	end
	return entries
end

local function score(entry, query)
	local name = entry.prepared.name
	local rank = name == query and 0 or name:sub(1, #query) == query and 10 or name:find(query, 1, true) and 20 or 30
	return rank + (entry.saved and 0 or 1)
end

local function insert_match(matches, entry, rank)
	local candidate = { entry = entry, score = rank }
	local position = #matches + 1

	for index, current in ipairs(matches) do
		if rank < current.score or (rank == current.score and entry.key < current.entry.key) then
			position = index
			break
		end
	end

	if position <= MAX_RESULTS then
		table.insert(matches, position, candidate)

		if #matches > MAX_RESULTS then
			table.remove(matches)
		end
	end
end

local function publish(state, results, message)
	state.results = results
	state.on_update(results, message)
end

local function prepare_saved_entry(entry)
	local summary = entry.summary

	if not summary then
		return false
	end

	if entry.base_label then
		entry.label = entry.base_label
		return true
	end

	entry.label = summary.title

	if summary.variant and summary.variant ~= "" and summary.variant ~= summary.title then
		entry.label = entry.label .. " - " .. summary.variant
	end

	entry.base_label = entry.label
	local searchable = entry.label .. (summary.level and (" Level " .. summary.level) or "")
	entry.prepared = matcher.prepare(searchable)
	return true
end

local function distinguish_saved_results(results)
	local counts = {}

	for _, entry in ipairs(results) do
		counts[entry.label] = (counts[entry.label] or 0) + 1
	end

	local variants = {}

	for _, entry in ipairs(results) do
		local label = entry.label

		if counts[label] > 1 then
			variants[label] = (variants[label] or 0) + 1
			entry.label = label
				.. " - "
				.. (entry.monster.wiki_title and "All variants" or "Variant " .. variants[label])
		end
	end
end

local function scan_batch(state)
	local last = math.min(state.position + ROWS_PER_TICK - 1, #state.index)

	local reads = 0

	for index = state.position, last do
		local entry = state.index[index]

		if state.saved_only and not entry.resolved then
			if reads >= LEGACY_READS_PER_TICK then
				break
			end

			entry.summary = cache.describe(entry.monster)
			entry.resolved = true
			reads = reads + 1
		end

		local available = not state.saved_only or prepare_saved_entry(entry)
		entry.prepared = entry.prepared or matcher.prepare(entry.monster.name)

		if available and state.matches(entry.prepared) then
			insert_match(state.top, entry, score(entry, state.key))
		end

		state.position = index + 1
	end

	if #state.index == 0 then
		state.position = 1
	end

	if state.position <= #state.index then
		return
	end

	state.position = nil
	local results = {}

	for _, candidate in ipairs(state.top) do
		results[#results + 1] = candidate.entry
	end

	if state.saved_only then
		distinguish_saved_results(results)
	end

	if state.items then
		publish(
			state,
			results,
			#results == 0 and "No dropped items match your search." or "Select an item to see which monsters drop it."
		)
		return
	end

	publish(
		state,
		results,
		#results == 0 and "No monsters match your search."
			or state.saved_only and "Select a monster to refresh its Wiki data."
			or "Select a monster."
	)
end

---@param on_update fun(results: table[], message: string)
---@param saved_only boolean? only monsters with saved lookups, for refreshing them
---@param kind "items"? search dropped items instead of monsters
function search.new(on_update, saved_only, kind)
	next_subscription = next_subscription + 1
	local subscription = "monster_lookup_search_" .. next_subscription
	local state = {
		tick = 0,
		on_update = on_update,
		results = {},
		saved_only = saved_only == true,
		items = kind == "items",
	}
	local controller = {}

	function controller.get_query()
		return state.query or ""
	end

	function controller.set_query(text)
		if not state.started then
			return
		end

		local query = normalize(text)
		local key = query:lower()

		if key == state.key then
			return
		end

		state.query, state.key, state.due, state.position = query, key, nil, nil
		local exact = state.items and state.exact[key]

		if exact then
			publish(state, dropper_results(exact))
		elseif #query >= 3 or (state.saved_only and #query > 0) then
			state.matches = matcher.compile(query)
			state.due = state.tick + DEBOUNCE_TICKS
			publish(state, {}, state.items and "Searching items..." or "Searching names...")
		else
			publish(
				state,
				{},
				state.saved_only and "Search saved Wiki monsters by name or location."
					or state.items and "Type at least 3 characters to search dropped items."
					or "Type at least 3 characters to search monsters."
			)
		end
	end

	function controller.stop()
		state.started = false
		state.due, state.position = nil, nil
		Event.Logic.Unsubscribe(subscription)
	end

	function controller.choose(result)
		if state.started then
			-- Only buttons from the current results can select a monster.
			for _, current in ipairs(state.results) do
				if current == result then
					-- picking an item from the list asks for its droppers, the search keeps
					-- going and the window fills the field with the full name
					if result.item then
						return { item = result.item_name }
					end

					local monster = result.monster
					controller.stop()
					return {
						name = monster.name,
						npc_id = monster.npc_id,
						wiki_title = monster.wiki_title,
						focus = result.focus,
					}
				end
			end
		end
	end

	function controller.start()
		if state.started then
			return
		end

		if state.items then
			state.index, state.exact = build_item_index()
		else
			state.index = build_index(state.saved_only)
		end
		state.started = true
		Event.Logic.Subscribe(subscription, function()
			state.tick = state.tick + 1

			if state.due and state.tick >= state.due then
				state.due = nil
				state.position, state.top = 1, {}
			end

			if state.position then
				scan_batch(state)
			end
		end)
		local previous = state.query or ""
		state.key = nil
		controller.set_query(previous)
	end

	return controller
end

return search
