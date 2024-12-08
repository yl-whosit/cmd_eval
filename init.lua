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

            local func, err = loadstring(code, "usercode")
            if not func then
                return false, err
            end

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
                    -- returned single value or error - just return it
                    return dump(res[2])
                else
                    -- returned multiple values: display one per line
                    local ret_vals = {}
                    for i=2, n do
                        table.insert(ret_vals, dump(res[i]))
                    end
                    return table.concat(ret_vals, ',\n')
                end
            end
            local res = helper(pcall(func))
            return ok, res
        end
    }
)
