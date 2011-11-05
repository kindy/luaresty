local rds_parse = require"rds.parser".parse
local sql_null = require"rds.parser".null

module(..., package.seeall)

local db_query_loc_prefix = '/i_db_query'
local mysql_thread_id_name = 'X-Mysql-Tid'
local get_db_query_loc_by_type

local _cfg = {}
function config(cfgs)
    for name, cfg in pairs(cfgs) do
        _cfg[name] = cfg
    end
end

-- @class DB
local DB = {}
-- 获取 db 实例
function DB:new(name)
    local o = {name = name}

    setmetatable(o, self)
    self.__index = self

    return o
end
function DB:get_srv()
    return 'db_' .. self.name
end
function DB:get_cfg()
    return _cfg[self.name]
end

--[[
* sql string/table - sql to query, support variables
* ctx table - ctx for sql eval
* opt table - options for sql eval or run
** dryrun boolean - return sql instead of execute it
** srv string/function - set server manual
--]]
function DB:query(sql, ctx, opt)
    -- print('sql->', require'cjson'.encode(sql))
    -- print('ctx->', require'cjson'.encode(ctx))

    if not ctx then ctx = {} end
    if not opt then opt = {} end

    -- print('ctx->', require'cjson'.encode(ctx))

    local sql = Seg:new(sql):to_sql(ctx)

    if opt.dryrun then
        return sql
    end

    local resp = ngx.location.capture(get_db_query_loc_by_type(self:get_cfg().type), {
        method = ngx.HTTP_POST,
        -- TODO make srv at runtime
        args = {srv = opt.srv or self:get_srv()},
        body = sql,
    })

    --ngx.log(ngx.WARN, 'query {' .. sql .. '} result [' .. resp.status .. ']->', resp.body)
    --ngx.say('query {' .. sql .. '} result [' .. resp.status .. ']->', resp.body)

    if resp.status ~= ngx.HTTP_OK or not resp.body then
        print("sql query error: " .. resp.status)
        return nil
    end

    local res, err = rds_parse(resp.body)
    if res == nil then
        print("rds parse error: " .. err)
        return nil
    end

    local rows = res.resultset
    local rownum = rows and #rows or 0
    res.resultn = rownum

    -- typ
    -- row, col:abc
    function res:get(typ)
        if rownum == 0 then
            return nil
        end

        if typ == 'row' then
            return rows[1]
        elseif typ == 'one' then
            return rows[1][1]
        end
    end

    return res
end
function DB:exec(fn)
    fn(self)
    return self
end
function DB:transaction(fn)
    -- TODO xxx
    -- local r = pcall(fn, self)
    -- err and self:rollback()
    error('db:transaction() not OK')
    return self
end
function DB:commit(fn)
    -- TODO xxx
    error('db:commit() not OK')
    return self
end
function DB:rollback(fn)
    -- TODO xxx
    error('db:rollback() not OK')
    return self
end


-- @class Seg
Seg = {
    _process = function(sql, idx)
        return string.gsub(sql[idx], '%$seg:([a-zA-Z0-9%-_]+)', sql)
    end
}
function Seg:process(key)
    return Seg._process(self.raw_sql, key or 1)
end
function Seg:new(sql)
    if type(sql) ~= 'table' then
        sql = {sql}
    end

    local o = {
        raw_sql = sql,
    }

    setmetatable(o, self)
    self.__index = self

    o.sql = o:process()

    return o
