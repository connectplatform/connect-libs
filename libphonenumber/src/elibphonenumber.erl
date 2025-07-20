-module(elibphonenumber).

-behaviour(application).

-export([
    start/2,
    stop/1
]).

start(_StartType, _StartArgs) ->
    elibphonenumber_sup:start_link().

stop(_State) ->
    ok.
