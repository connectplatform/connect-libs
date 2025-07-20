%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform Elasticsearch Client - Application Module
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_search_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%%===================================================================
%%% Application callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Start the ConnectPlatform Elasticsearch application
%%--------------------------------------------------------------------
start(_StartType, _StartArgs) ->
    connect_search_sup:start_link().

%%--------------------------------------------------------------------
%% @doc Stop the ConnectPlatform Elasticsearch application
%%--------------------------------------------------------------------
stop(_State) ->
    ok. 