-- the client doesnt have a utf8 library so this is needed to encode codepoints
-- needed for numeric html entities like &#8211;

local unicode = {}

function unicode.from_codepoint(code)
    if
        type(code) ~= "number"
        or code % 1 ~= 0
        or code < 0
        or code > 0x10FFFF
        or (code >= 0xD800 and code <= 0xDFFF)
    then
        return nil
    end

    if code <= 0x7F then
        return string.char(code)
    end

    if code <= 0x7FF then
        return string.char(0xC0 | (code >> 6), 0x80 | (code & 0x3F))
    end

    if code <= 0xFFFF then
        return string.char(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F))
    end

    return string.char(
        0xF0 | (code >> 18),
        0x80 | ((code >> 12) & 0x3F),
        0x80 | ((code >> 6) & 0x3F),
        0x80 | (code & 0x3F)
    )
end

return unicode
