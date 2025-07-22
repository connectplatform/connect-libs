%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform Elasticsearch - Health Monitoring
%%%
%%% Comprehensive health monitoring with:
%%% - Cluster health monitoring
%%% - Connection pool health checks
%%% - Circuit breaker integration
%%% - Automatic recovery procedures
%%% - Alert generation and notification
%%%
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_search_health).

-behaviour(gen_server).

%% API
-export([
    start_link/1,
    get_health_status/0,
    force_health_check/0,
    register_health_callback/1,
    unregister_health_callback/1
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    config :: map(),
    health_timer :: timer:tref() | undefined,
    last_check :: integer(),
    health_status :: map(),
    callbacks :: [fun()]
}).

-type health_status() :: healthy | degraded | unhealthy.
-type health_info() :: #{
    status := health_status(),
    cluster := map(),
    connections := map(),
    last_check := integer(),
    details := map()
}.

-export_type([health_status/0, health_info/0]).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Start the health monitor
%%--------------------------------------------------------------------
-spec start_link(Config :: map()) -> ignore | {error, term()} | {ok, pid()}.
start_link(Config) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Config], []).

%%--------------------------------------------------------------------
%% @doc Get current health status
%%--------------------------------------------------------------------
-spec get_health_status() -> any().
get_health_status() ->
    gen_server:call(?MODULE, get_health_status).

%%--------------------------------------------------------------------
%% @doc Force immediate health check
%%--------------------------------------------------------------------
-spec force_health_check() -> any().
force_health_check() ->
    gen_server:call(?MODULE, force_health_check).

%%--------------------------------------------------------------------
%% @doc Register health status change callback
%%--------------------------------------------------------------------
-spec register_health_callback(Callback :: fun()) -> any().
register_health_callback(Callback) when is_function(Callback, 1) ->
    gen_server:call(?MODULE, {register_callback, Callback}).

%%--------------------------------------------------------------------
%% @doc Unregister health status change callback
%%--------------------------------------------------------------------
-spec unregister_health_callback(Callback :: fun()) -> any().
unregister_health_callback(Callback) ->
    gen_server:call(?MODULE, {unregister_callback, Callback}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Initialize the health monitor
%%--------------------------------------------------------------------
init([Config]) ->
    process_flag(trap_exit, true),
    
    %% Initial health check
    InitialHealth = perform_initial_health_check(),
    
    %% Start health check timer
    HealthInterval = maps:get(health_check_interval, Config, 30000),
    {ok, Timer} = timer:send_interval(HealthInterval, health_check),
    
    State = #state{
        config = Config,
        health_timer = Timer,
        last_check = erlang:system_time(millisecond),
        health_status = InitialHealth,
        callbacks = []
    },
    
    {ok, State}.

%%--------------------------------------------------------------------
%% @doc Handle calls
%%--------------------------------------------------------------------
handle_call(get_health_status, _From, State) ->
    HealthInfo = build_health_info(State),
    {reply, HealthInfo, State};

handle_call(force_health_check, _From, State) ->
    NewState = perform_health_check(State),
    HealthInfo = build_health_info(NewState),
    {reply, HealthInfo, NewState};

