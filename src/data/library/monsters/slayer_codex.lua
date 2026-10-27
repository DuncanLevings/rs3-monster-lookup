-- Exact Wiki page matches only. Slayer categories can include creatures whose souls
-- produce a different dungeon variant, so never infer eligibility from a shared name.
local data = require("src/data/library/monsters/slayer_codex_data")
local wiki_text = require("src/data/library/utils/wiki_text")

local codex = {}
local by_page

function codex.find(title)
    if not by_page then
        by_page = {}

        for _, entry in ipairs(data.entries) do
            for _, page in ipairs(entry.pages) do
                local key = wiki_text.page_key(page)

                -- a page listed under several souls cant be told apart by page alone, so
                -- it gets no match
                if by_page[key] ~= nil then
                    by_page[key] = false
                else
                    by_page[key] = entry
                end
            end
        end
    end

    return by_page[wiki_text.page_key(title)] or nil
end

function codex.source_note()
    return "Slayer Codex reference saved " .. data.retrieved .. "; not live collection progress."
end

return codex