end
function Seg:to_sql(ctx)
    local sql = self.sql
    local _seg = self
    local call_count = {}
    local _quote_sql_str = ndk.set_var.set_quote_sql_str

    function quote(v)
        if type(v) == 'number' then
            return tostring(v)
        else
            return _quote_sql_str(tostring(v))
        end
    end

    return ngx.re.gsub(sql, '\\$(\\$+|(?:(\\w++):)?+([a-zA-Z0-9_-]++))', function(m)
        local esc, typ, key = m[1], m[2], m[3]
        if esc == '$' then
            return '$'
        end

        -- print(esc, typ, key)
        local v = ctx[key]
        if not typ or typ == '' then
            typ = 'quote'
        end

        -- call, kw, sym, syms, set, pair, quote
        if typ == 'call' then
            call_count[key] = (call_count[key] and call_count[key] or 0) + 1
            v = v(_seg, ctx, call_count[key])
        elseif typ == 'kw' then
            -- TODO check keyword list
            -- do nothing
        elseif typ == 'sym' then
            v = tostring(v)
            -- TODO check symobal valid
            v = '`' .. v .. '`'
        elseif typ == 'syms' then
            if type(v) ~= 'table' or #v < 1 then
                error('for syms type, value must be a table with at least 1 element')
            end
            local _v = {}
            for _, item in ipairs(v) do
                -- TODO check symobal valid
                _v[#_v + 1] = '`' .. tostring(item) .. '`'
            end
            v = table.concat(_v, ', ')
        elseif typ == 'set' then
            if type(v) ~= 'table' or #v < 1 then
                error('for set type, value must be a table with at least 1 element')
            end

            -- TODO all table must be the same type
            local _v = {}
            for _, item in ipairs(v) do
                _v[#_v + 1] = quote(tostring(item))
            end
            v = '(' .. table.concat(_v, ', ') .. ')'
        elseif typ == 'pair' then
            if type(v) ~= 'table' or #v < 2 then
                error('for pair type, value must be a table with at least 2 element')
            end
            v = quote(v[1]) .. ' and ' .. quote(v[2])
        elseif typ == 'quote' then
            v = quote(v)
        end

        if type(v) == 'boolean' then
            v = v and 't' or 'f'
        end

        return v or 'NULL'
    end)
end

get_db_query_loc_by_type = function (typ)
    return db_query_loc_prefix .. '_' .. typ
end

function build_ngxcfg_loc(db_cfg)
    local buf = {}

    table.insert(buf, [[location = ]] .. get_db_query_loc_by_type'mysql' .. [[ {
  internal;
  set_unescape_uri $backend $arg_srv;
  drizzle_query $echo_request_body;
  drizzle_pass  $backend;
  more_set_headers -s 504 "]] .. mysql_thread_id_name .. [[: $drizzle_thread_id";
}]])

    return '# resty.db generate db loc config\n' .. table.concat(buf, '\n')
end

function build_ngxcfg_ups(db_cfg)
    local buf = {}
    for name, cfg in pairs(db_cfg) do
        table.insert(buf, 'upstream db_' .. name .. ' {')
        local srvcfg = cfg.server
        local srvs = srvcfg[1]

        if type(srvs) == 'string' then
            srvs = {srvs}
        end

        -- TODO generate the code by cfg.type postgre, mysql ...
        for _, srv in ipairs(srvs) do
            table.insert(buf, '  drizzle_server ' .. srv .. ' dbname=' .. cfg.defaultdb
                .. ' user=' .. srvcfg.user .. ' password=' .. srvcfg.password
                .. ' protocol=' .. cfg.type .. ' charset=' .. (cfg.charset or 'utf8') .. ';')
        end

        if cfg.pool then
            table.insert(buf, '  drizzle_keepalive max=' .. cfg.pool.size
                .. ' overflow=' .. (cfg.pool.overflow or 'ignore') .. ' mode=single;')
        end

        table.insert(buf, '}')
    end

    return '# resty.db generate db ups config\n' .. table.concat(buf, '\n')
end

function build_ngxcfg(db_cfg)
    return build_ngxcfg_ups(db_cfg) .. '\n' .. build_ngxcfg_loc(db_cfg)
end


-- let db'abc' return DB:new'abc'
do
    local _meta = getmetatable(getfenv(1))
    local _db_cache = {}
    _meta.__call = function(db, name)
        if not _db_cache[name] and _cfg[name] then
            _db_cache[name] = DB:new(name)
        end

        return _db_cache[name] or error('db [' .. name .. '] not config-ed', 2)
    end
end

