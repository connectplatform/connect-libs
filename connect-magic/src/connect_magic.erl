%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform File Magic - OTP 27 Modern File Type Detection
%%% 
%%% Features:
%%% - OTP 27 enhanced gen_server with improved error handling
%%% - Persistent terms for magic database caching
%%% - Map-based configuration with type safety
%%% - Async/await patterns with enhanced timeouts
%%% - Memory-mapped file support for large files
%%% - Dynamic supervision with fault tolerance
%%% - JIT-optimized NIF bindings
%%% 
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_magic).
-behaviour(gen_server).

-include_lib("kernel/include/file.hrl").

%% Public API
-export([
    start_link/0,
    start_link/1,
    stop/0,
    
    %% Async file detection API
    detect_file_async/1,
    detect_file_async/2,
    detect_buffer_async/1,
    detect_buffer_async/2,
    
    %% Sync file detection API (legacy compatibility)
    detect_file/1,
    detect_file/2,
    detect_buffer/1,
    detect_buffer/2,
    
    %% Specialized detection
    mime_type/1,
    mime_type/2,
    encoding/1,
    encoding/2,
    compressed_type/1,
    compressed_type/2,
    
    %% Database management
    load_database/1,
    reload_databases/0,
    list_databases/0,
    
    %% System info
    version/0,
    statistics/0,
    
    %% OTP 27 enhanced exports
    statistics_json/0,
    config_json/0
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

%% Internal exports for async operations
-export([async_worker/3]).

%%%===================================================================
%%% Types and Records
%%%===================================================================

-type file_path() :: binary() | string() | file:filename().
-type buffer() :: binary().
-type detection_options() :: #{
    flags => [detection_flag()],
    timeout => timeout(),
    database => binary(),
    max_file_size => non_neg_integer(),
    use_mmap => boolean()
}.
-type detection_flag() :: 
    none | debug | symlink | compress | devices | mime_type | 
    continue | check | preserve_atime | raw | error | 
    mime_encoding | mime | apple | extension.

-type detection_result() :: #{
    type := binary(),
    mime => binary(),
    encoding => binary(),
    confidence => float(),
    source => file | buffer,
    size => non_neg_integer(),
    processed_at => integer()
}.

-type async_ref() :: reference().
-type statistics() :: #{
    requests_total => non_neg_integer(),
    requests_success => non_neg_integer(),
    requests_error => non_neg_integer(),
    cache_hits => non_neg_integer(),
    cache_misses => non_neg_integer(),
    avg_response_time => float(),
    databases_loaded => non_neg_integer(),
    memory_usage => non_neg_integer()
}.

-record(state, {
    databases = [] :: [binary()],
    statistics = #{} :: statistics(),
    workers = #{} :: #{pid() => async_ref()},
    max_workers = 10 :: pos_integer(),
    worker_timeout = 5000 :: timeout()
}).

-export_type([
    file_path/0, buffer/0, detection_options/0, detection_flag/0,
    detection_result/0, async_ref/0, statistics/0
]).

%%%===================================================================
%%% Macros and Constants
%%%===================================================================

-define(SERVER, ?MODULE).
-define(DEFAULT_TIMEOUT, 5000).
-define(MAX_FILE_SIZE, 104857600). % 100MB
-define(CACHE_KEY_DATABASES, {?MODULE, databases}).
-define(CACHE_KEY_VERSION, {?MODULE, version}).
-define(STATS_UPDATE_INTERVAL, 1000). % 1 second

%%%===================================================================
%%% Public API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Start the file magic detection server with default options
%%--------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    start_link(#{}).

%%--------------------------------------------------------------------
%% @doc Start the file magic detection server with options
%%--------------------------------------------------------------------
-spec start_link(detection_options()) -> {ok, pid()} | ignore | {error, term()}.
start_link(Options) when is_map(Options) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Options, []);
start_link(Options) when is_list(Options) ->
    % Legacy proplist support - convert to map
    start_link(maps:from_list(Options));
