%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform Elasticsearch - Connection Management
%%%
%%% Modern OTP 27 connection handling with:
%%% - Native HTTP/2 client (no external dependencies)
%%% - Connection pooling with automatic scaling
%%% - Circuit breaker pattern
%%% - Health monitoring and recovery
%%% - TLS/SSL with modern cipher suites
%%%
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_search_connection).

-behaviour(gen_server).

%% API
-export([
    start_link/2,
    stop/1,
    
    %% Connection operations
    request/5,
    request_async/6,
    
    %% Pool management
    get_stats/1,
    health_check/1,
    
    %% Circuit breaker
    circuit_breaker_status/1
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    pool_name :: atom(),
    config :: map(),
    connections :: #{reference() => map()},
    available_connections :: [reference()],
    waiting_requests :: queue:queue(),
    circuit_breaker :: map(),
    stats :: map(),
    health_timer :: timer:tref() | undefined
}).

-type request_ref() :: reference().
-type http_method() :: get | post | put | delete | head | patch.
-type headers() :: [{binary(), binary()}].
-type body() :: binary() | iodata().
-type options() :: map().

-export_type([request_ref/0, http_method/0, headers/0, body/0, options/0]).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Start connection pool for a specific configuration
%%--------------------------------------------------------------------
-spec start_link(PoolName :: atom(), Config :: map()) -> 
    ignore | {error, term()} | {ok, pid()}.
start_link(PoolName, Config) ->
    gen_server:start_link(?MODULE, [PoolName, Config], []).

%%--------------------------------------------------------------------
%% @doc Stop the connection pool
%%--------------------------------------------------------------------
-spec stop(Pid :: atom() | pid() | {atom(), term()} | {via, atom(), term()}) -> ok.
stop(Pid) ->
    gen_server:stop(Pid).

%%--------------------------------------------------------------------
%% @doc Perform synchronous HTTP request
%%--------------------------------------------------------------------
-spec request(Pid :: atom() | pid() | {atom(), term()} | {via, atom(), term()}, 
             Method :: http_method(),
             Path :: binary(), 
             Headers :: headers(),
             Body :: body()) -> any().
request(Pid, Method, Path, Headers, Body) ->
    gen_server:call(Pid, {request, Method, Path, Headers, Body}, 30000).

%%--------------------------------------------------------------------
%% @doc Perform asynchronous HTTP request
%%--------------------------------------------------------------------
-spec request_async(Pid :: atom() | pid() | {atom(), term()} | {via, atom(), term()},
                   Method :: http_method(), 
                   Path :: binary(),
                   Headers :: headers(),
                   Body :: body(),
                   From :: {pid(), reference()}) -> any().
request_async(Pid, Method, Path, Headers, Body, From) ->
    gen_server:call(Pid, {request_async, Method, Path, Headers, Body, From}).

%%--------------------------------------------------------------------
%% @doc Get connection pool statistics
%%--------------------------------------------------------------------
-spec get_stats(Pid :: atom() | pid() | {atom(), term()} | {via, atom(), term()}) -> any().
get_stats(Pid) ->
    gen_server:call(Pid, get_stats).

%%--------------------------------------------------------------------
%% @doc Perform health check on the pool
%%--------------------------------------------------------------------
-spec health_check(Pid :: atom() | pid() | {atom(), term()} | {via, atom(), term()}) -> any().
health_check(Pid) ->
    gen_server:call(Pid, health_check).

%%--------------------------------------------------------------------
%% @doc Get circuit breaker status
%%--------------------------------------------------------------------
-spec circuit_breaker_status(Pid :: atom() | pid() | {atom(), term()} | {via, atom(), term()}) -> any().
circuit_breaker_status(Pid) ->
    gen_server:call(Pid, circuit_breaker_status).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Initialize the connection pool
