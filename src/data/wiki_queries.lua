-- api query paths for the wiki. bucket is the wikis structured data store, it use its
-- infobox_monster and infobox_item tables. parse gives us a pages rendered html

local url = require("src/utils/url")

local queries = {}

function queries.bucket(query)
    return url.query({ action = "bucket", format = "json", query = query })
end

function queries.monster(field, value)
    local query = "bucket('infobox_monster').select('page_name','json').where("
        .. url.literal(field)
        .. ","
        .. url.literal(value)
        .. ").limit(10).run()"

    return queries.bucket(query)
end

function queries.page(title)
    return url.query({
        action = "parse",
        format = "json",
        formatversion = 2,
        page = title,
        prop = "text",
    })
end

function queries.items(names)
    local conditions = {}

    for _, name in ipairs(names) do
        conditions[#conditions + 1] = "{'page_name'," .. url.literal(name) .. "}"
    end

    local query = "bucket('infobox_item').select('page_name','item_id').where(bucket.Or("
        .. table.concat(conditions, ",")
        .. ")).limit(500).run()"

    return queries.bucket(query)
end

return queries
