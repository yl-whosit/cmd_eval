local MODNAME = core.get_current_modname()
local MODPATH = core.get_modpath(MODNAME)

local util = dofile(MODPATH .. DIR_DELIM .. "util.lua")
local dump_funcs = dofile(MODPATH .. DIR_DELIM .. "dump.lua")
local repl_dump = dump_funcs.repl_dump
local dump_dir = dump_funcs.dump_dir

local api = {}
_G[MODNAME] = api

-- per-player persistent environments
api.e = {}


local function orange_fmt(...)
    return core.colorize("#FFA91F", string.format(...))
end


local function create_shared_environment(player_name)
    local magic_keys = {
        -- These are _functions_ pretending to be _variables_, they will
        -- be called when indexing global environmet to get their value.
        me = function()
            return core.get_player_by_name(player_name)
        end,
        my_pos = function()
            local me = core.get_player_by_name(player_name)
            local pos = vector.zero() -- FIXME use last command position
            if me:is_player() then
                pos = me:get_pos()
            end
            return pos
        end,
        point = function()
            local me = core.get_player_by_name(player_name)
            local pointed_thing = util.raycast_crosshair(me, 200, true, false)
            if pointed_thing then
                return pointed_thing.intersection_point
            end
            return me:get_pos()
        end,
        this_obj = function()
            local me = core.get_player_by_name(player_name)
            local pointed_thing = util.raycast_crosshair_to_object(me, 200)
            if pointed_thing then
                return pointed_thing.ref
            end
            return nil
        end,
        this_node_pos = function()
            local me = core.get_player_by_name(player_name)
            local pointed_thing = util.raycast_crosshair(me, 200, false, false)
            if pointed_thing then
                return pointed_thing.under
            end
            return vector.round(me:get_pos())
        end,
        help = function()
            local msg = [[
# Variables:
me -- your player object
my_pos -- your position
here -- your position where command was executed at (does not change)
point -- the exact pos you're pointing with the crosshair
this_obj -- the obj you're pointing at with the crosshair or nil
this_node_pos -- the node position you're pointing at
global -- actual global environment (same as _G)

# Functions:
dir(t) -- print table key/values (returns nothing)
keys(t) -- print table keys (returns nothing)
goir(radius) -- return list of objects around you
oir(radius) -- return iterator for objects around you
]]
            core.chat_send_player(player_name, msg)
        end,
    }

    local g = {} -- "do not warn again" flags
    local global_proxy = setmetatable(
        {"<proxy>"},
        {
            __index = _G,
            __newindex = function(t, k, v)
                if _G[k] then
                    core.chat_send_player(player_name, orange_fmt("* Overwriting global: %s", dump(k)))
                else
                    core.chat_send_player(player_name, orange_fmt("* Creating new global: %s", dump(k)))
                        end
                _G[k] = v
            end,
        }
    )

    local eval_env = setmetatable(
        {
            --global = _G, -- this works, but dumps whole global env if you just print `cmd_eval` value
            _G = global_proxy, -- use our proxy to get warnings
            global = global_proxy, -- just a different name for globals
            my_name = player_name,
            print = function(...)
                -- print to chat, instead of console
                local msg = '< '
                for i = 1, select('#', ...) do
                    if i > 1 then msg = msg .. '\t' end
                    msg = msg .. tostring(select(i, ...))
                end
                core.chat_send_player(player_name, msg)
            end,
            dir = function(o)
                core.chat_send_player(player_name, dump_dir(o))
            end,
            keys = function(o)
                -- collect all keys of the table, no values
                if type(o) == "table" then
                    local keys = {}
                    for k, _ in pairs(o) do
                        local key = k
                        local t = type(key)
                        if t == "string" then
                            key = '"' .. key .. '"'
                        elseif t == "number" then
                            key = '[' .. key .. ']'
                        else
                            key = '[' .. tostring(key) .. ']'
                        end
                        table.insert(keys, key)
                    end
                    table.sort(keys)
                    core.chat_send_player(player_name, table.concat(keys, ',\n'))
                else
                    core.chat_send_player(player_name, string.format("Not a table: %s", dump(t)))
                end
            end,
            --dump = repl_dump,
            goir = function(radius)
                local me = core.get_player_by_name(player_name)
                if me then
                    local objs = core.get_objects_inside_radius(me:get_pos(), radius)
                    return objs
                else
                    return {}
                end
            end,
            oir = function(radius)
                local me = core.get_player_by_name(player_name)
                if me then
                    local objs = core.get_objects_inside_radius(me:get_pos(), radius)
                    local nextkey, v
                    --local i = 1
                    return function()
                        -- FIXME skip invalid objects here?
                        nextkey, v = next(objs, nextkey)
                        return v
                        -- i = i + 1
                        -- return objs[i]
                    end
                else
                    return function() return nil end
                end
            end,
        },
        {
            __index = function(self, key)
                -- we give warnings on accessing undeclared var because it's likely a typo
                local res = rawget(_G, key)
                if res == nil then
                    local magic = magic_keys[key]
                    if magic then
                        return magic()
                    elseif not g[key] then
                        core.chat_send_player(player_name, orange_fmt("* Accessing undeclared variable: %s", dump(key)))
                        g[key] = true -- warn only once
                    end
                end
                return res
            end
            -- there's no __newindex method because we allow assigning
            -- "globals" inside snippets, since those will be only
            -- accessible to eval and stored in `eval_env`
        }
    )
    return eval_env
