-- local display-name matching, shared by drops and monster search
-- with * or ? its a wildcard match on the item name

local item_search = {}

local function normalize(value)
    return value:lower():gsub("[^%w%s]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
end

-- only * and ? have special meaning; everything else is literal, not a Lua pattern
-- remember the last star so a mismatch can extend its match without recursive calls
local function wildcard_matches(name, pattern)
    local position, token = 1, 1
    local star, retry

    while position <= #name do
        local character = pattern:sub(token, token)

        if character == "?" or character == name:sub(position, position) then
            position, token = position + 1, token + 1
        elseif character == "*" then
            star, retry = token, position
            token = token + 1
        elseif star then
            retry = retry + 1
            position, token = retry, star + 1
        else
            return false
        end
    end

    while pattern:sub(token, token) == "*" do
        token = token + 1
    end

    return token > #pattern
end

local function is_subsequence(word, query)
    local position = 1

    for index = 1, #query do
        local found = word:find(query:sub(index, index), position, true)

        if not found then
            return false
        end

        position = found + 1
    end

    return true
end

-- typo tolerance on very short queries produces too many unrelated matches
local function differs_by_one_edit(word, query)
    if #query < 4 or math.abs(#word - #query) > 1 then
        return false
    end

    local left, right, edits = 1, 1, 0

    while left <= #word and right <= #query do
        if word:sub(left, left) == query:sub(right, right) then
            left, right = left + 1, right + 1
        else
            edits = edits + 1

            if edits > 1 then
                return false
            end

            if #word >= #query then
                left = left + 1
            end

            if #query >= #word then
                right = right + 1
            end
        end
    end

    return edits + (#word - left + 1) + (#query - right + 1) <= 1
end

local function matches_token(words, token)
    for _, word in ipairs(words) do
        if is_subsequence(word, token) or differs_by_one_edit(word, token) then
            return true
        end
    end

    return false
end

-- prepare each item once, then reuse it as the player types new queries
function item_search.prepare(name)
    local normalized = normalize(name)
    local words = {}

    for word in normalized:gmatch("%S+") do
        words[#words + 1] = word
    end

    return { name = name:lower(), normalized = normalized, words = words }
end

-- build one matcher per query, shared by every row. wildcard queries bypass fuzzy
-- matching; otherwise all query tokens must match, in any order
function item_search.compile(query)
    query = query:sub(1, 128):lower():match("^%s*(.-)%s*$")

    if query:find("[*?]") then
        local pattern = "*" .. query .. "*"

        return function(item)
            return wildcard_matches(item.name, pattern)
        end
    end

    local normalized = normalize(query)
    local tokens = {}

    for token in normalized:gmatch("%S+") do
        tokens[#tokens + 1] = token
    end

    return function(item)
        if item.normalized:find(normalized, 1, true) then
            return true
        end

        for _, token in ipairs(tokens) do
            if not matches_token(item.words, token) then
                return false
            end
        end

        return true
    end
end

return item_search
