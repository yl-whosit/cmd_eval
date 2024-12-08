local MODNAME = core.get_current_modname()

local api = {}
_G[MODNAME] = api

-- per-player persistent environments
api.e = {}


local function create_shared_environment(player_name)
    local me = core.get_player_by_name(player_name)
    local magic_keys = {
        me = function()
            return core.get_player_by_name(player_name)
        end,
        my_pos = function()
            local pos = here
            if me:is_player() then
                pos = me:get_pos()
            end
            return pos
        end,
        this_obj = function()
        end,
        this_node = function()
        end,
    }

    local g = {}
    local eval_env = setmetatable(
        {
            my_name = player_name,
            here = here,
        },
        {
            __index = function(self, key)
                local res = rawget(_G, key)
                if res == nil then
                    local magic = magic_keys[key]
                    if magic then
                        return magic()
                    elseif not g[key] then
                        core.chat_send_player(player_name, string.format("* Accessing undeclared variable: '%s'", key))
                        g[key] = true
                    end
                end
                return res
            end
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
    local here = me:get_pos()
    local cmd_env = {
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


core.register_chatcommand("eval",
    {
        params = "<code>",
        description = "Execute and dump value into chat",
        privs = { server = true },
        func = function(player_name, param)
            if param == "" then
                return false, "Gib code pls"
            end

            local code = param

            -- echo input back
            core.chat_send_player(player_name, "> " .. code)

            local func, err = loadstring('return ' .. code, "code")
            if not func then
                func, err = loadstring(code, "code")
            end
            if not func then
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
                if n == 2 then
                    -- returned single value or error
                    env._ = res[2]
                    if ok then
                        return dump(res[2])
                    else
                        -- combine returned error and stack trace
                        return string.format("%s\n%s", res[2], debug.traceback(coro))
                    end
                else
                    -- returned multiple values: display one per line
                    env._ = res[2]
                    local ret_vals = {}
                    for i=2, n do
                        table.insert(ret_vals, dump(res[i]))
                    end
                    return table.concat(ret_vals, ',\n')
                end
            end
            -- Creating a coroutine here, instead of using xpcall,
            -- allows us to get a clean stack trace up to this call.
            local res = helper(coroutine.resume(coro))
            return ok, res
        end
    }
)
