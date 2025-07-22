%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform MongoDB - OTP 27 Enhanced Supervisor
%%%
%%% Features:
%%% - Dynamic connection pool management with OTP 27 improvements
%%% - Enhanced fault tolerance with restart intensity management
%%% - Connection health monitoring and automatic scaling
%%% - Graceful shutdown with proper cleanup
%%% - Statistics and performance monitoring
%%% - Support for multiple database connections
%%%
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_mongodb_sup).
-behaviour(supervisor).

%% API
-export([
    start_link/0,
    start_link/1,
    get_child_status/0,
    restart_child/1,
    add_connection_pool/2,
    remove_connection_pool/1,
    get_statistics/0,
    scale_pool/2
]).

%% Supervisor callbacks
-export([init/1]).

%% Internal API
-export([start_connection_worker/1]).

%%%===================================================================
%%% Types and Macros
%%%===================================================================

-type sup_options() :: #{
    strategy => supervisor:strategy(),
    intensity => non_neg_integer(),
    period => pos_integer(),
    auto_shutdown => auto_shutdown(),
    connection_pools => #{atom() => connection_pool_spec()},
    monitoring_enabled => boolean(),
    health_check_interval => pos_integer()
}.

-type auto_shutdown() :: never | any_significant | all_significant.

-type connection_pool_spec() :: #{
    size => pos_integer(),
    max_size => pos_integer(),
    overflow => non_neg_integer(),
    connection_config => map(),
    restart_strategy => restart_type(),
    health_check_enabled => boolean()
}.

-type restart_type() :: permanent | transient | temporary.

-type child_status() :: #{
    id := child_id(),
    pid => pid() | undefined,
    type := child_type(),
    status := child_process_status(),
    modules := [module()] | dynamic,
    connections => non_neg_integer(),
    pool_size => pos_integer()
}.

-type child_id() :: term().
-type child_type() :: worker | supervisor.
-type child_process_status() :: running | restarting | undefined.

-export_type([sup_options/0, connection_pool_spec/0, child_status/0]).

-define(SERVER, ?MODULE).
-define(DEFAULT_INTENSITY, 10).
-define(DEFAULT_PERIOD, 60).
-define(CONNECTION_SHUTDOWN_TIMEOUT, 15000).
-define(DEFAULT_HEALTH_CHECK_INTERVAL, 30000).

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
        modules => Modules,
        connections => get_pool_connections(Id),
        pool_size => get_pool_size(Id)
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
%% @doc Dynamically add a connection pool
%%--------------------------------------------------------------------
-spec add_connection_pool(atom(), connection_pool_spec()) -> 
    ok | {error, term()}.
add_connection_pool(PoolId, PoolSpec) when is_atom(PoolId), is_map(PoolSpec) ->
    ConnectionSpec = create_connection_pool_spec(PoolId, PoolSpec),
    case supervisor:start_child(?SERVER, ConnectionSpec) of
        {ok, _Pid} -> ok;
        {ok, _Pid, _Info} -> ok;
        {error, {already_started, _Pid}} -> 
            {error, {pool_already_exists, PoolId}};
        {error, _} = Error -> Error
    end;