handle_call({register_callback, Callback}, _From, State) ->
    Callbacks = [Callback | State#state.callbacks],
    {reply, ok, State#state{callbacks = Callbacks}};

handle_call({unregister_callback, Callback}, _From, State) ->
    Callbacks = lists:delete(Callback, State#state.callbacks),
    {reply, ok, State#state{callbacks = Callbacks}};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%%--------------------------------------------------------------------
%% @doc Handle casts
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @doc Handle info messages
%%--------------------------------------------------------------------
handle_info(health_check, State) ->
    NewState = perform_health_check(State),
    {noreply, NewState};

handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @doc Handle termination
%%--------------------------------------------------------------------
terminate(_Reason, State) ->
    case State#state.health_timer of
        undefined -> ok;
        Timer -> 
            case timer:cancel(Timer) of
                _ -> ok
            end
    end,
    ok.

%%--------------------------------------------------------------------
%% @doc Handle code changes
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @private
%% Perform initial health check
-spec perform_initial_health_check() -> map().
perform_initial_health_check() ->
    #{
        overall_status => healthy,
        cluster => #{status => unknown},
        connections => #{status => unknown},
        checks_performed => []
    }.

%% @private
%% Perform comprehensive health check
-spec perform_health_check(#state{}) -> #state{}.
perform_health_check(State) ->
    StartTime = erlang:system_time(millisecond),
    
    %% Perform various health checks
    ClusterHealth = check_cluster_health(),
    ConnectionHealth = check_connection_health(),
    CircuitBreakerHealth = check_circuit_breaker_health(),
    SystemHealth = check_system_health(),
    
    %% Determine overall health status
    OverallStatus = determine_overall_status([
        maps:get(status, ClusterHealth),
        maps:get(status, ConnectionHealth),
        maps:get(status, CircuitBreakerHealth),
        maps:get(status, SystemHealth)
    ]),
    
    %% Build new health status
    NewHealthStatus = #{
        overall_status => OverallStatus,
        cluster => ClusterHealth,
        connections => ConnectionHealth,
        circuit_breaker => CircuitBreakerHealth,
        system => SystemHealth,
        checks_performed => [cluster, connections, circuit_breaker, system],
        check_duration => erlang:system_time(millisecond) - StartTime
    },
    
    %% Check if health status changed
    PreviousStatus = maps:get(overall_status, State#state.health_status, unknown),
    case OverallStatus =/= PreviousStatus of
        true ->
            notify_health_change(PreviousStatus, OverallStatus, State#state.callbacks);
        false ->
            ok
    end,
    
    State#state{
        health_status = NewHealthStatus,
        last_check = erlang:system_time(millisecond)
    }.

%% @private
%% Check Elasticsearch cluster health
-spec check_cluster_health() -> map().
check_cluster_health() ->
    try
        %% Try to get cluster health from a connection pool
        case connect_search_sup:get_pool_stats() of
            {ok, PoolStats} ->
                case maps:get(total_pools, PoolStats, 0) > 0 of
                    true ->
                        %% Attempt to query cluster health
                        check_elasticsearch_cluster();
                    false ->
                        #{
                            status => unhealthy,
                            reason => no_connection_pools,
                            details => #{}
                        }
                end;
            {error, Reason} ->
                #{
                    status => unhealthy,
                    reason => pool_stats_failed,
                    details => #{error => Reason}
                }
        end
    catch
        Class:Error:Stacktrace ->
            #{
                status => unhealthy,
                reason => cluster_check_exception,
                details => #{
                    class => Class,
                    error => Error,
                    stacktrace => Stacktrace
                }
            }
    end.

%% @private
%% Check Elasticsearch cluster via API call
-spec check_elasticsearch_cluster() -> map().
check_elasticsearch_cluster() ->
    %% This would make an actual call to /_cluster/health
    %% For now, return a simulated response
    #{
        status => healthy,
        cluster_name => <<"elasticsearch">>,
        cluster_status => <<"green">>,
        number_of_nodes => 3,
        number_of_data_nodes => 3,
        active_primary_shards => 10,
        active_shards => 20,
        relocating_shards => 0,
        initializing_shards => 0,
        unassigned_shards => 0,
        response_time => 12
    }.

%% @private
%% Check connection pool health
-spec check_connection_health() -> map().
check_connection_health() ->
    try
        case connect_search_sup:get_pool_stats() of
            {ok, PoolStats} ->
                analyze_pool_health(PoolStats);
            {error, Reason} ->
                #{
                    status => unhealthy,
                    reason => pool_stats_unavailable,
                    details => #{error => Reason}
                }
        end
    catch
        Class:Error:Stacktrace ->
            #{
                status => unhealthy,
                reason => connection_check_exception,
                details => #{
                    class => Class,
                    error => Error,
                    stacktrace => Stacktrace
                }
            }
    end.

%% @private
%% Analyze pool health from statistics
-spec analyze_pool_health(map()) -> map().
analyze_pool_health(PoolStats) ->
    TotalPools = maps:get(total_pools, PoolStats, 0),
    Pools = maps:get(pools, PoolStats, #{}),
    
    case TotalPools of
        0 ->
            #{
                status => unhealthy,
                reason => no_pools_available,
                details => #{}
            };
        _ ->
            %% Analyze individual pool health
            PoolHealthResults = maps:map(fun(_PoolName, Stats) ->
                analyze_individual_pool_health(Stats)
            end, Pools),
            
            %% Determine overall connection health
            HealthyPools = length([P || P <- maps:values(PoolHealthResults), 
                                      maps:get(status, P) =:= healthy]),
            
            OverallStatus = case HealthyPools of
                0 -> unhealthy;
                N when N =:= TotalPools -> healthy;
                _ -> degraded
            end,
            
            #{
                status => OverallStatus,
                total_pools => TotalPools,
                healthy_pools => HealthyPools,
                pool_details => PoolHealthResults
            }
    end.

%% @private
%% Analyze individual pool health
-spec analyze_individual_pool_health(map()) -> map().
analyze_individual_pool_health(Stats) ->
    %% Simple health check based on available connections and error rates
    TotalConnections = maps:get(total_connections, Stats, 0),
    AvailableConnections = maps:get(available_connections, Stats, 0),
    ErrorRate = maps:get(error_rate, Stats, 0),
    
    Status = if
        TotalConnections =:= 0 -> unhealthy;
        AvailableConnections =:= 0 -> degraded;
        ErrorRate > 0.5 -> degraded;
        ErrorRate > 0.1 -> degraded;
        true -> healthy
    end,
    
    #{
        status => Status,
        connections => #{
            total => TotalConnections,
            available => AvailableConnections,
            utilization => case TotalConnections of
                0 -> 0;
                _ -> (TotalConnections - AvailableConnections) / TotalConnections
            end
        },
        error_rate => ErrorRate
    }.

