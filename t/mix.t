# vim:set ft= ts=4 sw=4 et fdm=marker:

use t::Resty;

repeat_each(1);

plan tests => blocks() * repeat_each() * 2;

our $HtmlDir = html_dir;
our $RestyDir = resty_dir;

no_long_string();
no_root_location();

run_tests();

__DATA__

=== TEST 1: simple set (integer)
--- main_config
--- http_config eval
    "lua_package_path '$::RestyDir/?.lua;;';"
--- resty_files
>>> bin/gen-ups
-- package.path = ';;'
local db = require'resty.db'
require'config'
ngx.say(db:build_ngxcfg_ups())
>>> bin/gen-loc
-- package.path = ';;'
local db = require'resty.db'
require'config'
ngx.say(db:build_ngxcfg_loc())
>>> config.lua
local db = require'resty.db'
db.config{
    blog = { type = 'mysql', defaultdb = 'kblog', charset = 'utf8',
        server = { '127.0.0.1:3306', user = 'kblog', password = '123', }, pool = { size = 10, },
    };
}
>>> index.lua
local getfenv, setmetatable, require = getfenv, setmetatable, require
module(...)
setmetatable(getfenv(1), {__index = require'resty.index'})
>>> c/index.lua
module(..., package.seeall)
function content(self)
    ngx.print('abc')
end
--- http_config_by_resty
$ runbyngx bin/gen-ups
--- config_by_resty
$ runbyngx bin/gen-loc
--- config
location /static/ {
}
location / {
    access_by_lua "require'index'.access()";
    rewrite_by_lua "require'index'.rewrite()";
    content_by_lua "require'index'.content()";
}
--- request
GET /index
--- response_body chomp
abc