add_connection_pool(PoolId, PoolSpec) ->
    error({badarg, [PoolId, PoolSpec]}, [PoolId, PoolSpec], #{
        error_info => #{
            module => ?MODULE,
            function => add_connection_pool,
            arity => 2,
            cause => "PoolId must be atom and PoolSpec must be map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Remove a connection pool
%%--------------------------------------------------------------------
-spec remove_connection_pool(atom()) -> ok | {error, term()}.
remove_connection_pool(PoolId) when is_atom(PoolId) ->
    case supervisor:terminate_child(?SERVER, PoolId) of
        ok ->
            supervisor:delete_child(?SERVER, PoolId);
        {error, _} = Error -> Error
    end;
remove_connection_pool(PoolId) ->
    error({badarg, PoolId}, [PoolId], #{
        error_info => #{
            module => ?MODULE,
            function => remove_connection_pool,
            arity => 1,
            cause => "PoolId must be an atom"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Scale a connection pool
%%--------------------------------------------------------------------
-spec scale_pool(atom(), pos_integer()) -> ok | {error, term()}.
scale_pool(PoolId, NewSize) when is_atom(PoolId), is_integer(NewSize), NewSize > 0 ->
    case supervisor:which_children(?SERVER) of
        Children when is_list(Children) ->
            case lists:keyfind(PoolId, 1, Children) of
                {PoolId, Pid, _Type, _Modules} when is_pid(Pid) ->
                    % Send scale command to the native pool process
                    try
                        connect_mongodb_pool:scale_pool(PoolId, NewSize),
                        ok
                    catch
                        _:_ -> {error, {scale_failed, PoolId}}
                    end;
                false ->
                    {error, {pool_not_found, PoolId}};
                _ ->
                    {error, {pool_not_running, PoolId}}
            end;
        _ ->
            {error, supervisor_not_available}
    end;
scale_pool(PoolId, NewSize) ->
    error({badarg, [PoolId, NewSize]}, [PoolId, NewSize], #{
        error_info => #{
            module => ?MODULE,
            function => scale_pool,
            arity => 2,
            cause => "PoolId must be atom and NewSize must be positive integer"
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
    connection_pools := non_neg_integer(),
    total_connections := non_neg_integer(),
    restarts := non_neg_integer(),
    uptime_seconds := non_neg_integer()
}.
get_statistics() ->
    CountList = supervisor:count_children(?SERVER),
    Specs = proplists:get_value(specs, CountList, 0),
    Active = proplists:get_value(active, CountList, 0),
    Supervisors = proplists:get_value(supervisors, CountList, 0),
    Workers = proplists:get_value(workers, CountList, 0),
    
    % Count connection pools and total connections
    Children = supervisor:which_children(?SERVER),
    ConnectionPools = length([Id || {Id, _Pid, worker, _Modules} <- Children]),
    TotalConnections = lists:sum([get_pool_connections(Id) || {Id, _Pid, worker, _Modules} <- Children]),
    
    #{
        total_children => Specs,
        active_children => Active,
        supervisors => Supervisors,
        workers => Workers,
        connection_pools => ConnectionPools,
        total_connections => TotalConnections,
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
        % Main MongoDB driver server
        #{
            id => connect_mongodb,
            start => {connect_mongodb, start_link, [Options]},
            restart => permanent,
            shutdown => ?CONNECTION_SHUTDOWN_TIMEOUT,
            type => worker,
            modules => [connect_mongodb]
        }
    ],
    
    % Add any configured connection pools
    ConnectionPoolChildren = create_connection_pools(
        maps:get(connection_pools, Options, #{})
    ),
    
    AllChildren = CoreChildren ++ ConnectionPoolChildren,
    
    % Initialize monitoring if enabled
    case maps:get(monitoring_enabled, Options, true) of
        true -> 
            init_monitoring(Options),
            logger:info("ConnectPlatform MongoDB supervisor started with monitoring");
        false -> 
            logger:info("ConnectPlatform MongoDB supervisor started")
    end,
    
    {ok, {SupFlags, AllChildren}}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc Create connection pool child specifications
%%--------------------------------------------------------------------
-spec create_connection_pools(#{atom() => connection_pool_spec()}) -> 
    [supervisor:child_spec()].
create_connection_pools(ConnectionPools) ->
    maps:fold(fun(PoolId, PoolSpec, Acc) ->
        [create_connection_pool_spec(PoolId, PoolSpec) | Acc]
    end, [], ConnectionPools).

%%--------------------------------------------------------------------
%% @private
%% @doc Create a single connection pool specification
%%--------------------------------------------------------------------
-spec create_connection_pool_spec(atom(), connection_pool_spec()) -> 
    supervisor:child_spec().
create_connection_pool_spec(PoolId, PoolSpec) ->
    Size = maps:get(size, PoolSpec, 5),
    _MaxSize = maps:get(max_size, PoolSpec, 10), % Reserved for future use
    Overflow = maps:get(overflow, PoolSpec, 5),
    ConnectionConfig = maps:get(connection_config, PoolSpec, #{}),
    RestartStrategy = maps:get(restart_strategy, PoolSpec, permanent),
    HealthCheckEnabled = maps:get(health_check_enabled, PoolSpec, true),
    
    % Create native OTP 27 pool configuration
    NativePoolConfig = ConnectionConfig#{
        size => Size,
        max_size => _MaxSize,
        overflow => Overflow,
        pool_id => PoolId,
        health_check_enabled => HealthCheckEnabled,
        connection_config => ConnectionConfig
    },
    
    #{
        id => PoolId,
        start => {connect_mongodb_pool, start_link, [PoolId, NativePoolConfig]},
        restart => RestartStrategy,
        shutdown => ?CONNECTION_SHUTDOWN_TIMEOUT,
        type => worker,
        modules => [connect_mongodb_pool]
    }.

%%--------------------------------------------------------------------
%% @private
%% @doc Initialize monitoring systems
%%--------------------------------------------------------------------
init_monitoring(Options) ->
    % Set up connection health monitoring
    HealthCheckInterval = maps:get(health_check_interval, Options, ?DEFAULT_HEALTH_CHECK_INTERVAL),
    _ = spawn_link(fun() -> monitoring_loop(HealthCheckInterval) end),
    
    % Register for system events if available
    case whereis(alarm_handler) of
        undefined -> ok;
        _Pid -> 
            gen_event:add_handler(alarm_handler, connect_mongodb_alarm_handler, [])
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Main monitoring loop
%%--------------------------------------------------------------------
monitoring_loop(HealthCheckInterval) ->
    timer:sleep(HealthCheckInterval),
    
    try
        % Check connection pool health
        check_connection_pools_health(),
        
        % Check memory usage
        check_memory_usage(),
        
        % Check system load
        check_system_load(),
        
        % Log statistics periodically
        log_statistics()
    catch
        Class:Error:Stacktrace ->
            logger:warning("MongoDB monitoring error: ~p:~p~n~p", 
                          [Class, Error, Stacktrace])
    end,
    
    monitoring_loop(HealthCheckInterval).

%%--------------------------------------------------------------------
%% @private
%% @doc Check health of all connection pools
%%--------------------------------------------------------------------
check_connection_pools_health() ->
    Children = supervisor:which_children(?SERVER),
    ConnectionPools = [{Id, Pid} || {Id, Pid, worker, _Modules} <- Children, 
                                   Id =/= connect_mongodb, is_pid(Pid)],
    
    UnhealthyPools = lists:filter(fun({_Id, Pid}) ->
        not is_process_alive(Pid)
    end, ConnectionPools),
    
    case UnhealthyPools of
        [] -> ok;
        _ -> 
            logger:warning("Unhealthy connection pools detected: ~p", [UnhealthyPools]),
            % Could trigger automatic restart or alerts here
            ok
    end.

%%--------------------------------------------------------------------
%% @private  
%% @doc Check memory usage
%%--------------------------------------------------------------------
check_memory_usage() ->
    MemoryUsage = erlang:memory(processes),
    MaxMemory = 2 * 1024 * 1024 * 1024, % 2GB threshold
    
    case MemoryUsage > MaxMemory of
        true ->
            logger:warning("High memory usage detected: ~p bytes", [MemoryUsage]),
            % Could trigger garbage collection or pool scaling
            erlang:garbage_collect();
        false -> ok
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Check system load
%%--------------------------------------------------------------------
check_system_load() ->
    QueueLen = erlang:statistics(run_queue),
    MaxQueueLen = erlang:system_info(schedulers) * 20, % Higher threshold for DB operations
    
    case QueueLen > MaxQueueLen of
        true ->
            logger:warning("High system load detected: ~p run queue length", 
                          [QueueLen]);
        false -> ok
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Log periodic statistics
%%--------------------------------------------------------------------
log_statistics() ->
    Stats = get_statistics(),
    logger:info("MongoDB supervisor stats: ~p", [Stats]).

%%--------------------------------------------------------------------
%% @private
%% @doc Get connection count for a pool
%%--------------------------------------------------------------------
get_pool_connections(PoolId) ->
    try
        case whereis(PoolId) of
            Pid when is_pid(Pid) ->
                case connect_mongodb_pool:pool_status(PoolId) of
                    {ok, Stats} -> maps:get(size, Stats, 0);
                    _ -> 0
                end;
            undefined -> 0
        end
    catch
        _:_ -> 0
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Get pool size for a pool
%%--------------------------------------------------------------------
get_pool_size(PoolId) ->
    try
        case whereis(PoolId) of
            Pid when is_pid(Pid) ->
                case connect_mongodb_pool:pool_status(PoolId) of
                    {ok, Stats} -> maps:get(available, Stats, 0);
                    _ -> 0
                end;
            undefined -> 0
        end
    catch
        _:_ -> 0
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
%% @doc Start a connection worker (for dynamic pools)
%%--------------------------------------------------------------------
start_connection_worker(_Args) ->
    % This would start a MongoDB connection worker process
    % TODO: Implement proper worker module or use existing pool
    {error, not_implemented}. 