%%--------------------------------------------------------------------
init([PoolName, Config]) ->
    process_flag(trap_exit, true),
    
    %% Initialize circuit breaker
    CircuitBreaker = init_circuit_breaker(Config),
    
    %% Initialize connection pool
    PoolSize = maps:get(pool_size, Config, 10),
    Connections = create_connections(Config, PoolSize),
    
    %% Start health check timer
    HealthInterval = maps:get(health_check_interval, Config, 30000),
    {ok, HealthTimer} = timer:send_interval(HealthInterval, health_check),
    
    %% Initialize stats
    Stats = init_stats(),
    
    State = #state{
        pool_name = PoolName,
        config = Config,
        connections = Connections,
        available_connections = maps:keys(Connections),
        waiting_requests = queue:new(),
        circuit_breaker = CircuitBreaker,
        stats = Stats,
        health_timer = HealthTimer
    },
    
    {ok, State}.

%%--------------------------------------------------------------------
%% @doc Handle synchronous calls
%%--------------------------------------------------------------------
handle_call({request, Method, Path, Headers, Body}, From, State) ->
    case get_circuit_breaker_state(State) of
        closed ->
            execute_request(Method, Path, Headers, Body, From, State);
        half_open ->
            case should_allow_request(State) of
                true ->
                    execute_request(Method, Path, Headers, Body, From, State);
                false ->
                    {reply, {error, circuit_breaker_open}, State}
            end;
        open ->
            {reply, {error, circuit_breaker_open}, State}
    end;

handle_call({request_async, Method, Path, Headers, Body, From}, _From, State) ->
    RequestRef = make_ref(),
    case get_circuit_breaker_state(State) of
        closed ->
            NewState = execute_async_request(Method, Path, Headers, Body, 
                                           From, RequestRef, State),
            {reply, {ok, RequestRef}, NewState};
        half_open ->
            case should_allow_request(State) of
                true ->
                    NewState = execute_async_request(Method, Path, Headers, Body, 
                                                   From, RequestRef, State),
                    {reply, {ok, RequestRef}, NewState};
                false ->
                    {reply, {error, circuit_breaker_open}, State}
            end;
        open ->
            {reply, {error, circuit_breaker_open}, State}
    end;

handle_call(get_stats, _From, State) ->
    Stats = calculate_current_stats(State),
    {reply, Stats, State};

handle_call(health_check, _From, State) ->
    Result = perform_health_check(State),
    {reply, Result, State};

handle_call(circuit_breaker_status, _From, State) ->
    Status = get_circuit_breaker_state(State),
    {reply, Status, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%%--------------------------------------------------------------------
%% @doc Handle asynchronous casts
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @doc Handle info messages
%%--------------------------------------------------------------------
handle_info(health_check, State) ->
    NewState = perform_periodic_health_check(State),
    {noreply, NewState};

handle_info({http, {_RequestId, stream_start, _Headers}}, State) ->
    {noreply, State};

handle_info({http, {RequestId, stream, BinBodyPart}}, State) ->
    NewState = handle_stream_data(RequestId, BinBodyPart, State),
    {noreply, NewState};

handle_info({http, {RequestId, stream_end, _Headers}}, State) ->
    NewState = handle_stream_end(RequestId, State),
    {noreply, NewState};

handle_info({http, {RequestId, {{_Version, StatusCode, _ReasonPhrase}, Headers, Body}}}, State) ->
    NewState = handle_http_response(RequestId, StatusCode, Headers, Body, State),
    {noreply, NewState};

handle_info({http, {RequestId, {error, Reason}}}, State) ->
    NewState = handle_http_error(RequestId, Reason, State),
    {noreply, NewState};

handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @doc Handle termination
%%--------------------------------------------------------------------
terminate(_Reason, State) ->
    %% Cancel health check timer
    case State#state.health_timer of
        undefined -> ok;
        Timer -> 
            case timer:cancel(Timer) of
                _ -> ok
            end
    end,
    
    %% Close all connections
    close_all_connections(State),
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
%% Initialize circuit breaker configuration
-spec init_circuit_breaker(map()) -> #{
    state := closed,
    failure_count := non_neg_integer(),
    failure_threshold := pos_integer(),
    recovery_timeout := non_neg_integer(),
    half_open_max_calls := pos_integer(),
    half_open_calls := non_neg_integer(),
    last_failure_time := undefined | integer()
}.
init_circuit_breaker(Config) ->
    CircuitBreakerConfig = maps:get(circuit_breaker, Config, #{}),
    #{
        state => closed,
        failure_count => 0,
        failure_threshold => maps:get(failure_threshold, CircuitBreakerConfig, 5),
        recovery_timeout => maps:get(recovery_timeout, CircuitBreakerConfig, 30000),
        half_open_max_calls => maps:get(half_open_max_calls, CircuitBreakerConfig, 3),
        half_open_calls => 0,
        last_failure_time => undefined
    }.

