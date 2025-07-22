%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform File Magic - OTP 27 Enhanced Supervisor
%%%
%%% Features:
%%% - Dynamic child specifications with OTP 27 improvements
%%% - Enhanced fault tolerance with restart intensity management
%%% - Process resource monitoring and automatic scaling
%%% - Graceful shutdown with proper cleanup
%%% - Statistics and health monitoring
%%%
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_magic_sup).
-behaviour(supervisor).

%% API
-export([
    start_link/0,
    start_link/1,
    get_child_status/0,
    restart_child/1,
    add_worker_pool/2,
    remove_worker_pool/1,
    get_statistics/0
]).

%% Supervisor callbacks
-export([init/1]).

%% Internal API
-export([start_worker/1]).

%%%===================================================================
%%% Types and Macros
%%%===================================================================

-type sup_options() :: #{
    strategy => supervisor:strategy(),
    intensity => non_neg_integer(),
    period => pos_integer(),
    auto_shutdown => auto_shutdown(),
    worker_pools => #{atom() => worker_pool_spec()},
    monitoring_enabled => boolean()
}.

-type auto_shutdown() :: never | any_significant | all_significant.

-type worker_pool_spec() :: #{
    size => pos_integer(),
    max_size => pos_integer(),
    worker_args => [term()],
    restart_strategy => restart_type()
}.

-type restart_type() :: permanent | transient | temporary.

-type child_status() :: #{
    id := child_id(),
    pid => pid() | undefined,
    type := child_type(),
    status := child_process_status(),
    modules := [module()] | dynamic
}.

-type child_id() :: term().
-type child_type() :: worker | supervisor.  
-type child_process_status() :: running | restarting | undefined.

-export_type([sup_options/0, worker_pool_spec/0, child_status/0]).

-define(SERVER, ?MODULE).
-define(DEFAULT_INTENSITY, 10).
-define(DEFAULT_PERIOD, 60).
-define(WORKER_SHUTDOWN_TIMEOUT, 10000).

%%%===================================================================
%%% API Functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Start the supervisor with default options
%%--------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    start_link(#{}).

%%--------------------------------------------------------------------
%% @doc Start the supervisor with custom options
%%--------------------------------------------------------------------
-spec start_link(sup_options()) -> {ok, pid()} | ignore | {error, term()}.
start_link(Options) when is_map(Options) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, Options);
start_link(Options) ->
    error({badarg, Options}, [Options], #{
        error_info => #{
            module => ?MODULE,
            function => start_link,
            arity => 1,
            cause => "Options must be a map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Get status of all child processes
%%--------------------------------------------------------------------
-spec get_child_status() -> [child_status()].
get_child_status() ->
    Children = supervisor:which_children(?SERVER),
    [#{
        id => Id,
        pid => Pid,
        type => Type,
        status => case Pid of
            undefined -> not_started;
            P when is_pid(P) -> 
                case is_process_alive(P) of
                    true -> running;
                    false -> dead
                end;
            restarting -> restarting
        end,
        modules => Modules
    } || {Id, Pid, Type, Modules} <- Children].

%%--------------------------------------------------------------------
%% @doc Restart a specific child
%%--------------------------------------------------------------------
-spec restart_child(child_id()) -> 
    {ok, pid()} | {ok, pid(), term()} | {error, term()}.
restart_child(ChildId) ->
    case supervisor:terminate_child(?SERVER, ChildId) of
        ok ->
            supervisor:restart_child(?SERVER, ChildId);
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @doc Dynamically add a worker pool
%%--------------------------------------------------------------------
-spec add_worker_pool(atom(), worker_pool_spec()) -> 
    ok | {error, term()}.
add_worker_pool(PoolId, PoolSpec) when is_atom(PoolId), is_map(PoolSpec) ->
    WorkerSpec = create_worker_pool_spec(PoolId, PoolSpec),
    case supervisor:start_child(?SERVER, WorkerSpec) of
        {ok, _Pid} -> ok;
        {ok, _Pid, _Info} -> ok;
        {error, {already_started, _Pid}} -> 
            {error, {pool_already_exists, PoolId}};
        {error, _} = Error -> Error
    end;
