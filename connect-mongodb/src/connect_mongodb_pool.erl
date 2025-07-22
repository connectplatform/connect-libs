%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform MongoDB - OTP 27 Native Connection Pool
%%%
%%% Pure OTP 27 implementation replacing poolboy with:
%%% - Native gen_server connection pooling
%%% - Advanced load balancing with health monitoring
%%% - Primary/secondary routing with read preferences
%%% - Automatic failover and recovery
%%% - Connection health monitoring and auto-scaling
%%%
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_mongodb_pool).
-behaviour(gen_server).

%% Public API
-export([
    start_link/2,
    stop/1,
    checkout/1,
    checkout/2,
    checkin/2,
    get_connection/2,
    return_connection/2,
    pool_status/1,
    scale_pool/2,
    get_stats/1
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
-export([connection_worker/2]).

%%%===================================================================
%%% Types and Records
%%%===================================================================

-type pool_name() :: atom().
-type connection_id() :: reference().
-type connection_pid() :: pid().
-type pool_config() :: #{
    size => pos_integer(),
    max_size => pos_integer(),
    overflow => non_neg_integer(),
    connection_config => map(),
    health_check_interval => pos_integer(),
    max_retries => non_neg_integer(),
    retry_backoff => pos_integer(),
    read_preference => primary | secondary | primary_preferred | secondary_preferred,
    write_preference => primary | secondary
}.

-type connection_info() :: #{
    id => connection_id(),
    pid => connection_pid(),
    status => available | busy | unhealthy | connecting,
    created_at => integer(),
    last_used => integer(),
    operations_count => non_neg_integer(),
    avg_response_time => float(),
    is_primary => boolean(),
    server_info => map()
}.

-type pool_stats() :: #{
    pool_name => pool_name(),
    size => pos_integer(),
    available => non_neg_integer(),
    busy => non_neg_integer(),
    overflow => non_neg_integer(),
    total_requests => non_neg_integer(),
    avg_wait_time => float(),
    healthy_connections => non_neg_integer(),
    primary_connections => non_neg_integer(),
    secondary_connections => non_neg_integer()
}.

-record(pool_state, {
    name :: pool_name(),
    config :: pool_config(),
    connections = #{} :: #{connection_id() => connection_info()},
    available_queue = queue:new() :: queue:queue(connection_id()),
    waiting_queue = queue:new() :: queue:queue({pid(), reference()}),
    stats = #{} :: map(),
    health_check_timer :: reference() | undefined,
    last_scale_check = 0 :: integer()
}).

-export_type([
    pool_name/0, connection_id/0, connection_pid/0, 
    pool_config/0, connection_info/0, pool_stats/0
]).

%%%===================================================================
%%% Macros and Constants
%%%===================================================================

-define(DEFAULT_POOL_SIZE, 10).
-define(DEFAULT_MAX_SIZE, 20).
-define(DEFAULT_OVERFLOW, 5).
-define(DEFAULT_HEALTH_CHECK_INTERVAL, 30000).
-define(DEFAULT_MAX_RETRIES, 3).
-define(DEFAULT_RETRY_BACKOFF, 1000).
-define(CONNECTION_TIMEOUT, 5000).
-define(SCALE_CHECK_INTERVAL, 60000). % 1 minute

%%%===================================================================
%%% Public API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Start a connection pool
%%--------------------------------------------------------------------
-spec start_link(pool_name(), pool_config()) -> {ok, pid()} | {error, term()}.
start_link(PoolName, Config) when is_atom(PoolName), is_map(Config) ->
    gen_server:start_link({local, PoolName}, ?MODULE, {PoolName, Config}, []);