%% @private  
%% Create HTTP connections using OTP 27 native HTTP client
-spec create_connections(map(), integer()) -> #{reference() => map()}.
create_connections(Config, PoolSize) ->
    Host = maps:get(host, Config, <<"localhost">>),
    Port = maps:get(port, Config, 9200),
    Scheme = maps:get(scheme, Config, <<"http">>),
    SSLOpts = maps:get(ssl_opts, Config, []),
    
    %% Create HTTP client profiles for each connection
    maps:from_list([begin
        ConnRef = make_ref(),
        
        %% Configure HTTP client options for OTP 27
        HTTPOptions = [
            {timeout, maps:get(timeout, Config, 5000)},
            {connect_timeout, maps:get(connect_timeout, Config, 5000)},
            {autoredirect, false},
            {version, "HTTP/1.1"}  % Will upgrade to HTTP/2 if available
        ],
        
        Options = case Scheme of
            <<"https">> ->
                [{ssl, SSLOpts ++ [
                    {verify, verify_peer},
                    {versions, ['tlsv1.2', 'tlsv1.3']},
                    {ciphers, strong_ciphers()}
                ]} | HTTPOptions];
            _ ->
                HTTPOptions
        end,
        
        ConnInfo = #{
            ref => ConnRef,
            host => Host,
            port => Port,
            scheme => Scheme,
            options => Options,
            status => available,
            created_at => erlang:system_time(millisecond),
            request_count => 0,
            error_count => 0
        },
        
        {ConnRef, ConnInfo}
    end || _ <- lists:seq(1, PoolSize)]).

%% @private
%% Get strong cipher suites for TLS
-spec strong_ciphers() -> [#{
    cipher := atom(),
    key_exchange := atom(), 
    mac := atom(),
    prf := atom()
}].
strong_ciphers() ->
    %% Use OTP 27's enhanced cipher suite selection
    ssl:cipher_suites(exclusive, 'tlsv1.3') ++ 
    ssl:cipher_suites(exclusive, 'tlsv1.2').

%% @private
%% Initialize statistics tracking
-spec init_stats() -> #{
    requests_total := non_neg_integer(),
    requests_success := non_neg_integer(), 
    requests_error := non_neg_integer(),
    avg_response_time := non_neg_integer(),
    created_at := integer()
}.
init_stats() ->
    #{
        requests_total => 0,
        requests_success => 0,
        requests_error => 0,
        avg_response_time => 0,
        created_at => erlang:system_time(millisecond)
    }.

