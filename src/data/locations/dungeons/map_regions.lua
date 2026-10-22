-- Native membership for dedicated views whose other floors appear in a shared
-- map. These bounds come from map 41; they do not change diagram conversions.
return {
    strict = { [41] = true },
    shared = { [0] = true, [13] = true, [31] = true, [41] = true, [136] = true },
    [266] = {
        { 0, 4, 4672, 5440, 4735, 5503 },
        { 0, 4, 4608, 5376, 4671, 5503 },
    },
    [267] = { { 0, 4, 4672, 5568, 4735, 5631 } },
}
