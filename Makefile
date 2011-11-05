
pwd=$(shell pwd -P)
t_lua_path=$(pwd)/t/app/?.lua;$(pwd)/t/lib/?.lua;$(pwd)/inc/lua-TestMore/src/?.lua
t_lua_port=9005

.PHONY: t

t_files=$(wildcard t/*.t)

rm_t:
	@rm -rf bin/runbyngx_root_900*

t: rm_t $(t_files)

t/%.t:
	@LUA_PATH="$(t_lua_path);;" prove --exec "$(pwd)/bin/run-test $(t_lua_port) $(pwd) " $@
