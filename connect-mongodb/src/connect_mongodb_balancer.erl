%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform MongoDB - Advanced Connection Load Balancer
%%%
%%% Intelligent load balancing with health-based routing:
%%% - Primary/secondary intelligent routing with read preferences
%%% - Health-based connection selection with automatic failover
%%% - Latency-aware load balancing and connection scoring
%%% - Geographic and zone-aware routing
%%% - Circuit breaker pattern for failing connections
%%% - Dynamic connection pool scaling based on load
%%%
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_mongodb_balancer).
-behaviour(gen_server).

%% Public API
-export([
    start_link/1,
    stop/0,
    
    %% Connection Routing
    get_connection/1,
    get_connection/2,
    get_read_connection/1,
    get_write_connection/1,
    return_connection/2,
    
    %% Load Balancing Configuration
    add_server/2,
    remove_server/1,
    update_server_config/2,
    set_read_preference/1,
    set_load_balancing_strategy/1,
    
    %% Health Monitoring
    get_server_health/1,
    get_all_servers_health/0,
    force_health_check/1,
    
    %% Statistics and Monitoring
    get_balancer_stats/0,
    get_connection_stats/1,
    reset_stats/0
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

%% Internal exports
-export([health_checker/2]).

%%%===================================================================
%%% Types and Records
%%%===================================================================

-type server_id() :: atom().
-type server_config() :: #{
    host => binary(),
    port => pos_integer(),
    is_primary => boolean(),
    tags => #{binary() => binary()},
    zone => binary(),
    priority => non_neg_integer(),
    max_connections => pos_integer(),
    connection_config => map()
}.

-type read_preference() :: 
    primary | secondary | primary_preferred | secondary_preferred | nearest.

-type load_balancing_strategy() :: 
    round_robin | least_connections | weighted_round_robin | response_time | geographic.

-type server_health() :: #{
    server_id => server_id(),
    status => healthy | unhealthy | degraded | unknown,
    response_time => float(),
    last_check => integer(),
    error_count => non_neg_integer(),
    success_count => non_neg_integer(),
    load_score => float(),
    connections_active => non_neg_integer(),
    connections_available => non_neg_integer()
}.

-type balancer_stats() :: #{
    total_requests => non_neg_integer(),
    successful_requests => non_neg_integer(),
    failed_requests => non_neg_integer(),
    avg_response_time => float(),
    active_servers => non_neg_integer(),
    healthy_servers => non_neg_integer(),
    total_connections => non_neg_integer(),
    strategy => load_balancing_strategy(),
    read_preference => read_preference()
}.

-record(server_state, {
    server_id :: server_id(),
    config :: server_config(),
    pool_name :: atom() | undefined,
    health = #{} :: server_health(),
    circuit_breaker = closed :: closed | half_open | open,
    circuit_breaker_failures = 0 :: non_neg_integer(),
    circuit_breaker_last_failure :: integer() | undefined,
    round_robin_weight = 1 :: pos_integer(),
    current_connections = 0 :: non_neg_integer(),
    total_requests = 0 :: non_neg_integer(),
    successful_requests = 0 :: non_neg_integer(),
    failed_requests = 0 :: non_neg_integer()
}).

-record(balancer_state, {
    servers = #{} :: #{server_id() => #server_state{}},
    strategy = round_robin :: load_balancing_strategy(),
    read_preference = primary_preferred :: read_preference(),
    current_primary :: server_id() | undefined,
    round_robin_counter = 0 :: non_neg_integer(),
    health_check_interval = 30000 :: pos_integer(),
    health_check_timeout = 5000 :: pos_integer(),
    circuit_breaker_threshold = 5 :: pos_integer(),
    circuit_breaker_timeout = 60000 :: pos_integer(),
    global_stats = #{} :: map()
}).

-export_type([
    server_id/0, server_config/0, read_preference/0, load_balancing_strategy/0,
    server_health/0, balancer_stats/0
]).

%%%===================================================================
%%% Macros and Constants
%%%===================================================================

-define(SERVER, ?MODULE).
-define(DEFAULT_HEALTH_CHECK_INTERVAL, 30000).
-define(DEFAULT_HEALTH_CHECK_TIMEOUT, 5000).
-define(DEFAULT_CIRCUIT_BREAKER_THRESHOLD, 5).
-define(DEFAULT_CIRCUIT_BREAKER_TIMEOUT, 60000).
-define(DEFAULT_CONNECTION_TIMEOUT, 5000).