end


local function create_command_environment(player_name)
    local shared_env = api.e[player_name]
    if not shared_env then
        shared_env = create_shared_environment(player_name)
        api.e[player_name] = shared_env
    end

    local me = core.get_player_by_name(player_name)
    local here = me and me:get_pos()
    local cmd_env = {
        -- This is a special _per-command_ environment.
        -- The rationale is: each command should have it's own "here"
        -- It may matter when we start long-running tasks or something.
        here = here,
    }
    setmetatable(
        cmd_env,
        {
            __index = shared_env,
            __newindex = shared_env,
        }
    )
    return cmd_env
end

local cc = 0 -- count commands just to identify log messages

core.register_chatcommand("eval",
    {
        params = "<code>",
        description = "Execute and dump value into chat",
        privs = { server = true },
        func = function(player_name, param)
            if param == "" then
                return false, "Gib code pls"
            end

            cc = cc + 1

            local code = param

            -- echo input back
            core.chat_send_player(player_name, "> " .. code)
            core.log("action", string.format("[cmd_eval][%s] %s entered %s.", cc, player_name, dump(param)))

            local func, err = loadstring('return ' .. code, "code")
            if not func then
                func, err = loadstring(code, "code")
            end
            if not func then
                core.log("action", string.format("[cmd_eval][%s] parsing failed.", cc))
                return false, err
            end

            local env = create_command_environment(player_name)

            setfenv(func, env)

            local coro = coroutine.create(func)

            local ok
            local helper = function(...)
                -- We need this helper to access returned values
                -- twice - to get the number and to make a table with
                -- them.
                --
                -- This is a little convoluted, but it's to make sure
                -- that evaluating functions like:
                --
                -- (function() return 1,nil,3 end)()
                --
                -- will display all returned values.
                local n = select("#", ...)
                local res = {...}
                ok = res[1]
                if n == 1 then
                    -- In some cases, calling a function can return literal "nothing":
                    -- + Executing loadstring(`x = 1`) returns "nothing".
                    -- + API calls also can sometimes return literal "nothing" instead of nil
                    return ok and "Done." or "Failed without error message."
                elseif n == 2 then
                    -- returned single value or error
                    env._ = res[2] -- store result in "_" per-user "global" variable
                    if ok then
                        return repl_dump(res[2])
                    else
                        -- combine returned error and stack trace
                        return string.format("%s\n%s", res[2], debug.traceback(coro))
                    end
                else
                    -- returned multiple values: display one per line
                    env._ = res[2] -- store result in "_" per-user "global" variable
                    local ret_vals = {}
                    for i=2, n do
                        table.insert(ret_vals, repl_dump(res[i]))
                    end
                    return table.concat(ret_vals, ',\n')
                end
            end
            -- Creating a coroutine here, instead of using xpcall,
            -- allows us to get a clean stack trace up to this call.
            local res = helper(coroutine.resume(coro))
            res = string.gsub(res, "([^\n]+)", "| %1")
            if ok then
                core.log("info", string.format("[cmd_eval][%s] succeeded.", cc))
            else
                core.log("warning", string.format("[cmd_eval][%s] failed: %s.", cc, dump(res)))
            end
            return ok, res
        end
    }
)
