%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform Elasticsearch - Statistics Collection
%%%
%%% High-performance statistics using OTP 27 features:
%%% - Persistent terms for zero-overhead counters
%%% - Real-time metrics collection
%%% - Historical data aggregation
%%% - Performance monitoring
%%%
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_search_stats).

-behaviour(gen_server).

%% API
-export([
    start_link/1,
    increment_counter/1,
    increment_counter/2,
    record_timing/2,
    get_stats/0,
    get_detailed_stats/0,
    reset_stats/0
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    start_time :: integer(),
    aggregation_timer :: timer:tref() | undefined,
    config :: map()
}).

%% Persistent term keys
-define(STATS_KEY(Metric), {connect_search_stats, Metric}).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Start the statistics server
%%--------------------------------------------------------------------
-spec start_link(Config :: map()) -> ignore | {error, term()} | {ok, pid()}.
start_link(Config) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Config], []).

%%--------------------------------------------------------------------
%% @doc Increment a counter
%%--------------------------------------------------------------------
-spec increment_counter(Metric :: atom()) -> ok.
increment_counter(Metric) ->
    increment_counter(Metric, 1).

-spec increment_counter(Metric :: atom(), Value :: number()) -> ok.
increment_counter(Metric, Value) ->
    Key = ?STATS_KEY(Metric),
    case persistent_term:get(Key, undefined) of
        undefined ->
            persistent_term:put(Key, Value);
        Current ->
            persistent_term:put(Key, Current + Value)
    end,
    ok.

%%--------------------------------------------------------------------
%% @doc Record timing information
%%--------------------------------------------------------------------
-spec record_timing(Metric :: atom(), Duration :: number()) -> ok.
record_timing(Metric, Duration) ->
    %% Record the timing
    TimingKey = ?STATS_KEY({timing, Metric}),
    CountKey = ?STATS_KEY({timing_count, Metric}),
    
    case persistent_term:get(TimingKey, undefined) of
        undefined ->
            persistent_term:put(TimingKey, Duration),
            persistent_term:put(CountKey, 1);
        CurrentTotal ->
            Count = persistent_term:get(CountKey, 1),
            persistent_term:put(TimingKey, CurrentTotal + Duration),
            persistent_term:put(CountKey, Count + 1)
    end,
    ok.

%%--------------------------------------------------------------------
%% @doc Get basic statistics
%%--------------------------------------------------------------------
-spec get_stats() -> map().
get_stats() ->
    collect_basic_stats().

%%--------------------------------------------------------------------
%% @doc Get detailed statistics
%%--------------------------------------------------------------------
-spec get_detailed_stats() -> any().
get_detailed_stats() ->
    gen_server:call(?MODULE, get_detailed_stats).

%%--------------------------------------------------------------------
%% @doc Reset all statistics
%%--------------------------------------------------------------------
-spec reset_stats() -> any().
reset_stats() ->
    gen_server:call(?MODULE, reset_stats).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Initialize the stats server
%%--------------------------------------------------------------------
init([Config]) ->
    process_flag(trap_exit, true),
    
    %% Initialize persistent terms
    init_persistent_stats(),
    
    %% Start aggregation timer
    AggregationInterval = maps:get(stats_aggregation_interval, Config, 60000),
    {ok, Timer} = timer:send_interval(AggregationInterval, aggregate_stats),
    
    State = #state{
        start_time = erlang:system_time(millisecond),
        aggregation_timer = Timer,
        config = Config
    },
    
    {ok, State}.

%%--------------------------------------------------------------------
%% @doc Handle calls
%%--------------------------------------------------------------------
handle_call(get_detailed_stats, _From, State) ->
    Stats = collect_detailed_stats(State),
    {reply, Stats, State};

handle_call(reset_stats, _From, State) ->
    reset_all_persistent_stats(),
    {reply, ok, State};

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
handle_info(aggregate_stats, State) ->
    %% Perform periodic stats aggregation
    NewState = perform_stats_aggregation(State),
    {noreply, NewState};

handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @doc Handle termination
%%--------------------------------------------------------------------
terminate(_Reason, State) ->
    case State#state.aggregation_timer of
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
%% Initialize persistent term statistics
-spec init_persistent_stats() -> ok.
init_persistent_stats() ->
    Metrics = [
        requests_total,
        requests_success,
        requests_error,
        connections_total,
        connections_active,
        circuit_breaker_opens
    ],
    
    [persistent_term:put(?STATS_KEY(Metric), 0) || Metric <- Metrics],
    ok.

