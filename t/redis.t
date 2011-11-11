--[===[
--- http_config
# resty.redis generate redis ups config
upstream redis_main {
  server 127.0.0.1:6379;
  keepalive 10 single;
}
--- config
# resty.redis generate redis loc config
location = /i_redis_query {
  set_unescape_uri $backend $arg_srv;
  set_unescape_uri $n $arg_n;
  set_unescape_uri $cmds $arg_cmds;
  redis2_raw_queries $n $cmds;
  redis2_pass $backend;
}
location = /i_redis_query_post {
  set_unescape_uri $backend $arg_srv;
  set_unescape_uri $n $arg_n;
  redis2_raw_queries $n $echo_request_body;
  redis2_pass $backend;
}
--]===]

require 'fix-ngx-io'
require 'Test.More'

local redis = require'resty.redis'

plan(5)

local redis_cfg = {
    main = {
        server = {
            '127.0.0.1:6379',
            password = '123',
        },
        pool = {
            size = 10,
        },
    };
}
redis.config(redis_cfg)

local r0 = redis'main'
r0:del('a', 'b', 'c', 'd', 'e', 'x')

r0:set('a', 1)

is(r0:get'a', '1', 'get value')

r0:set('c', 2)
eq_array(r0:mget('d', 'a', 'b', 'c'), {nil, '1', nil, '2'}, 'mget value')

r0:mset('c', 4, 'd', 3)
eq_array(r0:mget('d', 'a', 'b', 'c'), {'3', '1', nil, '4'}, 'mget value')

r0:incr('c')
is(r0:get'c', '5', 'mget value')

r0:setbit('x', 1, 1)
eq_array(r0:raw_query{ {'getbit', 'x', 0}, {'getbit', 'x', 1} }, {0, 1}, 'mget value')
