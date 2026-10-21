-- Scale a high-contrast X in map tiles so its screen size stays legible.
local map_symbol = {}
local SYMBOL_PIXELS = 36

local function geometry(previous_zoom)
    local zoom_var = var and var.VarClient and var.VarClient.WORLDMAP_ZOOM
    local zoom = zoom_var and zoom_var.value
    if type(zoom) ~= "number" or zoom ~= zoom or zoom <= 0 or zoom > 1000 then
        zoom = previous_zoom or 100
    end
    -- The client's 37% label represents 37.5% (1.5 pixels per tile).
    local pixels_per_tile = zoom == 37 and 1.5 or zoom / 25
    -- At wide zooms the X competes with dense map icons and place names.
    local emphasis = math.max(0, math.min(1, (100 - zoom) / 50))
    local size = SYMBOL_PIXELS + 24 * emphasis
    local stroke = 4 + 4 * emphasis
    local outline = 2 + emphasis
    local outer = math.max(2, math.floor(size / 2 / pixels_per_tile + 0.5))
    local arm = math.max(1, math.min(outer - 1, math.floor(stroke / pixels_per_tile + 0.5)))
    local border = math.max(1, math.floor(outline / pixels_per_tile + 0.5))
    return outer, arm, border, zoom
end

local function x_mark(outer, arm)
    return {
        -outer,
        -outer + arm,
        -outer + arm,
        -outer,
        0,
        -arm,
        outer - arm,
        -outer,
        outer,
        -outer + arm,
        arm,
        0,
        outer,
        outer - arm,
        outer - arm,
        outer,
        0,
        arm,
        -outer + arm,
        outer,
        -outer,
        outer - arm,
        -arm,
        0,
    }
end

local function remove_layers(layers)
    for _, layer in ipairs(layers or {}) do
        if layer.accepted then
            layer.accepted = false
            -- Native bindings need a Lua caller between themselves and pcall.
            pcall(function()
                HintList.RemovePolygon(layer.args.name)
            end)
        end
    end
end

function map_symbol.new(name, target)
    return {
        name = name,
        -- The main map uses the building's surface position even for upstairs targets.
        coord = CoordGrid.new((target.x << 14) | target.z),
        layers = {},
        revision = 0,
    }
end

function map_symbol.destroy(symbol)
    remove_layers(symbol.layers)
    symbol.visible = false
end

function map_symbol.refresh(symbol)
    local outer, arm, border, zoom = geometry(symbol.zoom)
    local key = outer .. ":" .. arm .. ":" .. border
    symbol.zoom = zoom
    if symbol.key == key then
        return symbol.visible
    end

    remove_layers(symbol.layers)
    -- Keep the previous arguments alive through the next update interval.
    symbol.previous_layers = symbol.layers
    symbol.layers = {}
    symbol.revision = symbol.revision + 1
    symbol.key, symbol.visible = key, false
    for index, shape in ipairs({
        { outer = outer + border, arm = arm + border, colour = 0x101820FF },
        { outer = outer, arm = arm, colour = 0xFF4040FF },
    }) do
        local layer = {
            args = {
                name = symbol.name .. "_" .. symbol.revision .. "_" .. index,
                coordGrid = symbol.coord,
                polygon = x_mark(shape.outer, shape.arm),
                drawOnWorldMap = true,
                drawOnMiniMap = false,
                fillRGBA = shape.colour,
                outlineRGBA = shape.colour,
            },
        }
        symbol.layers[#symbol.layers + 1] = layer
        local ok, accepted = pcall(function()
            local result = HintList.AddPolygon(layer.args)
            return result
        end)
        layer.accepted = ok and accepted == true
        if not layer.accepted then
            remove_layers(symbol.layers)
            return false
        end
    end
    symbol.visible = true
    return true
end

return map_symbol