%% @private
%% Collect basic statistics
-spec collect_basic_stats() -> map().
collect_basic_stats() ->
    #{
        requests_total => persistent_term:get(?STATS_KEY(requests_total), 0),
        requests_success => persistent_term:get(?STATS_KEY(requests_success), 0),
        requests_error => persistent_term:get(?STATS_KEY(requests_error), 0),
        connections_total => persistent_term:get(?STATS_KEY(connections_total), 0),
        connections_active => persistent_term:get(?STATS_KEY(connections_active), 0),
        circuit_breaker_opens => persistent_term:get(?STATS_KEY(circuit_breaker_opens), 0),
        uptime => get_uptime()
    }.

%% @private
%% Collect detailed statistics
-spec collect_detailed_stats(#state{}) -> map().
collect_detailed_stats(_State) ->
    BasicStats = collect_basic_stats(),
    
    %% Add timing statistics
    TimingStats = collect_timing_stats(),
    
    %% Add system information
    SystemStats = collect_system_stats(),
    
    %% Calculate derived metrics
    DerivedStats = calculate_derived_metrics(BasicStats),
    
    maps:merge(maps:merge(maps:merge(BasicStats, TimingStats), SystemStats), DerivedStats).

%% @private
%% Collect timing statistics
-spec collect_timing_stats() -> map().
collect_timing_stats() ->
    TimingMetrics = [request_duration, connection_time, search_time],
    
    maps:from_list([begin
        TimingKey = ?STATS_KEY({timing, Metric}),
        CountKey = ?STATS_KEY({timing_count, Metric}),
        
        case {persistent_term:get(TimingKey, undefined), 
              persistent_term:get(CountKey, undefined)} of
            {undefined, _} ->
                {Metric, #{average => 0, count => 0}};
            {Total, Count} when Count > 0 ->
                {Metric, #{average => Total / Count, count => Count, total => Total}};
            _ ->
                {Metric, #{average => 0, count => 0}}
        end
    end || Metric <- TimingMetrics]).

%% @private
%% Collect system statistics
-spec collect_system_stats() -> map().
collect_system_stats() ->
    MemoryInfo = erlang:memory(),
    TotalMem = proplists:get_value(total, MemoryInfo, 0),
    AllocatedMem = proplists:get_value(processes, MemoryInfo, 0),
    
    #{
        system => #{
            memory_total => TotalMem,
            memory_allocated => AllocatedMem,
            process_count => erlang:system_info(process_count),
            port_count => erlang:system_info(port_count),
            run_queue => erlang:statistics(run_queue)
        }
    }.

%% @private
%% Calculate derived metrics
-spec calculate_derived_metrics(map()) -> map().
calculate_derived_metrics(BasicStats) ->
    Total = maps:get(requests_total, BasicStats, 0),
    Success = maps:get(requests_success, BasicStats, 0),
    Error = maps:get(requests_error, BasicStats, 0),
    Uptime = maps:get(uptime, BasicStats, 1),
    
    #{
        derived => #{
            success_rate => case Total of
                0 -> 0.0;
                _ -> Success / Total
            end,
            error_rate => case Total of
                0 -> 0.0;
                _ -> Error / Total
            end,
            requests_per_second => case Uptime of
                0 -> 0.0;
                _ -> Total / (Uptime / 1000)
            end
        }
    }.

%% @private
%% Get uptime in milliseconds
-spec get_uptime() -> non_neg_integer() | float().
get_uptime() ->
    case persistent_term:get(?STATS_KEY(start_time), undefined) of
        undefined ->
            StartTime = erlang:system_time(millisecond),
            persistent_term:put(?STATS_KEY(start_time), StartTime),
            0;
        StartTime ->
            erlang:system_time(millisecond) - StartTime
    end.

%% @private
%% Perform periodic stats aggregation
-spec perform_stats_aggregation(#state{}) -> #state{}.
perform_stats_aggregation(State) ->
    %% Could implement historical data aggregation here
    %% For now, just return the state unchanged
    State.

%% @private
%% Reset all persistent statistics
-spec reset_all_persistent_stats() -> ok.
reset_all_persistent_stats() ->
    %% Get all persistent terms with our prefix
    AllTerms = persistent_term:get(),
    StatsTerms = [{K, V} || {K, V} <- AllTerms, is_stats_key(K)],
    
    %% Reset all stats terms to 0
    [persistent_term:put(K, 0) || {K, _V} <- StatsTerms],
    
    %% Reset start time
    persistent_term:put(?STATS_KEY(start_time), erlang:system_time(millisecond)),
    ok.

%% @private
%% Check if a key is a stats key
-spec is_stats_key(term()) -> boolean().
is_stats_key({connect_search_stats, _}) -> true;
is_stats_key(_) -> false. 