local config = require'config'

module(..., package.seeall)

function exit (errcode)
    return ngx.exit(errcode)
end
function get_modpath_by_uri (uri, prefix)
    prefix = prefix or 'c'

    local modpath = uri:gsub('/+$', ''):gsub('^/+', ''):gsub('/', '.')

    return table.concat({prefix, modpath}, '.')
end
function get_route ()
    if ngx.ctx.mod then
        return ngx.ctx.mod
    end

    local modpath = get_modpath_by_uri(ngx.var.uri)

    local ok, mod = pcall(require, modpath)

    if ok then
        ngx.ctx.mod = mod
        return mod
    else
        print('require error ->', m)
        if m:match('not found:') then
            exit(404)
        else
            exit(500)
        end
    end
end

function run_if_exists (mod, method)
    if mod[method] then
        return mod[method](mod)
    end
end

function access ()
    return run_if_exists(get_route(), 'access')
end

function rewrite ()
    return run_if_exists(get_route(), 'rewrite')
end

function content ()
    return run_if_exists(get_route(), 'content')
end