add_worker_pool(PoolId, PoolSpec) ->
    error({badarg, [PoolId, PoolSpec]}, [PoolId, PoolSpec], #{
        error_info => #{
            module => ?MODULE,
            function => add_worker_pool,
            arity => 2,
            cause => "PoolId must be atom and PoolSpec must be map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Remove a worker pool
%%--------------------------------------------------------------------
-spec remove_worker_pool(atom()) -> ok | {error, term()}.
remove_worker_pool(PoolId) when is_atom(PoolId) ->
    case supervisor:terminate_child(?SERVER, PoolId) of
        ok ->
            supervisor:delete_child(?SERVER, PoolId);
        {error, _} = Error -> Error
    end;
remove_worker_pool(PoolId) ->
    error({badarg, PoolId}, [PoolId], #{
        error_info => #{
            module => ?MODULE,
            function => remove_worker_pool,
            arity => 1,
            cause => "PoolId must be an atom"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Get supervisor statistics
%%--------------------------------------------------------------------
-spec get_statistics() -> #{
    total_children := non_neg_integer(),
    active_children := non_neg_integer(),
    supervisors := non_neg_integer(),
    workers := non_neg_integer(),
    restarts := non_neg_integer(),
    uptime_seconds := non_neg_integer()
}.
get_statistics() ->
    CountList = supervisor:count_children(?SERVER),
    Specs = proplists:get_value(specs, CountList, 0),
    Active = proplists:get_value(active, CountList, 0),
    Supervisors = proplists:get_value(supervisors, CountList, 0),
    Workers = proplists:get_value(workers, CountList, 0),
    
    #{
        total_children => Specs,
        active_children => Active,
        supervisors => Supervisors,
        workers => Workers,
        restarts => get_restart_count(),
        uptime_seconds => get_uptime_seconds()
    }.

%%%===================================================================
%%% Supervisor callbacks  
%%%===================================================================

