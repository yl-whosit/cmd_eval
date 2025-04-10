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

local WAIT_FOR_FORMSPEC = {"WAIT_FOR_FORMSPEC"} -- unique value

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
            local pos = vector.zero() -- FIXME use last command position?
            if me and me:is_player() then
                pos = me:get_pos()
            end
            return pos
        end,
        point = function()
            local me = core.get_player_by_name(player_name)
            if me then
                local pointed_thing = util.raycast_crosshair(me, 200, true, false)
                if pointed_thing then
                    return pointed_thing.intersection_point
                end
                return me:get_pos()
            end
        end,
        this_obj = function()
            local me = core.get_player_by_name(player_name)
            if me then
                local pointed_thing = util.raycast_crosshair_to_object(me, 200)
                if pointed_thing then
                    return pointed_thing.ref
                end
            end
            return nil
        end,
        above = function()
            local me = core.get_player_by_name(player_name)
            if me then
                local pointed_thing = util.raycast_crosshair(me, 200, false, false)
                if pointed_thing then
                    return pointed_thing.above
                end
            end
            return nil
        end,
        under = function()
            local me = core.get_player_by_name(player_name)
            if me then
                local pointed_thing = util.raycast_crosshair(me, 200, false, false)
                if pointed_thing then
                    return pointed_thing.under
                end
            end
            return nil
        end,
        players = function()
            local pl = core.get_connected_players()
            local k, v
            return setmetatable(pl,
                {
                    __index = function(_t, n)
                        return core.get_player_by_name(n)
                    end,
                    __call = function(_t)
                        while next(pl, k) do
                            k, v = next(pl, k)
                            if v:is_valid() then
                                return v
                            end
                        end
                    end,
                }
            )
        end,
        help = function()
            local msg = [[
# Magic variables:
me -- your player object
my_pos -- your position
here -- your position where command was executed at (does not change)
point -- the exact pos you're pointing with the crosshair
this_obj -- the obj you're pointing at with the crosshair or nil
above -- same as pointed_thing.above of the node you're pointing at or nil
under -- same as pointed_thing.under of the node you're pointing at or nil
global -- actual global environment (same as _G)
players -- use players.name to access a player (supports `for p in players`)

# Functions:
dir(t) -- print table key/values (returns nothing)
keys(t) -- print table keys (returns nothing)
goir(radius) -- return list of objects around you
oir(radius) -- return iterator for objects around you
yield(value) -- yield value and pause eval, resume it with /eval_resume command
fsdump(value) -- show the value in a formspec window
fsinput(label, text) -- show a form that will return the text you entered
]]
            core.chat_send_player(player_name, msg)
        end,
    }

    local g = {} -- "do not warn again" flags
    local global_proxy = setmetatable(
        {"<proxy>"},
        {
            __index = _G,
            __newindex = function(_t, k, v)
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
                    core.chat_send_player(player_name, string.format("Not a table: %s", dump(o)))
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
                    return core.objects_inside_radius(me:get_pos(), radius)
                else
                    return function() return nil end
                end
            end,
            yield = coroutine.yield,
            fsdump = function(value)
                local output = type(value) == "string" and value or dump(value)
                local fs = {
                    "formspec_version[6]",
                    "size[19,10]",
                    "textarea[0.1,0.8;18.8,8.1;a;Output;", core.formspec_escape(output), "]",
                    "button_exit[18.1,0.1;0.8,0.7;x;x]",
                    "button_exit[15.9,9.1;3,0.8;resume;resume]",
                }

                core.show_formspec(player_name, "cmd_eval:dump", table.concat(fs, ""))
                coroutine.yield(WAIT_FOR_FORMSPEC)
                return value
            end,
            fsinput = function(label, text)
                label = label and tostring(label) or "Input"
                text = text and tostring(text) or ""
                local fs = {
                    "formspec_version[6]",
                    "size[19,10]",
                    "textarea[0.1,0.8;18.8,8.1;input;", core.formspec_escape(label), ";", core.formspec_escape(text), "]",
                    "button_exit[18.1,0.1;0.8,0.7;x;x]",
                    "button_exit[15.9,9.1;3,0.8;send;send]",
                }

                core.show_formspec(player_name, "cmd_eval:input", table.concat(fs, ""))
                local result = coroutine.yield(WAIT_FOR_FORMSPEC)
                return result
            end,
            ascii = util.ascii,
            unascii = util.unascii,
        },
        {
            __index = function(_self, key)
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

local last_coro_by_player = {}
-- setmetatable({},
--     {
--         __index = function(t, k) local new = {};
--             rawset(t, k, new);
--             return new
--         end
--     }
-- )


local helper = function(coro, env, ...)
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
    local ok = res[1]
    if n == 1 then
        -- In some cases, calling a function can return literal "nothing":
        -- + Executing loadstring(`x = 1`) returns "nothing".
        -- + API calls also can sometimes return literal "nothing" instead of nil
        return ok, ok and "Done." or "Failed without error message."
    elseif n == 2 then
        -- returned single value or error
        env._ = res[2] -- store result in "_" per-user "global" variable
        if ok then
            return ok, repl_dump(res[2]), res[2]
        else
            -- combine returned error and stack trace
            return ok, string.format("%s\n%s", res[2], debug.traceback(coro))
        end
    else
        -- returned multiple values: display one per line
        env._ = res[2] -- store result in "_" per-user "global" variable
        local ret_vals = {}
        for i=2, n do
            table.insert(ret_vals, repl_dump(res[i]))
        end
        return ok, table.concat(ret_vals, ',\n')
    end
end


local function resume_coroutine(player_name, ...)

    local last = last_coro_by_player[player_name]
    if not last then
        return false, "* Nothing to resume"
    end

    local c_id, coro, env = last.cc, last.coro, last.env

    local coro_status = coroutine.status(coro)
    if coro_status ~= "suspended" then
        return false, "* Cannot resume dead coroutine"
    end

    local ok, res, raw = helper(coro, env, coroutine.resume(coro, ...))
    res = string.gsub(res, "([^\n]+)", "| %1")
    coro_status = coroutine.status(coro)
    if coro_status == "suspended" then
        if raw == WAIT_FOR_FORMSPEC then
            res = "* Waiting for formspec..."
        else
            res = res .. "\n* coroutine suspended, type /eval_resume to continue"
        end
    else
        -- coroutine is dead, clean it up
        last_coro_by_player[player_name] = nil
    end
    if ok then
        core.log("info", string.format("[cmd_eval][%s] succeeded.", c_id))
    else
        core.log("warning", string.format("[cmd_eval][%s] failed: %s.", c_id, dump(res)))
    end
    return ok, res
end


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

            -- Creating a coroutine here, instead of using xpcall,
            -- allows us to get a clean stack trace up to this call.
            local coro = coroutine.create(func)

            last_coro_by_player[player_name] = {
                cc = cc,
                coro = coro,
                env = env,
            }

            return resume_coroutine(player_name)
        end
    }
)


