-- turns wiki html (and the odd bit of wikitext in infobox values) into plain text
-- tags are stripped and < > removed after decoding so wiki text cant inject game formatting
-- tags like <col> into our labels

local unicode = require("src/utils/unicode")

local wiki_text = {}
local ENTITIES = {
    amp = "&",
    lt = "<",
    gt = ">",
    quot = '"',
    apos = "'",
    nbsp = " ",
    ndash = "–",
    mdash = "—",
    minus = "-",
    times = "x",
    hellip = "...",
}

local function decode_entity(entity)
    if ENTITIES[entity] then
        return ENTITIES[entity]
    end

    local code = entity:match("^#x(%x+)$")
    code = code and tonumber(code, 16) or tonumber(entity:match("^#(%d+)$"))

    local decoded = unicode.from_codepoint(code)

    if decoded then
        return decoded
    end

    return "&" .. entity .. ";"
end

function wiki_text.decode(text)
    -- extra parens so only the string comes back, not gsubs match count as well
    return ((text or ""):gsub("&([#%w]+);", decode_entity))
end

function wiki_text.plain(text)
    text = (text or ""):gsub("<sup.-</sup>", "")
    text = text:gsub("<br%s*/?>", " "):gsub("<[^>]*>", "")

    text = wiki_text.decode(text)
    text = text:gsub("%[%[([^]|]+)|([^]]+)%]%]", "%2"):gsub("%[%[([^]]+)%]%]", "%1")
    text = text:gsub("[<>]", ""):gsub("%s+", " ")

    return text:match("^%s*(.-)%s*$")
end

-- reads one attribute from a tag's attribute string. the frontier stops "id" matching the
-- end of something like data-id, and the name is escaped so dashes work as written
function wiki_text.attribute(attributes, name)
    local pattern = "%f[%w%-]" .. name:gsub("%p", "%%%0") .. '="([^"]*)"'
    return wiki_text.decode(attributes:match(pattern) or "")
end

-- wiki titles are the same page whatever the case or with _ for spaces, so lookups by title
-- go through this. "Lumbridge_Swamp_Caves " -> "lumbridge swamp caves"
function wiki_text.page_key(title)
    return (type(title) == "string" and title or "")
        :gsub("_", " ")
        :gsub("%s+", " ")
        :match("^%s*(.-)%s*$")
        :lower()
end

function wiki_text.price(text)
    text = wiki_text.plain(text):gsub(",", ""):gsub("–", "-")
    local minimum, maximum = text:match("^%s*(%d+)%s*%-%s*(%d+)%s*$")

    if minimum then
        return { minimum = tonumber(minimum), maximum = tonumber(maximum) }
    end

    return tonumber(text)
end

return wiki_text