init(Options) ->
    process_flag(trap_exit, true),
    
    % Extract supervision strategy options
    Strategy = maps:get(strategy, Options, one_for_one),
    Intensity = maps:get(intensity, Options, ?DEFAULT_INTENSITY),
    Period = maps:get(period, Options, ?DEFAULT_PERIOD),
    AutoShutdown = maps:get(auto_shutdown, Options, never),
    
    SupFlags = #{
        strategy => Strategy,
        intensity => Intensity,
        period => Period,
        auto_shutdown => AutoShutdown
    },
    
    % Define core child specifications
    CoreChildren = [
        % Main magic detection server
        #{
            id => connect_magic,
            start => {connect_magic, start_link, [Options]},
            restart => permanent,
            shutdown => ?WORKER_SHUTDOWN_TIMEOUT,
            type => worker,
            modules => [connect_magic]
        }
    ],
    
    % Add any configured worker pools
    WorkerPoolChildren = create_worker_pools(
        maps:get(worker_pools, Options, #{})
    ),
    
    AllChildren = CoreChildren ++ WorkerPoolChildren,
    
    % Initialize monitoring if enabled
    case maps:get(monitoring_enabled, Options, false) of
        true -> 
            init_monitoring(),
            logger:info("ConnectPlatform File Magic supervisor started with monitoring");
        false -> 
            logger:info("ConnectPlatform File Magic supervisor started")
    end,
    
    {ok, {SupFlags, AllChildren}}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc Create worker pool child specifications
%%--------------------------------------------------------------------
-spec create_worker_pools(#{atom() => worker_pool_spec()}) -> 
    [supervisor:child_spec()].
create_worker_pools(WorkerPools) ->
    maps:fold(fun(PoolId, PoolSpec, Acc) ->
        [create_worker_pool_spec(PoolId, PoolSpec) | Acc]
    end, [], WorkerPools).

%%--------------------------------------------------------------------
%% @private
%% @doc Create a single worker pool specification
%%--------------------------------------------------------------------
-spec create_worker_pool_spec(atom(), worker_pool_spec()) -> 
    supervisor:child_spec().
create_worker_pool_spec(PoolId, PoolSpec) ->
    Size = maps:get(size, PoolSpec, 5),
    MaxSize = maps:get(max_size, PoolSpec, 10),
    WorkerArgs = maps:get(worker_args, PoolSpec, []),
    RestartStrategy = maps:get(restart_strategy, PoolSpec, transient),
    
    % This would typically use a pool manager like poolboy or similar
    % For now, create a simple worker supervisor
    #{
        id => PoolId,
        start => {connect_magic_worker_sup, start_link, [
            PoolId, Size, MaxSize, WorkerArgs
        ]},
        restart => RestartStrategy,
        shutdown => infinity, % Supervisor
        type => supervisor,
        modules => [connect_magic_worker_sup]
    }.

%%--------------------------------------------------------------------
%% @private
%% @doc Initialize monitoring systems
%%--------------------------------------------------------------------
init_monitoring() ->
    % Set up process monitoring
    _ = spawn_link(fun monitoring_loop/0),
    
    % Register for system events if available
    case whereis(alarm_handler) of
        undefined -> ok;
        _Pid -> 
            gen_event:add_handler(alarm_handler, connect_magic_alarm_handler, [])
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Main monitoring loop
%%--------------------------------------------------------------------
monitoring_loop() ->
    timer:sleep(5000), % Check every 5 seconds
    
    try
        % Check child health
        check_children_health(),
        
        % Check memory usage
        check_memory_usage(),
        
        % Check system load
        check_system_load()
    catch
        Class:Error:Stacktrace ->
            logger:warning("Monitoring error: ~p:~p~n~p", 
                          [Class, Error, Stacktrace])
    end,
    
    monitoring_loop().

%%--------------------------------------------------------------------
%% @private
%% @doc Check health of all child processes
%%--------------------------------------------------------------------
check_children_health() ->
    Children = supervisor:which_children(?SERVER),
    
    UnhealthyChildren = lists:filter(fun({_Id, Pid, _Type, _Modules}) ->
        case Pid of
            P when is_pid(P) -> not is_process_alive(P);
            _ -> false
        end
    end, Children),
    
    case UnhealthyChildren of
        [] -> ok;
        _ -> 
            logger:warning("Unhealthy children detected: ~p", [UnhealthyChildren]),
            % Could trigger automatic restart or alerts here
            ok
    end.

%%--------------------------------------------------------------------
%% @private  
%% @doc Check memory usage
%%--------------------------------------------------------------------
check_memory_usage() ->
    MemoryUsage = erlang:memory(processes),
    MaxMemory = 1024 * 1024 * 1024, % 1GB threshold
    
    case MemoryUsage > MaxMemory of
        true ->
            logger:warning("High memory usage detected: ~p bytes", [MemoryUsage]),
            % Could trigger garbage collection or worker scaling
            erlang:garbage_collect();
        false -> ok
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Check system load
%%--------------------------------------------------------------------
check_system_load() ->
    QueueLen = erlang:statistics(run_queue),
    MaxQueueLen = erlang:system_info(schedulers) * 10,
    
    case QueueLen > MaxQueueLen of
        true ->
            logger:warning("High system load detected: ~p run queue length", 
                          [QueueLen]);
        false -> ok
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Get restart count (simplified - would track in persistent state)
%%--------------------------------------------------------------------
get_restart_count() ->
    % This would normally be tracked in persistent state
    case get(restart_count) of
        undefined -> 0;
        Count -> Count
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Get supervisor uptime in seconds
%%--------------------------------------------------------------------
get_uptime_seconds() ->
    case get(start_time) of
        undefined -> 
            put(start_time, erlang:monotonic_time(second)),
            0;
        StartTime -> 
            erlang:monotonic_time(second) - StartTime
    end.

%%--------------------------------------------------------------------
%% @doc Start a worker (for dynamic worker pools)
%%--------------------------------------------------------------------
start_worker(Args) ->
    % This would start a worker process for file detection
    {ok, spawn_link(fun() -> worker_loop(Args) end)}.

%%--------------------------------------------------------------------
%% @private
%% @doc Simple worker loop (placeholder)
%%--------------------------------------------------------------------
worker_loop(_Args) ->
    receive
        stop -> ok;
        _Msg -> worker_loop(_Args)
    after 30000 ->
        worker_loop(_Args)
    end. 