-- api query paths for the wiki. everything comes from bucket, the wikis structured data store:
-- infobox_monster for stats, dropsline for drops, coordinates for spawns and infobox_item for
-- item ids

local url = require("src/utils/url")

local queries = {}

local function build_query(parameters)
    parameters.curtimestamp = 1
    parameters.maxlag = 5
    return url.query(parameters)
end

function queries.time()
    return build_query({ action = "query", format = "json", formatversion = 2, curtimestamp = 1 })
end

function queries.bucket(query)
    return build_query({ action = "bucket", format = "json", query = query })
end

function queries.monster(field, value)
    local query = "bucket('infobox_monster').select('page_name','json').where("
        .. url.literal(field)
        .. ","
        .. url.literal(value)
        .. ").limit("
        .. (field == "page_name" and 100 or 10)
        .. ").run()"

    return queries.bucket(query)
end

-- every drop row for one page, the biggest bosses have around 200 so this leaves plenty of room
function queries.drops(title)
    local query = "bucket('dropsline').select('item_name','drop_json','rare_drop_table').where("
        .. "'page_name',"
        .. url.literal(title)
        .. ").limit(1000).run()"

    return queries.bucket(query)
end

-- map pins for one page, used for the locations tab
function queries.spawns(title)
    local query = "bucket('coordinates').select('mapid','plane','x','y').where("
        .. "'page_name',"
        .. url.literal(title)
        .. ").limit(500).run()"

    return queries.bucket(query)
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
