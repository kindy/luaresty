local parser = require "redis.parser"
local cjson = require'cjson'
local _FILE = string.gsub(tostring(debug.getinfo(1).source), '^[^/]+', '', 1)

-- http://wiki.nginx.org/LuaRedisParser
-- local res, typ = parser.parse_reply(reply)

module(..., package.seeall)

local _mod = getfenv(1)
local redis_query_loc = '/i_redis_query'

local _cfg = {}
function config(cfgs)
    for name, cfg in pairs(cfgs) do
        _cfg[name] = cfg
    end
end

-- @class Redis
local Redis = {}
-- 获取 redis 实例 并选择 db (不可更改)
function Redis:new(name, n)
    local o = {name = name, db = n,}

    setmetatable(o, self)
    self.__index = self

    return o
end
function Redis:get_srv()
    return 'redis_' .. self.name
end
function Redis:get_cfg()
    return _cfg[self.name]
end
--[[
reqs = {
        {"set", "foo", "hello world"},
        {"get", "foo"}
    }
--]]
function Redis:raw_query(reqs)
    table.insert(reqs, 1, {'select', self.db})

    local raw_reqs = {}
    local reqs_n = #reqs
    local req_length = 0 -- use POST or GET
    for _, req in ipairs(reqs) do
        local c = parser.build_query(req)
        req_length = req_length + #c
        table.insert(raw_reqs, c)
    end

    print('query->', cjson.encode({
        srv = self:get_srv(),
        n = reqs_n,
        cmds = table.concat(raw_reqs, ''),
    }))
    local use_post = req_length > 1024 * 20
    local res
    if use_post then
        res = ngx.location.capture(redis_query_loc .. '_post',
            {
                method = ngx.HTTP_POST,
                args = {
                    srv = self:get_srv(),
                    n = reqs_n,
                },
                body = table.concat(raw_reqs, '')
            })
    else
        res = ngx.location.capture(redis_query_loc,
            {
                args = {
                    srv = self:get_srv(),
                    n = reqs_n,
                    cmds = table.concat(raw_reqs, ''),
                },
            })
    end

    if res.status ~= ngx.HTTP_OK or not res.body then
        print("redis query error: " .. res.status)
        return nil
    end

    local replies = parser.parse_replies(res.body, reqs_n)
    local ret = {}
    for i, reply in ipairs(replies) do
        table.insert(ret, reply[1])
    end
    table.remove(ret, 1)

    return ret
end
--[[
local rslt = red:pipe(function()
    SET('xx', 1)
    GET'xx'
    INCR'xx'
    GET'xx'
end)

local rslt = red:raw_query{
    {'set', 'xx', 1},
    {'get', 'xx'},
    {'incr', 'xx'},
    {'get', 'xx'},
}
--]]
function Redis:pipe(sql, ctx, opt)
end
function Redis:build_cmd(...)
    return {...}
end

local _cmds
local _cmds_unsupport = {}
do
    local _json_file = string.gsub(_FILE, '%.[^.]+$', '.json', 1)
    _cmds = cjson.decode(io.open(_json_file):read('*a'))
    local _unsupports = {}
    for _, k in ipairs(_unsupports) do
        _cmds_unsupport[k] = true
    end
end
setmetatable(Redis, {
    __index = function (m, key)
        key = string.upper(key)
        print('got->', key)

        local def = _cmds[key]
        if def then
            if _cmds_unsupport[key] then
                error('command [' .. key .. '] unsupport now')
            end

            return function (self, ...)
                local cmd = self:build_cmd(key, ...)

                return self:raw_query{cmd}[1]
            end
        end
    end,
})

function build_ngxcfg_loc(redis_cfg)
    -- 使用 redis:build_ngxcfg_loc 的方式调用
    if redis_cfg == _mod then redis_cfg = _cfg end

    local buf = {}

    table.insert(buf, [[location = ]] .. redis_query_loc .. [[ {
  set_unescape_uri $backend $arg_srv;
  set_unescape_uri $n $arg_n;
  set_unescape_uri $cmds $arg_cmds;
  redis2_raw_queries $n $cmds;
  redis2_pass $backend;
}
location = ]] .. redis_query_loc .. [[_post {
  set_unescape_uri $backend $arg_srv;
  set_unescape_uri $n $arg_n;
  redis2_raw_queries $n $echo_request_body;
  redis2_pass $backend;
}]])

    return '# resty.redis generate redis loc config\n' .. table.concat(buf, '\n')
end

function build_ngxcfg_ups(redis_cfg)
    -- 使用 redis:build_ngxcfg_ups 的方式调用
    if redis_cfg == _mod then redis_cfg = _cfg end

    local buf = {}

    for name, cfg in pairs(redis_cfg) do
        table.insert(buf, 'upstream redis_' .. name .. ' {')
        local srvcfg = cfg.server
        local srvs = srvcfg[1]

        if type(srvs) == 'string' then
            srvs = {srvs}
        end

        for _, srv in ipairs(srvs) do
            table.insert(buf, '  server ' .. srv .. ';')
        end

        if cfg.pool then
            table.insert(buf, '  keepalive ' .. cfg.pool.size .. ' single;')
        end

        table.insert(buf, '}')
    end

    return '# resty.redis generate redis ups config\n' .. table.concat(buf, '\n')
end


-- let redis('abc', 1) return Redis:new('abc', 1)
do
    local _meta = getmetatable(_mod)
    local _redis_cache = {}
    _meta.__call = function(red, name, n)
        n = n or 0

        local _k = name .. ':' .. n
        if not _redis_cache[_k] and _cfg[name] then
            _redis_cache[_k] = Redis:new(name, n)
        end

        return _redis_cache[_k] or error('redis [' .. name .. '] not config-ed', 2)
    end
end

