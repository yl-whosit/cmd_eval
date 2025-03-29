-- Copied from luanti builins and modified.

-- Modified output:
-- 1. Name of player or luaentity for userdata
-- 2. Invalid ObjectRefs
-- 3. Output indices of "array" tables


local keywords = {
    ["and"] = true,
    ["break"] = true,
    ["do"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["end"] = true,
    ["false"] = true,
    ["for"] = true,
    ["function"] = true,
    ["goto"] = true,  -- Lua 5.2
    ["if"] = true,
    ["in"] = true,
    ["local"] = true,
    ["nil"] = true,
    ["not"] = true,
    ["or"] = true,
    ["repeat"] = true,
    ["return"] = true,
    ["then"] = true,
    ["true"] = true,
    ["until"] = true,
    ["while"] = true,
}
local function is_valid_identifier(str)
    if not str:find("^[a-zA-Z_][a-zA-Z0-9_]*$") or keywords[str] then
        return false
    end
    return true
end



local function basic_dump(o)
    local tp = type(o)
    if tp == "number" then
        return tostring(o)
    elseif tp == "string" then
        return string.format("%q", o)
    elseif tp == "boolean" then
        return tostring(o)
    elseif tp == "nil" then
        return "nil"
	-- Uncomment for full function dumping support.
	-- Not currently enabled because bytecode isn't very human-readable and
	-- dump's output is intended for humans.
	--elseif tp == "function" then
	--	return string.format("loadstring(%q)", string.dump(o))
    elseif tp == "userdata" then
        if o.is_valid and not o:is_valid() then
            return string.format('#<Obj:invalid: %s>', o)
        end
        if o.is_player then
            if o:is_player() then
                return string.format('#<Obj:player: "%s">', o:get_player_name())
            else
                local e = o:get_luaentity()
                if e then
                    return string.format('#<Obj:lua: "%s">', e.name)
                else
                    return string.format('#<Obj: %s>', o)
                end
            end
        end
        return string.format("#<%s>", o)
    else
        return string.format("#<%s>", tp)
    end
end


local function repl_dump(o, indent, nested, level)
    local t = type(o)
    if t ~= "table" then
        return basic_dump(o)
    end

    -- Contains table -> true/nil of currently nested tables
    nested = nested or {}
    if nested[o] then
        return "<circular reference>"
    end
    nested[o] = true
    indent = indent or "\t"
    level = level or 1

    local ret = {}
    local dumped_indexes = {}
    for i, v in ipairs(o) do
        ret[#ret + 1] = string.format("[%s] = %s", i, repl_dump(v, indent, nested, level + 1))
        dumped_indexes[i] = true
    end
    for k, v in pairs(o) do
        if not dumped_indexes[k] then
            if type(k) ~= "string" or not is_valid_identifier(k) then
                k = "["..repl_dump(k, indent, nested, level + 1).."]"
            end
            v = repl_dump(v, indent, nested, level + 1)
            ret[#ret + 1] = k.." = "..v
        end
    end
    nested[o] = nil
    if indent ~= "" then
        local indent_str = "\n"..string.rep(indent, level)
        local end_indent_str = "\n"..string.rep(indent, level - 1)
        return string.format("{%s%s%s}",
                             indent_str,
                             table.concat(ret, ","..indent_str),
                             end_indent_str)
    end
    return "{"..table.concat(ret, ", ").."}"
end


local function dump_dir(o)
    -- dump only top-level key = value pairs
    local t = type(o)
    if t ~= "table" then
        return basic_dump(o)
    end

    local ret = {}
    local dumped_indexes = {}
    for i, v in ipairs(o) do
        ret[#ret + 1] = string.format("[%s] = %s", i, basic_dump(v))
        dumped_indexes[i] = true
    end
    for k, v in pairs(o) do
        if not dumped_indexes[k] then
            if type(k) ~= "string" or not is_valid_identifier(k) then
                k = "["..basic_dump(k).."]"
            end
            v = basic_dump(v)
            ret[#ret + 1] = k.." = "..v
        end
    end
    return "{\n "..table.concat(ret, ",\n ").."\n}"
end

local dump_funcs = {
    repl_dump = repl_dump,
    dump_dir = dump_dir,
}

return dump_funcs