core.register_chatcommand("eval_resume",
    {
        params = "<string to pass through yield>",
        description = "Resume previous command",
        privs = { server = true },
        func = function(player_name, param)
            core.log("action", string.format("[cmd_eval] %s resumed previous command", player_name, dump(param)))
            core.chat_send_player(player_name, "* resuming...")

            -- it's possible to send the string back to the coroutine through this
            return resume_coroutine(player_name, param or "")
        end
    }
)


core.register_chatcommand("eval_reset",
    {
        description = "Restore your environment by clearing all variables you assigned",
        privs = { server = true },
        func = function(player_name, param)
            core.log("action", string.format("[cmd_eval] %s reset their environmet", player_name, dump(param)))
            api.e[player_name] = nil
            return true, orange_fmt("* Your environment has been reset to default.")
        end
    }
)


core.register_on_player_receive_fields(
    function(player, formname, fields)
        if formname == "cmd_eval:dump" or formname == "cmd_eval:input" then
            local player_name = player and player.is_player and player:is_player() and player:get_player_name()
            if not player_name then
                return
            end

            if fields.resume or fields.send then
                -- check for correct privs again, just in case
                if not core.check_player_privs(player_name, { server = true }) then
                    return true
                end

                -- check if there's anything wating for the formspec
                local last = last_coro_by_player[player_name]
                if not last then
                    return true -- nothing to resume
                end

                -- Resuming coroutine only in specific cases allows us
                -- to close the formspec, do something, then resume
                -- execution by typing `/eval_resume [input]`
                local ok, res, show_res
                if formname == "cmd_eval:input" and fields.send then
                    -- Player had fsinput() call pending and pushed
                    -- `send` - pass their input back to the coroutine
                    local input = fields.input or ""
                    ok, res = resume_coroutine(player_name, input)
                    show_res = true
                elseif formname == "cmd_eval:dump" and fields.resume then
                    -- Player had dump window open, and pushed
                    -- `resume` so we resume the coro.
                    ok, res = resume_coroutine(player_name)
                    show_res = true
                end

                if show_res then
                    if ok then
                        core.chat_send_player(player_name, res)
                    else
                        -- not sure if we need to handle errors here in some way?
                        core.chat_send_player(player_name, res)
                    end
                end
            end
            return true
        end
        return  -- did not match known FS names
    end
)
