-- areas that have their own map but whose other floors are drawn on a shared one. the
-- bounds come from map 41, theyre only for working out which area youre in and dont change
-- any coordinate conversion
return {
    strict = { [41] = true },
    shared = { [0] = true, [13] = true, [31] = true, [41] = true, [136] = true },
    [266] = {
        { 0, 4, 4672, 5440, 4735, 5503 },
        { 0, 4, 4608, 5376, 4671, 5503 },
    },
    [267] = { { 0, 4, 4672, 5568, 4735, 5631 } },
}