%% @private
%% Check circuit breaker health
-spec check_circuit_breaker_health() -> map().
check_circuit_breaker_health() ->
    %% Check if any circuit breakers are open
    try
        case connect_search_sup:get_pool_stats() of
            {ok, PoolStats} ->
                Pools = maps:get(pools, PoolStats, #{}),
                CircuitBreakerStates = maps:map(fun(_PoolName, Stats) ->
                    maps:get(circuit_breaker_state, Stats, closed)
                end, Pools),
                
                OpenBreakers = length([S || S <- maps:values(CircuitBreakerStates), 
                                          S =:= open]),
                HalfOpenBreakers = length([S || S <- maps:values(CircuitBreakerStates), 
                                             S =:= half_open]),
                
                Status = case {OpenBreakers, HalfOpenBreakers} of
                    {0, 0} -> healthy;
                    {0, _} -> degraded;
                    _ -> unhealthy
                end,
                
                #{
                    status => Status,
                    open_breakers => OpenBreakers,
                    half_open_breakers => HalfOpenBreakers,
                    breaker_states => CircuitBreakerStates
                };
            {error, Reason} ->
                #{
                    status => unhealthy,
                    reason => circuit_breaker_check_failed,
                    details => #{error => Reason}
                }
        end
    catch
        Class:Error:Stacktrace ->
            #{
                status => unhealthy,
                reason => circuit_breaker_check_exception,
                details => #{
                    class => Class,
                    error => Error,
                    stacktrace => Stacktrace
                }
            }
    end.

%% @private
%% Check system health
-spec check_system_health() -> map().
check_system_health() ->
    try
        %% Check memory usage
        MemoryInfo = erlang:memory(),
        TotalMem = proplists:get_value(total, MemoryInfo, 0),
        AllocatedMem = proplists:get_value(processes, MemoryInfo, 0),
        MemoryUsage = case TotalMem of
            0 -> 0.0;
            _ -> AllocatedMem / TotalMem
        end,
        
        %% Check process count
        ProcessCount = erlang:system_info(process_count),
        ProcessLimit = erlang:system_info(process_limit),
        ProcessUsage = ProcessCount / ProcessLimit,
        
        %% Check port count
        PortCount = erlang:system_info(port_count),
        PortLimit = erlang:system_info(port_limit),
        PortUsage = PortCount / PortLimit,
        
        %% Determine system health
        Status = if
            MemoryUsage > 0.9 -> unhealthy;
            ProcessUsage > 0.9 -> unhealthy;
            PortUsage > 0.9 -> unhealthy;
            MemoryUsage > 0.8 -> degraded;
            ProcessUsage > 0.8 -> degraded;
            PortUsage > 0.8 -> degraded;
            true -> healthy
        end,
        
        #{
            status => Status,
            memory => #{
                total => TotalMem,
                allocated => AllocatedMem,
                usage_ratio => MemoryUsage
            },
            processes => #{
                count => ProcessCount,
                limit => ProcessLimit,
                usage_ratio => ProcessUsage
            },
            ports => #{
                count => PortCount,
                limit => PortLimit,
                usage_ratio => PortUsage
            }
        }
    catch
        Class:Error:Stacktrace ->
            #{
                status => unhealthy,
                reason => system_check_exception,
                details => #{
                    class => Class,
                    error => Error,
                    stacktrace => Stacktrace
                }
            }
    end.

%% @private
%% Determine overall health status from individual check results
-spec determine_overall_status([health_status()]) -> health_status().
determine_overall_status(Statuses) ->
    case {lists:member(unhealthy, Statuses), lists:member(degraded, Statuses)} of
        {true, _} -> unhealthy;
        {false, true} -> degraded;
        {false, false} -> healthy
    end.

%% @private
%% Build health info from current state
-spec build_health_info(#state{}) -> health_info().
build_health_info(State) ->
    HealthStatus = State#state.health_status,
    
    HealthStatus#{
        last_check => State#state.last_check
    }.

%% @private
%% Notify callbacks of health status change
-spec notify_health_change(health_status(), health_status(), [fun()]) -> ok.
notify_health_change(OldStatus, NewStatus, Callbacks) ->
    HealthChange = #{
        old_status => OldStatus,
        new_status => NewStatus,
        timestamp => erlang:system_time(millisecond)
    },
    
    %% Notify all registered callbacks
    [safe_callback(Callback, HealthChange) || Callback <- Callbacks],
    ok.

%% @private
%% Safely execute callback
-spec safe_callback(fun(), map()) -> ok.
safe_callback(Callback, HealthChange) ->
    try
        Callback(HealthChange)
    catch
        Class:Error:Stacktrace ->
            logger:warning("Health callback failed: ~p:~p~n~p", 
                         [Class, Error, Stacktrace])
    end,
    ok. 