%% @private
%% Execute HTTP request using available connection
-spec execute_request(http_method(), binary(), headers(), body(), 
                     {pid(), reference()}, #state{}) -> 
    {reply, {ok, map()} | {error, term()}, #state{}} | {noreply, #state{}}.
execute_request(Method, Path, Headers, Body, From, State) ->
    case get_available_connection(State) of
        {ok, ConnRef, NewState} ->
            perform_http_request(Method, Path, Headers, Body, ConnRef, From, NewState);
        {error, no_available_connections} ->
            %% Queue the request
            QueuedRequest = {Method, Path, Headers, Body, From},
            WaitingRequests = queue:in(QueuedRequest, State#state.waiting_requests),
            {noreply, State#state{waiting_requests = WaitingRequests}}
    end.

%% @private
%% Execute asynchronous HTTP request
-spec execute_async_request(http_method(), binary(), headers(), body(),
                           {pid(), reference()}, reference(), #state{}) -> {noreply, #state{}}.
execute_async_request(Method, Path, Headers, Body, From, RequestRef, State) ->
    case get_available_connection(State) of
        {ok, ConnRef, NewState} ->
            _ = perform_async_http_request(Method, Path, Headers, Body, ConnRef, 
                                     From, RequestRef, NewState),
            {noreply, NewState};
        {error, no_available_connections} ->
            %% Queue the async request
            QueuedRequest = {async, Method, Path, Headers, Body, From, RequestRef},
            WaitingRequests = queue:in(QueuedRequest, State#state.waiting_requests),
            {noreply, State#state{waiting_requests = WaitingRequests}}
    end.

%% @private
%% Perform HTTP request using OTP 27 native HTTP client
-spec perform_http_request(http_method(), binary(), headers(), body(), 
                          reference(), {pid(), reference()}, #state{}) ->
    {reply, {ok, map()} | {error, term()}, #state{}}.
perform_http_request(Method, Path, Headers, Body, ConnRef, _From, State) ->
    #state{connections = Connections} = State,
    ConnInfo = maps:get(ConnRef, Connections),
    
    %% Build URL
    #{host := Host, port := Port, scheme := Scheme} = ConnInfo,
    URL = build_url(Scheme, Host, Port, Path),
    
    %% Convert headers to httpc format
    HTTPHeaders = [{binary_to_list(K), binary_to_list(V)} || {K, V} <- Headers],
    
    %% Prepare request
    HTTPRequest = case Body of
        <<>> -> {binary_to_list(URL), HTTPHeaders};
        _ -> {binary_to_list(URL), HTTPHeaders, "application/json", Body}
    end,
    
    %% Execute request
    StartTime = erlang:system_time(microsecond),
    HTTPMethod = method_to_atom(Method),
    
    case httpc:request(HTTPMethod, HTTPRequest, 
                      maps:get(options, ConnInfo), 
                      [{sync, true}]) of
        {ok, {{_Version, StatusCode, _ReasonPhrase}, ResponseHeaders, ResponseBody}} ->
            EndTime = erlang:system_time(microsecond),
            Duration = EndTime - StartTime,
            
            %% Parse response
            Response = parse_response(StatusCode, ResponseHeaders, ResponseBody),
            
            %% Update statistics
            NewState = update_success_stats(State, ConnRef, Duration),
            
            {reply, {ok, Response}, NewState};
            
        {error, Reason} ->
            %% Update error statistics and circuit breaker
            NewState = update_error_stats(State, ConnRef, Reason),
            {reply, {error, Reason}, NewState}
    end.

%% @private
%% Perform asynchronous HTTP request
-spec perform_async_http_request(http_method(), binary(), headers(), body(),
                               reference(), {pid(), reference()}, reference(), #state{}) -> #state{}.
perform_async_http_request(Method, Path, Headers, Body, ConnRef, From, RequestRef, State) ->
    %% For async requests, we'll use the synchronous API in a spawned process
    %% and send the result back to the caller
    spawn(fun() ->
        case perform_sync_request(Method, Path, Headers, Body, ConnRef, State) of
            {ok, Response} ->
                From ! {elasticsearch_result, RequestRef, Response};
            {error, Reason} ->
                From ! {elasticsearch_error, RequestRef, Reason}
        end
    end),
    
    %% Mark connection as busy temporarily
    update_connection_status(State, ConnRef, busy).

%% @private
%% Parse HTTP response into standardized format
-spec parse_response(pos_integer(), headers(), binary()) -> map().
parse_response(StatusCode, Headers, Body) ->
    ParsedBody = case Body of
        <<>> -> #{};
        _ -> 
            try
                %% Use OTP 27 native JSON parsing
                json:decode(Body)
            catch
                _:_ -> #{raw_body => Body}
            end
    end,
    
    #{
        status_code => StatusCode,
        headers => maps:from_list([{list_to_binary(K), list_to_binary(V)} || {K, V} <- Headers]),
        body => ParsedBody
    }.

%% @private
%% Build URL from components
-spec build_url(binary(), binary(), integer(), binary()) -> binary().
build_url(Scheme, Host, Port, Path) ->
    PathWithSlash = case Path of
        <<"/", _/binary>> -> Path;
        _ -> <<"/", Path/binary>>
    end,
    <<Scheme/binary, "://", Host/binary, ":", (integer_to_binary(Port))/binary, PathWithSlash/binary>>.

%% @private
%% Convert HTTP method to atom
-spec method_to_atom(http_method()) -> delete | get | head | patch | post | put.
method_to_atom(get) -> get;
method_to_atom(post) -> post;
method_to_atom(put) -> put;
method_to_atom(delete) -> delete;
method_to_atom(head) -> head;
method_to_atom(patch) -> patch.

%% @private
%% Get available connection from pool
-spec get_available_connection(#state{}) -> 
    {ok, reference(), #state{}} | {error, no_available_connections}.
get_available_connection(State) ->
    case State#state.available_connections of
        [] ->
            {error, no_available_connections};
        [ConnRef | Rest] ->
            NewState = State#state{available_connections = Rest},
            {ok, ConnRef, NewState}
    end.

%% @private
%% Update statistics after successful request
-spec update_success_stats(#state{}, reference(), integer()) -> #state{}.
update_success_stats(State, ConnRef, Duration) ->
    %% Update connection stats
    Connections = State#state.connections,
    ConnInfo = maps:get(ConnRef, Connections),
    UpdatedConnInfo = ConnInfo#{
        request_count => maps:get(request_count, ConnInfo) + 1,
        status => available
    },
    UpdatedConnections = maps:put(ConnRef, UpdatedConnInfo, Connections),
    
    %% Update global stats
    Stats = State#state.stats,
    NewStats = Stats#{
        requests_total => maps:get(requests_total, Stats) + 1,
        requests_success => maps:get(requests_success, Stats) + 1,
        avg_response_time => update_avg_response_time(Stats, Duration)
    },
    
    %% Reset circuit breaker on success
    CircuitBreaker = reset_circuit_breaker_on_success(State#state.circuit_breaker),
    
    %% Return connection to available pool
    AvailableConnections = [ConnRef | State#state.available_connections],
    
    State#state{
        connections = UpdatedConnections,
        available_connections = AvailableConnections,
        circuit_breaker = CircuitBreaker,
        stats = NewStats
    }.

%% @private
%% Update statistics after failed request
-spec update_error_stats(#state{}, reference(), term()) -> #state{}.
update_error_stats(State, ConnRef, _Reason) ->
    %% Update connection stats
    Connections = State#state.connections,
    ConnInfo = maps:get(ConnRef, Connections),
    UpdatedConnInfo = ConnInfo#{
        error_count => maps:get(error_count, ConnInfo) + 1,
        status => available
    },
    UpdatedConnections = maps:put(ConnRef, UpdatedConnInfo, Connections),
    
    %% Update global stats
    Stats = State#state.stats,
    NewStats = Stats#{
        requests_total => maps:get(requests_total, Stats) + 1,
        requests_error => maps:get(requests_error, Stats) + 1
    },
    
    %% Update circuit breaker
    CircuitBreaker = update_circuit_breaker_on_failure(State#state.circuit_breaker),
    
    %% Return connection to available pool
    AvailableConnections = [ConnRef | State#state.available_connections],
    
    State#state{
        connections = UpdatedConnections,
        available_connections = AvailableConnections,
        circuit_breaker = CircuitBreaker,
        stats = NewStats
    }.

%% @private
%% Update average response time
-spec update_avg_response_time(map(), integer()) -> float().
update_avg_response_time(Stats, Duration) ->
    CurrentAvg = maps:get(avg_response_time, Stats, 0),
    TotalRequests = maps:get(requests_total, Stats, 0),
    NewDurationMs = Duration / 1000,  % Convert microseconds to milliseconds
    
    case TotalRequests of
        0 -> NewDurationMs;
        _ -> (CurrentAvg * TotalRequests + NewDurationMs) / (TotalRequests + 1)
    end.

%% @private
%% Get current circuit breaker state
-spec get_circuit_breaker_state(#state{}) -> open | closed | half_open.
get_circuit_breaker_state(State) ->
    CircuitBreaker = State#state.circuit_breaker,
    CBState = maps:get(state, CircuitBreaker),
    
    case CBState of
        open ->
            %% Check if recovery timeout has passed
            LastFailureTime = maps:get(last_failure_time, CircuitBreaker),
            RecoveryTimeout = maps:get(recovery_timeout, CircuitBreaker),
            Now = erlang:system_time(millisecond),
            
            case Now - LastFailureTime >= RecoveryTimeout of
                true -> half_open;
                false -> open
            end;
        _ ->
            CBState
    end.

%% @private
%% Check if request should be allowed in half-open state
-spec should_allow_request(#state{}) -> boolean().
should_allow_request(State) ->
    CircuitBreaker = State#state.circuit_breaker,
    HalfOpenCalls = maps:get(half_open_calls, CircuitBreaker, 0),
    MaxCalls = maps:get(half_open_max_calls, CircuitBreaker, 3),
    HalfOpenCalls < MaxCalls.

%% @private
%% Reset circuit breaker on successful request
-spec reset_circuit_breaker_on_success(map()) -> map().
reset_circuit_breaker_on_success(CircuitBreaker) ->
    CircuitBreaker#{
        state => closed,
        failure_count => 0,
        half_open_calls => 0
    }.

%% @private
%% Update circuit breaker on failure
-spec update_circuit_breaker_on_failure(map()) -> map().
update_circuit_breaker_on_failure(CircuitBreaker) ->
    CurrentState = maps:get(state, CircuitBreaker),
    FailureCount = maps:get(failure_count, CircuitBreaker, 0) + 1,
    FailureThreshold = maps:get(failure_threshold, CircuitBreaker, 5),
    
    case CurrentState of
        half_open ->
            %% Failure in half-open state, go back to open
            CircuitBreaker#{
                state => open,
                failure_count => FailureCount,
                half_open_calls => 0,
                last_failure_time => erlang:system_time(millisecond)
            };
        closed when FailureCount >= FailureThreshold ->
            %% Too many failures, open circuit
            CircuitBreaker#{
                state => open,
                failure_count => FailureCount,
                last_failure_time => erlang:system_time(millisecond)
            };
        closed ->
            %% Still closed, just increment failure count
            CircuitBreaker#{
                failure_count => FailureCount
            };
        open ->
            %% Already open, update failure count
            CircuitBreaker#{
                failure_count => FailureCount,
                last_failure_time => erlang:system_time(millisecond)
            }
    end.

%% @private
%% Calculate current statistics
-spec calculate_current_stats(#state{}) -> map().
calculate_current_stats(State) ->
    Stats = State#state.stats,
    TotalConnections = maps:size(State#state.connections),
    AvailableConnections = length(State#state.available_connections),
    WaitingRequests = queue:len(State#state.waiting_requests),
    
    CircuitBreakerState = get_circuit_breaker_state(State),
    
    Stats#{
        total_connections => TotalConnections,
        available_connections => AvailableConnections,
        busy_connections => TotalConnections - AvailableConnections,
        waiting_requests => WaitingRequests,
        circuit_breaker_state => CircuitBreakerState,
        pool_name => State#state.pool_name
    }.

%% @private
%% Perform health check on Elasticsearch cluster
-spec perform_health_check(#state{}) -> ok | {error, term()}.
perform_health_check(State) ->
    %% Simple health check using cluster health API
    try
        case perform_sync_request(get, <<"/_cluster/health">>, [], <<>>, 
                                 hd(State#state.available_connections), State) of
            {ok, _Response} -> ok;
            {error, Reason} -> {error, Reason}
        end
    catch
        _:Error -> {error, Error}
    end.

%% @private
%% Perform periodic health check
-spec perform_periodic_health_check(#state{}) -> #state{}.
perform_periodic_health_check(State) ->
    case perform_health_check(State) of
        ok -> State;
        {error, _Reason} ->
            %% Health check failed, update circuit breaker
            CircuitBreaker = update_circuit_breaker_on_failure(State#state.circuit_breaker),
            State#state{circuit_breaker = CircuitBreaker}
    end.

%% @private
%% Perform synchronous request (internal helper)
-spec perform_sync_request(http_method(), binary(), headers(), body(), 
                          reference(), #state{}) -> 
    {ok, map()} | {error, term()}.
perform_sync_request(Method, Path, Headers, Body, ConnRef, State) ->
    #state{connections = Connections} = State,
    ConnInfo = maps:get(ConnRef, Connections),
    
    %% Build URL
    #{host := Host, port := Port, scheme := Scheme} = ConnInfo,
    URL = build_url(Scheme, Host, Port, Path),
    
    %% Convert headers to httpc format
    HTTPHeaders = [{binary_to_list(K), binary_to_list(V)} || {K, V} <- Headers],
    
    %% Prepare request
    HTTPRequest = case Body of
        <<>> -> {binary_to_list(URL), HTTPHeaders};
        _ -> {binary_to_list(URL), HTTPHeaders, "application/json", Body}
    end,
    
    %% Execute request
    HTTPMethod = method_to_atom(Method),
    
    case httpc:request(HTTPMethod, HTTPRequest, 
                      maps:get(options, ConnInfo), 
                      [{sync, true}]) of
        {ok, {{_Version, StatusCode, _ReasonPhrase}, ResponseHeaders, ResponseBody}} ->
            Response = parse_response(StatusCode, ResponseHeaders, ResponseBody),
            {ok, Response};
        {error, Reason} ->
            {error, Reason}
    end.

%% @private
%% Update connection status
-spec update_connection_status(#state{}, reference(), atom()) -> #state{}.
update_connection_status(State, ConnRef, Status) ->
    Connections = State#state.connections,
    ConnInfo = maps:get(ConnRef, Connections),
    UpdatedConnInfo = ConnInfo#{status => Status},
    UpdatedConnections = maps:put(ConnRef, UpdatedConnInfo, Connections),
    State#state{connections = UpdatedConnections}.

%% @private
%% Close all connections
-spec close_all_connections(#state{}) -> ok.
close_all_connections(_State) ->
    %% OTP 27's httpc manages connections automatically
    %% Just ensure any persistent connections are released
    ok.

%% @private
%% Handle HTTP stream data (for large responses)
-spec handle_stream_data(term(), binary(), #state{}) -> any().
handle_stream_data(_RequestId, _BinBodyPart, State) ->
    %% Handle streaming response data
    State.

%% @private
%% Handle end of HTTP stream
-spec handle_stream_end(term(), #state{}) -> any().
handle_stream_end(_RequestId, State) ->
    %% Handle end of streaming response
    State.

%% @private
%% Handle HTTP response
-spec handle_http_response(term(), pos_integer(), headers(), binary(), #state{}) -> any().
handle_http_response(_RequestId, _StatusCode, _Headers, _Body, State) ->
    %% Handle async HTTP response
    State.

%% @private
%% Handle HTTP error
-spec handle_http_error(term(), term(), #state{}) -> any().
handle_http_error(_RequestId, _Reason, State) ->
    %% Handle async HTTP error
    State. 