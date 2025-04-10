local fmt = string.format


-- get actual eye_pos of the player (including eye_offset)
local function player_get_eye_pos(player)
    local p_pos = player:get_pos()
    local p_eye_height = player:get_properties().eye_height
    p_pos.y = p_pos.y + p_eye_height
    local p_eye_pos = p_pos
    local p_eye_offset = vector.multiply(player:get_eye_offset(), 0.1)
    local yaw = player:get_look_horizontal()
    p_eye_pos = vector.add(p_eye_pos, vector.rotate_around_axis(p_eye_offset, {x=0,y=1,z=0}, yaw))
    return p_eye_pos
end


-- return first thing player is pointing at
local function raycast_crosshair(player, range, point_to_objects, point_to_liquids)
    local p_eye_pos = player_get_eye_pos(player)
    local to = vector.add(p_eye_pos, vector.multiply(player:get_look_dir(), range))
    local ray = core.raycast(p_eye_pos, to, point_to_objects, point_to_liquids)
    local pointed_thing = ray:next()
    while pointed_thing do
        if pointed_thing.type == "object" and pointed_thing.ref == player then
            -- exclude the player themselves from the raycast
            pointed_thing = ray:next()
        else
            return pointed_thing
        end
    end
    -- FIXME return "nothing" pointed thing?
    return nil
end


-- return first object
local function raycast_crosshair_to_object(player, range)
    local p_eye_pos = player_get_eye_pos(player)
    local to = vector.add(p_eye_pos, vector.multiply(player:get_look_dir(), range))
    -- point_to_objects = true, point_to_liquids = false
    local ray = core.raycast(p_eye_pos, to, true, false)
    local pointed_thing = ray:next()
    while pointed_thing do
        if pointed_thing.type == "object" then
            if pointed_thing.ref ~= player then
                return pointed_thing
            end
        end
        pointed_thing = ray:next()
    end
    -- FIXME return "nothing" pointed thing?
    return nil
end




-- get position and thing that player is pointing at or nil
local function get_pointed_position(player, range, point_to_objects, point_to_liquids)
    local pointed_thing = raycast_crosshair(player, range, point_to_objects, point_to_liquids)
    local pointed_pos = nil
    if pointed_thing then
        if pointed_thing.type == "node" then
            -- middle between "above" and "under"
            pointed_pos = vector.multiply(vector.add(pointed_thing.above, pointed_thing.under), 0.5)
        elseif pointed_thing.type == "object" then
            -- TODO point at the middle of collision box? (or not, ground may be better)
            pointed_pos = pointed_thing.ref:get_pos()
        end
    end
    return pointed_pos, pointed_thing
end

local escapes = {
    ['\a'] = '\\a',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
    ['\v'] = '\\v',
    ['\\'] = '\\\\',
    ['"'] = '\\"',
}

local unescapes = {
    ['\\a'] = '\a',
    ['\\b'] = '\b',
    ['\\f'] = '\f',
    ['\\n'] = '\n',
    ['\\r'] = '\r',
    ['\\t'] = '\t',
    ['\\v'] = '\v',
    ['\\\\'] = '\\',
    ['\\"'] = '"',
}

local function escape_nonascii(c)
    return escapes[c] or string.format('\\x%02x', string.byte(c))
end


local function ascii(str)
    str = str:gsub('[%c\r\n\\"\128-\255]', escape_nonascii)
    return str
end


local function unescape_hex(backslashes, hex)
    if #backslashes % 2 == 0 then
        -- Even number of backslashes, they escape each other, not the digits.
        -- Return them so that next step can treat them.
        return backslashes .. 'x' .. hex
    else
        -- Remove the odd backslash, which escapes the hex code.
        -- The rest will be processed by the next step.
        backslashes = backslashes:sub(1, -2)
    end
    local c = string.char(tonumber(hex, 16))
    if c == '\\' then
        -- will be unsecaped by the next step ("\x5cb" --> "\\b")
        c = '\\\\'
    end
    return backslashes .. c
end


local function unascii(str)
    --str = str:gsub('(\\+)(%d%d%d)', unescape_digits)
    str = str:gsub('(\\+)x(%x%x)', unescape_hex)
    str = str:gsub('\\[abfnrtv\\"]', unescapes)
    return str
end


local util = {
    player_get_eye_pos = player_get_eye_pos,
    raycast_crosshair = raycast_crosshair,
    raycast_crosshair_to_object = raycast_crosshair_to_object,
    get_pointed_position = get_pointed_position,
    ascii = ascii,
    unascii = unascii,
}
return util