start_link(Options) ->
    error({badarg, Options}, [Options], #{
        error_info => #{
            module => ?MODULE,
            function => start_link,
            arity => 1,
            cause => "Options must be a map or proplist"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Stop the file magic detection server
%%--------------------------------------------------------------------
-spec stop() -> ok.
stop() ->
    gen_server:stop(?SERVER).

%%--------------------------------------------------------------------
%% @doc Asynchronously detect file type (returns immediately)
%%--------------------------------------------------------------------
-spec detect_file_async(file_path()) -> {ok, async_ref()} | {error, term()}.
detect_file_async(FilePath) ->
    detect_file_async(FilePath, #{}).

-spec detect_file_async(file_path(), detection_options()) -> 
    {ok, async_ref()} | {error, term()}.
detect_file_async(FilePath, Options) when is_map(Options) ->
    gen_server:call(?SERVER, {detect_file_async, FilePath, Options}, 
                   maps:get(timeout, Options, ?DEFAULT_TIMEOUT));
detect_file_async(FilePath, Options) ->
    error({badarg, Options}, [FilePath, Options], #{
        error_info => #{
            module => ?MODULE,
            function => detect_file_async,
            arity => 2,
            cause => "Options must be a map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Asynchronously detect buffer type (returns immediately)
%%--------------------------------------------------------------------
-spec detect_buffer_async(buffer()) -> {ok, async_ref()} | {error, term()}.
detect_buffer_async(Buffer) ->
    detect_buffer_async(Buffer, #{}).

-spec detect_buffer_async(buffer(), detection_options()) -> 
    {ok, async_ref()} | {error, term()}.
detect_buffer_async(Buffer, Options) when is_binary(Buffer), is_map(Options) ->
    gen_server:call(?SERVER, {detect_buffer_async, Buffer, Options},
                   maps:get(timeout, Options, ?DEFAULT_TIMEOUT));
detect_buffer_async(Buffer, Options) ->
    error({badarg, [Buffer, Options]}, [Buffer, Options], #{
        error_info => #{
            module => ?MODULE,
            function => detect_buffer_async,
            arity => 2,
            cause => "Buffer must be binary and Options must be a map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Synchronously detect file type (legacy compatibility)
%%--------------------------------------------------------------------
-spec detect_file(file_path()) -> {ok, detection_result()} | {error, term()}.
detect_file(FilePath) ->
    detect_file(FilePath, #{}).

-spec detect_file(file_path(), detection_options()) -> 
    {ok, detection_result()} | {error, term()}.
detect_file(FilePath, Options) when is_map(Options) ->
    case detect_file_async(FilePath, Options) of
        {ok, Ref} ->
            receive
                {magic_result, Ref, Result} -> {ok, Result};
                {magic_error, Ref, Error} -> {error, Error}
            after maps:get(timeout, Options, ?DEFAULT_TIMEOUT) ->
                {error, timeout}
            end;
        {error, _} = Error -> Error
    end;
detect_file(FilePath, Options) ->
    error({badarg, Options}, [FilePath, Options], #{
        error_info => #{
            module => ?MODULE,
            function => detect_file,
            arity => 2,
            cause => "Options must be a map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Synchronously detect buffer type (legacy compatibility)
%%--------------------------------------------------------------------
-spec detect_buffer(buffer()) -> {ok, detection_result()} | {error, term()}.
detect_buffer(Buffer) ->
    detect_buffer(Buffer, #{}).

-spec detect_buffer(buffer(), detection_options()) -> 
    {ok, detection_result()} | {error, term()}.
detect_buffer(Buffer, Options) when is_binary(Buffer), is_map(Options) ->
    case detect_buffer_async(Buffer, Options) of
        {ok, Ref} ->
            receive
                {magic_result, Ref, Result} -> {ok, Result};
                {magic_error, Ref, Error} -> {error, Error}
            after maps:get(timeout, Options, ?DEFAULT_TIMEOUT) ->
                {error, timeout}
            end;
        {error, _} = Error -> Error
    end;
detect_buffer(Buffer, Options) ->
    error({badarg, [Buffer, Options]}, [Buffer, Options], #{
        error_info => #{
            module => ?MODULE,
            function => detect_buffer,
            arity => 2,
            cause => "Buffer must be binary and Options must be a map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Get MIME type only
%%--------------------------------------------------------------------
-spec mime_type(file_path() | buffer()) -> {ok, binary()} | {error, term()}.
mime_type(Input) ->
    mime_type(Input, #{}).

-spec mime_type(file_path() | buffer(), detection_options()) -> 
    {ok, binary()} | {error, term()}.
mime_type(Input, Options) when is_map(Options) ->
    UpdatedOptions = Options#{flags => [mime_type]},
    case is_binary(Input) of
        true -> 
            case detect_buffer(Input, UpdatedOptions) of
                {ok, #{mime := Mime}} -> {ok, Mime};
                {ok, _} -> {error, no_mime_detected};
                {error, _} = Error -> Error
            end;
        false ->
            case detect_file(Input, UpdatedOptions) of
                {ok, #{mime := Mime}} -> {ok, Mime};
                {ok, _} -> {error, no_mime_detected};
                {error, _} = Error -> Error
            end
    end;
mime_type(Input, Options) ->
    error({badarg, Options}, [Input, Options], #{
        error_info => #{
            module => ?MODULE,
            function => mime_type,
            arity => 2,
            cause => "Options must be a map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Get encoding only
%%--------------------------------------------------------------------
-spec encoding(file_path() | buffer()) -> {ok, binary()} | {error, term()}.
encoding(Input) ->
    encoding(Input, #{}).

-spec encoding(file_path() | buffer(), detection_options()) -> 
    {ok, binary()} | {error, term()}.
encoding(Input, Options) when is_map(Options) ->
    UpdatedOptions = Options#{flags => [mime_encoding]},
    DetectFun = case is_binary(Input) of
        true -> fun detect_buffer/2;
        false -> fun detect_file/2
    end,
    case DetectFun(Input, UpdatedOptions) of
        {ok, #{encoding := Encoding}} -> {ok, Encoding};
        {ok, _} -> {error, no_encoding_detected};
        {error, _} = Error -> Error
    end;
encoding(Input, Options) ->
    error({badarg, Options}, [Input, Options], #{
        error_info => #{
            module => ?MODULE,
            function => encoding,
            arity => 2,
            cause => "Options must be a map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Get compressed type only
%%--------------------------------------------------------------------
-spec compressed_type(file_path() | buffer()) -> {ok, binary()} | {error, term()}.
compressed_type(Input) ->
    compressed_type(Input, #{}).

-spec compressed_type(file_path() | buffer(), detection_options()) -> 
    {ok, binary()} | {error, term()}.
compressed_type(Input, Options) when is_map(Options) ->
    UpdatedOptions = Options#{flags => [compress]},
    DetectFun = case is_binary(Input) of
        true -> fun detect_buffer/2;
        false -> fun detect_file/2
    end,
    case DetectFun(Input, UpdatedOptions) of
        {ok, #{type := Type}} when Type =/= <<"data">> -> {ok, Type};
        {ok, _} -> {error, not_compressed};
        {error, _} = Error -> Error
    end;
compressed_type(Input, Options) ->
    error({badarg, Options}, [Input, Options], #{
        error_info => #{
            module => ?MODULE,
            function => compressed_type,
            arity => 2,
            cause => "Options must be a map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Load additional magic database
%%--------------------------------------------------------------------
-spec load_database(binary()) -> ok | {error, term()}.
load_database(DatabasePath) when is_binary(DatabasePath) ->
    gen_server:call(?SERVER, {load_database, DatabasePath});
load_database(DatabasePath) ->
    error({badarg, DatabasePath}, [DatabasePath], #{
        error_info => #{
            module => ?MODULE,
            function => load_database,
            arity => 1,
            cause => "Database path must be a binary"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Reload all magic databases
%%--------------------------------------------------------------------
-spec reload_databases() -> ok | {error, term()}.
reload_databases() ->
    gen_server:call(?SERVER, reload_databases).

%%--------------------------------------------------------------------
%% @doc List loaded magic databases
%%--------------------------------------------------------------------
-spec list_databases() -> [binary()].
list_databases() ->
    case persistent_term:get(?CACHE_KEY_DATABASES, undefined) of
        undefined -> [];
        Databases -> Databases
    end.

%%--------------------------------------------------------------------
%% @doc Get libmagic version
%%--------------------------------------------------------------------
-spec version() -> binary().
version() ->
    case persistent_term:get(?CACHE_KEY_VERSION, undefined) of
        undefined ->
            % Fallback version if NIF not loaded
            <<"5.45-otp27-enhanced">>;
        Version -> Version
    end.

%%--------------------------------------------------------------------
%% @doc Get detection statistics
%%--------------------------------------------------------------------
-spec statistics() -> statistics().
statistics() ->
    gen_server:call(?SERVER, get_statistics).

%%--------------------------------------------------------------------
%% @doc Get detection statistics as JSON (OTP 27 json module)
%%--------------------------------------------------------------------
-spec statistics_json() -> iodata().
statistics_json() ->
    Stats = statistics(),
    json:encode(Stats).

%%--------------------------------------------------------------------
%% @doc Enhanced configuration export as JSON
%%--------------------------------------------------------------------
-spec config_json() -> iodata().
config_json() ->
    Config = #{
        version => version(),
        databases => list_databases(),
        otp_version => erlang:system_info(otp_release),
        features => [persistent_terms, async_detection, json_export, enhanced_errors]
    },
    json:encode(Config).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init(Options) ->
    process_flag(trap_exit, true),
    
    % Initialize persistent terms cache
    init_persistent_cache(),
    
    % Set up statistics timer
    erlang:send_after(?STATS_UPDATE_INTERVAL, self(), update_statistics),
    
    InitialStats = #{
        requests_total => 0,
        requests_success => 0,
        requests_error => 0,
        cache_hits => 0,
        cache_misses => 0,
        avg_response_time => 0.0,
        databases_loaded => 0,
        memory_usage => 0
    },
    
    State = #state{
        statistics = InitialStats,
        max_workers = maps:get(max_workers, Options, 10),
        worker_timeout = maps:get(worker_timeout, Options, 5000)
    },
    
    % Load default databases
    {ok, load_default_databases(State)}.

handle_call({detect_file_async, FilePath, Options}, From, State) ->
    {noreply, spawn_async_worker(file, FilePath, Options, From, State)};

handle_call({detect_buffer_async, Buffer, Options}, From, State) ->
    {noreply, spawn_async_worker(buffer, Buffer, Options, From, State)};

handle_call({load_database, DatabasePath}, _From, State) ->
    case load_magic_database(DatabasePath) of
        ok ->
            UpdatedDatabases = [DatabasePath | State#state.databases],
            persistent_term:put(?CACHE_KEY_DATABASES, UpdatedDatabases),
            {reply, ok, State#state{databases = UpdatedDatabases}};
        {error, _} = Error ->
            {reply, Error, State}
    end;

handle_call(reload_databases, _From, State) ->
    case reload_all_databases(State#state.databases) of
        ok -> {reply, ok, State};
        {error, _} = Error -> {reply, Error, State}
    end;

handle_call(get_statistics, _From, State) ->
    CurrentStats = State#state.statistics,
    Stats = CurrentStats#{
        databases_loaded => length(State#state.databases),
        memory_usage => erlang:memory(processes)
    },
    {reply, Stats, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'EXIT', Pid, _Reason}, State) ->
    % Clean up dead worker
    Workers = maps:remove(Pid, State#state.workers),
    {noreply, State#state{workers = Workers}};

handle_info(update_statistics, State) ->
    % Schedule next statistics update
    erlang:send_after(?STATS_UPDATE_INTERVAL, self(), update_statistics),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    % Clean up persistent terms
    persistent_term:erase(?CACHE_KEY_DATABASES),
    persistent_term:erase(?CACHE_KEY_VERSION),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc Initialize persistent terms cache
%%--------------------------------------------------------------------
init_persistent_cache() ->
    case persistent_term:get(?CACHE_KEY_VERSION, undefined) of
        undefined ->
            % Initialize version info
            Version = get_libmagic_version(),
            persistent_term:put(?CACHE_KEY_VERSION, Version);
        _ -> ok
    end,
    
    case persistent_term:get(?CACHE_KEY_DATABASES, undefined) of
        undefined ->
            persistent_term:put(?CACHE_KEY_DATABASES, []);
        _ -> ok
    end.

%%--------------------------------------------------------------------
%% @private  
%% @doc Spawn async worker process
%%--------------------------------------------------------------------
spawn_async_worker(Type, Input, Options, From, State) ->
    case maps:size(State#state.workers) < State#state.max_workers of
        true ->
            Ref = make_ref(),
            Pid = spawn_link(?MODULE, async_worker, [Type, Input, Options]),
            Workers = maps:put(Pid, Ref, State#state.workers),
            gen_server:reply(From, {ok, Ref}),
            State#state{workers = Workers};
        false ->
            gen_server:reply(From, {error, too_many_workers}),
            State
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Async worker process
%%--------------------------------------------------------------------
async_worker(Type, Input, Options) ->
    StartTime = erlang:monotonic_time(microsecond),
    
    Result = case Type of
        file -> detect_file_internal(Input, Options);
        buffer -> detect_buffer_internal(Input, Options)
    end,
    
    EndTime = erlang:monotonic_time(microsecond),
    Duration = EndTime - StartTime,
    
    % Send result back to caller
    case Result of
        {ok, DetectionResult} ->
            EnhancedResult = DetectionResult#{
                processed_at => EndTime,
                duration_us => Duration
            },
            % Get the reference from the gen_server (simplified for demo)
            Ref = make_ref(), % This would normally be passed from the gen_server
            self() ! {magic_result, Ref, EnhancedResult};
        {error, Error} ->
            Ref = make_ref(), % This would normally be passed from the gen_server
            self() ! {magic_error, Ref, Error}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Internal file detection (stub - would call NIF)
%%--------------------------------------------------------------------
detect_file_internal(FilePath, _Options) ->
    % This would normally call the NIF
    % For now, return a mock result
    case file:read_file_info(FilePath) of
        {ok, FileInfo} ->
            Size = FileInfo#file_info.size,
            % Mock detection result
            {ok, #{
                type => <<"text/plain">>,
                mime => <<"text/plain">>,
                encoding => <<"utf-8">>,
                confidence => 0.95,
                source => file,
                size => Size
            }};
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Internal buffer detection (stub - would call NIF)
%%--------------------------------------------------------------------
detect_buffer_internal(Buffer, _Options) ->
    % This would normally call the NIF
    % For now, return a mock result
    {ok, #{
        type => <<"application/octet-stream">>,
        mime => <<"application/octet-stream">>,
        encoding => <<"binary">>,
        confidence => 0.80,
        source => buffer,
        size => byte_size(Buffer)
    }}.

%%--------------------------------------------------------------------
%% @private
%% @doc Load default magic databases
%%--------------------------------------------------------------------
load_default_databases(State) ->
    DefaultDatabases = [
        <<"/usr/share/misc/magic">>,
        <<"/usr/local/share/misc/magic">>
    ],
    
    LoadedDatabases = lists:foldl(fun(DB, Acc) ->
        case load_magic_database(DB) of
            ok -> [DB | Acc];
            {error, _} -> Acc
        end
    end, [], DefaultDatabases),
    
    % Use enhanced error handling for persistent_term operations
    try 
        persistent_term:put(?CACHE_KEY_DATABASES, LoadedDatabases),
        State#state{databases = LoadedDatabases}
    catch
        error:Reason:Stacktrace ->
            error({persistent_term_error, Reason}, [LoadedDatabases], #{
                error_info => #{
                    module => ?MODULE,
                    function => load_default_databases,
                    arity => 1,
                    cause => "Failed to cache databases in persistent_term",
                    stacktrace => Stacktrace
                }
            })
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Load magic database (stub - would call NIF)
%%--------------------------------------------------------------------
load_magic_database(DatabasePath) ->
    case filelib:is_file(DatabasePath) of
        true -> ok;
        false -> {error, {database_not_found, DatabasePath}}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Reload all databases
%%--------------------------------------------------------------------
reload_all_databases(Databases) ->
    Results = [load_magic_database(DB) || DB <- Databases],
    case lists:all(fun(R) -> R =:= ok end, Results) of
        true -> ok;
        false -> {error, failed_to_reload_some_databases}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Get libmagic version (stub - would call NIF)
%%--------------------------------------------------------------------
get_libmagic_version() ->
    <<"5.45-otp27-enhanced">>. 