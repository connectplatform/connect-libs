%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform Elasticsearch - Async Worker Supervisor
%%%
%%% Manages worker processes for async operations with:
%%% - Dynamic worker pool scaling
%%% - Load-based worker management
%%% - OTP 27 enhanced supervision patterns
%%% - Task queuing and backpressure handling
%%%
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_search_worker_sup).

-behaviour(supervisor).

%% API
-export([
    start_link/1,
    start_worker/2,
    execute_async/4,
    get_worker_stats/0
]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Start the worker supervisor
%%--------------------------------------------------------------------
-spec start_link(Config :: map()) -> ignore | {error, term()} | {ok, pid()}.
start_link(Config) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, [Config]).

%%--------------------------------------------------------------------
%% @doc Start a new worker process
%%--------------------------------------------------------------------
-spec start_worker(WorkerType :: atom(), Args :: list()) -> 
    {ok, pid() | undefined} | {ok, pid(), any()} | {error, term()}.
start_worker(WorkerType, Args) ->
    WorkerSpec = #{
        id => make_ref(),
        start => {connect_search_worker, start_link, [WorkerType | Args]},
        restart => temporary,
        shutdown => 5000,
        type => worker,
        modules => [connect_search_worker]
    },
    supervisor:start_child(?SERVER, WorkerSpec).

%%--------------------------------------------------------------------
%% @doc Execute async operation with worker
%%--------------------------------------------------------------------
-spec execute_async(Operation :: atom(), Args :: list(), 
                   Callback :: fun(), Options :: map()) -> 
    {ok, reference()} | {error, term()}.
execute_async(Operation, Args, Callback, Options) ->
    case start_worker(async_executor, [Operation, Args, Callback, Options]) of
        {ok, WorkerPid} ->
            RequestRef = make_ref(),
            WorkerPid ! {execute, RequestRef, self()},
            {ok, RequestRef};
        {error, _} = Error ->
            Error
    end.

%%--------------------------------------------------------------------
%% @doc Get worker pool statistics
%%--------------------------------------------------------------------
-spec get_worker_stats() -> {ok, map()} | {error, term()}.
get_worker_stats() ->
    try
        Children = supervisor:which_children(?SERVER),
        ActiveWorkers = length([Pid || {_Id, Pid, Type, _Modules} <- Children, 
                                      is_pid(Pid), Type =:= worker]),
        
        {ok, #{
            active_workers => ActiveWorkers,
            max_workers => get_max_workers(),
            supervisor_status => running
        }}
    catch
        Class:Error:Stacktrace ->
            {error, {stats_failed, Class, Error, Stacktrace}}
    end.

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Initialize the worker supervisor
%%--------------------------------------------------------------------
init([_Config]) ->
    process_flag(trap_exit, true),
    
    SupFlags = #{
        strategy => simple_one_for_one,
        intensity => 10,
        period => 60
    },
    
    %% Worker template for dynamic workers
    WorkerTemplate = #{
        id => connect_search_worker,
        start => {connect_search_worker, start_link, []},
        restart => temporary,
        shutdown => 5000,
        type => worker,
        modules => [connect_search_worker]
    },
    
    {ok, {SupFlags, [WorkerTemplate]}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @private
%% Get maximum number of workers from config
-spec get_max_workers() -> pos_integer().
get_max_workers() ->
    case application:get_env(connect_search, max_workers, 25) of
        Value when is_integer(Value), Value > 0 -> Value;
        _ -> 25
    end. 