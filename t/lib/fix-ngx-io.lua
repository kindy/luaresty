if ngx then
local io = require 'io'
local xio = {}

local function get_stderr ()
    if not ngx.ctx.err_file then
        ngx.ctx.err_file = io.open(ngx.var.lua_log_path, 'w')
    end

    return ngx.ctx.err_file
end

local function nullfn () end

setmetatable(xio, {
    __index = function (x, key)
        if key == 'stderr' then
            return get_stderr()
        elseif key == 'stdout' then
            return {
                write = function (self, ...)
                    ngx.print(...)
                end,
                seek = nullfn,
                close = nullfn,
            }
        else
            return io[key]
        end
    end,
})

package.loaded['io'] = xio
end

return nil
