%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform MongoDB Driver - Application Module
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_mongodb_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%%===================================================================
%%% Application callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Start the ConnectPlatform MongoDB application
%%--------------------------------------------------------------------
start(_StartType, _StartArgs) ->
    connect_mongodb_sup:start_link().

%%--------------------------------------------------------------------
%% @doc Stop the ConnectPlatform MongoDB application
%%--------------------------------------------------------------------
stop(_State) ->
    ok. 