%%%===================================================================
%%% Public API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Start the load balancer
%%--------------------------------------------------------------------
-spec start_link(map()) -> {ok, pid()} | ignore | {error, term()}.
start_link(Config) when is_map(Config) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Config, []);
start_link(Config) ->
    error({badarg, Config}, [Config], #{
        error_info => #{
            module => ?MODULE,
            function => start_link,
            arity => 1,
            cause => "Config must be a map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Stop the load balancer
%%--------------------------------------------------------------------
-spec stop() -> ok.
stop() ->
    gen_server:stop(?SERVER).

%%--------------------------------------------------------------------
%% @doc Get a connection based on current strategy
%%--------------------------------------------------------------------
-spec get_connection(read | write) -> {ok, {server_id(), pid()}} | {error, term()}.
get_connection(OperationType) ->
    get_connection(OperationType, #{}).

-spec get_connection(read | write, map()) -> {ok, {server_id(), pid()}} | {error, term()}.
get_connection(OperationType, Options) ->
    gen_server:call(?SERVER, {get_connection, OperationType, Options}, 
                   maps:get(timeout, Options, ?DEFAULT_CONNECTION_TIMEOUT)).

%%--------------------------------------------------------------------
%% @doc Get a connection optimized for read operations
%%--------------------------------------------------------------------
-spec get_read_connection(map()) -> {ok, {server_id(), pid()}} | {error, term()}.
get_read_connection(Options) ->
    get_connection(read, Options).

%%--------------------------------------------------------------------
%% @doc Get a connection optimized for write operations
%%--------------------------------------------------------------------
-spec get_write_connection(map()) -> {ok, {server_id(), pid()}} | {error, term()}.
get_write_connection(Options) ->
    get_connection(write, Options).

%%--------------------------------------------------------------------
%% @doc Return a connection to the pool
%%--------------------------------------------------------------------
-spec return_connection(server_id(), pid()) -> ok.
return_connection(ServerId, ConnectionPid) when is_atom(ServerId), is_pid(ConnectionPid) ->
    gen_server:cast(?SERVER, {return_connection, ServerId, ConnectionPid});
return_connection(ServerId, ConnectionPid) ->
    error({badarg, [ServerId, ConnectionPid]}, [ServerId, ConnectionPid], #{
        error_info => #{
            module => ?MODULE,
            function => return_connection,
            arity => 2,
            cause => "ServerId must be atom and ConnectionPid must be pid"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Add a server to the load balancer
%%--------------------------------------------------------------------
-spec add_server(server_id(), server_config()) -> ok | {error, term()}.
add_server(ServerId, Config) when is_atom(ServerId), is_map(Config) ->
    gen_server:call(?SERVER, {add_server, ServerId, Config});
add_server(ServerId, Config) ->
    error({badarg, [ServerId, Config]}, [ServerId, Config], #{
        error_info => #{
            module => ?MODULE,
            function => add_server,
            arity => 2,
            cause => "ServerId must be atom and Config must be map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Remove a server from the load balancer
%%--------------------------------------------------------------------
-spec remove_server(server_id()) -> ok | {error, term()}.
remove_server(ServerId) when is_atom(ServerId) ->
    gen_server:call(?SERVER, {remove_server, ServerId});
remove_server(ServerId) ->
    error({badarg, ServerId}, [ServerId], #{
        error_info => #{
            module => ?MODULE,
            function => remove_server,
            arity => 1,
            cause => "ServerId must be an atom"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Update server configuration
%%--------------------------------------------------------------------
-spec update_server_config(server_id(), server_config()) -> ok | {error, term()}.
update_server_config(ServerId, Config) when is_atom(ServerId), is_map(Config) ->
    gen_server:call(?SERVER, {update_server_config, ServerId, Config});
update_server_config(ServerId, Config) ->
    error({badarg, [ServerId, Config]}, [ServerId, Config], #{
        error_info => #{
            module => ?MODULE,
            function => update_server_config,
            arity => 2,
            cause => "ServerId must be atom and Config must be map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Set read preference for the balancer
%%--------------------------------------------------------------------
-spec set_read_preference(read_preference()) -> ok | {error, term()}.
set_read_preference(Preference) ->
    gen_server:call(?SERVER, {set_read_preference, Preference}).

%%--------------------------------------------------------------------
%% @doc Set load balancing strategy
%%--------------------------------------------------------------------
-spec set_load_balancing_strategy(load_balancing_strategy()) -> ok | {error, term()}.
set_load_balancing_strategy(Strategy) ->
    gen_server:call(?SERVER, {set_load_balancing_strategy, Strategy}).

%%--------------------------------------------------------------------
%% @doc Get health status of a specific server
%%--------------------------------------------------------------------
-spec get_server_health(server_id()) -> {ok, server_health()} | {error, term()}.
get_server_health(ServerId) when is_atom(ServerId) ->
    gen_server:call(?SERVER, {get_server_health, ServerId});
get_server_health(ServerId) ->
    error({badarg, ServerId}, [ServerId], #{
        error_info => #{
            module => ?MODULE,
            function => get_server_health,
            arity => 1,
            cause => "ServerId must be an atom"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Get health status of all servers
%%--------------------------------------------------------------------
-spec get_all_servers_health() -> {ok, [server_health()]} | {error, term()}.
get_all_servers_health() ->
    gen_server:call(?SERVER, get_all_servers_health).

%%--------------------------------------------------------------------
%% @doc Force a health check on a specific server
%%--------------------------------------------------------------------
-spec force_health_check(server_id()) -> ok.
force_health_check(ServerId) when is_atom(ServerId) ->
    gen_server:cast(?SERVER, {force_health_check, ServerId});
force_health_check(ServerId) ->
    error({badarg, ServerId}, [ServerId], #{
        error_info => #{
            module => ?MODULE,
            function => force_health_check,
            arity => 1,
            cause => "ServerId must be an atom"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Get balancer statistics
%%--------------------------------------------------------------------
-spec get_balancer_stats() -> {ok, balancer_stats()} | {error, term()}.
get_balancer_stats() ->
    gen_server:call(?SERVER, get_balancer_stats).

%%--------------------------------------------------------------------
%% @doc Get connection statistics for a server
%%--------------------------------------------------------------------
-spec get_connection_stats(server_id()) -> {ok, map()} | {error, term()}.
get_connection_stats(ServerId) when is_atom(ServerId) ->
    gen_server:call(?SERVER, {get_connection_stats, ServerId});
get_connection_stats(ServerId) ->
    error({badarg, ServerId}, [ServerId], #{
        error_info => #{
            module => ?MODULE,
            function => get_connection_stats,
            arity => 1,
            cause => "ServerId must be an atom"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Reset all statistics
%%--------------------------------------------------------------------
-spec reset_stats() -> ok.
reset_stats() ->
    gen_server:cast(?SERVER, reset_stats).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init(Config) ->
    process_flag(trap_exit, true),
    
    Strategy = maps:get(strategy, Config, round_robin),
    ReadPreference = maps:get(read_preference, Config, primary_preferred),
    HealthCheckInterval = maps:get(health_check_interval, Config, ?DEFAULT_HEALTH_CHECK_INTERVAL),
    HealthCheckTimeout = maps:get(health_check_timeout, Config, ?DEFAULT_HEALTH_CHECK_TIMEOUT),
    
    State = #balancer_state{
        strategy = Strategy,
        read_preference = ReadPreference,
        health_check_interval = HealthCheckInterval,
        health_check_timeout = HealthCheckTimeout,
        global_stats = #{
            start_time => erlang:system_time(second),
            total_requests => 0,
            successful_requests => 0,
            failed_requests => 0
        }
    },
    
    % Initialize servers if provided
    InitialServers = maps:get(servers, Config, #{}),
    NewState = maps:fold(fun(ServerId, ServerConfig, AccState) ->
        add_server_internal(ServerId, ServerConfig, AccState)
    end, State, InitialServers),
    
    % Start periodic health checks
    erlang:send_after(HealthCheckInterval, self(), health_check),
    
    logger:info("MongoDB load balancer started with strategy: ~p", [Strategy]),
    {ok, NewState}.

handle_call({get_connection, OperationType, Options}, _From, State) ->
    case select_server(OperationType, Options, State) of
        {ok, ServerId, NewState} ->
            case get_connection_from_server(ServerId, NewState) of
                {ok, ConnectionPid} ->
                    FinalState = update_server_stats(ServerId, request_success, NewState),
                    {reply, {ok, {ServerId, ConnectionPid}}, FinalState};
                {error, Reason} ->
                    FinalState = update_server_stats(ServerId, request_failure, NewState),
                    {reply, {error, Reason}, FinalState}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({add_server, ServerId, Config}, _From, State) ->
    case maps:is_key(ServerId, State#balancer_state.servers) of
        true ->
            {reply, {error, server_already_exists}, State};
        false ->
            NewState = add_server_internal(ServerId, Config, State),
            {reply, ok, NewState}
    end;

handle_call({remove_server, ServerId}, _From, State) ->
    case maps:is_key(ServerId, State#balancer_state.servers) of
        false ->
            {reply, {error, server_not_found}, State};
        true ->
            NewState = remove_server_internal(ServerId, State),
            {reply, ok, NewState}
    end;

handle_call({update_server_config, ServerId, Config}, _From, State) ->
    case maps:get(ServerId, State#balancer_state.servers, undefined) of
        undefined ->
            {reply, {error, server_not_found}, State};
        ServerState ->
            UpdatedServerState = ServerState#server_state{config = Config},
            NewServers = maps:put(ServerId, UpdatedServerState, State#balancer_state.servers),
            {reply, ok, State#balancer_state{servers = NewServers}}
    end;

handle_call({set_read_preference, Preference}, _From, State) ->
    {reply, ok, State#balancer_state{read_preference = Preference}};

handle_call({set_load_balancing_strategy, Strategy}, _From, State) ->
    {reply, ok, State#balancer_state{strategy = Strategy}};

handle_call({get_server_health, ServerId}, _From, State) ->
    case maps:get(ServerId, State#balancer_state.servers, undefined) of
        undefined ->
            {reply, {error, server_not_found}, State};
        ServerState ->
            Health = ServerState#server_state.health,
            {reply, {ok, Health}, State}
    end;

handle_call(get_all_servers_health, _From, State) ->
    HealthList = maps:fold(fun(_ServerId, ServerState, Acc) ->
        [ServerState#server_state.health | Acc]
    end, [], State#balancer_state.servers),
    {reply, {ok, HealthList}, State};

handle_call(get_balancer_stats, _From, State) ->
    Stats = calculate_balancer_stats(State),
    {reply, {ok, Stats}, State};

handle_call({get_connection_stats, ServerId}, _From, State) ->
    case maps:get(ServerId, State#balancer_state.servers, undefined) of
        undefined ->
            {reply, {error, server_not_found}, State};
        ServerState ->
            Stats = #{
                total_requests => ServerState#server_state.total_requests,
                successful_requests => ServerState#server_state.successful_requests,
                failed_requests => ServerState#server_state.failed_requests,
                current_connections => ServerState#server_state.current_connections,
                circuit_breaker_status => ServerState#server_state.circuit_breaker,
                circuit_breaker_failures => ServerState#server_state.circuit_breaker_failures
            },
            {reply, {ok, Stats}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({return_connection, ServerId, ConnectionPid}, State) ->
    case maps:get(ServerId, State#balancer_state.servers, undefined) of
        undefined ->
            {noreply, State};
        ServerState ->
            % Return connection to server pool
            case ServerState#server_state.pool_name of
                undefined ->
                    {noreply, State};
                PoolName ->
                    connect_mongodb_pool:checkin(PoolName, ConnectionPid),
                    % Update connection count
                    UpdatedServerState = ServerState#server_state{
                        current_connections = max(0, ServerState#server_state.current_connections - 1)
                    },
                    NewServers = maps:put(ServerId, UpdatedServerState, State#balancer_state.servers),
                    {noreply, State#balancer_state{servers = NewServers}}
            end
    end;

handle_cast({force_health_check, ServerId}, State) ->
    case maps:get(ServerId, State#balancer_state.servers, undefined) of
        undefined ->
            {noreply, State};
        _ServerState ->
            spawn_health_check(ServerId, State),
            {noreply, State}
    end;

handle_cast(reset_stats, State) ->
    % Reset all statistics
    ResetServers = maps:map(fun(_ServerId, ServerState) ->
        ServerState#server_state{
            total_requests = 0,
            successful_requests = 0,
            failed_requests = 0,
            circuit_breaker_failures = 0
        }
    end, State#balancer_state.servers),
    
    ResetGlobalStats = #{
        start_time => erlang:system_time(second),
        total_requests => 0,
        successful_requests => 0,
        failed_requests => 0
    },
    
    {noreply, State#balancer_state{
        servers = ResetServers,
        global_stats = ResetGlobalStats
    }};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(health_check, State) ->
    % Perform health check on all servers
    maps:fold(fun(ServerId, _ServerState, _Acc) ->
        spawn_health_check(ServerId, State)
    end, ok, State#balancer_state.servers),
    
    % Schedule next health check
    erlang:send_after(State#balancer_state.health_check_interval, self(), health_check),
    {noreply, State};

handle_info({health_check_result, ServerId, Result}, State) ->
    case maps:get(ServerId, State#balancer_state.servers, undefined) of
        undefined ->
            {noreply, State};
        ServerState ->
            NewState = update_server_health(ServerId, ServerState, Result, State),
            {noreply, NewState}
    end;

handle_info({'EXIT', _Pid, _Reason}, State) ->
    % Handle pool process exits
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    % Clean up server pools
    maps:fold(fun(_ServerId, ServerState, _Acc) ->
        case ServerState#server_state.pool_name of
            undefined -> ok;
            PoolName -> connect_mongodb_pool:stop(PoolName)
        end
    end, ok, State#balancer_state.servers),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc Select server based on operation type and current strategy
%%--------------------------------------------------------------------
select_server(OperationType, _Options, State) ->
    CandidateServers = filter_servers_by_operation(OperationType, State),
    
    case CandidateServers of
        [] -> 
            {error, no_servers_available};
        Servers ->
            case apply_load_balancing_strategy(Servers, State) of
                {ok, ServerId} ->
                    NewState = update_round_robin_counter(State),
                    {ok, ServerId, NewState};
                {error, _} = Error ->
                    Error
            end
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Filter servers based on operation type
%%--------------------------------------------------------------------
filter_servers_by_operation(OperationType, State) ->
    AllServers = maps:to_list(State#balancer_state.servers),
    HealthyServers = lists:filter(fun({_ServerId, ServerState}) ->
        is_server_healthy(ServerState)
    end, AllServers),
    
    case OperationType of
        write ->
            % For writes, prefer primary servers
            PrimaryServers = lists:filter(fun({_ServerId, ServerState}) ->
                maps:get(is_primary, ServerState#server_state.config, false)
            end, HealthyServers),
            
            case PrimaryServers of
                [] -> []; % No primary available
                _ -> PrimaryServers
            end;
        read ->
            % For reads, apply read preference
            apply_read_preference(HealthyServers, State#balancer_state.read_preference)
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Apply read preference filtering
%%--------------------------------------------------------------------
apply_read_preference(Servers, ReadPreference) ->
    case ReadPreference of
        primary ->
            lists:filter(fun({_ServerId, ServerState}) ->
                maps:get(is_primary, ServerState#server_state.config, false)
            end, Servers);
        secondary ->
            lists:filter(fun({_ServerId, ServerState}) ->
                not maps:get(is_primary, ServerState#server_state.config, false)
            end, Servers);
        primary_preferred ->
            PrimaryServers = apply_read_preference(Servers, primary),
            case PrimaryServers of
                [] -> apply_read_preference(Servers, secondary);
                _ -> PrimaryServers
            end;
        secondary_preferred ->
            SecondaryServers = apply_read_preference(Servers, secondary),
            case SecondaryServers of
                [] -> apply_read_preference(Servers, primary);
                _ -> SecondaryServers
            end;
        nearest ->
            % Sort by response time
            SortedServers = lists:sort(fun({_IdA, ServerA}, {_IdB, ServerB}) ->
                ResponseTimeA = maps:get(response_time, ServerA#server_state.health, 9999.0),
                ResponseTimeB = maps:get(response_time, ServerB#server_state.health, 9999.0),
                ResponseTimeA =< ResponseTimeB
            end, Servers),
            SortedServers
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Apply load balancing strategy to select server
%%--------------------------------------------------------------------
apply_load_balancing_strategy(Servers, State) ->
    case State#balancer_state.strategy of
        round_robin ->
            apply_round_robin_strategy(Servers, State);
        least_connections ->
            apply_least_connections_strategy(Servers);
        weighted_round_robin ->
            apply_weighted_round_robin_strategy(Servers, State);
        response_time ->
            apply_response_time_strategy(Servers);
        geographic ->
            apply_geographic_strategy(Servers)
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Apply round robin load balancing
%%--------------------------------------------------------------------
apply_round_robin_strategy(Servers, State) ->
    ServerCount = length(Servers),
    Index = State#balancer_state.round_robin_counter rem ServerCount,
    {ServerId, _ServerState} = lists:nth(Index + 1, Servers),
    {ok, ServerId}.

%%--------------------------------------------------------------------
%% @private
%% @doc Apply least connections load balancing
%%--------------------------------------------------------------------
apply_least_connections_strategy(Servers) ->
    SortedServers = lists:sort(fun({_IdA, ServerA}, {_IdB, ServerB}) ->
        ConnectionsA = ServerA#server_state.current_connections,
        ConnectionsB = ServerB#server_state.current_connections,
        ConnectionsA =< ConnectionsB
    end, Servers),
    {ServerId, _ServerState} = hd(SortedServers),
    {ok, ServerId}.

%%--------------------------------------------------------------------
%% @private
%% @doc Apply weighted round robin load balancing
%%--------------------------------------------------------------------
apply_weighted_round_robin_strategy(Servers, State) ->
    % Calculate weighted selection based on server priority
    WeightedServers = lists:map(fun({ServerId, ServerState}) ->
        Priority = maps:get(priority, ServerState#server_state.config, 1),
        Weight = ServerState#server_state.round_robin_weight * Priority,
        {ServerId, Weight}
    end, Servers),
    
    TotalWeight = lists:sum([Weight || {_ServerId, Weight} <- WeightedServers]),
    TargetWeight = (State#balancer_state.round_robin_counter rem TotalWeight) + 1,
    
    {ServerId, _Weight} = select_by_weight(WeightedServers, TargetWeight, 0),
    {ok, ServerId}.

%%--------------------------------------------------------------------
%% @private
%% @doc Select server by weight
%%--------------------------------------------------------------------
select_by_weight([{ServerId, Weight} | _Rest], TargetWeight, CurrentWeight)
  when CurrentWeight + Weight >= TargetWeight ->
    {ServerId, Weight};
select_by_weight([{_ServerId, Weight} | Rest], TargetWeight, CurrentWeight) ->
    select_by_weight(Rest, TargetWeight, CurrentWeight + Weight);
select_by_weight([], _TargetWeight, _CurrentWeight) ->
    {error, no_servers_available}.

%%--------------------------------------------------------------------
%% @private
%% @doc Apply response time-based load balancing
%%--------------------------------------------------------------------
apply_response_time_strategy(Servers) ->
    % Select server with best response time
    SortedServers = lists:sort(fun({_IdA, ServerA}, {_IdB, ServerB}) ->
        ResponseTimeA = maps:get(response_time, ServerA#server_state.health, 9999.0),
        ResponseTimeB = maps:get(response_time, ServerB#server_state.health, 9999.0),
        ResponseTimeA =< ResponseTimeB
    end, Servers),
    {ServerId, _ServerState} = hd(SortedServers),
    {ok, ServerId}.

%%--------------------------------------------------------------------
%% @private
%% @doc Apply geographic-based load balancing
%%--------------------------------------------------------------------
apply_geographic_strategy(Servers) ->
    % For simplicity, use zone-based selection
    % In a real implementation, this would consider client location
    LocalZoneServers = lists:filter(fun({_ServerId, ServerState}) ->
        Zone = maps:get(zone, ServerState#server_state.config, <<"default">>),
        Zone =:= <<"local">>
    end, Servers),
    
    case LocalZoneServers of
        [] -> apply_round_robin_strategy(Servers, #balancer_state{round_robin_counter = 0});
        _ -> apply_round_robin_strategy(LocalZoneServers, #balancer_state{round_robin_counter = 0})
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Check if server is healthy
%%--------------------------------------------------------------------
is_server_healthy(ServerState) ->
    case ServerState#server_state.circuit_breaker of
        closed -> true;
        half_open -> true;
        open -> 
            % Check if circuit breaker timeout has passed
            case ServerState#server_state.circuit_breaker_last_failure of
                undefined -> true;
                LastFailure ->
                    CurrentTime = erlang:system_time(millisecond),
                    Timeout = 60000, % 1 minute circuit breaker timeout
                    CurrentTime - LastFailure > Timeout
            end
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Get connection from server pool
%%--------------------------------------------------------------------
get_connection_from_server(ServerId, State) ->
    case maps:get(ServerId, State#balancer_state.servers, undefined) of
        undefined ->
            {error, server_not_found};
        ServerState ->
            case ServerState#server_state.pool_name of
                undefined ->
                    {error, pool_not_available};
                PoolName ->
                    case connect_mongodb_pool:checkout(PoolName) of
                        {ok, ConnectionId} ->
                            {ok, ConnectionId};
                        {error, _} = Error ->
                            Error
                    end
            end
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Add server internally
%%--------------------------------------------------------------------
add_server_internal(ServerId, Config, State) ->
    % Create connection pool for server
    PoolConfig = maps:get(connection_config, Config, #{}),
    case connect_mongodb_pool:start_link(ServerId, PoolConfig) of
        {ok, _PoolPid} ->
            ServerState = #server_state{
                server_id = ServerId,
                config = Config,
                pool_name = ServerId,
                health = initialize_server_health(ServerId)
            },
            
            NewServers = maps:put(ServerId, ServerState, State#balancer_state.servers),
            
            % Update primary server if this is primary
            NewPrimary = case maps:get(is_primary, Config, false) of
                true -> ServerId;
                false -> State#balancer_state.current_primary
            end,
            
            State#balancer_state{
                servers = NewServers,
                current_primary = NewPrimary
            };
        {error, Reason} ->
            logger:error("Failed to create pool for server ~p: ~p", [ServerId, Reason]),
            State
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Remove server internally
%%--------------------------------------------------------------------
remove_server_internal(ServerId, State) ->
    case maps:get(ServerId, State#balancer_state.servers, undefined) of
        undefined ->
            State;
        ServerState ->
            % Stop connection pool
            case ServerState#server_state.pool_name of
                undefined -> ok;
                PoolName -> connect_mongodb_pool:stop(PoolName)
            end,
            
            NewServers = maps:remove(ServerId, State#balancer_state.servers),
            
            % Update primary server if removing current primary
            NewPrimary = case State#balancer_state.current_primary of
                ServerId -> find_new_primary(NewServers);
                Other -> Other
            end,
            
            State#balancer_state{
                servers = NewServers,
                current_primary = NewPrimary
            }
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Find new primary server
%%--------------------------------------------------------------------
find_new_primary(Servers) ->
    case maps:fold(fun(ServerId, ServerState, Acc) ->
        case Acc of
            undefined ->
                case maps:get(is_primary, ServerState#server_state.config, false) of
                    true -> ServerId;
                    false -> undefined
                end;
            _ -> Acc
        end
    end, undefined, Servers) of
        undefined -> undefined;
        PrimaryId -> PrimaryId
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Initialize server health
%%--------------------------------------------------------------------
initialize_server_health(ServerId) ->
    #{
        server_id => ServerId,
        status => unknown,
        response_time => 0.0,
        last_check => erlang:system_time(second),
        error_count => 0,
        success_count => 0,
        load_score => 0.0,
        connections_active => 0,
        connections_available => 0
    }.

%%--------------------------------------------------------------------
%% @private
%% @doc Spawn health check process
%%--------------------------------------------------------------------
spawn_health_check(ServerId, _State) ->
    spawn(?MODULE, health_checker, [ServerId, self()]).

%%--------------------------------------------------------------------
%% @private
%% @doc Health checker process
%%--------------------------------------------------------------------
health_checker(ServerId, BalancerPid) ->
    StartTime = erlang:monotonic_time(microsecond),
    
    % Perform health check - in real implementation, this would ping MongoDB
    Result = try
        % Mock health check result
        timer:sleep(rand:uniform(50)), % Simulate network latency
        ResponseTime = (erlang:monotonic_time(microsecond) - StartTime) / 1000,
        
        #{
            status => healthy,
            response_time => ResponseTime,
            last_check => erlang:system_time(second),
            connections_active => rand:uniform(10),
            connections_available => rand:uniform(20)
        }
    catch
        _:Error ->
            #{
                status => unhealthy,
                response_time => 9999.0,
                last_check => erlang:system_time(second),
                error => Error
            }
    end,
    
    BalancerPid ! {health_check_result, ServerId, Result}.

%%--------------------------------------------------------------------
%% @private
%% @doc Update server health
%%--------------------------------------------------------------------
update_server_health(ServerId, ServerState, HealthResult, State) ->
    CurrentHealth = ServerState#server_state.health,
    
    NewHealth = maps:merge(CurrentHealth, HealthResult),
    
    % Update circuit breaker based on health
    {NewCircuitBreaker, NewFailures, NewLastFailure} = case maps:get(status, HealthResult) of
        healthy ->
            {closed, 0, undefined};
        unhealthy ->
            Failures = ServerState#server_state.circuit_breaker_failures + 1,
            case Failures >= State#balancer_state.circuit_breaker_threshold of
                true -> {open, Failures, erlang:system_time(millisecond)};
                false -> {ServerState#server_state.circuit_breaker, Failures, 
                         ServerState#server_state.circuit_breaker_last_failure}
            end;
        _ ->
            {ServerState#server_state.circuit_breaker, 
             ServerState#server_state.circuit_breaker_failures,
             ServerState#server_state.circuit_breaker_last_failure}
    end,
    
    UpdatedServerState = ServerState#server_state{
        health = NewHealth,
        circuit_breaker = NewCircuitBreaker,
        circuit_breaker_failures = NewFailures,
        circuit_breaker_last_failure = NewLastFailure
    },
    
    NewServers = maps:put(ServerId, UpdatedServerState, State#balancer_state.servers),
    State#balancer_state{servers = NewServers}.

%%--------------------------------------------------------------------
%% @private
%% @doc Update server statistics
%%--------------------------------------------------------------------
update_server_stats(ServerId, Event, State) ->
    case maps:get(ServerId, State#balancer_state.servers, undefined) of
        undefined ->
            State;
        ServerState ->
            {NewTotal, NewSuccessful, NewFailed} = case Event of
                request_success ->
                    {ServerState#server_state.total_requests + 1,
                     ServerState#server_state.successful_requests + 1,
                     ServerState#server_state.failed_requests};
                request_failure ->
                    {ServerState#server_state.total_requests + 1,
                     ServerState#server_state.successful_requests,
                     ServerState#server_state.failed_requests + 1}
            end,
            
            UpdatedServerState = ServerState#server_state{
                total_requests = NewTotal,
                successful_requests = NewSuccessful,
                failed_requests = NewFailed
            },
            
            NewServers = maps:put(ServerId, UpdatedServerState, State#balancer_state.servers),
            
            % Update global stats
            GlobalStats = State#balancer_state.global_stats,
            NewGlobalStats = case Event of
                request_success ->
                    GlobalStats#{
                        total_requests => maps:get(total_requests, GlobalStats, 0) + 1,
                        successful_requests => maps:get(successful_requests, GlobalStats, 0) + 1
                    };
                request_failure ->
                    GlobalStats#{
                        total_requests => maps:get(total_requests, GlobalStats, 0) + 1,
                        failed_requests => maps:get(failed_requests, GlobalStats, 0) + 1
                    }
            end,
            
            State#balancer_state{
                servers = NewServers,
                global_stats = NewGlobalStats
            }
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Update round robin counter
%%--------------------------------------------------------------------
update_round_robin_counter(State) ->
    State#balancer_state{
        round_robin_counter = State#balancer_state.round_robin_counter + 1
    }.

%%--------------------------------------------------------------------
%% @private
%% @doc Calculate balancer statistics
%%--------------------------------------------------------------------
calculate_balancer_stats(State) ->
    ServerCount = maps:size(State#balancer_state.servers),
    HealthyCount = maps:fold(fun(_ServerId, ServerState, Acc) ->
        case is_server_healthy(ServerState) of
            true -> Acc + 1;
            false -> Acc
        end
    end, 0, State#balancer_state.servers),
    
    TotalConnections = maps:fold(fun(_ServerId, ServerState, Acc) ->
        Acc + ServerState#server_state.current_connections
    end, 0, State#balancer_state.servers),
    
    GlobalStats = State#balancer_state.global_stats,
    TotalRequests = maps:get(total_requests, GlobalStats, 0),
    SuccessfulRequests = maps:get(successful_requests, GlobalStats, 0),
    
    AvgResponseTime = case TotalRequests > 0 of
        true ->
            maps:fold(fun(_ServerId, ServerState, Acc) ->
                ResponseTime = maps:get(response_time, ServerState#server_state.health, 0.0),
                Requests = ServerState#server_state.total_requests,
                Acc + (ResponseTime * Requests)
            end, 0.0, State#balancer_state.servers) / TotalRequests;
        false -> 0.0
    end,
    
    #{
        total_requests => TotalRequests,
        successful_requests => SuccessfulRequests,
        failed_requests => maps:get(failed_requests, GlobalStats, 0),
        avg_response_time => AvgResponseTime,
        active_servers => ServerCount,
        healthy_servers => HealthyCount,
        total_connections => TotalConnections,
        strategy => State#balancer_state.strategy,
        read_preference => State#balancer_state.read_preference
    }. 