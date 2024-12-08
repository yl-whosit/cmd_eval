core.register_chatcommand("eval",
    {
        params = "<code>",
        description = "Execute and dump value into chat",
        privs = { server = true },
        func = function(name, param)
            if param == "" then
                return false, "Gib code pls"
            end
            local code = "return " .. param

            -- echo input back
            core.chat_send_player(name, "> " .. code)

            local func, err = loadstring(code, "code")
            if not func then
                return false, err
            end

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
                    if ok then
                        return dump(res[2])
                    else
                        -- combine returned error and stack trace
                        return string.format("%s\n%s", res[2], debug.traceback(coro))
                    end
                else
                    -- returned multiple values: display one per line
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
