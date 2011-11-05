--[===[
--- http_config
# resty.db generate db ups config
upstream db_blog {
  drizzle_server 127.0.0.1:3306 dbname=test user=abc password=123 protocol=mysql charset=utf8;
  drizzle_keepalive max=10 overflow=ignore mode=single;
}
--- config
# resty.db generate db loc config
location = /i_db_query_mysql {
  internal;
  set_unescape_uri $backend $arg_srv;
  drizzle_query $echo_request_body;
  drizzle_pass  $backend;
  more_set_headers -s 504 "X-Mysql-Tid: $drizzle_thread_id";
}
--- sql_prepare
grant all on test.* to 'abc'@'localhost' identified by '123';
use test;
create table cat (name char(30), age int);
insert into cat values('mm', 1), ('oo', 2);
--]===]

require 'fix-ngx-io'
require 'Test.More'

plan(5)

local db = require'resty.db'
local cjson = require'cjson'

local print = ngx.say

local db_cfg = {
    blog = {
        type = 'mysql',
        defaultdb = 'test',
        charset = 'utf8',
        server = {
            '127.0.0.1:3306',
            user = 'abc',
            password = '123',
        },
        pool = {
            size = 10,
        },
    };
}
db.config(db_cfg)

local seg = {
    [[select '$$' as xx, $kw:x $sym:x2, b, c, $syms:x3 from ($seg:x5) where a = $a and b >= $b or a in $set:a2 or a between $pair:a3 and $call:x4 order by xx desc]],
    x5 = [[select * from $sym:b]],
}
local seg_p = [[select '$$' as xx, $kw:x $sym:x2, b, c, $syms:x3 from (select * from $sym:b) where a = $a and b >= $b or a in $set:a2 or a between $pair:a3 and $call:x4 order by xx desc]]
local rslt = [[select '$' as xx, distinct `xxx`, b, c, `d`, `e` from (select * from `b`) where a = 'a' and b >= 'b' or a in ('a2') or a between 1 and 2 and `a` is not NULL order by xx desc]]
local ctx= {
    x = 'distinct',
    x2 = 'xxx',
    x3 = {'d', 'e'},
    x4 = function(seg, ctx, idx) return [[`a` is not NULL]] end,
    a = 'a',
    b = 'b',
    a2 = {'a2'},
    a3 = {1, 2},
}

-- query("select * from abc")
-- query({"select $syms:qlist from ($seg:subq1) as t"
--      subq1 = "select $syms:qlist from xxx",
-- }, {
--     qlist = {'a', 'b'}
-- })
-- query({"select $seg:qlist from ($seg:subq1) as t group by a",
--     qlist = "concat($prefix_a, a, $suff_a) as a_full, sum(b) as total",
--     subq1 = "select $seg:qlist from xxx",
-- }, {
--     prefix_a = 'xx_',
--     suff_a = '_yy',
-- }, {dryrun = true})

is(db.Seg._process(seg, 1), seg_p, 'seg process')

local db_blog = db'blog'

is(db_blog:query(seg, ctx, {dryrun = true}), rslt, 'db:query with expand')

is(db.build_ngxcfg_ups(db_cfg), [[# resty.db generate db ups config
upstream db_blog {
  drizzle_server 127.0.0.1:3306 dbname=test user=abc password=123 protocol=mysql charset=utf8;
  drizzle_keepalive max=10 overflow=ignore mode=single;
}]], 'build_ngxcfg_ups')

is(db.build_ngxcfg_loc(db_cfg),
    [[# resty.db generate db loc config
location = /i_db_query_mysql {
  internal;
  set_unescape_uri $backend $arg_srv;
  drizzle_query $echo_request_body;
  drizzle_pass  $backend;
  more_set_headers -s 504 "X-Mysql-Tid: $drizzle_thread_id";
}]], 'build_ngxcfg_loc')

is(cjson.encode(db'blog':query('select * from cat;', nil, {result = ''}).resultset),
    [===[[{"name":"mm","age":1},{"name":"oo","age":2}]]===], 'db:query and json')

--[[
db'blog':exec(function(db)
    db:query('START TRANSACTION')
    db:query('insert into a values (8, "xx")')
    db:query('select * from a order by id desc limit 1')
    db:query('COMMIT')
    db:query('select * from a limit 2')
end)
--]]

