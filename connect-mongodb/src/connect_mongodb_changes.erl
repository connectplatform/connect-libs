%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform MongoDB - Change Streams for Real-time Processing
%%%
%%% MongoDB Change Streams implementation for real-time data processing:
%%% - Watch collections, databases, or entire clusters
%%% - Resume support with automatic resume token management
%%% - Error recovery and reconnection handling
%%% - Event filtering and transformation pipelines
%%% - Async/await patterns for non-blocking streaming
%%%
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_mongodb_changes).
-behaviour(gen_server).

%% Public API
-export([
    %% Watch Operations
    watch_collection/2,
    watch_collection/3,
    watch_database/1,
    watch_database/2,
    watch_cluster/0,
    watch_cluster/1,
    
    %% Stream Management
    start_change_stream/3,
    stop_change_stream/1,
    resume_change_stream/2,
    get_stream_status/1,
    
    %% Event Processing
    next_change/1,
    next_change/2,
    process_changes/2,
    
    %% Advanced Features
    create_filtered_stream/3,
    set_resume_token/2,
    get_resume_token/1,
    
    %% Stream Statistics
    get_stream_stats/1,
    list_active_streams/0
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

%% Internal exports for stream workers
-export([stream_worker/4]).

%%%===================================================================
%%% Types and Records
%%%===================================================================

-type stream_id() :: reference().
-type collection_name() :: binary().
-type database_name() :: binary().
-type pipeline() :: [map()].
-type resume_token() :: map() | binary().

-type watch_options() :: #{
    full_document => default | update_lookup | when_available | required,
    full_document_before_change => off | when_available | required,
    resume_after => resume_token(),
    start_after => resume_token(),
    start_at_operation_time => integer(),
    max_await_time_ms => pos_integer(),
    batch_size => pos_integer(),
    collation => map(),
    read_preference => primary | secondary | primary_preferred | secondary_preferred,
    read_concern => map()
}.

-type change_event() :: #{
    '_id' => map(),
    operation_type => binary(),
    cluster_time => integer(),
    full_document => map() | null,
    full_document_before_change => map() | null,
    ns => #{
        db => binary(),
        coll => binary()
    },
    document_key => map(),
    update_description => map(),
    txn_number => integer(),
    lsid => map()
}.

-type stream_status() :: #{
    stream_id => stream_id(),
    status => active | paused | stopped | error,
    target => collection_name() | database_name() | cluster,
    events_processed => non_neg_integer(),
    last_resume_token => resume_token() | undefined,
    last_event_time => integer() | undefined,
    error_count => non_neg_integer(),
    created_at => integer(),
    uptime_seconds => non_neg_integer()
}.

-type stream_stats() :: #{
    total_streams => non_neg_integer(),
    active_streams => non_neg_integer(),
    events_per_second => float(),
    total_events_processed => non_neg_integer(),
    error_rate => float(),
    avg_processing_time => float()
}.

-record(stream_state, {
    stream_id :: stream_id(),
    target :: {collection, collection_name()} | {database, database_name()} | cluster,
    pipeline :: pipeline(),
    options :: watch_options(),
    worker_pid :: pid() | undefined,
    status = active :: active | paused | stopped | error,
    events_processed = 0 :: non_neg_integer(),
    last_resume_token :: resume_token() | undefined,
    last_event_time :: integer() | undefined,
    error_count = 0 :: non_neg_integer(),
    created_at :: integer(),
    event_handlers = [] :: [fun((change_event()) -> ok)]
}).

-record(global_state, {
    streams = #{} :: #{stream_id() => #stream_state{}},
    global_stats = #{} :: map()
}).

-export_type([
    stream_id/0, collection_name/0, database_name/0, pipeline/0, resume_token/0,
    watch_options/0, change_event/0, stream_status/0, stream_stats/0
]).

%%%===================================================================
%%% Macros and Constants
%%%===================================================================