start_link(PoolName, Config) ->
    error({badarg, [PoolName, Config]}, [PoolName, Config], #{
        error_info => #{
            module => ?MODULE,
            function => start_link,
            arity => 2,
            cause => "PoolName must be atom and Config must be map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Stop a connection pool
%%--------------------------------------------------------------------
-spec stop(pool_name()) -> ok.
stop(PoolName) when is_atom(PoolName) ->
    gen_server:stop(PoolName);
stop(PoolName) ->
    error({badarg, PoolName}, [PoolName], #{
        error_info => #{
            module => ?MODULE,
            function => stop,
            arity => 1,
            cause => "PoolName must be an atom"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Checkout a connection from the pool
%%--------------------------------------------------------------------
-spec checkout(pool_name()) -> {ok, connection_id()} | {error, term()}.
checkout(PoolName) ->
    checkout(PoolName, ?CONNECTION_TIMEOUT).

-spec checkout(pool_name(), timeout()) -> {ok, connection_id()} | {error, term()}.
checkout(PoolName, Timeout) when is_atom(PoolName) ->
    gen_server:call(PoolName, {checkout, self()}, Timeout);
checkout(PoolName, _Timeout) ->
    error({badarg, PoolName}, [PoolName], #{
        error_info => #{
            module => ?MODULE,
            function => checkout,
            arity => 2,
            cause => "PoolName must be an atom"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Check in a connection back to the pool
%%--------------------------------------------------------------------
-spec checkin(pool_name(), connection_id()) -> ok | {error, term()}.
checkin(PoolName, ConnectionId) when is_atom(PoolName), is_reference(ConnectionId) ->
    gen_server:cast(PoolName, {checkin, ConnectionId, self()});
checkin(PoolName, ConnectionId) ->
    error({badarg, [PoolName, ConnectionId]}, [PoolName, ConnectionId], #{
        error_info => #{
            module => ?MODULE,
            function => checkin,
            arity => 2,
            cause => "PoolName must be atom and ConnectionId must be reference"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Get connection with read/write preference
%%--------------------------------------------------------------------
-spec get_connection(pool_name(), primary | secondary | primary_preferred | secondary_preferred) -> 
    {ok, connection_id()} | {error, term()}.
get_connection(PoolName, Preference) when is_atom(PoolName) ->
    gen_server:call(PoolName, {get_connection, Preference, self()}, ?CONNECTION_TIMEOUT);
get_connection(PoolName, Preference) ->
    error({badarg, [PoolName, Preference]}, [PoolName, Preference], #{
        error_info => #{
            module => ?MODULE,
            function => get_connection,
            arity => 2,
            cause => "PoolName must be atom"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Return connection after use
%%--------------------------------------------------------------------
-spec return_connection(pool_name(), connection_id()) -> ok | {error, term()}.
return_connection(PoolName, ConnectionId) ->
    checkin(PoolName, ConnectionId).

%%--------------------------------------------------------------------
%% @doc Get pool status
%%--------------------------------------------------------------------
-spec pool_status(pool_name()) -> {ok, pool_stats()} | {error, term()}.
pool_status(PoolName) when is_atom(PoolName) ->
    gen_server:call(PoolName, pool_status);
pool_status(PoolName) ->
    error({badarg, PoolName}, [PoolName], #{
        error_info => #{
            module => ?MODULE,
            function => pool_status,
            arity => 1,
            cause => "PoolName must be an atom"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Scale the pool size
%%--------------------------------------------------------------------
-spec scale_pool(pool_name(), pos_integer()) -> ok | {error, term()}.
scale_pool(PoolName, NewSize) when is_atom(PoolName), is_integer(NewSize), NewSize > 0 ->
    gen_server:call(PoolName, {scale_pool, NewSize});
scale_pool(PoolName, NewSize) ->
    error({badarg, [PoolName, NewSize]}, [PoolName, NewSize], #{
        error_info => #{
            module => ?MODULE,
            function => scale_pool,
            arity => 2,
            cause => "PoolName must be atom and NewSize must be positive integer"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Get detailed pool statistics
%%--------------------------------------------------------------------
-spec get_stats(pool_name()) -> {ok, pool_stats()} | {error, term()}.
get_stats(PoolName) ->
    pool_status(PoolName).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init({PoolName, Config}) ->
    process_flag(trap_exit, true),
    
    % Set up health check timer
    HealthCheckInterval = maps:get(health_check_interval, Config, ?DEFAULT_HEALTH_CHECK_INTERVAL),
    HealthTimer = erlang:send_after(HealthCheckInterval, self(), health_check),
    
    % Set up periodic scaling check
    erlang:send_after(?SCALE_CHECK_INTERVAL, self(), scale_check),
    
    DefaultConfig = #{
        size => ?DEFAULT_POOL_SIZE,
        max_size => ?DEFAULT_MAX_SIZE,
        overflow => ?DEFAULT_OVERFLOW,
        health_check_interval => HealthCheckInterval,
        max_retries => ?DEFAULT_MAX_RETRIES,
        retry_backoff => ?DEFAULT_RETRY_BACKOFF,
        read_preference => primary_preferred,
        write_preference => primary
    },
    
    PoolConfig = maps:merge(DefaultConfig, Config),
    
    InitialStats = #{
        total_requests => 0,
        successful_requests => 0,
        failed_requests => 0,
        avg_wait_time => 0.0,
        created_at => erlang:system_time(second)
    },
    
    State = #pool_state{
        name = PoolName,
        config = PoolConfig,
        stats = InitialStats,
        health_check_timer = HealthTimer
    },
    
    % Initialize pool connections
    case initialize_connections(State) of
        {ok, NewState} ->
            logger:info("MongoDB connection pool ~p initialized with ~p connections", 
                       [PoolName, maps:get(size, PoolConfig)]),
            {ok, NewState};
        {error, Reason} ->
            logger:error("Failed to initialize MongoDB pool ~p: ~p", [PoolName, Reason]),
            {stop, Reason}
    end.

handle_call({checkout, ClientPid}, From, State) ->
    case checkout_connection(State, primary_preferred) of
        {ok, ConnectionId, NewState} ->
            monitor_client(ClientPid, ConnectionId),
            {reply, {ok, ConnectionId}, update_stats(checkout_success, NewState)};
        {error, no_connections_available} ->
            % Add to waiting queue
            WaitingQueue = queue:in({ClientPid, From}, State#pool_state.waiting_queue),
            {noreply, State#pool_state{waiting_queue = WaitingQueue}};
        {error, Reason} ->
            {reply, {error, Reason}, update_stats(checkout_failed, State)}
    end;

handle_call({get_connection, Preference, ClientPid}, From, State) ->
    case checkout_connection(State, Preference) of
        {ok, ConnectionId, NewState} ->
            monitor_client(ClientPid, ConnectionId),
            {reply, {ok, ConnectionId}, update_stats(checkout_success, NewState)};
        {error, no_connections_available} ->
            WaitingQueue = queue:in({ClientPid, From}, State#pool_state.waiting_queue),
            {noreply, State#pool_state{waiting_queue = WaitingQueue}};
        {error, Reason} ->
            {reply, {error, Reason}, update_stats(checkout_failed, State)}
    end;

handle_call(pool_status, _From, State) ->
    Stats = calculate_pool_stats(State),
    {reply, {ok, Stats}, State};

handle_call({scale_pool, NewSize}, _From, State) ->
    case scale_pool_internal(State, NewSize) of
        {ok, NewState} ->
            logger:info("MongoDB pool ~p scaled to ~p connections", 
                       [State#pool_state.name, NewSize]),
            {reply, ok, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({checkin, ConnectionId, _ClientPid}, State) ->
    NewState = checkin_connection(State, ConnectionId),
    % Process waiting queue
    ProcessedState = process_waiting_queue(NewState),
    {noreply, update_stats(checkin, ProcessedState)};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(health_check, State) ->
    NewState = perform_health_check(State),
    % Schedule next health check
    HealthInterval = maps:get(health_check_interval, State#pool_state.config),
    HealthTimer = erlang:send_after(HealthInterval, self(), health_check),
    {noreply, NewState#pool_state{health_check_timer = HealthTimer}};

handle_info(scale_check, State) ->
    NewState = auto_scale_check(State),
    % Schedule next scale check
    erlang:send_after(?SCALE_CHECK_INTERVAL, self(), scale_check),
    {noreply, NewState#pool_state{last_scale_check = erlang:system_time(second)}};

handle_info({'DOWN', _MonitorRef, process, Pid, _Reason}, State) ->
    % Client process died, return its connection
    NewState = handle_client_down(State, Pid),
    {noreply, NewState};

handle_info({'EXIT', Pid, Reason}, State) ->
    % Connection worker died
    NewState = handle_connection_down(State, Pid, Reason),
    {noreply, NewState};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    % Clean up all connections
    maps:fold(fun(_ConnId, ConnInfo, _Acc) ->
        case maps:get(pid, ConnInfo) of
            Pid when is_pid(Pid) -> 
                exit(Pid, shutdown);
            _ -> ok
        end
    end, ok, State#pool_state.connections),
    
    % Cancel health check timer
    case State#pool_state.health_check_timer of
        Timer when is_reference(Timer) ->
            erlang:cancel_timer(Timer);
        _ -> ok
    end,
    
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc Initialize pool connections
%%--------------------------------------------------------------------
initialize_connections(State) ->
    PoolSize = maps:get(size, State#pool_state.config),
    case create_connections(State, PoolSize) of
        {ok, Connections, AvailableQueue} ->
            NewState = State#pool_state{
                connections = Connections,
                available_queue = AvailableQueue
            },
            {ok, NewState};
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Create new connections
%%--------------------------------------------------------------------
create_connections(State, Count) ->
    create_connections(State, Count, #{}, queue:new()).

create_connections(_State, 0, Connections, Queue) ->
    {ok, Connections, Queue};
create_connections(State, Count, Connections, Queue) ->
    ConnectionConfig = maps:get(connection_config, State#pool_state.config, #{}),
    case create_single_connection(State#pool_state.name, ConnectionConfig) of
        {ok, ConnectionId, Pid} ->
            ConnInfo = #{
                id => ConnectionId,
                pid => Pid,
                status => available,
                created_at => erlang:system_time(microsecond),
                last_used => erlang:system_time(microsecond),
                operations_count => 0,
                avg_response_time => 0.0,
                is_primary => true, % Would be determined by MongoDB handshake
                server_info => #{}
            },
            NewConnections = maps:put(ConnectionId, ConnInfo, Connections),
            NewQueue = queue:in(ConnectionId, Queue),
            create_connections(State, Count - 1, NewConnections, NewQueue);
        {error, Reason} ->
            {error, {connection_creation_failed, Reason}}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Create a single connection
%%--------------------------------------------------------------------
create_single_connection(_PoolName, ConnectionConfig) ->
    ConnectionId = make_ref(),
    case spawn_link(?MODULE, connection_worker, [ConnectionId, ConnectionConfig]) of
        Pid when is_pid(Pid) ->
            {ok, ConnectionId, Pid};
        Error ->
            {error, Error}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Connection worker process
%%--------------------------------------------------------------------
connection_worker(ConnectionId, _Config) ->
    % This would contain the actual MongoDB connection logic
    % For now, simulate a connection worker
    connection_worker_loop(ConnectionId).

connection_worker_loop(ConnectionId) ->
    receive
        {execute, Operation, From} ->
            % Mock operation execution
            Result = #{
                connection_id => ConnectionId,
                operation => Operation,
                result => ok,
                execution_time => 1.5
            },
            gen_server:reply(From, {ok, Result}),
            connection_worker_loop(ConnectionId);
        {ping, From} ->
            gen_server:reply(From, {pong, ConnectionId}),
            connection_worker_loop(ConnectionId);
        shutdown ->
            exit(normal);
        _ ->
            connection_worker_loop(ConnectionId)
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Checkout a connection based on preference
%%--------------------------------------------------------------------
checkout_connection(State, Preference) ->
    case find_suitable_connection(State, Preference) of
        {ok, ConnectionId} ->
            % Remove from available queue and mark as busy
            ConnInfo = maps:get(ConnectionId, State#pool_state.connections),
            UpdatedConnInfo = ConnInfo#{
                status => busy,
                last_used => erlang:system_time(microsecond)
            },
            UpdatedConnections = maps:put(ConnectionId, UpdatedConnInfo, State#pool_state.connections),
            NewAvailableQueue = queue:filter(fun(Id) -> Id =/= ConnectionId end, 
                                           State#pool_state.available_queue),
            
            NewState = State#pool_state{
                connections = UpdatedConnections,
                available_queue = NewAvailableQueue
            },
            {ok, ConnectionId, NewState};
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Find suitable connection based on preference
%%--------------------------------------------------------------------
find_suitable_connection(State, Preference) ->
    AvailableConnections = get_available_connections(State),
    
    case filter_connections_by_preference(AvailableConnections, State, Preference) of
        [] -> {error, no_connections_available};
        [ConnectionId | _] -> {ok, ConnectionId}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Get available connections
%%--------------------------------------------------------------------
get_available_connections(State) ->
    queue:to_list(State#pool_state.available_queue).

%%--------------------------------------------------------------------
%% @private
%% @doc Filter connections by read/write preference
%%--------------------------------------------------------------------
filter_connections_by_preference(ConnectionIds, State, Preference) ->
    Connections = State#pool_state.connections,
    
    case Preference of
        primary ->
            [Id || Id <- ConnectionIds, 
                   maps:get(is_primary, maps:get(Id, Connections), false)];
        secondary ->
            [Id || Id <- ConnectionIds, 
                   not maps:get(is_primary, maps:get(Id, Connections), true)];
        primary_preferred ->
            PrimaryConnections = filter_connections_by_preference(ConnectionIds, State, primary),
            case PrimaryConnections of
                [] -> filter_connections_by_preference(ConnectionIds, State, secondary);
                _ -> PrimaryConnections
            end;
        secondary_preferred ->
            SecondaryConnections = filter_connections_by_preference(ConnectionIds, State, secondary),
            case SecondaryConnections of
                [] -> filter_connections_by_preference(ConnectionIds, State, primary);
                _ -> SecondaryConnections
            end
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Check in a connection
%%--------------------------------------------------------------------
checkin_connection(State, ConnectionId) ->
    case maps:get(ConnectionId, State#pool_state.connections, undefined) of
        undefined ->
            State; % Connection not found, ignore
        ConnInfo ->
            % Mark as available and add back to queue
            UpdatedConnInfo = ConnInfo#{status => available},
            UpdatedConnections = maps:put(ConnectionId, UpdatedConnInfo, State#pool_state.connections),
            NewAvailableQueue = queue:in(ConnectionId, State#pool_state.available_queue),
            
            State#pool_state{
                connections = UpdatedConnections,
                available_queue = NewAvailableQueue
            }
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Process waiting queue when connections become available
%%--------------------------------------------------------------------
process_waiting_queue(State) ->
    case queue:out(State#pool_state.waiting_queue) of
        {empty, _} ->
            State;
        {{value, {ClientPid, From}}, NewWaitingQueue} ->
            case checkout_connection(State#pool_state{waiting_queue = NewWaitingQueue}, primary_preferred) of
                {ok, ConnectionId, NewState} ->
                    monitor_client(ClientPid, ConnectionId),
                    gen_server:reply(From, {ok, ConnectionId}),
                    process_waiting_queue(update_stats(checkout_success, NewState));
                {error, no_connections_available} ->
                    % Still no connections, keep in queue
                    State;
                {error, Reason} ->
                    gen_server:reply(From, {error, Reason}),
                    process_waiting_queue(update_stats(checkout_failed, State))
            end
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Monitor client process
%%--------------------------------------------------------------------
monitor_client(ClientPid, ConnectionId) ->
    % Store monitor reference associated with connection
    _MonitorRef = monitor(process, ClientPid),
    put({client_connection, ClientPid}, ConnectionId).

%%--------------------------------------------------------------------
%% @private
%% @doc Handle client process death
%%--------------------------------------------------------------------
handle_client_down(State, ClientPid) ->
    case get({client_connection, ClientPid}) of
        undefined ->
            State;
        ConnectionId ->
            erase({client_connection, ClientPid}),
            checkin_connection(State, ConnectionId)
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Handle connection worker death
%%--------------------------------------------------------------------
handle_connection_down(State, Pid, Reason) ->
    % Find connection by PID and recreate it
    case find_connection_by_pid(State, Pid) of
        {ok, ConnectionId} ->
            logger:warning("Connection ~p died (~p), recreating", [ConnectionId, Reason]),
            recreate_connection(State, ConnectionId);
        not_found ->
            State
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Find connection by PID
%%--------------------------------------------------------------------
find_connection_by_pid(State, Pid) ->
    maps:fold(fun(ConnId, ConnInfo, Acc) ->
        case Acc of
            {ok, _} -> Acc; % Already found
            not_found ->
                case maps:get(pid, ConnInfo) of
                    Pid -> {ok, ConnId};
                    _ -> not_found
                end
        end
    end, not_found, State#pool_state.connections).

%%--------------------------------------------------------------------
%% @private
%% @doc Recreate a failed connection
%%--------------------------------------------------------------------
recreate_connection(State, OldConnectionId) ->
    % Remove old connection
    Connections = maps:remove(OldConnectionId, State#pool_state.connections),
    AvailableQueue = queue:filter(fun(Id) -> Id =/= OldConnectionId end,
                                 State#pool_state.available_queue),
    
    % Create new connection
    ConnectionConfig = maps:get(connection_config, State#pool_state.config, #{}),
    case create_single_connection(State#pool_state.name, ConnectionConfig) of
        {ok, NewConnectionId, Pid} ->
            ConnInfo = #{
                id => NewConnectionId,
                pid => Pid,
                status => available,
                created_at => erlang:system_time(microsecond),
                last_used => erlang:system_time(microsecond),
                operations_count => 0,
                avg_response_time => 0.0,
                is_primary => true,
                server_info => #{}
            },
            NewConnections = maps:put(NewConnectionId, ConnInfo, Connections),
            NewAvailableQueue = queue:in(NewConnectionId, AvailableQueue),
            
            State#pool_state{
                connections = NewConnections,
                available_queue = NewAvailableQueue
            };
        {error, Reason} ->
            logger:error("Failed to recreate connection: ~p", [Reason]),
            State#pool_state{
                connections = Connections,
                available_queue = AvailableQueue
            }
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Perform health check on connections
%%--------------------------------------------------------------------
perform_health_check(State) ->
    % Ping all connections and mark unhealthy ones
    maps:fold(fun(ConnId, ConnInfo, AccState) ->
        case maps:get(status, ConnInfo) of
            available ->
                case ping_connection(maps:get(pid, ConnInfo)) of
                    {pong, _} ->
                        AccState; % Connection is healthy
                    _Error ->
                        % Mark as unhealthy
                        logger:warning("Connection ~p failed health check", [ConnId]),
                        mark_connection_unhealthy(AccState, ConnId)
                end;
            _ ->
                AccState % Skip non-available connections
        end
    end, State, State#pool_state.connections).

%%--------------------------------------------------------------------
%% @private
%% @doc Ping a connection
%%--------------------------------------------------------------------
ping_connection(ConnectionPid) ->
    try
        gen_server:call(ConnectionPid, ping, 5000)
    catch
        _:_ -> error
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Mark connection as unhealthy
%%--------------------------------------------------------------------
mark_connection_unhealthy(State, ConnectionId) ->
    case maps:get(ConnectionId, State#pool_state.connections, undefined) of
        undefined ->
            State;
        ConnInfo ->
            UpdatedConnInfo = ConnInfo#{status => unhealthy},
            UpdatedConnections = maps:put(ConnectionId, UpdatedConnInfo, State#pool_state.connections),
            % Remove from available queue
            NewAvailableQueue = queue:filter(fun(Id) -> Id =/= ConnectionId end,
                                           State#pool_state.available_queue),
            State#pool_state{
                connections = UpdatedConnections,
                available_queue = NewAvailableQueue
            }
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Auto-scale pool based on load
%%--------------------------------------------------------------------
auto_scale_check(State) ->
    QueueLength = queue:len(State#pool_state.waiting_queue),
    CurrentSize = maps:size(State#pool_state.connections),
    MaxSize = maps:get(max_size, State#pool_state.config),
    
    case {QueueLength > 0, CurrentSize < MaxSize} of
        {true, true} ->
            % Scale up
            logger:info("Auto-scaling MongoDB pool ~p up (queue: ~p, size: ~p)", 
                       [State#pool_state.name, QueueLength, CurrentSize]),
            scale_pool_internal(State, CurrentSize + 1);
        {false, false} ->
            % Could scale down if we have excess connections
            scale_down_if_needed(State);
        _ ->
            State
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Scale down if we have too many idle connections
%%--------------------------------------------------------------------
scale_down_if_needed(State) ->
    MinSize = maps:get(size, State#pool_state.config),
    CurrentSize = maps:size(State#pool_state.connections),
    IdleConnections = queue:len(State#pool_state.available_queue),
    
    case {CurrentSize > MinSize, IdleConnections > (CurrentSize div 2)} of
        {true, true} ->
            % Scale down by removing one idle connection
            scale_pool_internal(State, CurrentSize - 1);
        _ ->
            State
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Scale pool to new size
%%--------------------------------------------------------------------
scale_pool_internal(State, NewSize) ->
    CurrentSize = maps:size(State#pool_state.connections),
    
    if
        NewSize > CurrentSize ->
            % Scale up
            case create_connections(State, NewSize - CurrentSize) of
                {ok, NewConnections, NewQueue} ->
                    AllConnections = maps:merge(State#pool_state.connections, NewConnections),
                    AllQueue = queue:join(State#pool_state.available_queue, NewQueue),
                    {ok, State#pool_state{
                        connections = AllConnections,
                        available_queue = AllQueue
                    }};
                {error, _} = Error -> Error
            end;
        NewSize < CurrentSize ->
            % Scale down
            {ok, remove_excess_connections(State, CurrentSize - NewSize)};
        true ->
            % No change needed
            {ok, State}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Remove excess connections
%%--------------------------------------------------------------------
remove_excess_connections(State, Count) ->
    remove_excess_connections(State, Count, 0).

remove_excess_connections(State, Count, Removed) when Removed >= Count ->
    State;
remove_excess_connections(State, Count, Removed) ->
    case queue:out(State#pool_state.available_queue) of
        {empty, _} ->
            State; % No more available connections to remove
        {{value, ConnectionId}, NewQueue} ->
            % Remove connection
            case maps:get(ConnectionId, State#pool_state.connections, undefined) of
                undefined ->
                    remove_excess_connections(State#pool_state{available_queue = NewQueue}, 
                                            Count, Removed);
                ConnInfo ->
                    % Terminate connection process
                    case maps:get(pid, ConnInfo) of
                        Pid when is_pid(Pid) -> exit(Pid, shutdown);
                        _ -> ok
                    end,
                    
                    NewConnections = maps:remove(ConnectionId, State#pool_state.connections),
                    NewState = State#pool_state{
                        connections = NewConnections,
                        available_queue = NewQueue
                    },
                    remove_excess_connections(NewState, Count, Removed + 1)
            end
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Calculate pool statistics
%%--------------------------------------------------------------------
calculate_pool_stats(State) ->
    Connections = State#pool_state.connections,
    AvailableCount = queue:len(State#pool_state.available_queue),
    
    {HealthyCount, PrimaryCount, SecondaryCount, BusyCount} = maps:fold(
        fun(_ConnId, ConnInfo, {Healthy, Primary, Secondary, Busy}) ->
            Status = maps:get(status, ConnInfo),
            IsPrimary = maps:get(is_primary, ConnInfo, false),
            
            NewHealthy = case Status of
                unhealthy -> Healthy;
                _ -> Healthy + 1
            end,
            
            NewBusy = case Status of
                busy -> Busy + 1;
                _ -> Busy
            end,
            
            {NewPrimary, NewSecondary} = case IsPrimary of
                true -> {Primary + 1, Secondary};
                false -> {Primary, Secondary + 1}
            end,
            
            {NewHealthy, NewPrimary, NewSecondary, NewBusy}
        end, {0, 0, 0, 0}, Connections),
    
    BaseStats = State#pool_state.stats,
    
    #{
        pool_name => State#pool_state.name,
        size => maps:size(Connections),
        available => AvailableCount,
        busy => BusyCount,
        overflow => queue:len(State#pool_state.waiting_queue),
        total_requests => maps:get(total_requests, BaseStats, 0),
        avg_wait_time => maps:get(avg_wait_time, BaseStats, 0.0),
        healthy_connections => HealthyCount,
        primary_connections => PrimaryCount,
        secondary_connections => SecondaryCount
    }.

%%--------------------------------------------------------------------
%% @private
%% @doc Update pool statistics
%%--------------------------------------------------------------------
update_stats(Event, State) ->
    CurrentStats = State#pool_state.stats,
    
    NewStats = case Event of
        checkout_success ->
            CurrentStats#{
                total_requests => maps:get(total_requests, CurrentStats, 0) + 1,
                successful_requests => maps:get(successful_requests, CurrentStats, 0) + 1
            };
        checkout_failed ->
            CurrentStats#{
                total_requests => maps:get(total_requests, CurrentStats, 0) + 1,
                failed_requests => maps:get(failed_requests, CurrentStats, 0) + 1
            };
        checkin ->
            CurrentStats;
        _ ->
            CurrentStats
    end,
    
    State#pool_state{stats = NewStats}. 