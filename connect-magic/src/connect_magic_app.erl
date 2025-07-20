%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform File Magic - Application Module
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_magic_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%%===================================================================
%%% Application callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Start the ConnectPlatform File Magic application
%%--------------------------------------------------------------------
start(_StartType, _StartArgs) ->
    connect_magic_sup:start_link().

%%--------------------------------------------------------------------
%% @doc Stop the ConnectPlatform File Magic application
%%--------------------------------------------------------------------
stop(_State) ->
    ok. 