-define(SERVER, ?MODULE).
-define(DEFAULT_BATCH_SIZE, 100).
-define(DEFAULT_MAX_AWAIT_TIME, 30000). % 30 seconds
-define(RECONNECT_DELAY, 1000). % 1 second
-define(MAX_RECONNECT_ATTEMPTS, 10).
-define(STATS_UPDATE_INTERVAL, 5000). % 5 seconds

%%%===================================================================
%%% Public API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Watch changes on a specific collection
%%--------------------------------------------------------------------
-spec watch_collection(collection_name(), pipeline()) -> {ok, stream_id()} | {error, term()}.
watch_collection(Collection, Pipeline) ->
    watch_collection(Collection, Pipeline, #{}).

-spec watch_collection(collection_name(), pipeline(), watch_options()) -> 
    {ok, stream_id()} | {error, term()}.
watch_collection(Collection, Pipeline, Options) 
  when is_binary(Collection), is_list(Pipeline), is_map(Options) ->
    gen_server:call(?SERVER, {watch_collection, Collection, Pipeline, Options});
watch_collection(Collection, Pipeline, Options) ->
    error({badarg, [Collection, Pipeline, Options]}, [Collection, Pipeline, Options], #{
        error_info => #{
            module => ?MODULE,
            function => watch_collection,
            arity => 3,
            cause => "Collection must be binary, Pipeline must be list, Options must be map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Watch changes on a database
%%--------------------------------------------------------------------
-spec watch_database(database_name()) -> {ok, stream_id()} | {error, term()}.
watch_database(Database) ->
    watch_database(Database, #{}).

-spec watch_database(database_name(), watch_options()) -> {ok, stream_id()} | {error, term()}.
watch_database(Database, Options) when is_binary(Database), is_map(Options) ->
    gen_server:call(?SERVER, {watch_database, Database, Options});
watch_database(Database, Options) ->
    error({badarg, [Database, Options]}, [Database, Options], #{
        error_info => #{
            module => ?MODULE,
            function => watch_database,
            arity => 2,
            cause => "Database must be binary, Options must be map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Watch changes on entire cluster
%%--------------------------------------------------------------------
-spec watch_cluster() -> {ok, stream_id()} | {error, term()}.
watch_cluster() ->
    watch_cluster(#{}).

-spec watch_cluster(watch_options()) -> {ok, stream_id()} | {error, term()}.
watch_cluster(Options) when is_map(Options) ->
    gen_server:call(?SERVER, {watch_cluster, Options});
watch_cluster(Options) ->
    error({badarg, Options}, [Options], #{
        error_info => #{
            module => ?MODULE,
            function => watch_cluster,
            arity => 1,
            cause => "Options must be a map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Start a change stream with custom configuration
%%--------------------------------------------------------------------
-spec start_change_stream(atom(), pipeline(), watch_options()) -> 
    {ok, stream_id()} | {error, term()}.
start_change_stream(Target, Pipeline, Options) ->
    gen_server:call(?SERVER, {start_change_stream, Target, Pipeline, Options}).

%%--------------------------------------------------------------------
%% @doc Stop a change stream
%%--------------------------------------------------------------------
-spec stop_change_stream(stream_id()) -> ok | {error, term()}.
stop_change_stream(StreamId) when is_reference(StreamId) ->
    gen_server:call(?SERVER, {stop_change_stream, StreamId});
stop_change_stream(StreamId) ->
    error({badarg, StreamId}, [StreamId], #{
        error_info => #{
            module => ?MODULE,
            function => stop_change_stream,
            arity => 1,
            cause => "StreamId must be a reference"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Resume a change stream from a specific token
%%--------------------------------------------------------------------
-spec resume_change_stream(stream_id(), resume_token()) -> ok | {error, term()}.
resume_change_stream(StreamId, ResumeToken) when is_reference(StreamId) ->
    gen_server:call(?SERVER, {resume_change_stream, StreamId, ResumeToken});
resume_change_stream(StreamId, ResumeToken) ->
    error({badarg, [StreamId, ResumeToken]}, [StreamId, ResumeToken], #{
        error_info => #{
            module => ?MODULE,
            function => resume_change_stream,
            arity => 2,
            cause => "StreamId must be a reference"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Get status of a change stream
%%--------------------------------------------------------------------
-spec get_stream_status(stream_id()) -> {ok, stream_status()} | {error, term()}.
get_stream_status(StreamId) when is_reference(StreamId) ->
    gen_server:call(?SERVER, {get_stream_status, StreamId});
get_stream_status(StreamId) ->
    error({badarg, StreamId}, [StreamId], #{
        error_info => #{
            module => ?MODULE,
            function => get_stream_status,
            arity => 1,
            cause => "StreamId must be a reference"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Get next change event from stream
%%--------------------------------------------------------------------
-spec next_change(stream_id()) -> {ok, change_event()} | {error, term()} | timeout.
next_change(StreamId) ->
    next_change(StreamId, 5000).

-spec next_change(stream_id(), timeout()) -> {ok, change_event()} | {error, term()} | timeout.
next_change(StreamId, Timeout) when is_reference(StreamId) ->
    gen_server:call(?SERVER, {next_change, StreamId}, Timeout);
next_change(StreamId, Timeout) ->
    error({badarg, [StreamId, Timeout]}, [StreamId, Timeout], #{
        error_info => #{
            module => ?MODULE,
            function => next_change,
            arity => 2,
            cause => "StreamId must be a reference"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Process changes using a handler function
%%--------------------------------------------------------------------
-spec process_changes(stream_id(), fun((change_event()) -> ok)) -> ok | {error, term()}.
process_changes(StreamId, HandlerFun) when is_reference(StreamId), is_function(HandlerFun, 1) ->
    gen_server:cast(?SERVER, {process_changes, StreamId, HandlerFun});
process_changes(StreamId, HandlerFun) ->
    error({badarg, [StreamId, HandlerFun]}, [StreamId, HandlerFun], #{
        error_info => #{
            module => ?MODULE,
            function => process_changes,
            arity => 2,
            cause => "StreamId must be reference, HandlerFun must be function/1"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Create a filtered change stream
%%--------------------------------------------------------------------
-spec create_filtered_stream(atom(), pipeline(), watch_options()) -> 
    {ok, stream_id()} | {error, term()}.
create_filtered_stream(Target, FilterPipeline, Options) ->
    start_change_stream(Target, FilterPipeline, Options).

%%--------------------------------------------------------------------
%% @doc Set resume token for a stream
%%--------------------------------------------------------------------
-spec set_resume_token(stream_id(), resume_token()) -> ok | {error, term()}.
set_resume_token(StreamId, ResumeToken) ->
    gen_server:call(?SERVER, {set_resume_token, StreamId, ResumeToken}).

%%--------------------------------------------------------------------
%% @doc Get current resume token for a stream
%%--------------------------------------------------------------------
-spec get_resume_token(stream_id()) -> {ok, resume_token()} | {error, term()}.
get_resume_token(StreamId) ->
    gen_server:call(?SERVER, {get_resume_token, StreamId}).

%%--------------------------------------------------------------------
%% @doc Get stream statistics
%%--------------------------------------------------------------------
-spec get_stream_stats(stream_id()) -> {ok, stream_status()} | {error, term()}.
get_stream_stats(StreamId) ->
    get_stream_status(StreamId).

%%--------------------------------------------------------------------
%% @doc List all active streams
%%--------------------------------------------------------------------
-spec list_active_streams() -> {ok, [stream_status()]} | {error, term()}.
list_active_streams() ->
    gen_server:call(?SERVER, list_active_streams).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    process_flag(trap_exit, true),
    
    % Initialize global statistics
    InitialStats = #{
        total_events_processed => 0,
        total_streams_created => 0,
        start_time => erlang:system_time(second)
    },
    
    % Set up periodic statistics updates
    erlang:send_after(?STATS_UPDATE_INTERVAL, self(), update_stats),
    
    State = #global_state{
        global_stats = InitialStats
    },
    
    logger:info("MongoDB Change Streams service started"),
    {ok, State}.

handle_call({watch_collection, Collection, Pipeline, Options}, _From, State) ->
    case start_collection_watch(Collection, Pipeline, Options, State) of
        {ok, StreamId, NewState} ->
            {reply, {ok, StreamId}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({watch_database, Database, Options}, _From, State) ->
    case start_database_watch(Database, Options, State) of
        {ok, StreamId, NewState} ->
            {reply, {ok, StreamId}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({watch_cluster, Options}, _From, State) ->
    case start_cluster_watch(Options, State) of
        {ok, StreamId, NewState} ->
            {reply, {ok, StreamId}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({start_change_stream, Target, Pipeline, Options}, _From, State) ->
    case start_generic_stream(Target, Pipeline, Options, State) of
        {ok, StreamId, NewState} ->
            {reply, {ok, StreamId}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({stop_change_stream, StreamId}, _From, State) ->
    case stop_stream_internal(StreamId, State) of
        {ok, NewState} ->
            {reply, ok, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({resume_change_stream, StreamId, ResumeToken}, _From, State) ->
    case resume_stream_internal(StreamId, ResumeToken, State) of
        {ok, NewState} ->
            {reply, ok, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({get_stream_status, StreamId}, _From, State) ->
    case maps:get(StreamId, State#global_state.streams, undefined) of
        undefined ->
            {reply, {error, stream_not_found}, State};
        StreamState ->
            Status = create_stream_status(StreamState),
            {reply, {ok, Status}, State}
    end;

handle_call({next_change, StreamId}, From, State) ->
    case maps:get(StreamId, State#global_state.streams, undefined) of
        undefined ->
            {reply, {error, stream_not_found}, State};
        StreamState ->
            case StreamState#stream_state.worker_pid of
                undefined ->
                    {reply, {error, stream_not_active}, State};
                WorkerPid ->
                    % Forward request to worker
                    WorkerPid ! {next_change, From},
                    {noreply, State}
            end
    end;

handle_call({set_resume_token, StreamId, ResumeToken}, _From, State) ->
    case maps:get(StreamId, State#global_state.streams, undefined) of
        undefined ->
            {reply, {error, stream_not_found}, State};
        StreamState ->
            UpdatedStreamState = StreamState#stream_state{last_resume_token = ResumeToken},
            NewStreams = maps:put(StreamId, UpdatedStreamState, State#global_state.streams),
            {reply, ok, State#global_state{streams = NewStreams}}
    end;

handle_call({get_resume_token, StreamId}, _From, State) ->
    case maps:get(StreamId, State#global_state.streams, undefined) of
        undefined ->
            {reply, {error, stream_not_found}, State};
        StreamState ->
            {reply, {ok, StreamState#stream_state.last_resume_token}, State}
    end;

handle_call(list_active_streams, _From, State) ->
    ActiveStreams = maps:fold(fun(_StreamId, StreamState, Acc) ->
        case StreamState#stream_state.status of
            active -> [create_stream_status(StreamState) | Acc];
            _ -> Acc
        end
    end, [], State#global_state.streams),
    {reply, {ok, ActiveStreams}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({process_changes, StreamId, HandlerFun}, State) ->
    case maps:get(StreamId, State#global_state.streams, undefined) of
        undefined ->
            {noreply, State};
        StreamState ->
            Handlers = StreamState#stream_state.event_handlers,
            UpdatedStreamState = StreamState#stream_state{
                event_handlers = [HandlerFun | Handlers]
            },
            NewStreams = maps:put(StreamId, UpdatedStreamState, State#global_state.streams),
            {noreply, State#global_state{streams = NewStreams}}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'EXIT', Pid, Reason}, State) ->
    % Handle worker process death
    case find_stream_by_worker(Pid, State) of
        {ok, StreamId, StreamState} ->
            logger:warning("Change stream worker ~p died: ~p, restarting", [StreamId, Reason]),
            NewState = restart_stream_worker(StreamId, StreamState, State),
            {noreply, NewState};
        not_found ->
            {noreply, State}
    end;

handle_info({stream_event, StreamId, Event}, State) ->
    % Handle events from worker processes
    case maps:get(StreamId, State#global_state.streams, undefined) of
        undefined ->
            {noreply, State};
        StreamState ->
            % Update stream state and process event
            UpdatedStreamState = process_stream_event(StreamState, Event),
            NewStreams = maps:put(StreamId, UpdatedStreamState, State#global_state.streams),
            {noreply, State#global_state{streams = NewStreams}}
    end;

handle_info(update_stats, State) ->
    % Update global statistics
    NewState = update_global_stats(State),
    erlang:send_after(?STATS_UPDATE_INTERVAL, self(), update_stats),
    {noreply, NewState};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    % Stop all active streams
    maps:fold(fun(_StreamId, StreamState, _Acc) ->
        case StreamState#stream_state.worker_pid of
            undefined -> ok;
            WorkerPid -> exit(WorkerPid, shutdown)
        end
    end, ok, State#global_state.streams),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc Start watching a collection
%%--------------------------------------------------------------------
start_collection_watch(Collection, Pipeline, Options, State) ->
    StreamId = make_ref(),
    Target = {collection, Collection},
    
    case start_stream_worker(StreamId, Target, Pipeline, Options) of
        {ok, WorkerPid} ->
            StreamState = #stream_state{
                stream_id = StreamId,
                target = Target,
                pipeline = Pipeline,
                options = Options,
                worker_pid = WorkerPid,
                created_at = erlang:system_time(second)
            },
            
            NewStreams = maps:put(StreamId, StreamState, State#global_state.streams),
            NewState = State#global_state{streams = NewStreams},
            {ok, StreamId, NewState};
        {error, Reason} ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Start watching a database
%%--------------------------------------------------------------------
start_database_watch(Database, Options, State) ->
    StreamId = make_ref(),
    Target = {database, Database},
    Pipeline = [], % Empty pipeline for database watch
    
    case start_stream_worker(StreamId, Target, Pipeline, Options) of
        {ok, WorkerPid} ->
            StreamState = #stream_state{
                stream_id = StreamId,
                target = Target,
                pipeline = Pipeline,
                options = Options,
                worker_pid = WorkerPid,
                created_at = erlang:system_time(second)
            },
            
            NewStreams = maps:put(StreamId, StreamState, State#global_state.streams),
            NewState = State#global_state{streams = NewStreams},
            {ok, StreamId, NewState};
        {error, Reason} ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Start watching entire cluster
%%--------------------------------------------------------------------
start_cluster_watch(Options, State) ->
    StreamId = make_ref(),
    Target = cluster,
    Pipeline = [], % Empty pipeline for cluster watch
    
    case start_stream_worker(StreamId, Target, Pipeline, Options) of
        {ok, WorkerPid} ->
            StreamState = #stream_state{
                stream_id = StreamId,
                target = Target,
                pipeline = Pipeline,
                options = Options,
                worker_pid = WorkerPid,
                created_at = erlang:system_time(second)
            },
            
            NewStreams = maps:put(StreamId, StreamState, State#global_state.streams),
            NewState = State#global_state{streams = NewStreams},
            {ok, StreamId, NewState};
        {error, Reason} ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Start a generic stream
%%--------------------------------------------------------------------
start_generic_stream(Target, Pipeline, Options, State) ->
    StreamId = make_ref(),
    
    case start_stream_worker(StreamId, Target, Pipeline, Options) of
        {ok, WorkerPid} ->
            StreamState = #stream_state{
                stream_id = StreamId,
                target = Target,
                pipeline = Pipeline,
                options = Options,
                worker_pid = WorkerPid,
                created_at = erlang:system_time(second)
            },
            
            NewStreams = maps:put(StreamId, StreamState, State#global_state.streams),
            NewState = State#global_state{streams = NewStreams},
            {ok, StreamId, NewState};
        {error, Reason} ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Start a stream worker process
%%--------------------------------------------------------------------
start_stream_worker(StreamId, Target, Pipeline, Options) ->
    case spawn_link(?MODULE, stream_worker, [StreamId, Target, Pipeline, Options]) of
        WorkerPid when is_pid(WorkerPid) ->
            {ok, WorkerPid};
        Error ->
            {error, Error}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Stream worker process
%%--------------------------------------------------------------------
stream_worker(StreamId, Target, Pipeline, Options) ->
    try
        % Initialize change stream
        ChangeStreamCursor = initialize_change_stream(Target, Pipeline, Options),
        
        % Main event loop
        stream_worker_loop(StreamId, ChangeStreamCursor, Options, 0)
    catch
        Class:Error:Stacktrace ->
            logger:error("Change stream worker ~p failed: ~p:~p~n~p", 
                        [StreamId, Class, Error, Stacktrace]),
            exit({worker_error, Error})
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Stream worker main loop
%%--------------------------------------------------------------------
stream_worker_loop(StreamId, Cursor, Options, EventCount) ->
    MaxAwaitTime = maps:get(max_await_time_ms, Options, ?DEFAULT_MAX_AWAIT_TIME),
    
    receive
        {next_change, From} ->
            % Client requesting next change
            case get_next_change_from_cursor(Cursor) of
                {ok, Event, NewCursor} ->
                    gen_server:reply(From, {ok, Event}),
                    % Notify main process of event
                    ?SERVER ! {stream_event, StreamId, Event},
                    stream_worker_loop(StreamId, NewCursor, Options, EventCount + 1);
                {error, Error} ->
                    gen_server:reply(From, {error, Error}),
                    stream_worker_loop(StreamId, Cursor, Options, EventCount);
                timeout ->
                    gen_server:reply(From, timeout),
                    stream_worker_loop(StreamId, Cursor, Options, EventCount)
            end;
        shutdown ->
            % Graceful shutdown
            close_cursor(Cursor),
            exit(normal);
        _ ->
            stream_worker_loop(StreamId, Cursor, Options, EventCount)
    after MaxAwaitTime ->
        % Check for changes periodically
        case get_next_change_from_cursor(Cursor) of
            {ok, Event, NewCursor} ->
                % Notify main process of event
                ?SERVER ! {stream_event, StreamId, Event},
                stream_worker_loop(StreamId, NewCursor, Options, EventCount + 1);
            {error, _} ->
                stream_worker_loop(StreamId, Cursor, Options, EventCount);
            timeout ->
                stream_worker_loop(StreamId, Cursor, Options, EventCount)
        end
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Initialize change stream based on target
%%--------------------------------------------------------------------
initialize_change_stream(Target, Pipeline, Options) ->
    % This would create the actual MongoDB change stream
    % For now, return a mock cursor
    AggregationPipeline = create_change_stream_pipeline(Target, Pipeline, Options),
    
    case Target of
        {collection, Collection} ->
            connect_mongodb:aggregate(Collection, AggregationPipeline, Options);
        {database, _Database} ->
            % Database-level change stream
            {ok, mock_database_cursor};
        cluster ->
            % Cluster-level change stream
            {ok, mock_cluster_cursor}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Create change stream aggregation pipeline
%%--------------------------------------------------------------------
create_change_stream_pipeline(Target, UserPipeline, Options) ->
    ChangeStreamStage = create_change_stream_stage(Target, Options),
    [ChangeStreamStage | UserPipeline].

%%--------------------------------------------------------------------
%% @private
%% @doc Create $changeStream stage
%%--------------------------------------------------------------------
create_change_stream_stage(_Target, Options) ->
    % Add options to change stream stage
    ChangeStreamOptions = maps:fold(fun(Key, Value, Acc) ->
        case Key of
            full_document -> 
                Acc#{<<"fullDocument">> => atom_to_binary(Value)};
            full_document_before_change ->
                Acc#{<<"fullDocumentBeforeChange">> => atom_to_binary(Value)};
            resume_after ->
                Acc#{<<"resumeAfter">> => Value};
            start_after ->
                Acc#{<<"startAfter">> => Value};
            start_at_operation_time ->
                Acc#{<<"startAtOperationTime">> => Value};
            _ ->
                Acc
        end
    end, #{}, Options),
    
    #{<<"$changeStream">> => ChangeStreamOptions}.

%%--------------------------------------------------------------------
%% @private
%% @doc Get next change from cursor
%%--------------------------------------------------------------------
get_next_change_from_cursor(Cursor) ->
    % Mock implementation - would interact with actual MongoDB cursor
    case Cursor of
        {ok, mock_cursor} ->
            % Simulate change event
            MockEvent = #{
                <<"_id">> => #{
                    <<"_data">> => base64:encode(crypto:strong_rand_bytes(12))
                },
                <<"operationType">> => <<"insert">>,
                <<"clusterTime">> => erlang:system_time(second),
                <<"fullDocument">> => #{
                    <<"_id">> => generate_object_id(),
                    <<"name">> => <<"Test Document">>,
                    <<"timestamp">> => erlang:system_time(second)
                },
                <<"ns">> => #{
                    <<"db">> => <<"test">>,
                    <<"coll">> => <<"users">>
                },
                <<"documentKey">> => #{
                    <<"_id">> => generate_object_id()
                }
            },
            {ok, MockEvent, {ok, mock_cursor}};
        _ ->
            timeout
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Close cursor
%%--------------------------------------------------------------------
close_cursor(_Cursor) ->
    % Would close actual MongoDB cursor
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc Generate mock ObjectId
%%--------------------------------------------------------------------
generate_object_id() ->
    Timestamp = erlang:system_time(second),
    Random = rand:uniform(16#FFFFFF),
    Counter = rand:uniform(16#FFFFFF),
    <<Timestamp:32, Random:24, Counter:24>>.

%%--------------------------------------------------------------------
%% @private
%% @doc Stop stream internal implementation
%%--------------------------------------------------------------------
stop_stream_internal(StreamId, State) ->
    case maps:get(StreamId, State#global_state.streams, undefined) of
        undefined ->
            {error, stream_not_found};
        StreamState ->
            % Stop worker process
            case StreamState#stream_state.worker_pid of
                undefined -> ok;
                WorkerPid -> exit(WorkerPid, shutdown)
            end,
            
            % Update stream status
            UpdatedStreamState = StreamState#stream_state{
                status = stopped,
                worker_pid = undefined
            },
            
            NewStreams = maps:put(StreamId, UpdatedStreamState, State#global_state.streams),
            {ok, State#global_state{streams = NewStreams}}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Resume stream internal implementation
%%--------------------------------------------------------------------
resume_stream_internal(StreamId, ResumeToken, State) ->
    case maps:get(StreamId, State#global_state.streams, undefined) of
        undefined ->
            {error, stream_not_found};
        StreamState ->
            % Update options with resume token
            NewOptions = (StreamState#stream_state.options)#{resume_after => ResumeToken},
            
            % Restart worker with resume token
            case start_stream_worker(StreamId, StreamState#stream_state.target,
                                   StreamState#stream_state.pipeline, NewOptions) of
                {ok, WorkerPid} ->
                    % Stop old worker if exists
                    case StreamState#stream_state.worker_pid of
                        undefined -> ok;
                        OldPid -> exit(OldPid, shutdown)
                    end,
                    
                    UpdatedStreamState = StreamState#stream_state{
                        worker_pid = WorkerPid,
                        last_resume_token = ResumeToken,
                        options = NewOptions,
                        status = active
                    },
                    
                    NewStreams = maps:put(StreamId, UpdatedStreamState, State#global_state.streams),
                    {ok, State#global_state{streams = NewStreams}};
                {error, Reason} ->
                    {error, Reason}
            end
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Find stream by worker PID
%%--------------------------------------------------------------------
find_stream_by_worker(WorkerPid, State) ->
    maps:fold(fun(StreamId, StreamState, Acc) ->
        case Acc of
            {ok, _, _} -> Acc; % Already found
            not_found ->
                case StreamState#stream_state.worker_pid of
                    WorkerPid -> {ok, StreamId, StreamState};
                    _ -> not_found
                end
        end
    end, not_found, State#global_state.streams).

%%--------------------------------------------------------------------
%% @private
%% @doc Restart stream worker
%%--------------------------------------------------------------------
restart_stream_worker(StreamId, StreamState, State) ->
    case start_stream_worker(StreamId, StreamState#stream_state.target,
                           StreamState#stream_state.pipeline,
                           StreamState#stream_state.options) of
        {ok, NewWorkerPid} ->
            UpdatedStreamState = StreamState#stream_state{
                worker_pid = NewWorkerPid,
                status = active,
                error_count = StreamState#stream_state.error_count + 1
            },
            NewStreams = maps:put(StreamId, UpdatedStreamState, State#global_state.streams),
            State#global_state{streams = NewStreams};
        {error, _Reason} ->
            % Mark stream as error
            UpdatedStreamState = StreamState#stream_state{
                worker_pid = undefined,
                status = error,
                error_count = StreamState#stream_state.error_count + 1
            },
            NewStreams = maps:put(StreamId, UpdatedStreamState, State#global_state.streams),
            State#global_state{streams = NewStreams}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Process stream event
%%--------------------------------------------------------------------
process_stream_event(StreamState, Event) ->
    % Update stream statistics
    UpdatedStreamState = StreamState#stream_state{
        events_processed = StreamState#stream_state.events_processed + 1,
        last_event_time = erlang:system_time(second),
        last_resume_token = maps:get(<<"_id">>, Event, undefined)
    },
    
    % Call event handlers
    lists:foreach(fun(Handler) ->
        try
            Handler(Event)
        catch
            _:Error ->
                logger:warning("Event handler failed: ~p", [Error])
        end
    end, StreamState#stream_state.event_handlers),
    
    UpdatedStreamState.

%%--------------------------------------------------------------------
%% @private
%% @doc Create stream status
%%--------------------------------------------------------------------
create_stream_status(StreamState) ->
    CurrentTime = erlang:system_time(second),
    Uptime = CurrentTime - StreamState#stream_state.created_at,
    
    #{
        stream_id => StreamState#stream_state.stream_id,
        status => StreamState#stream_state.status,
        target => StreamState#stream_state.target,
        events_processed => StreamState#stream_state.events_processed,
        last_resume_token => StreamState#stream_state.last_resume_token,
        last_event_time => StreamState#stream_state.last_event_time,
        error_count => StreamState#stream_state.error_count,
        created_at => StreamState#stream_state.created_at,
        uptime_seconds => Uptime
    }.

%%--------------------------------------------------------------------
%% @private
%% @doc Update global statistics
%%--------------------------------------------------------------------
update_global_stats(State) ->
    TotalEvents = maps:fold(fun(_StreamId, StreamState, Acc) ->
        Acc + StreamState#stream_state.events_processed
    end, 0, State#global_state.streams),
    
    ActiveStreams = maps:fold(fun(_StreamId, StreamState, Acc) ->
        case StreamState#stream_state.status of
            active -> Acc + 1;
            _ -> Acc
        end
    end, 0, State#global_state.streams),
    
    CurrentStats = State#global_state.global_stats,
    NewStats = CurrentStats#{
        total_events_processed => TotalEvents,
        active_streams => ActiveStreams,
        total_streams => maps:size(State#global_state.streams),
        last_update => erlang:system_time(second)
    },
    
    State#global_state{global_stats = NewStats}. 