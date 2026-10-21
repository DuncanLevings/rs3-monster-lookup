-- Exact Wiki page matches only. Slayer categories can include creatures whose souls
-- produce a different dungeon variant, so never infer eligibility from a shared name.
local data = require("src/data/slayer_codex_data")

local codex = {}
local by_page

local function page_key(title)
    return title:gsub("_", " "):lower()
end

function codex.find(title)
    if not by_page then
        by_page = {}

        for _, entry in ipairs(data.entries) do
            for _, page in ipairs(entry.pages) do
                local key = page_key(page)

                -- A page listed under several souls needs more precise identification.
                if by_page[key] ~= nil then
                    by_page[key] = false
                else
                    by_page[key] = entry
                end
            end
        end
    end

    return by_page[page_key(title)] or nil
end

function codex.source_note()
    return "Slayer Codex reference saved " .. data.retrieved .. "; not live collection progress."
end

return codex
